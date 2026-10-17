# Checkmk for arm64, based on the official Checkmk docker_image/Dockerfile.
# The packages are built from the official sources by
# https://github.com/sergiodadi/check-mk-raspberry
#
# The package to install is pinned per variant in versions.json; build with
# scripts/build.sh <variant>, which passes the entry as build args.
ARG IMAGE_CMK_BASE="ubuntu:24.04"
# hadolint ignore=DL3006
FROM ${IMAGE_CMK_BASE}
LABEL org.opencontainers.image.authors="Jimmy Bristow <jbristow@home-lab.tech>"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Ports:
# 5000 - Serves the Checkmk GUI
# 6557 - Serves Livestatus (if enabled via "omd config")
# 8000 - Agent receiver (agent registration / TLS)
EXPOSE 5000 6557 8000

# When all processes of the site are running everything should be fine
HEALTHCHECK --interval=1m --timeout=5s --start-period=2m \
    CMD omd status || exit 1

# The following variables can be set during container init (docker run -e KEY=val)
ENV CMK_SITE_ID="cmk"
# Set this to "on" to enable livestatus via network
ENV CMK_LIVESTATUS_TCP=""
# A random password will be generated in case you don't set this
ENV CMK_PASSWORD=""
# Specify the FQDN of your relay mail server to sent mails to
ENV MAIL_RELAY_HOST=""
# Set a timezone
ENV TZ=""
# Set this to "on" to write a tarball of the site to /backups before "omd update"
ENV CMK_BACKUP_ON_UPDATE=""
# Add helper variable to better detect when running inside container.
# Used e.g. for omd update
ENV CMK_CONTAINERIZED="TRUE"

COPY docker-entrypoint.sh /
COPY hooks/ /docker-entrypoint.d/
# Starts the entrypoint script and hands over CMD by default
ENTRYPOINT ["/docker-entrypoint.sh"]

# Install the tools the entrypoint needs. Kept separate from the Checkmk
# install so version bumps reuse this layer.
# hadolint ignore=DL3008
RUN set -e \
    && echo "exit 101" > /usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        tzdata \
        postfix \
        libsasl2-modules \
        inetutils-syslogd \
        bsd-mailx \
        gnupg2 \
        openssh-client \
        iputils-ping \
        net-tools \
        git \
    && apt-get clean \
    && rm /usr/sbin/policy-rc.d \
    && rm -rf /var/lib/apt/lists/*

# Pure build time variable declarations (docker build --build-arg KEY=val).
# Values come from versions.json, see scripts/build.sh.
ARG CMK_VERSION
ARG CMK_EDITION
ARG DISTRO_CODENAME
ARG CMK_RELEASE_TAG
ARG CMK_PKG_SHA256
# Additional distro packages, e.g. php8.4-cgi on trixie so apt does not pull
# in libapache2-mod-php to satisfy the php dependency
ARG CMK_EXTRA_PACKAGES=""
ARG CMK_PKG_BASE_URL="https://github.com/sergiodadi/check-mk-raspberry/releases/download"

# Fetch the package, verify it against the pinned checksum and install it
# together with its dependencies.
# hadolint ignore=DL3008,SC2086
RUN set -e \
    && : "${CMK_VERSION:?}" "${CMK_EDITION:?}" "${DISTRO_CODENAME:?}" "${CMK_RELEASE_TAG:?}" "${CMK_PKG_SHA256:?}" \
    && mkdir -p /usr/share/man/man8 \
    && echo "exit 101" > /usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d \
    && export DEBIAN_FRONTEND=noninteractive \
    && PKG_FILE="check-mk-${CMK_EDITION}-${CMK_VERSION}_0.${DISTRO_CODENAME}_$(dpkg --print-architecture).deb" \
    && curl -fsSL -o "/tmp/${PKG_FILE}" "${CMK_PKG_BASE_URL}/${CMK_RELEASE_TAG}/${PKG_FILE}" \
    && echo "${CMK_PKG_SHA256}  /tmp/${PKG_FILE}" | sha256sum -c - \
    && apt-get update \
    && apt-get install -y --no-install-recommends "/tmp/${PKG_FILE}" ${CMK_EXTRA_PACKAGES} \
    && dpkg -i "$(ls /omd/versions/default/share/check_mk/agents/check-mk-agent_*-1_all.deb)" \
    && rm -f "/tmp/${PKG_FILE}" \
    && apt-get clean \
    && rm /usr/sbin/policy-rc.d \
    && rm -rf /var/lib/apt/lists/*

LABEL \
    org.opencontainers.image.title="Checkmk (arm64)" \
    org.opencontainers.image.version="${CMK_VERSION}" \
    org.opencontainers.image.description="Checkmk ${CMK_EDITION} for arm64 devices such as the Raspberry Pi" \
    org.opencontainers.image.source="https://github.com/JzJad/checkmk-arm64-docker" \
    org.opencontainers.image.licenses="GPL-2.0-only"
