# Changelog

## 1.0.1

- A dev build (slug ending in `_dev`) publishes under `smart_mqtt_dev` topics, MQTT client ID and unique IDs,
  with " (dev)" after the device name, so it runs next to the stable app with its own devices.

## 1.0.0

- Publishes SMART data of every ATA and NVMe drive that UDisks2 reports to MQTT, with Home Assistant discovery.
