# Home Assistant App: Loki Journal Shipper

_Ships the Home Assistant OS journal to Grafana Loki with Grafana Alloy._

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]

Ships the Home Assistant OS journal (Core, Supervisor, every app container and the OS itself) to
[Grafana Loki](https://grafana.com/oss/loki/) using the official [Grafana Alloy](https://grafana.com/docs/alloy/latest/).

The only privilege it asks for is read access to the host journal (`journald: true`), and Alloy runs under its
own AppArmor profile.

See the **Documentation** tab for options and labels.

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
