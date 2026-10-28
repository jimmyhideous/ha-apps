#!/usr/bin/env bash
# Smoke test: runs the app under its AppArmor profile with the runner's journal, a stand-in Supervisor API,
# a mapped /config and Loki with auth enabled, then checks shipping, options, merged config and the ingress UI.
#
# Usage: smoke.sh <image>   (Ubuntu runner with Docker and AppArmor)
set -euo pipefail

IMAGE="$1"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOKI_IMAGE="grafana/loki:3.4.2"
BUSYBOX_IMAGE="busybox:1.37.0"
NET="ha-alloy-smoke"
HOST_LABEL="ci-smoke"
TENANT="ci-tenant"
INGRESS_ENTRY="/api/hassio_ingress/smoke-token"
SUPERVISOR_IP="172.30.32.2"
MARKER="ha-alloy-smoke-${GITHUB_RUN_ID:-local}-${RANDOM}${RANDOM}"
DATA="$(mktemp -d)"
CONFIG="$(mktemp -d)"

cleanup() {
    echo "::group::app log"; docker logs app 2>&1 || true; echo "::endgroup::"
    echo "::group::supervisor stand-in log"; docker logs supervisor 2>&1 || true; echo "::endgroup::"
    echo "::group::AppArmor denials"; sudo journalctl -k --no-pager 2>/dev/null | grep 'apparmor="DENIED"' | grep ci_ha_alloy || true; echo "::endgroup::"
    docker rm -f app loki supervisor >/dev/null 2>&1 || true
    docker network rm "${NET}" >/dev/null 2>&1 || true
    sudo rm -rf "${DATA}" "${CONFIG}"
}
trap cleanup EXIT

fail() { echo "::error::$*"; exit 1; }

# HTTP GET from the network; prints the body, or the error line on failure.
probe() {
    local ip="$1" path="$2"
    docker run --rm --network "${NET}" ${ip:+--ip "${ip}"} "${BUSYBOX_IMAGE}" \
        wget -q -O - "http://app:8099${path}" 2>&1
}

echo "::group::Load the AppArmor profile"
sed -E 's/^profile ha_alloy /profile ci_ha_alloy /' "${APP_DIR}/apparmor.txt" | sudo apparmor_parser -r -W
sudo grep -E '^ci_ha_alloy( |//)' /sys/kernel/security/apparmor/profiles
echo "::endgroup::"

echo "::group::Start Loki"
# Supervisor network layout: the Supervisor is 172.30.32.2, containers get addresses from 172.30.33.0/24.
docker network create --subnet 172.30.32.0/23 --ip-range 172.30.33.0/24 "${NET}" >/dev/null
docker run -d --name loki --network "${NET}" -p 127.0.0.1:3100:3100 "${LOKI_IMAGE}" \
    -config.file=/etc/loki/local-config.yaml -auth.enabled=true >/dev/null
for _ in $(seq 60); do
    curl -fsS http://127.0.0.1:3100/ready >/dev/null 2>&1 && break
    sleep 2
done
curl -fsS http://127.0.0.1:3100/ready
echo "::endgroup::"

echo "::group::Start the app"
JOURNAL=/var/log/journal
sudo find "${JOURNAL}" -name '*.journal' 2>/dev/null | grep -q . || JOURNAL=/run/log/journal
echo "host journal: ${JOURNAL}"
OPTIONS=$(jq -nc --arg host "${HOST_LABEL}" --arg tenant "${TENANT}" '{
    loki_url: "http://loki:3100/loki/api/v1/push", host_label: $host, max_age: "1h",
    config_mode: "merged", log_level: "info", exclude: "ha-alloy-excluded", memory_limit: "256MiB",
    tenant_id: $tenant, tls_insecure_skip_verify: false}')
echo "${OPTIONS}" > "${DATA}/options.json"
mkdir -p "${DATA}/www/addons/self/options"
echo "{\"result\": \"ok\", \"data\": ${OPTIONS}}" > "${DATA}/www/addons/self/options/config"
echo "{\"result\": \"ok\", \"data\": {\"slug\": \"ha_alloy\", \"ingress\": true, \"ingress_entry\": \"${INGRESS_ENTRY}\", \"ingress_port\": 8099}}" \
    > "${DATA}/www/addons/self/info"
