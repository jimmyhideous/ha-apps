"""Publish disk SMART data from UDisks2 on the host system bus to MQTT, with Home Assistant MQTT discovery.

UDisks2 refreshes SMART data on its own schedule, so the publisher only reads the cached values and never starts a
SMART update or self-test. Topic names and unique IDs use a hash of the serial number; the serial itself is never
published or logged.
"""

import asyncio
import hashlib
import json
import logging
import os
import signal

import paho.mqtt.client as mqtt
from dbus_fast import BusType, Message, MessageType
from dbus_fast.aio import MessageBus

UDISKS = "org.freedesktop.UDisks2"
DRIVE = f"{UDISKS}.Drive"
ATA = f"{UDISKS}.Drive.Ata"
NVME = f"{UDISKS}.NVMe.Controller"
# Base of every topic, MQTT client ID, device ID and unique ID. The run script sets smart_mqtt_dev for a dev build, so
# it can run next to the stable app without sharing devices or entities.
TOPIC = os.environ.get("SMART_MQTT_TOPIC", "smart_mqtt")
DEV_BUILD = TOPIC.endswith("_dev")
AVAILABILITY_TOPIC = f"{TOPIC}/status"
APP_URL = "https://github.com/jimmyhideous/ha-apps/tree/main/smart_mqtt"
KELVIN_OFFSET = 273.15
SECONDS_PER_HOUR = 3600
BYTES_PER_TB = 10**12
# UDisks2 refreshes SMART data about every 10 minutes; reading more often repeats the same values.
READ_INTERVAL_SECONDS = 600

ATA_REALLOCATED_SECTORS = 0x05
ATA_REPORTED_UNCORRECTABLE = 0xBB
ATA_CRC_ERRORS = 0xC7
# Vendor-specific ATA attributes whose normalized value counts down from 100 as the flash wears, in lookup order.
ATA_WEAR_ATTRIBUTES = (0xB1, 0xAD, 0xE7, 0xE9, 0xCA)
# Fields of one SmartGetAttributes entry: (id, name, flags, value, worst, threshold, pretty, pretty_unit, expansion).
ATA_NORMALIZED = 3
ATA_PRETTY = 6

# State key: (component, name, unit, device_class, state_class)
SENSORS = {
    "problem": ("binary_sensor", "Health", None, "problem", None),
    "temperature": ("sensor", "Temperature", "°C", "temperature", "measurement"),
    "power_on_hours": ("sensor", "Power-on time", "h", "duration", "total_increasing"),
    "wear_leveling": ("sensor", "Wear leveling", "%", None, "measurement"),
    "endurance_used": ("sensor", "Endurance used", "%", None, "measurement"),
    "available_spare": ("sensor", "Available spare", "%", None, "measurement"),
    "data_written": ("sensor", "Data written", "TB", "data_size", "total_increasing"),
    "reallocated_sectors": ("sensor", "Reallocated sectors", None, None, "measurement"),
    "bad_sectors": ("sensor", "Bad sectors", None, None, "measurement"),
    "uncorrectable_errors": ("sensor", "Uncorrectable errors", None, None, "measurement"),
    "crc_errors": ("sensor", "Interface CRC errors", None, None, "measurement"),
    "media_errors": ("sensor", "Media errors", None, None, "measurement"),
}

log = logging.getLogger("smart_mqtt")


async def call(bus, path, interface, member, signature="", body=()):
    """Call a UDisks2 method and return the first value of the reply."""
    reply = await bus.call(
        Message(destination=UDISKS, path=path, interface=interface, member=member, signature=signature, body=list(body))
    )
    if reply.message_type == MessageType.ERROR:
        raise RuntimeError(f"{interface}.{member}: {reply.error_name} {reply.body}")
    return reply.body[0]


def unwrap(variants):
    return {key: variant.value for key, variant in variants.items()}


def temperature(kelvin):
    """Return degrees Celsius, or None when the drive reports no temperature (0 K)."""
    return round(kelvin - KELVIN_OFFSET, 1) if kelvin > 0 else None


def ata_state(props, attributes):
    by_id = {attribute[0]: attribute for attribute in attributes}
    failing = props["SmartFailing"] or props["SmartNumAttributesFailing"] > 0
    state = {
        "problem": "ON" if failing else "OFF",
        "temperature": temperature(props["SmartTemperature"]),
        "power_on_hours": props["SmartPowerOnSeconds"] // SECONDS_PER_HOUR,
        "bad_sectors": props["SmartNumBadSectors"],
    }
    for key, attribute_id in (
        ("reallocated_sectors", ATA_REALLOCATED_SECTORS),
        ("uncorrectable_errors", ATA_REPORTED_UNCORRECTABLE),
        ("crc_errors", ATA_CRC_ERRORS),
    ):
        if attribute_id in by_id:
            state[key] = by_id[attribute_id][ATA_PRETTY]
    # A normalized value below 0 means the drive doesn't report one.
    state["wear_leveling"] = next(
        (
            by_id[i][ATA_NORMALIZED]
            for i in ATA_WEAR_ATTRIBUTES
            if i in by_id and by_id[i][ATA_NORMALIZED] >= 0
        ),
        None,
    )
    return state


