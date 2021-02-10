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

# Helpers
case "${1:-}" in
  # Short hand helper to generate password hash
  "hash")
    shift
    # Interactive.
    echo "Going to generate a password hash with salt: $SALT"
    caddy hash-password -algorithm bcrypt -salt "$SALT"
    exit
  ;;
  # Helper to get the ca.crt out (once initialized)
  "cert")
    if [ "$TLS" != internal ]; then
      echo "Your server is not configured in self-signing mode. This command is a no-op in that case."
      exit 1
    fi
    if [ ! -e "/certs/pki/authorities/local/root.crt" ]; then
      echo "No root certificate installed or generated. Run the container so that a cert is generated, or provide one at runtime."
      exit 1
    fi
    cat /certs/pki/authorities/local/root.crt
    exit
  ;;
esac

# Given how the caddy conf is set right now, we cannot have these be not set, so, stuff in randomized shit in there
readonly SALT="${SALT:-"$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64 | base64)"}"
readonly USERNAME="${USERNAME:-"$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)"}"
readonly PASSWORD="${PASSWORD:-$(caddy hash-password -algorithm bcrypt -salt "$SALT" -plaintext "$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)")}"

# Bonjour the container if asked to
if [ "${MDNS_ENABLED:-}" == true ]; then
  goello-server -name "$MDNS_NAME" -host "$MDNS_HOST" -port "$PORT" -type "$MDNS_TYPE" &
fi

# Make sure this defaults to lockdown if not set explicitly
PULL="${PULL:-anonymous}"
PUSH="${PUSH:-disabled}"
# Disabled pull (for maintenance, the only case where this makes sense) implies disabled push
[ "$PULL" != "disabled" ] || PUSH="disabled"


# Override registry config proper
export REGISTRY_LOG_LEVEL="${LOG_LEVEL:-info}"
export REGISTRY_HTTP_SECRET="${REGISTRY_HTTP_SECRET:-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)}"
export REGISTRY_HTTP_ADDR="${REGISTRY_HTTP_ADDR:-127.0.0.1:5000}"

# Sugar for garbage collection
if [ "${1:-}" == "garbage-collect" ]; then
  shift
  registry garbage-collect /config/registry/main.yml "$@"
  exit
fi

# Run once configured
registry serve /config/registry/main.yml &

# Trick caddy into using the proper location for shit... still, /tmp keeps on being used (possibly by the pki lib?)
HOME=/data/caddy-home exec caddy run -config /config/caddy/main.conf --adapter caddyfile "$@"
