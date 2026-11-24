# https://contributors.home-assistant.io/apps/guides/dockerfile/
ARG BUILD_FROM=ghcr.io/home-assistant/base-python:3.14-alpine3.24
FROM ${BUILD_FROM}

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && rm /tmp/requirements.txt

COPY rootfs /

LABEL \
    org.opencontainers.image.title="Home Assistant App: SMART to MQTT" \
    org.opencontainers.image.description="Publishes disk SMART data from UDisks2 to MQTT with Home Assistant discovery" \
    org.opencontainers.image.source="https://github.com/jimmyhideous/ha-apps" \
    org.opencontainers.image.licenses="MIT"
