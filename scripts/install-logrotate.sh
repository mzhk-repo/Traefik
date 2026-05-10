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

sanitize_env_value() {
  printf '%s' "$1" | sed -E 's/[[:space:]]+#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

run_privileged() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
    return 0
  fi

  echo "[install-logrotate] ERROR: root або sudo потрібні для запису /etc/logrotate.d." >&2
  exit 1
}

ENV_FILE="${ORCHESTRATOR_ENV_FILE:-}"
if [[ -z "${VOL_LOGS_PATH:-}" && ( -z "${ENV_FILE}" || ! -f "${ENV_FILE}" ) ]]; then
  if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    ENV_FILE="${PROJECT_ROOT}/.env"
    echo "[install-logrotate] WARNING: ORCHESTRATOR_ENV_FILE не передано. Fallback на .env — тільки для dev." >&2
  else
    echo "[install-logrotate] ERROR: env file не знайдено. Передай ORCHESTRATOR_ENV_FILE або поклади .env." >&2
    exit 1
  fi
fi

vol_logs_path="$(sanitize_env_value "${VOL_LOGS_PATH:-$(read_env_var "VOL_LOGS_PATH" "${ENV_FILE}")}")"
if [[ -z "${vol_logs_path}" ]]; then
  echo "[install-logrotate] VOL_LOGS_PATH is missing in ${ENV_FILE}" >&2
  exit 1
fi

case "${vol_logs_path}" in
  /*)
    ;;
  *)
    echo "[install-logrotate] VOL_LOGS_PATH must be an absolute path: ${vol_logs_path}" >&2
    exit 1
    ;;
esac

if [[ "${vol_logs_path}" == *$'\n'* || "${vol_logs_path}" == *"*"* || "${vol_logs_path}" == *"?"* ]]; then
  echo "[install-logrotate] VOL_LOGS_PATH contains unsupported characters" >&2
  exit 1
fi

if ! command -v logrotate >/dev/null 2>&1; then
  echo "[install-logrotate] ERROR: logrotate command is not available on host" >&2
  exit 1
fi

rotate_size="$(sanitize_env_value "${TRAEFIK_LOGROTATE_SIZE:-100M}")"
rotate_count="$(sanitize_env_value "${TRAEFIK_LOGROTATE_ROTATE:-14}")"
logrotate_path="${TRAEFIK_LOGROTATE_PATH:-/etc/logrotate.d/traefik}"
tmp_config="$(mktemp "${TMPDIR:-/tmp}/traefik-logrotate.XXXXXX")"
cleanup() {
  if [[ -n "${tmp_config:-}" ]]; then
    run_privileged rm -f "${tmp_config}" || true
  fi
}
trap cleanup EXIT

cat > "${tmp_config}" <<EOF
${vol_logs_path}/traefik/*.log {
    su root root
    daily
    maxsize ${rotate_size}
    rotate ${rotate_count}
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    dateext
}
EOF

run_privileged chown root:root "${tmp_config}"
run_privileged chmod 0644 "${tmp_config}"
run_privileged logrotate -d "${tmp_config}" >/dev/null

echo "[install-logrotate] Installing logrotate policy: ${logrotate_path}"
run_privileged install -m 0644 "${tmp_config}" "${logrotate_path}"
echo "[install-logrotate] Done: ${logrotate_path}"
