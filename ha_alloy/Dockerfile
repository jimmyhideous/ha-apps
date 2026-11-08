# https://contributors.home-assistant.io/apps/guides/dockerfile/
# Debian base: Alloy's journal reader needs glibc and libsystemd.
ARG BUILD_FROM=ghcr.io/home-assistant/base-debian:bookworm
FROM ${BUILD_FROM}

# GitHub release tag without "v"; updated by Renovate.
ARG ALLOY_VERSION=1.21.2
ARG TARGETARCH

RUN \
    if [ -z "${TARGETARCH}" ]; then \
        echo "TARGETARCH is not set, please use Docker BuildKit for the build." && exit 1; \
    fi \
    && case "${TARGETARCH}" in \
        amd64) alloy_arch="amd64" ;; \
        arm64) alloy_arch="arm64" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" && exit 1 ;; \
    esac \
    && alloy_deb="alloy-${ALLOY_VERSION}-1.${alloy_arch}.deb" \
    && alloy_url="https://github.com/grafana/alloy/releases/download/v${ALLOY_VERSION}" \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl libsystemd0 nginx \
    && cd /tmp \
    && curl -fsSLO "${alloy_url}/${alloy_deb}" \
    && curl -fsSL "${alloy_url}/SHA256SUMS" | grep " ${alloy_deb}\$" | sha256sum -c - \
    && apt-get install -y --no-install-recommends "/tmp/${alloy_deb}" \
    && rm -f "/tmp/${alloy_deb}" /etc/nginx/sites-enabled/default \
    && rm -rf /var/lib/apt/lists/* \
    && /usr/bin/alloy --version \
    && /usr/sbin/nginx -v

COPY rootfs /

LABEL \
    org.opencontainers.image.title="Home Assistant App: HA Alloy" \
    org.opencontainers.image.description="Ships the Home Assistant OS journal to Grafana Loki with Grafana Alloy" \
    org.opencontainers.image.source="https://github.com/jimmyhideous/ha-apps" \
    org.opencontainers.image.licenses="MIT"
