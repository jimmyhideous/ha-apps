#!/usr/bin/env bash
# Integration test: runs the app against a stand-in Supervisor API, a private D-Bus system bus with a stand-in
# UDisks2 (tests/fake_udisks2.py) and a Mosquitto broker, then checks the discovery and state messages, that no
# serial number is published, the offline message on stop, and a start with an external broker (mqtt_host).
#
# Usage: integration.sh <image>   (Ubuntu runner with Docker)
set -euo pipefail

IMAGE="$1"
TESTS="$(cd "$(dirname "$0")" && pwd)"
DBUS_IMAGE="alpine:3.24"
MOSQUITTO_IMAGE="eclipse-mosquitto:2.0.23"
BUSYBOX_IMAGE="busybox:1.37.0"
NET="smart-mqtt-integration"
BUS_VOLUME="smart-mqtt-integration-bus"
BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"
DATA="$(mktemp -d)"

cleanup() {
    echo "::group::app log"; docker logs app 2>&1 || true; echo "::endgroup::"
    echo "::group::udisks log"; docker logs udisks 2>&1 || true; echo "::endgroup::"
    docker rm -f app udisks dbus mosquitto supervisor >/dev/null 2>&1 || true
    docker volume rm "${BUS_VOLUME}" >/dev/null 2>&1 || true
    docker network rm "${NET}" >/dev/null 2>&1 || true
    sudo rm -rf "${DATA}"
}
trap cleanup EXIT

fail() { echo "::error::$*"; exit 1; }

# Prints every retained message under the app's topics as "topic payload" lines.
retained() {
    docker run --rm --network "${NET}" "${MOSQUITTO_IMAGE}" \
        mosquitto_sub -h mosquitto -t 'homeassistant/device/#' -t 'smart_mqtt/#' -v --retained-only -W 3 2>/dev/null || true
}

# Prints the payload of one topic from the retained messages in $messages.
payload() { awk -v t="$1" '$1 == t { sub(/^[^ ]+ /, ""); print }' <<< "${messages}"; }

hash12() { printf '%s' "$1" | sha256sum | cut -c1-12; }

# Starts a new app container, as the Supervisor does on every start; bashio caches API answers in /tmp.
start_app() {
    docker rm -f app >/dev/null 2>&1 || true
    docker run -d --name app --network "${NET}" -e SUPERVISOR_TOKEN=test \
        -e DBUS_SYSTEM_BUS_ADDRESS="${BUS_ADDRESS}" -v "${BUS_VOLUME}:/run/dbus" -v "${DATA}:/data" "${IMAGE}" >/dev/null
}

check_app_errors() {
    if docker logs app 2>&1 | grep -E 'Traceback|ERROR'; then
        fail "the app logged errors"
    fi
}

# Writes the app's options (JSON on stdin) to /data/options.json (read by the publisher) and to the stand-in
# Supervisor's options endpoint (read by bashio::config).
set_options() {
    local options
    options="$(cat)"
    sudo mkdir -p "${DATA}/www/addons/self/options" "${DATA}/www/apps/self/options"
    echo "${options}" | sudo tee "${DATA}/options.json" >/dev/null
    for api in addons apps; do
        echo "{\"result\": \"ok\", \"data\": ${options}}" | sudo tee "${DATA}/www/${api}/self/options/config" >/dev/null
    done
}

echo "::group::Start the broker, the system bus and the stand-in UDisks2"
# bashio reaches the Supervisor by the name "supervisor", so the network needs no fixed addresses.
docker network create "${NET}" >/dev/null
docker volume create "${BUS_VOLUME}" >/dev/null
docker run -d --name mosquitto --network "${NET}" "${MOSQUITTO_IMAGE}" mosquitto -c /mosquitto-no-auth.conf >/dev/null
docker run -d --name dbus --network "${NET}" -v "${BUS_VOLUME}:/run/dbus" "${DBUS_IMAGE}" sh -euc '
    apk add --no-cache -q dbus
    cat > /tmp/bus.conf <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>system</type>
  <listen>unix:path=/run/dbus/system_bus_socket</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow user="*"/>
    <allow own="*"/>
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
  </policy>
</busconfig>
EOF
    exec dbus-daemon --nofork --nopidfile --config-file=/tmp/bus.conf' >/dev/null
bus_ready=""
for _ in $(seq 60); do
    docker run --rm -v "${BUS_VOLUME}:/run/dbus" "${BUSYBOX_IMAGE}" test -S /run/dbus/system_bus_socket && { bus_ready=1; break; }
    sleep 1
done
[[ -n "${bus_ready}" ]] || { docker logs dbus 2>&1 | tail -20; fail "the system bus did not start"; }
docker run -d --name udisks --network none -v "${BUS_VOLUME}:/run/dbus" -v "${TESTS}:/tests:ro" \
    -e DBUS_SYSTEM_BUS_ADDRESS="${BUS_ADDRESS}" --entrypoint python3 "${IMAGE}" /tests/fake_udisks2.py >/dev/null
ready=""
for _ in $(seq 30); do
    grep -q "fake UDisks2 ready" <<< "$(docker logs udisks 2>&1)" && { ready=1; break; }
    sleep 1
done
[[ -n "${ready}" ]] || fail "the stand-in UDisks2 did not start"
echo "::endgroup::"

