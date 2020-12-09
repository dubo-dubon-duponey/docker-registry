#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

# Ensure the data folder is writable
[ -w "/data" ] || {
  >&2 printf "/data is not writable. Check your mount permissions.\n"
  exit 1
}

[ -w "/certs" ] || {
  >&2 printf "/certs is not writable. Check your mount permissions.\n"
  exit 1
}

[ -w "/tmp" ] || {
  >&2 printf "/tmp is not writable. Check your mount permissions.\n"
  exit 1
}

# Given how the caddy conf is set right now, we cannot have these be not set, so, stuff in randomized shit in there
SALT="${SALT:-"$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64 | base64)"}"
USERNAME="${USERNAME:-"$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)"}"
PASSWORD="${PASSWORD:-$(caddy hash-password -algorithm bcrypt -salt "$SALT" -plaintext "$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)")}"

# Set registry log level
export REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/data
export REGISTRY_LOG_LEVEL="${LOG_LEVEL:-info}"
export REGISTRY_HTTP_ADDR="${REGISTRY_HTTP_ADDR:-127.0.0.1:5000}"
export REGISTRY_HTTP_SECRET="${REGISTRY_HTTP_SECRET:-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)}"

# Make sure this defaults to lockdown if not set explicitly
PULL="${PULL:-anonymous}"
PUSH="${PUSH:-disabled}"
# Disabled pull (for maintenance, the only case where this makes sense) implies disabled push
[ "$PULL" != "disabled" ] || PUSH="disabled"

case "${1:-}" in
  # Short hand helper to generate password hashs
  "hash")
    shift
    # Interactive.
    echo "Going to generate a password hash with salt: $SALT"
    caddy hash-password -algorithm bcrypt -salt "$SALT"
    exit
  ;;
esac

# Bonjour the container
if [ "${MDNS:-}" == enabled ]; then
  goello-server -name "$MDNS_NAME" -host "$MDNS_HOST" -port "$PORT" -type "$MDNS_TYPE" &
fi

# Trick caddy into using the proper location for shit... still, /tmp keeps on being used (possibly by the pki lib?)
HOME=/data/caddy-home caddy run -config /config/caddy/main.conf --adapter caddyfile &

# Run once configured
exec registry serve /config/registry/main.yml
