# https://contributors.home-assistant.io/apps/guides/dockerfile/
# Official multi-arch Home Assistant Debian base image (s6-overlay v3 + bashio). Debian, not Alpine: Alloy's
# journal reader needs glibc and libsystemd.
ARG BUILD_FROM=ghcr.io/home-assistant/base-debian:bookworm
FROM ${BUILD_FROM}

# Grafana Alloy release (GitHub tag without the leading "v"). Renovate bumps this line from
# github.com/grafana/alloy releases; the release's .deb is always named alloy-<version>-1.<arch>.deb.
ARG ALLOY_VERSION=1.21.2
ARG TARGETARCH

# Install the Alloy .deb attached to the GitHub release, verified against that release's SHA256SUMS.
# TARGETARCH (amd64/arm64) is set by BuildKit and matches the Debian architecture names of the release assets.
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
    && apt-get install -y --no-install-recommends ca-certificates curl libsystemd0 \
    && cd /tmp \
    && curl -fsSLO "${alloy_url}/${alloy_deb}" \
    && curl -fsSL "${alloy_url}/SHA256SUMS" | grep " ${alloy_deb}\$" | sha256sum -c - \
    && apt-get install -y --no-install-recommends "/tmp/${alloy_deb}" \
    && rm -f "/tmp/${alloy_deb}" \
    && rm -rf /var/lib/apt/lists/* \
    && /usr/bin/alloy --version

# Copy root filesystem (s6-rc service, Alloy pipeline)
COPY rootfs /

LABEL \
    org.opencontainers.image.title="Home Assistant App: Loki Journal Shipper" \
    org.opencontainers.image.description="Ships the Home Assistant OS journal to Grafana Loki with Grafana Alloy" \
    org.opencontainers.image.source="https://github.com/jimmyhideous/ha-apps" \
    org.opencontainers.image.licenses="MIT"