echo "::group::Start the stand-in Supervisor and the app"
mkdir -p "${DATA}/www/services"
echo '{"result": "ok", "data": {"host": "mosquitto", "port": 1883, "ssl": false, "protocol": "3.1.1",
    "username": "addons", "password": "test"}}' > "${DATA}/www/services/mqtt"
echo '{"discovery_prefix": "homeassistant", "log_level": "debug", "mqtt_port": 1883, "mqtt_tls": false}' | set_options
sudo chown -R root:root "${DATA}"
sudo chmod 755 "${DATA}"
docker run -d --name supervisor --network "${NET}" -v "${DATA}/www:/www:ro" "${BUSYBOX_IMAGE}" \
    httpd -f -v -p 80 -h /www >/dev/null
start_app
echo "::endgroup::"

echo "::group::Discovery and state"
ata_id="$(hash12 TESTSERIAL0001)"
nvme_id="$(hash12 TESTSERIAL0002)"
messages=""
for _ in $(seq 30); do
    messages="$(retained)"
    grep -q "^smart_mqtt/${ata_id}/state " <<< "${messages}" && grep -q "^smart_mqtt/${nvme_id}/state " <<< "${messages}" && break
    sleep 2
done
echo "${messages}"
[[ "$(payload smart_mqtt/status)" == "online" ]] || fail "smart_mqtt/status is not online"
grep -q "Using the MQTT broker app: mosquitto:1883" <<< "$(docker logs app 2>&1)" ||
    fail "the app did not use the broker app from the services API"

ata_state="$(payload "smart_mqtt/${ata_id}/state")"
jq -e '. == {"problem": "OFF", "temperature": 40.0, "power_on_hours": 6021, "bad_sectors": 0,
    "reallocated_sectors": 0, "uncorrectable_errors": 0, "crc_errors": 0, "wear_leveling": 81}' \
    <<< "${ata_state}" >/dev/null || fail "unexpected ATA state: ${ata_state}"
nvme_state="$(payload "smart_mqtt/${nvme_id}/state")"
jq -e '. == {"problem": "OFF", "temperature": 34.9, "power_on_hours": 1234, "endurance_used": 3,
    "available_spare": 100, "media_errors": 0, "data_written": 12.345}' \
    <<< "${nvme_state}" >/dev/null || fail "unexpected NVMe state: ${nvme_state}"

ata_config="$(payload "homeassistant/device/smart_mqtt_${ata_id}/config")"
jq -e --arg id "${ata_id}" '
    .dev.ids == ["smart_mqtt_" + $id] and .dev.mdl == "Micron 1100 SATA 256GB" and (.dev | has("mf") | not)
    and .stat_t == "smart_mqtt/" + $id + "/state" and .avty_t == "smart_mqtt/status"
    and (.cmps | keys) == ["bad_sectors", "crc_errors", "power_on_hours", "problem", "reallocated_sectors",
        "temperature", "uncorrectable_errors", "wear_leveling"]
    and .cmps.problem.p == "binary_sensor" and .cmps.problem.dev_cla == "problem"
    and .cmps.temperature.uniq_id == "smart_mqtt_" + $id + "_temperature"
    and .cmps.temperature.unit_of_meas == "°C" and .cmps.temperature.val_tpl == "{{ value_json.temperature }}"' \
    <<< "${ata_config}" >/dev/null || fail "unexpected ATA discovery config: ${ata_config}"
nvme_config="$(payload "homeassistant/device/smart_mqtt_${nvme_id}/config")"
jq -e '.cmps.data_written.dev_cla == "data_size" and .cmps.data_written.unit_of_meas == "TB"
    and .cmps.endurance_used.unit_of_meas == "%"' \
    <<< "${nvme_config}" >/dev/null || fail "unexpected NVMe discovery config: ${nvme_config}"

[[ "$(grep -c '^homeassistant/device/' <<< "${messages}")" -eq 2 ]] || fail "expected discovery for 2 drives"
if grep -q TESTSERIAL <<< "${messages}$(docker logs app 2>&1)"; then
    fail "a serial number reached MQTT or the log"
fi
echo "::endgroup::"

echo "::group::Stop"
docker stop app >/dev/null
messages="$(retained)"
[[ "$(payload smart_mqtt/status)" == "offline" ]] || fail "smart_mqtt/status is not offline after stop"
echo "::endgroup::"

echo "::group::External broker"
# No broker app in the services API: the app must use mqtt_host.
sudo rm "${DATA}/www/services/mqtt"
echo '{"discovery_prefix": "homeassistant", "log_level": "info", "mqtt_host": "mosquitto", "mqtt_port": 1883,
    "mqtt_username": "external", "mqtt_password": "test", "mqtt_tls": false}' | set_options
check_app_errors
start_app
for _ in $(seq 30); do
    messages="$(retained)"
    [[ "$(payload smart_mqtt/status)" == "online" ]] && break
    sleep 2
done
[[ "$(payload smart_mqtt/status)" == "online" ]] || fail "smart_mqtt/status is not online with mqtt_host"
grep -q "Using the MQTT broker from mqtt_host: mosquitto:1883" <<< "$(docker logs app 2>&1)" ||
    fail "the app did not use mqtt_host"
echo "::endgroup::"

check_app_errors
echo "Integration test passed"