# User folder: an existing file that must stay untouched and a component that uses the built-in writer.
echo "keep me" > "${CONFIG}/README.txt"
printf 'loki.relabel "user_smoke" {\n  forward_to = [loki.write.loki.receiver]\n}\n' > "${CONFIG}/smoke.alloy"
sudo chown -R root:root "${DATA}" "${CONFIG}"
sudo chmod 755 "${DATA}" "${CONFIG}"
docker run -d --name supervisor --network "${NET}" -v "${DATA}/www:/www:ro" "${BUSYBOX_IMAGE}" \
    httpd -f -v -p 80 -h /www >/dev/null
docker run -d --name app --network "${NET}" \
    --security-opt apparmor=ci_ha_alloy \
    -e SUPERVISOR_TOKEN=smoke-test \
    -v "${JOURNAL}:/var/log/journal:ro" \
    -v "${DATA}:/data" \
    -v "${CONFIG}:/config" \
    "${IMAGE}" >/dev/null
sleep 10
[[ "$(docker inspect -f '{{.State.Running}}' app)" == "true" ]] || fail "the app exited"
[[ "$(docker inspect -f '{{.AppArmorProfile}}' app)" == "ci_ha_alloy" ]] || fail "not running under the AppArmor profile"
echo "::endgroup::"

echo "::group::Ship marker lines"
logger -t ha-alloy-excluded "${MARKER}-excluded"
logger -t ha-alloy-smoke "${MARKER}"
loki_query() {
    curl -fsS -G -H "X-Scope-OrgID: ${TENANT}" http://127.0.0.1:3100/loki/api/v1/query_range \
        --data-urlencode "query=$1" --data-urlencode "since=15m" | jq -r '.data.result[].values[][1]'
}
found=""
for _ in $(seq 45); do
    found=$(loki_query "{job=\"journal\", host=\"${HOST_LABEL}\", app=\"ha-alloy-smoke\"} |= \"${MARKER}\"" \
        | grep -F "${MARKER}" || true)
    [[ -n "${found}" ]] && break
    sleep 2
done
echo "::endgroup::"
[[ -n "${found}" ]] || fail "marker ${MARKER} did not reach Loki as tenant ${TENANT}"
echo "Loki received: ${found}"

code=$(curl -s -o /dev/null -w '%{http_code}' -G http://127.0.0.1:3100/loki/api/v1/query_range \
    --data-urlencode 'query={job="journal"}')
[[ "${code}" == "401" ]] || fail "Loki answered ${code} without a tenant header: auth is not enabled"

excluded=$(loki_query "{host=\"${HOST_LABEL}\"} |= \"${MARKER}-excluded\"" || true)
[[ -z "${excluded}" ]] || fail "exclude: the ha-alloy-excluded line reached Loki"

echo "::group::Ingress UI"
ui=""
for _ in $(seq 15); do
    ui=$(probe "${SUPERVISOR_IP}" / || true)
    grep -qF "<base href=\"${INGRESS_ENTRY}/\"" <<< "${ui}" && break
    sleep 2
done
grep -qF "<base href=\"${INGRESS_ENTRY}/\"" <<< "${ui}" || { echo "${ui}"; fail "UI index has no <base href=\"${INGRESS_ENTRY}/\">"; }
components=$(probe "${SUPERVISOR_IP}" /api/v0/web/components || true)
jq -e '.[] | select(.localID == "loki.relabel.user_smoke")' <<< "${components}" >/dev/null \
    || { echo "${components}"; fail "API through ingress does not list loki.relabel.user_smoke"; }
jq -r '.[].localID' <<< "${components}"
denied=$(probe "" / || true)
grep -q '403' <<< "${denied}" || { echo "${denied}"; fail "ingress port answered a client other than ${SUPERVISOR_IP}"; }
echo "::endgroup::"

[[ "$(sudo cat "${CONFIG}/README.txt")" == "keep me" ]] || fail "/config/README.txt was changed"
[[ ! -e "${CONFIG}/example.alloy.disabled" ]] || fail "example.alloy.disabled written to a non-empty /config"

memlimit=$(docker exec app curl -fsS http://127.0.0.1:12345/metrics | awk '$1 == "go_gc_gomemlimit_bytes" {printf "%d", $2}')
[[ "${memlimit}" == "268435456" ]] || fail "memory_limit: go_gc_gomemlimit_bytes is '${memlimit}', expected 268435456"

docker logs app 2>&1 | grep -q 'level=info' || fail "log_level info: Alloy logged no info lines"
[[ "$(docker inspect -f '{{.State.Running}}' app)" == "true" ]] || fail "the app exited"
if docker logs app 2>&1 | grep -E 'level=error|\[(emerg|alert|crit)\]'; then
    fail "Alloy or nginx logged errors"
fi
echo "Smoke test passed"
