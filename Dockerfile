#######################
# Extra builder for healthchecker
#######################
ARG           BUILDER_BASE=dubodubonduponey/base:builder
ARG           RUNTIME_BASE=dubodubonduponey/base:runtime
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8ca3d255e0c846307bf72740f731e6210c3

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
RUN           arch="${TARGETPLATFORM#*/}"; \
              env GOOS=linux GOARCH="${arch%/*}" go build -mod=vendor -v -ldflags "-s -w" -o /dist/boot/bin/http-health ./cmd/http

#######################
# Builder custom
#######################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder

ARG           GIT_REPO=github.com/dubo-dubon-duponey/distribution
ARG           GIT_VERSION=XXX

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
RUN           arch="${TARGETPLATFORM#*/}"; \
              VERSION=$(git describe --match 'v[0-9]*' --dirty='.m' --always); \
              REVISION=$(git rev-parse HEAD)$(if ! git diff --no-ext-diff --quiet --exit-code; then echo .m; fi); \
              PKG=github.com/docker/distribution; \
              FLAGS="-X $PKG/version.Version=$VERSION -X $PKG/version.Revision=$REVISION -X $PKG/version.Package=$PKG"; \
              env GOOS=linux GOARCH="${arch%/*}" go build -mod=vendor -v -ldflags "-s -w $FLAGS" -o /dist/boot/bin/apt-mirror ./cmd/go-apt-mirror/main.go

COPY          --from=builder-healthcheck /dist/boot/bin /dist/boot/bin
RUN           chmod 555 /dist/boot/bin/*

#######################
# Running image
#######################
# hadolint ignore=DL3006
FROM          $RUNTIME_BASE

COPY          --from=builder --chown=$BUILD_UID:root /dist .

#VOLUME [ "/var/lib/aptutil", "/var/spool/go-apt-mirror", "/var/spool/go-apt-cacher"]

#EXPOSE 3142

#WORKDIR "/var/lib/aptutil"
