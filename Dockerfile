ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2022-05-01@sha256:b97738238e9d1423b6de8d5a96f4310ae7039ffa4af19cd6a85f5f70d0faef99
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2022-05-01@sha256:984cf8672b483ca94333b5b37e19a95b115047dee05955767ed5b1bac1140e0c
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2022-05-01@sha256:5e44963d961cf7594cf8a0d1bba98fd5da69d7881cb77c142a43ceab230e87df
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2022-05-01@sha256:6268013e3bd16eaaf7dd15c7689f8740bd00af1149c92795cc42fab4f3c6d07a

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools

FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-main

ARG           GIT_REPO=github.com/docker/distribution
#ARG           GIT_VERSION=6248a88
#ARG           GIT_COMMIT=6248a88d03badbe49c4969f802f5860b6fb2a685
# Borked with recent go - likely to do with it not using go mod yet and not enclined to fix
#ARG           GIT_VERSION=v2.8.1
#ARG           GIT_COMMIT=b5ca020cfbe998e5af3457fda087444cf5116496
ARG           GIT_VERSION=cd51f38
ARG           GIT_COMMIT=cd51f38d537ddef391113dd00d16f9ce8b5f9569

ENV           WITH_BUILD_SOURCE=./cmd/registry/main.go
ENV           WITH_BUILD_OUTPUT=registry

ENV           WITH_LDFLAGS="-X $GIT_REPO/version.Version=$GIT_VERSION -X $GIT_REPO/version.Revision=$GIT_COMMIT -X $GIT_REPO/version.Package=$GIT_REPO"

RUN           git clone --recurse-submodules https://"$GIT_REPO" .; git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download

#######################
# Main builder
#######################
FROM          --platform=$BUILDPLATFORM fetcher-main                                                                    AS builder-main

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
                export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
                export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
                export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
                export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
                [ ! "${ENABLE_STATIC:-}" ] || { \
                  [ ! "${WITH_CGO_NET:-}" ] || { \
                    ENABLE_STATIC=; \
                    LDFLAGS="${LDFLAGS:-} -static-libgcc -static-libstdc++"; \
                  }; \
                  [ "$GOARCH" == "amd64" ] || [ "$GOARCH" == "arm64" ] || [ "${ENABLE_PIE:-}" != true ] || ENABLE_STATIC=; \
                }; \
                WITH_LDFLAGS="${WITH_LDFLAGS:-} -linkmode=external -extld="$CC" -extldflags \"${LDFLAGS:-} ${ENABLE_STATIC:+-static}${ENABLE_PIE:+-pie}\""; \
                WITH_TAGS="${WITH_TAGS:-} cgo ${ENABLE_STATIC:+static static_build}"; \
              }; \
              go build -ldflags "-s -w -v ${WITH_LDFLAGS:-}" -tags "${WITH_TAGS:-} net${WITH_CGO_NET:+c}go osusergo" -o /dist/boot/bin/"$WITH_BUILD_OUTPUT" "$WITH_BUILD_SOURCE"

#######################
# Builder assembly
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS builder

COPY          --from=builder-main   /dist/boot          /dist/boot

COPY          --from=builder-tools  /boot/bin/goello-server-ng /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/caddy         /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/http-health   /dist/boot/bin

RUN           setcap 'cap_net_bind_service+ep' /dist/boot/bin/caddy

RUN           RUNNING=true \
              STATIC=true \
                dubo-check validate /dist/boot/bin/*

RUN           RO_RELOCATIONS=true \
                dubo-check validate /dist/boot/bin/caddy

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

#USER          root

# Caddy internal pki depend on this to perform certain cert manipulations
# XXX double check this - this is the only image that has it, so either add it everywhere or remove here
# XXX this just? mute the warning about certutil, but is this required?
# not according to mat: https://caddy.community/t/how-to-enable-local-https-using-a-raspberry-pi-3/7467/9
#              apt-get update -qq          && \
#              apt-get install -qq --no-install-recommends libnss3-tools=2:3.61-1 && \
#              apt-get -qq autoremove      && \
#              apt-get -qq clean           && \
#              rm -rf /var/lib/apt/lists/* && \
#              rm -rf /tmp/*               && \
#              rm -rf /var/tmp/*

#USER          dubo-dubon-duponey

# Access-control for pull and push
# disabled, anonymous, authenticated
ENV           PULL="anonymous"
# disabled, anonymous, authenticated
ENV           PUSH="disabled"

ENV           _SERVICE_NICK="registry"
ENV           _SERVICE_TYPE="http"

COPY          --from=builder --chown=$BUILD_UID:root /dist /

### Front server configuration
## Advanced settings that usually should not be changed
# Ports for http and https - recent changes in docker make it no longer necessary to have caps, plus we have our NET_BIND_SERVICE cap set anyhow - it's 2021, there is no reason to keep on venerating privileged ports
ENV           ADVANCED_PORT_HTTPS=443
ENV           ADVANCED_PORT_HTTP=80
EXPOSE        443
EXPOSE        80
# By default, tls should be restricted to 1.3 - you may downgrade to 1.2+ for compatibility with older clients (webdav client on macos, older browsers)
ENV           ADVANCED_TLS_MIN=1.3
# Name advertised by Caddy in the server http header
ENV           ADVANCED_SERVER_NAME="DuboDubonDuponey/1.0 (Caddy/2) [$_SERVICE_NICK]"
# Root certificate to trust for mTLS - this is not used if MTLS is disabled
ENV           ADVANCED_MTLS_TRUST="/certs/mtls_ca.crt"
# Log verbosity for
ENV           LOG_LEVEL="warn"
# Whether to start caddy at all or not
ENV           PROXY_HTTPS_ENABLED=true
# Domain name to serve
ENV           DOMAIN="$_SERVICE_NICK.local"
ENV           ADDITIONAL_DOMAINS="https://*.debian.org"
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt - use "" to disable TLS entirely
ENV           TLS="internal"
# Issuer name to appear in certificates
#ENV           TLS_ISSUER="Dubo Dubon Duponey"
# Either disable_redirects or ignore_loaded_certs if one wants the redirects
ENV           TLS_AUTO=disable_redirects
# Staging
# https://acme-staging-v02.api.letsencrypt.org/directory
# Plain
# https://acme-v02.api.letsencrypt.org/directory
# PKI
# https://pki.local
ENV           TLS_SERVER="https://acme-v02.api.letsencrypt.org/directory"
# Either require_and_verify or verify_if_given, or "" to disable mTLS altogether
ENV           MTLS="require_and_verify"
# Realm for authentication - set to "" to disable authentication entirely
ENV           AUTH="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           AUTH_USERNAME="dubo-dubon-duponey"
ENV           AUTH_PASSWORD="cmVwbGFjZV9tZV93aXRoX3NvbWV0aGluZwo="
### mDNS broadcasting
# Whether to enable MDNS broadcasting or not
ENV           MDNS_ENABLED=true
# Type to advertise
ENV           MDNS_TYPE="_$_SERVICE_TYPE._tcp"
# Name is used as a short description for the service
ENV           MDNS_NAME="$_SERVICE_NICK mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local (set to empty string to disable mDNS announces entirely)
ENV           MDNS_HOST="$_SERVICE_NICK"
# Also announce the service as a workstation (for example for the benefit of coreDNS mDNS)
ENV           MDNS_STATION=true
# Caddy certs will be stored here
VOLUME        /certs
# Caddy uses this
VOLUME        /tmp
# Used by the backend service
VOLUME        /data
ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1

