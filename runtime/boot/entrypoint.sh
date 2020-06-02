#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

# Ensure the data folder is writable
#[ -w "/data" ] || {
#  >&2 printf "/data is not writable. Check your mount permissions.\n"
#  exit 1
#}

args=()

[ ! "$ALSA_CARD" ]              || args+=(--card          "$ALSA_CARD")

# Run once configured
exec registry --help
