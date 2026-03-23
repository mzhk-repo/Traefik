#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${ENV_FILE:-${PROJECT_ROOT}/.env}"
if [[ ! -f "${ENV_FILE}" && -f "${PROJECT_ROOT}/archive/.env" ]]; then
  ENV_FILE="${PROJECT_ROOT}/archive/.env"
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[init-volumes] Env file not found. Checked: ${PROJECT_ROOT}/.env and ${PROJECT_ROOT}/archive/.env" >&2
  exit 1
fi

vol_line="$(grep -E '^[[:space:]]*VOL_LOGS_PATH[[:space:]]*=' "${ENV_FILE}" | tail -n1 || true)"
if [[ -z "${vol_line}" ]]; then
  echo "[init-volumes] VOL_LOGS_PATH is missing in ${ENV_FILE}" >&2
  exit 1
fi

vol_logs_path="${vol_line#*=}"
# Remove trailing inline comments like: /path # comment
vol_logs_path="$(printf '%s' "${vol_logs_path}" | sed -E 's/[[:space:]]+#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"

# Strip optional surrounding quotes
if [[ "${vol_logs_path}" =~ ^\".*\"$ || "${vol_logs_path}" =~ ^\'.*\'$ ]]; then
  vol_logs_path="${vol_logs_path:1:${#vol_logs_path}-2}"
fi

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