def nvme_state(props, attributes):
    state = {
        "problem": "ON" if props["SmartCriticalWarning"] else "OFF",
        "temperature": temperature(props["SmartTemperature"]),
        "power_on_hours": props["SmartPowerOnHours"],
        "endurance_used": attributes.get("percent_used"),
        "available_spare": attributes.get("avail_spare"),
        "media_errors": attributes.get("media_errors"),
    }
    # libblockdev reports total_data_written in bytes and leaves it out when it is 0.
    if "total_data_written" in attributes:
        state["data_written"] = round(attributes["total_data_written"] / BYTES_PER_TB, 3)
    return state


async def read_drives(bus):
    """Return (drive_id, drive properties, state) for every drive with SMART data."""
    objects = await call(bus, "/org/freedesktop/UDisks2", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects")
    drives = []
    for path, interfaces in objects.items():
        if DRIVE not in interfaces:
            continue
        drive = unwrap(interfaces[DRIVE])
        drive_id = hashlib.sha256((drive["Serial"] or drive["WWN"] or drive["Id"]).encode()).hexdigest()[:12]
        try:
            if ATA in interfaces:
                props = unwrap(interfaces[ATA])
                if not (props["SmartSupported"] and props["SmartEnabled"] and props["SmartUpdated"]):
                    continue
                state = ata_state(props, await call(bus, path, ATA, "SmartGetAttributes", "a{sv}", [{}]))
            elif NVME in interfaces:
                props = unwrap(interfaces[NVME])
                if not props["SmartUpdated"]:
                    continue
                attributes = unwrap(await call(bus, path, NVME, "SmartGetAttributes", "a{sv}", [{}]))
                state = nvme_state(props, attributes)
            else:
                continue
        except RuntimeError as err:
            log.warning("Skipping %s (%s): %s", drive["Model"], drive_id, err)
            continue
        drives.append((drive_id, drive, {key: value for key, value in state.items() if value is not None}))
    return drives


def discovery_config(drive_id, drive, keys):
    """Return the Home Assistant device discovery payload for one drive."""
    components = {}
    for key in keys:
        component, name, unit, device_class, state_class = SENSORS[key]
        config = {
            "p": component,
            "name": name,
            "uniq_id": f"{TOPIC}_{drive_id}_{key}",
            "val_tpl": f"{{{{ value_json.{key} }}}}",
            "unit_of_meas": unit,
            "dev_cla": device_class,
            "stat_cla": state_class,
        }
        components[key] = {option: value for option, value in config.items() if value is not None}
    device = {
        "ids": [f"{TOPIC}_{drive_id}"],
        "name": (drive["Model"] or "Disk") + (" (dev)" if DEV_BUILD else ""),
        "mf": drive["Vendor"],
        "mdl": drive["Model"],
        "sw": drive["Revision"],
    }
    return {
        "dev": {option: value for option, value in device.items() if value},
        "o": {"name": "SMART to MQTT", "url": APP_URL},
        "avty_t": AVAILABILITY_TOPIC,
        "stat_t": f"{TOPIC}/{drive_id}/state",
        "cmps": components,
    }


def connect_mqtt():
    # QoS 1 messages published before the broker accepts the connection wait in paho's queue.
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=TOPIC)
    if os.environ.get("MQTT_USERNAME"):
        client.username_pw_set(os.environ["MQTT_USERNAME"], os.environ.get("MQTT_PASSWORD") or None)
    if os.environ.get("MQTT_TLS") == "true":
        # Unset files: the system's public CAs and no client certificate.
        client.tls_set(
            ca_certs=os.environ.get("MQTT_CA_CERT") or None,
            certfile=os.environ.get("MQTT_CLIENT_CERT") or None,
            keyfile=os.environ.get("MQTT_CLIENT_KEY") or None,
        )
    client.will_set(AVAILABILITY_TOPIC, "offline", qos=1, retain=True)
    client.on_connect = lambda c, userdata, flags, reason, props: c.publish(
        AVAILABILITY_TOPIC, "online", qos=1, retain=True
    )
    client.connect(os.environ["MQTT_HOST"], int(os.environ["MQTT_PORT"]))
    client.loop_start()
    return client


async def main():
    with open("/data/options.json", encoding="utf-8") as f:
        options = json.load(f)
    logging.basicConfig(level=options["log_level"].upper(), format="%(asctime)s %(levelname)s: %(message)s")
    prefix = options["discovery_prefix"]

    client = connect_mqtt()
    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    stop = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        asyncio.get_running_loop().add_signal_handler(sig, stop.set)

    announced = {}
    while not stop.is_set():
        drives = await read_drives(bus)
        if not drives:
            log.warning("UDisks2 reports no drive with SMART data")
        for drive_id, drive, state in drives:
            keys = sorted(state)
            if announced.get(drive_id) != keys:
                config = discovery_config(drive_id, drive, keys)
                client.publish(f"{prefix}/device/{TOPIC}_{drive_id}/config", json.dumps(config), qos=1, retain=True)
                announced[drive_id] = keys
                log.info("Announced %s (%s): %s", drive["Model"], drive_id, ", ".join(keys))
            client.publish(f"{TOPIC}/{drive_id}/state", json.dumps(state), qos=1, retain=True)
            log.debug("%s (%s): %s", drive["Model"], drive_id, state)
        try:
            await asyncio.wait_for(stop.wait(), READ_INTERVAL_SECONDS)
        except TimeoutError:
            pass

    client.publish(AVAILABILITY_TOPIC, "offline", qos=1, retain=True).wait_for_publish(5)
    client.disconnect()
    client.loop_stop()
    bus.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
