#!/usr/bin/env bash
# Smoke test: runs the app with a stand-in Supervisor API and an SSH server, then checks the key setup, an SSH
# session through remote-shell, the ttyd page through ingress and that ingress refuses other clients.
#
# Usage: smoke.sh <image>   (Ubuntu runner with Docker)
set -euo pipefail

IMAGE="$1"
SSHD_IMAGE="alpine:3.22"
BUSYBOX_IMAGE="busybox:1.37.0"
NET="remote-terminal-smoke"
INGRESS_ENTRY="/api/hassio_ingress/smoke-token"
SUPERVISOR_IP="172.30.32.2"
DATA="$(mktemp -d)"

cleanup() {
    echo "::group::app log"; docker logs app 2>&1 || true; echo "::endgroup::"
    echo "::group::sshd log"; docker logs sshd 2>&1 || true; echo "::endgroup::"
    docker rm -f app sshd supervisor >/dev/null 2>&1 || true
    docker network rm "${NET}" >/dev/null 2>&1 || true
    sudo rm -rf "${DATA}"
}
trap cleanup EXIT

fail() { echo "::error::$*"; exit 1; }

# HTTP GET from the network; prints the body, or the error line on failure.
probe() {
    local ip="$1" path="$2"
    docker run --rm --network "${NET}" ${ip:+--ip "${ip}"} "${BUSYBOX_IMAGE}" \
        wget -q -O - "http://app:8099${path}" 2>&1
}

echo "::group::Start the stand-in Supervisor"
# Supervisor network layout: the Supervisor is 172.30.32.2, containers get addresses from 172.30.33.0/24.
docker network create --subnet 172.30.32.0/23 --ip-range 172.30.33.0/24 "${NET}" >/dev/null
# packages fails on purpose: sshd starts after the app, which must log a warning and keep running.
OPTIONS='{"host": "sshd", "port": 22, "username": "tester", "tmux_session": "", "font_size": 14,
    "packages": ["Tmux"], "env_vars": [{"name": "SMOKE_VAR", "value": "a b'"'"'c\"d $HOME; x"}]}'
echo "${OPTIONS}" > "${DATA}/options.json"
mkdir -p "${DATA}/www/addons/self/options"
echo "{\"result\": \"ok\", \"data\": ${OPTIONS}}" > "${DATA}/www/addons/self/options/config"
echo "{\"result\": \"ok\", \"data\": {\"slug\": \"remote_terminal\", \"ingress\": true, \"ingress_entry\": \"${INGRESS_ENTRY}\", \"ingress_port\": 8099}}" \
    > "${DATA}/www/addons/self/info"
cp -r "${DATA}/www/addons" "${DATA}/www/apps"
sudo chown -R root:root "${DATA}"
sudo chmod 755 "${DATA}"
docker run -d --name supervisor --network "${NET}" -v "${DATA}/www:/www:ro" "${BUSYBOX_IMAGE}" \
    httpd -f -v -p 80 -h /www >/dev/null
echo "::endgroup::"

echo "::group::Start the app"
docker run -d --name app --network "${NET}" -e SUPERVISOR_TOKEN=smoke-test -v "${DATA}:/data" "${IMAGE}" >/dev/null
pubkey=""
for _ in $(seq 30); do
    pubkey=$(sudo cat "${DATA}/ssh/id_ed25519.pub" 2>/dev/null || true)
    [[ -n "${pubkey}" ]] && docker logs app 2>&1 | grep -qF "${pubkey}" && break
    sleep 1
done
[[ -n "${pubkey}" ]] || fail "no client key in /data/ssh"
docker logs app 2>&1 | grep -qF "${pubkey}" || fail "the public key is not in the log"
[[ "$(docker inspect -f '{{.State.Running}}' app)" == "true" ]] || fail "the app exited"
warned=""
for _ in $(seq 15); do
    docker logs app 2>&1 | grep -q "Package install on tester@sshd failed" && { warned=1; break; }
    sleep 1
done
[[ -n "${warned}" ]] || fail "no warning for the failed package install"
docker logs app 2>&1 | grep -q "Installing missing packages on tester@sshd: tmux" || fail "package names were not lowercased"
[[ "$(docker inspect -f '{{.State.Running}}' app)" == "true" ]] || fail "the app exited after the package install"
# A session that cannot log in (sshd is not up yet) shows the public key in the panel.
out=$(echo | docker exec -i app /usr/local/bin/remote-shell 2>&1 || true)
grep -qF "${pubkey}" <<< "${out}" || { echo "${out}"; fail "a failed login did not show the public key"; }
echo "::endgroup::"

echo "::group::Start the SSH server"
docker run -d --name sshd --network "${NET}" -e PUBKEY="${pubkey}" "${SSHD_IMAGE}" sh -euc '
    apk add --no-cache -q openssh-server
    adduser -D tester
    echo "tester:*" | chpasswd -e
    mkdir -p -m 700 /home/tester/.ssh
    echo "${PUBKEY}" > /home/tester/.ssh/authorized_keys
    chown -R tester:tester /home/tester/.ssh
    ssh-keygen -A
    exec /usr/sbin/sshd -D -e' >/dev/null
ready=""
for _ in $(seq 60); do
    docker logs sshd 2>&1 | grep -q "Server listening" && { ready=1; break; }
    sleep 1
done
[[ -n "${ready}" ]] || fail "sshd did not start"
echo "::endgroup::"

echo "::group::SSH session"
# One argument: ssh joins its arguments with spaces and the remote shell parses the result.
out=$(docker exec app /usr/local/bin/remote-shell 'echo "smoke-ok $(id -un)"' 2>&1 || true)
echo "${out}"
grep -q "smoke-ok tester" <<< "${out}" || fail "remote-shell did not run a command as tester@sshd"
# No arguments: the login shell with env_vars, reading its commands from stdin.
out=$(echo 'echo "[${SMOKE_VAR}]"; exit' | docker exec -i app /usr/local/bin/remote-shell 2>&1 || true)
echo "${out}"
grep -qF "[a b'c\"d \$HOME; x]" <<< "${out}" || fail "env_vars did not reach the remote shell"
docker exec app ssh-keygen -F sshd -f /data/ssh/known_hosts >/dev/null || fail "the host key was not pinned"
echo "::endgroup::"

echo "::group::Ingress"
page=""
for _ in $(seq 15); do
    page=$(probe "${SUPERVISOR_IP}" / || true)
    grep -qi "ttyd" <<< "${page}" && break
    sleep 2
done
grep -qi "ttyd" <<< "${page}" || { echo "${page}" | head -c 500; fail "ingress did not serve the ttyd page"; }
token=$(probe "${SUPERVISOR_IP}" /token || true)
grep -q '"token"' <<< "${token}" || { echo "${token}"; fail "ingress did not serve /token"; }
denied=$(probe "" / || true)
grep -q '403' <<< "${denied}" || { echo "${denied}"; fail "ingress port answered a client other than ${SUPERVISOR_IP}"; }
echo "::endgroup::"

[[ "$(docker inspect -f '{{.State.Running}}' app)" == "true" ]] || fail "the app exited"
if docker logs app 2>&1 | grep -E '\[(emerg|alert|crit)\]|ERROR'; then
    fail "the app logged errors"
fi
echo "Smoke test passed"
