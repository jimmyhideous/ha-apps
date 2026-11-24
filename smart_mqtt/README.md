# Home Assistant App: SMART to MQTT

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]

Disk health sensors in Home Assistant. The app reads SMART data of the host's ATA and NVMe drives from UDisks2 and
publishes it to MQTT with discovery, so each drive appears as a device with health, temperature and wear sensors.
It needs no raw disk access and runs with protection mode on.

Options and setup: **Documentation** tab.

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
