#!/usr/bin/env bash
# Thin wrapper: delegates to run-init-container.sh with CONTAINER_ENGINE=podman.
# Kept for backward compatibility; prefer run-init-container.sh directly.
set -euo pipefail

export CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"
exec "$(dirname "${BASH_SOURCE[0]}")/run-init-container.sh" "$@"
