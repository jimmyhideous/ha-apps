#!/usr/bin/env bash
# Smoke test: start the app the way the Supervisor does and check that a journal line reaches Loki.
#
# - Loki runs in a throwaway container.
# - The app's AppArmor profile is loaded as "ci_ha_alloy" and the app runs under it.
# - The runner's systemd journal is mounted read-only at /var/log/journal (as `journald: true` does), and
#   /data/options.json holds the app options (as the Supervisor writes them).
# - A unique marker is written to the journal with `logger`; the test passes when Loki returns it with the
#   app's labels, and fails if Alloy logs an error.
#
# Usage: smoke.sh <image>   (run from the repository root on an Ubuntu runner with Docker and AppArmor)
set -euo pipefail

IMAGE="$1"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOKI_IMAGE="grafana/loki:3.4.2"
NET="ha-alloy-smoke"
HOST_LABEL="ci-smoke"
MARKER="ha-alloy-smoke-${GITHUB_RUN_ID:-local}-${RANDOM}${RANDOM}"
DATA="$(mktemp -d)"

cleanup() {
    echo "::group::app log"; docker logs app 2>&1 || true; echo "::endgroup::"
    docker rm -f app loki >/dev/null 2>&1 || true
    docker network rm "${NET}" >/dev/null 2>&1 || true
    sudo rm -rf "${DATA}"
}
trap cleanup EXIT

echo "::group::Load the AppArmor profile"
sed -E 's/^profile ha_alloy /profile ci_ha_alloy /' "${APP_DIR}/apparmor.txt" | sudo apparmor_parser -r -W
sudo grep -E '^ci_ha_alloy( |//)' /sys/kernel/security/apparmor/profiles
echo "::endgroup::"

echo "::group::Start Loki"
docker network create "${NET}" >/dev/null
docker run -d --name loki --network "${NET}" -p 127.0.0.1:3100:3100 "${LOKI_IMAGE}" >/dev/null
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
cat > "${DATA}/options.json" <<EOF
{"loki_url": "http://loki:3100/loki/api/v1/push", "host_label": "${HOST_LABEL}", "max_age": "1h"}
EOF
docker run -d --name app --network "${NET}" \
    --security-opt apparmor=ci_ha_alloy \
    -v "${JOURNAL}:/var/log/journal:ro" \
    -v "${DATA}:/data" \
    "${IMAGE}" >/dev/null
sleep 10
[[ "$(docker inspect -f '{{.State.Running}}' app)" == "true" ]] || { echo "::error::the app exited"; exit 1; }
[[ "$(docker inspect -f '{{.AppArmorProfile}}' app)" == "ci_ha_alloy" ]] || { echo "::error::not running under the AppArmor profile"; exit 1; }
echo "::endgroup::"

echo "::group::Ship a marker line"
logger -t ha-alloy-smoke "${MARKER}"
query="{job=\"journal\", host=\"${HOST_LABEL}\", app=\"ha-alloy-smoke\"} |= \"${MARKER}\""
found=""
for _ in $(seq 45); do
    found=$(curl -fsS -G http://127.0.0.1:3100/loki/api/v1/query_range \
        --data-urlencode "query=${query}" --data-urlencode "since=15m" \
        | jq -r '.data.result[].values[][1]' | grep -F "${MARKER}" || true)
    [[ -n "${found}" ]] && break
    sleep 2
done
echo "::endgroup::"

[[ -n "${found}" ]] || { echo "::error::marker ${MARKER} did not reach Loki"; exit 1; }
[[ "$(docker inspect -f '{{.State.Running}}' app)" == "true" ]] || { echo "::error::the app exited"; exit 1; }
if docker logs app 2>&1 | grep -E 'level=error'; then
    echo "::error::Alloy logged errors"
    exit 1
fi
echo "Loki received: ${found}"
