# Changelog

## 1.1.1

- Update ghcr.io/home-assistant/base-python to 3.15.

## 1.1.0

- New options `mqtt_ca_cert`, `mqtt_client_cert` and `mqtt_client_key` for an external TLS broker with a private
  CA or client certificates. They name files in the Home Assistant `/ssl` folder, which the app now reads.

## 1.0.1

- A dev build (slug ending in `_dev`) publishes under `smart_mqtt_dev` topics, MQTT client ID and unique IDs,
  with " (dev)" after the device name, so it runs next to the stable app with its own devices.

## 1.0.0

- Publishes SMART data of every ATA and NVMe drive that UDisks2 reports to MQTT, with Home Assistant discovery.
