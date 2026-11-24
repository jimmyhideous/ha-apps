# SMART to MQTT

Reads the SMART data that UDisks2 on the host keeps for every ATA and NVMe drive, and publishes it to MQTT with
Home Assistant discovery. Each drive becomes a device with its own sensors. The app talks to UDisks2 over the host
system bus, so it needs no raw disk access and works with protection mode on.

## Installation

1. Set up the MQTT integration with a broker: an MQTT broker app such as **Mosquitto broker**, or an external
   broker.
2. Add the repository `https://github.com/jimmyhideous/ha-apps` (**Settings > Apps > Install app >** menu **> Repositories**).
3. Install **SMART to MQTT**. For an external broker, set `mqtt_host` and its login. Start the app.

## Options

| Option | Default | Description |
|---|---|---|
| `discovery_prefix` | `homeassistant` | Discovery prefix of the MQTT integration. |
| `log_level` | `info` | `debug` logs every reading. |
| `mqtt_host` | unset | External MQTT broker, a hostname or IP address. When empty, the app uses the broker app that the Supervisor reports, with its own login. |
| `mqtt_port` | `1883` | Port of the external broker. |
| `mqtt_username` | unset | Login for the external broker. |
| `mqtt_password` | unset | Password for the external broker. |
| `mqtt_tls` | `false` | Connect to the external broker with TLS, checking its certificate against the system's public CAs. A broker with a private CA isn't supported. |

The app reads SMART data every 10 minutes, the interval at which UDisks2 refreshes it.

## Sensors

Each drive gets the sensors its SMART data supports:

| Sensor | ATA | NVMe | Description |
|---|---|---|---|
| Health | yes | yes | Problem when the drive reports SMART failure, a failing attribute (ATA) or a critical warning (NVMe). |
| Temperature | yes | yes | Current drive temperature. |
| Power-on time | yes | yes | Hours the drive has been powered on. |
| Wear leveling | yes | | Normalized value of the drive's wear attribute (177, 173, 231, 233 or 202, the first one present). It starts at 100 and counts down as the flash wears; its meaning varies by vendor. |
| Endurance used | | yes | Percentage of the rated endurance used. It can pass 100. |
| Available spare | | yes | Remaining spare capacity, in percent. |
| Data written | | yes | Total data written, in TB. |
| Reallocated sectors | yes | | Raw value of attribute 5. |
| Bad sectors | yes | | Bad sectors UDisks2 counts from the drive's attributes. |
| Uncorrectable errors | yes | | Raw value of attribute 187. |
| Interface CRC errors | yes | | Raw value of attribute 199. Rising values usually point to the cable or connector. |
| Media errors | | yes | Unrecovered data integrity errors. |

## MQTT topics

- `smart_mqtt/status`: `online` while the app runs, `offline` when it stops (last will).
- `smart_mqtt/<id>/state`: JSON with the drive's values, retained.
- `<discovery_prefix>/device/smart_mqtt_<id>/config`: device discovery, retained.

A dev build (an app slug ending in `_dev`) uses `smart_mqtt_dev` instead of `smart_mqtt` in every topic, the
MQTT client ID and the unique IDs, and adds " (dev)" to the device names. It runs next to the stable app with its
own devices and entities.

`<id>` is the first 12 hex digits of the SHA-256 hash of the drive's serial number. The serial number itself is
never published or logged.

## Limitations

- Drives that UDisks2 doesn't report with SMART data, such as most USB sticks and some USB enclosures, get no
  sensors.
- UDisks2 doesn't report total data written for ATA drives.
- The app only reads cached values. It never starts a SMART self-test or changes drive settings.
