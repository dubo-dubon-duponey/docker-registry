#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

# Ensure the data folder is writable
[ -w "/data" ] || {
  >&2 printf "/data is not writable. Check your mount permissions.\n"
  exit 1
}

if [ "${USERNAME:-}" ]; then
  export REGISTRY_AUTH=htpasswd
  export REGISTRY_AUTH_HTPASSWD_REALM="$REALM"
  export REGISTRY_AUTH_HTPASSWD_PATH=/data/htpasswd
  printf "%s:%s\n" "$USERNAME" "$(printf "%s" "$PASSWORD" | base64 -d)" > /data/htpasswd
fi

# args=()

# Run once configured
exec registry serve /config/config.yml
