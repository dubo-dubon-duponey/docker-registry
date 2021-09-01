# What

Turn-key simple Docker Registry with mDNS, automatic TLS, and configurable minimalistic pull/push ACLs.

# Why

There are many good reasons to maintain one (or multiple) private (internal or public) registry(ies).
Chief among them, latency (both on push, for developers or build systems, and on pull, for nodes that need to redeploy frequently),
but obviously also security (or at least the ability to control it), and confidentiality of your images.

For such small-scale environments, expensive commercial solutions are overblown, and the 
open-source Docker Registry does not provide much by default in terms of access control and security.

## Image features

 * optional mDNS broadcasting (eg: access your registry with `registry.local`)
 * turn-key TLS, either with self-signed certs, or using LetsEncrypt
 * pull can and push can be disabled separately, set to anonymous, or to a specific user
 * multi-architecture:
   * [x] linux/amd64
   * [x] linux/386
   * [x] linux/arm64
   * [x] linux/arm/v7
   * [x] linux/arm/v6
   * [x] linux/ppc64le
   * [x] linux/s390x
 * hardened:
    * [x] image runs read-only
    * [x] image runs with no capabilities (unless you want it on a privileged port)
    * [x] process runs as a non-root user, disabled login, no shell
 * lightweight
    * [x] based on our slim [Debian Bullseye](https://github.com/dubo-dubon-duponey/docker-debian)
    * [x] simple entrypoint script
    * [x] multi-stage build with no installed dependencies for the runtime image
<!--      (libnss3-tools which is required to manipulate certificates) -->
 * observable
    * [x] healthcheck
    * [x] log to stdout
    * [ ] ~~prometheus endpoint~~

## Run

### Local registry with mDNS and anonymous pull

```bash
docker run -d \
    --net bridge \
    --cap-drop ALL \
    --read-only \
    ghcr.io/dubo-dubon-duponey/registry
```

## Acknowledgements

This is based on:
* [Caddy](https://github.com/caddyserver/caddy)
* [Docker Registry](https://github.com/docker/distribution)
* [goello mDNS](https://github.com/dubo-dubon-duponey/goello)

<!--
## Moar?

See [DEVELOP.md](DEVELOP.md)

## Mode: internal

Trust the cert on mac:


```
# TL;DR

## Linux

# Unclear if Debian 10 is the same or not
sudo mkdir -p /etc/docker/certs.d/registry.local:4443
openssl s_client -showcerts -servername registry.local -connect registry.local:4443 </dev/null 2>/dev/null | awk '/BEGIN/,/END/{ if(/BEGIN/){a++}; print}' | sudo tee /etc/docker/certs.d/registry.local:4443/ca.crt
# XXX note that debian 9 requires explicit:
# sudo apt-get install avahi-daemon avahi-discover libnss-mdns

## macOS
openssl s_client -showcerts -servername registry.local -connect registry.local:4443 </dev/null 2>/dev/null | awk '/BEGIN/,/END/{ if(/BEGIN/){a++}; print}' > registry.local.ca.crt
security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain registry.local.ca.crt
# Then restart docker
# [snip]


# Alternatively, you can retrieve the CA from the container if you are on the same host and have access to the container:
docker exec -ti registry cat /certs/pki/authorities/local/root.crt > myca.crt

```

# Caveats

 * pull and push authenticated with different credentials is bonkers right now
 * actually, forget about the openssl shit, need the ROOT CA, not the intermediate...
    -> add a route for the root ca.crt
    /root-ca.crt

-->
