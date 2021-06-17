#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

# shellcheck source=/dev/null
root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)/../"

# shellcheck source=/dev/null
. "$root"/hack/setup.sh

case "${1:-}" in
  "--version")
    exit
  ;;
  "--help")
    exit
  ;;
  *)
    cd "$root"
    target=image
    files=("$root/hack/recipe.cue" "$root/hack/cue_tool.cue")
    params=()
    isparam=
    for i in "$@"; do
      if [ "${i:0:2}" == "--" ]; then
        params+=("$i")
        isparam=true
      elif [ "$isparam" == true ]; then
        params+=("$i")
        isparam=
      elif [ "${i##*.}" == "cue" ]; then
        files+=("$i")
      else
        target="$i"
      fi
    done
    com=(cue)
    com+=("${params[@]}")
    com+=("$target")
    com+=("${files[@]}")

    echo "------------------------------------------------------------------"
    echo "Buildkit: $BUILDKIT_HOST"
    for i in "${com[@]}"; do
      if [ "${i:0:2}" == -- ]; then
        >&2 printf " %s" "$i"
      else
        >&2 printf " %s\n" "$i"
      fi
    done
    "${com[@]}" || {
      cd - > /dev/null
      echo "Execution failure"
      exit 1
    }
    cd - > /dev/null
  ;;
esac