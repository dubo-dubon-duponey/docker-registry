ARG           BUILDER_BASE=dubodubonduponey/base@sha256:b51f084380bc1bd2b665840317b6f19ccc844ee2fc7e700bf8633d95deba2819
ARG           RUNTIME_BASE=dubodubonduponey/base@sha256:d28e8eed3e87e8dc5afdd56367d3cf2da12a0003d064b5c62405afbe4725ee99

#######################
# Extra builder for healthchecker
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8ca3d255e0c846307bf72740f731e6210c3
ARG           BUILD_TARGET=./cmd/http
ARG           BUILD_OUTPUT=http-health
ARG           BUILD_FLAGS="-s -w"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v \
                -ldflags "$BUILD_FLAGS" -o /dist/boot/bin/"$BUILD_OUTPUT" "$BUILD_TARGET"

#######################
# Goello
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-goello

ARG           GIT_REPO=github.com/dubo-dubon-duponey/goello
ARG           GIT_VERSION=3799b6035dd5c4d5d1c061259241a9bedda810d6
ARG           BUILD_TARGET=./cmd/server
ARG           BUILD_OUTPUT=goello-server
ARG           BUILD_FLAGS="-s -w"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v \
                -ldflags "$BUILD_FLAGS" -o /dist/boot/bin/"$BUILD_OUTPUT" "$BUILD_TARGET"

#######################
# Caddy
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-caddy

# This is 2.4.0
ARG           GIT_REPO=github.com/caddyserver/caddy
ARG           GIT_VERSION=bc2210247861340c644d9825ac2b2860f8c6e12a
ARG           BUILD_TARGET=./cmd/caddy
ARG           BUILD_OUTPUT=caddy
ARG           BUILD_FLAGS="-s -w"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone https://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v \
                -ldflags "$BUILD_FLAGS" -o /dist/boot/bin/"$BUILD_OUTPUT" "$BUILD_TARGET"

#######################
# Main builder
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-main

ARG           GIT_REPO=github.com/docker/distribution
# Feb 10, 2021 - apparently reviving
# ARG           GIT_VERSION=22c074842eaad74036164f95b2182a9d0fe484b5
# May 12, 2021
ARG           GIT_VERSION=c63b580546d309bc085b7402d83370f5f04d2c40
ARG           BUILD_TARGET=./cmd/registry/main.go
ARG           BUILD_OUTPUT=registry
ARG           BUILD_FLAGS="-s -w -X $GIT_REPO/version.Version=$BUILD_VERSION -X $GIT_REPO/version.Revision=$BUILD_REVISION -X $GIT_REPO/version.Package=$GIT_REPO"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v \
                -ldflags "$BUILD_FLAGS" -o /dist/boot/bin/"$BUILD_OUTPUT" "$BUILD_TARGET"

#######################
# Builder assembly
#######################
# hadolint ignore=DL3006
FROM          $BUILDER_BASE                                                                                             AS builder

COPY          --from=builder-healthcheck /dist/boot/bin /dist/boot/bin
COPY          --from=builder-goello /dist/boot/bin /dist/boot/bin
COPY          --from=builder-caddy /dist/boot/bin /dist/boot/bin
COPY          --from=builder-main /dist/boot/bin /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot/bin -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
# hadolint ignore=DL3006
FROM          $RUNTIME_BASE

#USER          root

# Caddy internal pki depend on this to perform certain cert manipulations
# XXX double check this - this is the only image that has it, so either add it everywhere or remove here
# XXX this just? mute the warning about certutil, but is this required?
# not according to mat: https://caddy.community/t/how-to-enable-local-https-using-a-raspberry-pi-3/7467/9
#RUN           apt-get update -qq          && \
#              apt-get install -qq --no-install-recommends \
#                libnss3-tools=2:3.42.1-1+deb10u3 && \
#              apt-get -qq autoremove      && \
#              apt-get -qq clean           && \
#              rm -rf /var/lib/apt/lists/* && \
#              rm -rf /tmp/*               && \
#              rm -rf /var/tmp/*

#USER          dubo-dubon-duponey

COPY          --from=builder --chown=$BUILD_UID:root /dist .

### Front server configuration
# Port to use
ENV           PORT=4443
EXPOSE        4443
# Log verbosity for
ENV           LOG_LEVEL="warn"
# Domain name to serve
ENV           DOMAIN="registry.local"
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt
ENV           TLS="internal"

# Access-control for pull and push
# disabled, anonymous, authenticated
ENV           PULL="anonymous"
# disabled, anonymous, authenticated
ENV           PUSH="disabled"

# Realm in case access is authenticated
ENV           REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           USERNAME=""
ENV           PASSWORD=""

### mDNS broadcasting
# Enable/disable mDNS support
ENV           MDNS_ENABLED=false
# Name is used as a short description for the service
ENV           MDNS_NAME="Registry mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local
ENV           MDNS_HOST="registry"
# Type to advertise
ENV           MDNS_TYPE="_http._tcp"

# Caddy certs will be stored here
VOLUME        /certs

# Caddy uses this
VOLUME        /tmp

# Registry data will be stored here
VOLUME        /data

ENV           HEALTHCHECK_URL=http://127.0.0.1:10000/v2/?healthcheck

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
