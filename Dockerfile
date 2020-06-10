ARG           BUILDER_BASE=dubodubonduponey/base:builder
ARG           RUNTIME_BASE=dubodubonduponey/base:runtime

#######################
# Extra builder for healthchecker
#######################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8ca3d255e0c846307bf72740f731e6210c3

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
RUN           arch="${TARGETPLATFORM#*/}"; \
              env GOOS=linux GOARCH="${arch%/*}" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/http-health ./cmd/http

#######################
# Builder custom
#######################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder

ARG           GIT_REPO=github.com/docker/distribution
# That's 2.7.1
ARG           GIT_VERSION=2461543d988979529609e8cb6fca9ca190dc48da

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
RUN           arch="${TARGETPLATFORM#*/}"; \
              VERSION=$(git describe --match 'v[0-9]*' --dirty='.m' --always); \
              REVISION=$(git rev-parse HEAD)$(if ! git diff --no-ext-diff --quiet --exit-code; then echo .m; fi); \
              PKG=github.com/docker/distribution; \
              FLAGS="-X $PKG/version.Version=$VERSION -X $PKG/version.Revision=$REVISION -X $PKG/version.Package=$PKG"; \
              env GOOS=linux GOARCH="${arch%/*}" go build -v -ldflags "-s -w $FLAGS" -o /dist/boot/bin/registry ./cmd/registry/main.go

COPY          --from=builder-healthcheck /dist/boot/bin /dist/boot/bin
RUN           chmod 555 /dist/boot/bin/*

#######################
# Running image
#######################
# hadolint ignore=DL3006
FROM          $RUNTIME_BASE

COPY          --from=builder --chown=$BUILD_UID:root /dist .

EXPOSE        5000

VOLUME        /data

ENV           HEALTHCHECK_URL=http://127.0.0.1:5000/v2/

HEALTHCHECK   --interval=30s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1

