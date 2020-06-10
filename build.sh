#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

export DEBIAN_DATE=2020-06-01
export TITLE="Docker Registry"
export DESCRIPTION="A dubo image for Docker registry"
export IMAGE_NAME="registry"

# Registry is broken right now wrt gomodules
export GO111MODULE=auto

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)/helpers.sh"
