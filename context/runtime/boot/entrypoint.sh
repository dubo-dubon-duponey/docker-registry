#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)"
readonly root
# shellcheck source=/dev/null
source "$root/helpers.sh"
# shellcheck source=/dev/null
source "$root/mdns.sh"

helpers::dir::writable "/certs"
helpers::dir::writable "$XDG_DATA_HOME" create
helpers::dir::writable "$XDG_DATA_DIRS" create
helpers::dir::writable "$XDG_RUNTIME_DIR" create
helpers::dir::writable "$XDG_STATE_HOME" create
helpers::dir::writable "$XDG_CACHE_HOME" create

# mDNS blast if asked to
[ ! "${MDNS_HOST:-}" ] || {
  _mdns_port="$([ "$TLS" != "" ] && printf "%s" "${PORT_HTTPS:-443}" || printf "%s" "${PORT_HTTP:-80}")"
  [ ! "${MDNS_STATION:-}" ] || mdns::records::add "_workstation._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "$_mdns_port"
  mdns::records::add "${MDNS_TYPE:-_http._tcp}" "$MDNS_HOST" "${MDNS_NAME:-}" "$_mdns_port"
  mdns::records::broadcast &
}

# Start the sidecar
start::sidecar &

# Make sure this defaults to lockdown if not set explicitly
readonly PULL="${PULL:-anonymous}"
PUSH="${PUSH:-disabled}"
# Disabled pull (for maintenance, the only case where this makes sense) implies disabled push
[ "$PULL" != "disabled" ] || PUSH="disabled"

readonly PUSH

# Override registry config proper
export REGISTRY_LOG_LEVEL="${LOG_LEVEL:-info}"
export REGISTRY_HTTP_SECRET="${REGISTRY_HTTP_SECRET:-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)}"

# Helpers
case "${1:-}" in
  "gc")
    shift
    registry garbage-collect /config/registry/main.yml "$@"
    exit
  ;;
esac

# Run once configured
exec registry serve /config/registry/main.yml "$@"
