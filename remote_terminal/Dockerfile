# https://contributors.home-assistant.io/apps/guides/dockerfile/
ARG BUILD_FROM=ghcr.io/home-assistant/base-debian:bookworm
FROM ${BUILD_FROM}

# GitHub release tag; Debian has no ttyd package, so the static release binary is used.
ARG TTYD_VERSION=1.7.7
ARG TARGETARCH

RUN \
    if [ -z "${TARGETARCH}" ]; then \
        echo "TARGETARCH is not set, please use Docker BuildKit for the build." && exit 1; \
    fi \
    && case "${TARGETARCH}" in \
        amd64) ttyd_arch="x86_64" ;; \
        arm64) ttyd_arch="aarch64" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" && exit 1 ;; \
    esac \
    && ttyd_url="https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}" \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl nginx openssh-client \
    && cd /tmp \
    && curl -fsSLO "${ttyd_url}/ttyd.${ttyd_arch}" \
    && curl -fsSL "${ttyd_url}/SHA256SUMS" | grep " ttyd.${ttyd_arch}\$" | sha256sum -c - \
    && install -m 755 "/tmp/ttyd.${ttyd_arch}" /usr/local/bin/ttyd \
    && rm -f "/tmp/ttyd.${ttyd_arch}" /etc/nginx/sites-enabled/default \
    && rm -rf /var/lib/apt/lists/* \
    && ttyd --version \
    && /usr/sbin/nginx -v

COPY rootfs /

LABEL \
    org.opencontainers.image.title="Home Assistant App: Remote Terminal" \
    org.opencontainers.image.description="Web terminal that opens an SSH session on another host" \
    org.opencontainers.image.source="https://github.com/jimmyhideous/ha-apps" \
    org.opencontainers.image.licenses="MIT"
