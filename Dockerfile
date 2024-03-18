ARG           FROM_REGISTRY=docker.io/dubodubonduponey

ARG           FROM_IMAGE_BUILDER=base:builder-bookworm-2024-03-01
ARG           FROM_IMAGE_AUDITOR=base:auditor-bookworm-2024-03-01
ARG           FROM_IMAGE_RUNTIME=base:runtime-bookworm-2024-03-01
ARG           FROM_IMAGE_TOOLS=tools:linux-bookworm-2024-03-01

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools

FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-main

ARG           GIT_REPO=github.com/docker/distribution
# Bumping September 2023
#ARG           GIT_VERSION=v2.8.3
#ARG           GIT_COMMIT=4772604ae973031ab32dd9805a4bccf61d94909f
# Just sick of it. At least the latest main finally have a go.mod
ARG           GIT_VERSION=3cb985c
ARG           GIT_COMMIT=3cb985cac0cc56c643d28083c867f47902a6aae9

ENV           GOFLAGS="-mod=vendor"

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
                dubo-check validate /dist/boot/bin/http-health
RUN           RUNNING=true \
              STATIC=true \
                dubo-check validate /dist/boot/bin/goello-server-ng

RUN           RUNNING=true \
              RO_RELOCATIONS=true \
                dubo-check validate /dist/boot/bin/caddy

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

# Access-control for pull and push
# disabled, anonymous, authenticated
ENV           PULL="anonymous"
# disabled, anonymous, authenticated
ENV           PUSH="disabled"

ENV           _SERVICE_NICK="registry"
ENV           _SERVICE_TYPE="_http._tcp"

COPY          --from=builder --chown=$BUILD_UID:root /dist /

#####
# Global
#####
# Log verbosity (debug, info, warn, error, fatal)
ENV           LOG_LEVEL="warn"
# Domain name to serve
ENV           DOMAIN="$_SERVICE_NICK.local"

#####
# Mod mDNS
#####
# Whether to disable mDNS broadcasting or not
ENV           MOD_MDNS_ENABLED=true
# Name is used as a short description for the service
ENV           MOD_MDNS_NAME="$_SERVICE_NICK display name"
# The service will be annonced and reachable at MOD_MDNS_HOST.local
ENV           MOD_MDNS_HOST="$_SERVICE_NICK"

#####
# Mod mTLS
#####
# Whether to enable client certificate validation or not (Caddy only for now - since ghost would use OPA instead)
ENV           MOD_MTLS_ENABLED=false
# Either require_and_verify or verify_if_given
ENV           MOD_MTLS_MODE="verify_if_given"

#####
# Mod Basic Auth
#####
# Whether to enable basic auth
ENV           MOD_BASICAUTH_ENABLED=false
# Realm displayed for auth
ENV           MOD_BASICAUTH_REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           MOD_BASICAUTH_USERNAME="dubo-dubon-duponey"
ENV           MOD_BASICAUTH_PASSWORD="cmVwbGFjZV9tZV93aXRoX3NvbWV0aGluZwo="

#####
# Mod HTTP
#####
# Whether to disable the HTTP mod altogether
ENV           MOD_HTTP_ENABLED=true
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt
ENV           MOD_HTTP_TLS_MODE="internal"

#####
# Advanced settings
#####
# Service type
ENV           ADVANCED_MOD_MDNS_TYPE="$_SERVICE_TYPE"
# Also announce the service as a workstation (for example for the benefit of coreDNS mDNS)
ENV           ADVANCED_MOD_MDNS_STATION=true
# Root certificate to trust for client cert verification
ENV           ADVANCED_MOD_MTLS_TRUST="/certs/pki/authorities/local/root.crt"
# Ports for http and https - recent changes in docker make it no longer necessary to have caps, plus we have our NET_BIND_SERVICE cap set anyhow - it's 2021, there is no reason to keep on venerating privileged ports
ENV           ADVANCED_MOD_HTTP_PORT=443
ENV           ADVANCED_MOD_HTTP_PORT_INSECURE=80
# By default, tls should be restricted to 1.3 - you may downgrade to 1.2+ for compatibility with older clients (webdav client on macos, older browsers)
ENV           ADVANCED_MOD_HTTP_TLS_MIN=1.3
# Name advertised by Caddy in the server http header
ENV           ADVANCED_MOD_HTTP_SERVER_NAME="DuboDubonDuponey/1.0 (Caddy/2)"
# ACME server to use (for testing)
# Staging
# https://acme-staging-v02.api.letsencrypt.org/directory
# Plain
# https://acme-v02.api.letsencrypt.org/directory
# PKI
# https://pki.local
ENV           ADVANCED_MOD_HTTP_TLS_SERVER="https://acme-v02.api.letsencrypt.org/directory"
# Either disable_redirects or ignore_loaded_certs if one wants the redirects
ENV           ADVANCED_MOD_HTTP_TLS_AUTO=disable_redirects
# Whether to disable TLS and serve only plain old http
ENV           ADVANCED_MOD_HTTP_TLS_ENABLED=true
# Additional domains aliases
ENV           ADVANCED_MOD_HTTP_ADDITIONAL_DOMAINS=""

#####
# Wrap-up
#####
EXPOSE        443
EXPOSE        80

# Caddy certs will be stored here
VOLUME        /certs
# Caddy uses this
VOLUME        /tmp
# Used by the backend service
VOLUME        /data

ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1

