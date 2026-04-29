#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

read_env_var() {
  local key="$1"
  local file="$2"
  grep -m1 "^${key}=" "${file}" \
    | cut -d= -f2- \
    | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

ENV_FILE="${ORCHESTRATOR_ENV_FILE:-}"
if [[ -z "${ENV_FILE}" || ! -f "${ENV_FILE}" ]]; then
  if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    ENV_FILE="${PROJECT_ROOT}/.env"
    echo "[init-volumes] WARNING: ORCHESTRATOR_ENV_FILE не передано. Fallback на .env — тільки для dev." >&2
  else
    echo "[init-volumes] ERROR: env file не знайдено. Передай ORCHESTRATOR_ENV_FILE або поклади .env." >&2
    exit 1
  fi
fi

vol_logs_path="$(read_env_var "VOL_LOGS_PATH" "${ENV_FILE}")"
if [[ -z "${vol_logs_path}" ]]; then
  echo "[init-volumes] VOL_LOGS_PATH is missing in ${ENV_FILE}" >&2
  exit 1
fi

vol_logs_path="$(printf '%s' "${vol_logs_path}" | sed -E 's/[[:space:]]+#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"

if [[ -z "${vol_logs_path}" ]]; then
  echo "[init-volumes] VOL_LOGS_PATH resolved to empty value from ${ENV_FILE}" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[init-volumes] docker command is not available" >&2
  exit 1
fi

echo "[init-volumes] Initializing logs volume path: ${vol_logs_path}"

docker run --rm \
  -v "${vol_logs_path}:/host-logs" \
  alpine:3.20 \
  sh -eu -c '
    mkdir -p /host-logs/traefik
    chmod 0775 /host-logs /host-logs/traefik || true
  '

echo "[init-volumes] Done: ${vol_logs_path}/traefik"
