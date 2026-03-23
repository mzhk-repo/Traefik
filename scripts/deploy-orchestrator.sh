#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log() {
  printf '[deploy-orchestrator] %s\n' "$*"
}

cd "${PROJECT_ROOT}"

if [[ -x "./scripts/init-volumes.sh" ]]; then
  log "Running init-volumes.sh"
  bash ./scripts/init-volumes.sh
else
  log "init-volumes.sh not found, skipping"
fi

log "Orchestration script completed"
