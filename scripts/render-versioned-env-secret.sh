#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${ORCHESTRATOR_ENV_FILE:-}"
WRITE_ENV_FILE=""
PAYLOAD_SECRET_KEY="TRAEFIK_APP_ENV_PAYLOAD_SECRET_NAME"
GENERATED_SECRET_KEYS=(
  TRAEFIK_APP_ENV_PAYLOAD_SECRET_NAME
)
PRINT_EXPORT=false
PAYLOAD_TMP=""
RENDERED_SECRET_KEYS=()
RENDERED_SECRET_NAMES=()

log() {
  printf '[versioned-env-secret] %s\n' "$*" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  scripts/render-versioned-env-secret.sh [--env-file FILE] [--write-env-file FILE] [--print-export]

Створює immutable Docker secret для runtime env payload.
Назва secret містить hash payload, тому зміна env-значень створює
новий Docker secret name і новий Swarm service spec.

Options:
  --env-file FILE        Runtime env file (default: ORCHESTRATOR_ENV_FILE, fallback ./.env для dev)
  --write-env-file FILE  Замінити/додати generated *_SECRET_NAME у цьому env-файлі
  --print-export         Надрукувати shell export lines для ручних інтеграцій
  -h, --help             Показати цю довідку
USAGE
}

cleanup() {
  rm -f "${PAYLOAD_TMP:-}"
}

trap cleanup EXIT

resolve_env_file() {
  local project_root="$1"
  local requested_file="$2"

  if [[ -n "${requested_file}" ]]; then
    printf '%s\n' "${requested_file}"
    return 0
  fi

  if [[ -n "${ORCHESTRATOR_ENV_FILE:-}" ]]; then
    printf '%s\n' "${ORCHESTRATOR_ENV_FILE}"
    return 0
  fi

  if [[ -f "${project_root}/.env" ]]; then
    log "WARNING: ORCHESTRATOR_ENV_FILE не передано. Fallback на локальний .env — тільки для dev."
    printf '%s\n' "${project_root}/.env"
    return 0
  fi

  die "env file not found. Set ORCHESTRATOR_ENV_FILE, pass --env-file, or provide local .env for dev."
}

validate_secret_base() {
  local secret_base="$1"

  [[ "${secret_base}" =~ ^[A-Za-z0-9_.-]+$ ]] || die "invalid secret base name: ${secret_base}"
}

read_env_var() {
  local key="$1"
  local file="$2"

  awk -v requested_key="${key}" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    {
      line = $0
      sub(/\r$/, "", line)
      candidate = line
      sub(/^[[:space:]]*export[[:space:]]+/, "", candidate)
      if (candidate ~ /^[[:space:]]*#/ || candidate !~ /=/) {
        next
      }
      key = trim(substr(candidate, 1, index(candidate, "=") - 1))
      if (key == requested_key) {
        value = trim(substr(candidate, index(candidate, "=") + 1))
        if (value ~ /^".*"$/ || value ~ /^\047.*\047$/) {
          value = substr(value, 2, length(value) - 2)
        }
        print value
        exit
      }
    }
  ' "${file}"
}

create_or_reuse_secret() {
  local secret_name="$1"
  local secret_file="$2"
  local description="$3"

  if docker secret inspect "${secret_name}" >/dev/null 2>&1; then
    log "${description} already exists: ${secret_name}"
  else
    log "Creating ${description}: ${secret_name}"
    docker secret create "${secret_name}" "${secret_file}" >/dev/null
  fi
}

remember_rendered_secret() {
  local secret_key="$1"
  local secret_name="$2"

  RENDERED_SECRET_KEYS+=("${secret_key}")
  RENDERED_SECRET_NAMES+=("${secret_name}")
}

write_rendered_secrets_to_env_file() {
  local env_file="$1"
  local secret_key secret_name index update_tmp

  [[ -n "${env_file}" ]] || return 0

  for index in "${!RENDERED_SECRET_KEYS[@]}"; do
    secret_key="${RENDERED_SECRET_KEYS[${index}]}"
    secret_name="${RENDERED_SECRET_NAMES[${index}]}"
    update_tmp="$(mktemp "$(dirname "${env_file}")/.versioned-secret-name.XXXXXX")"
    chmod 600 "${update_tmp}"
    awk -v secret_key="${secret_key}" -v secret_name="${secret_name}" '
      function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        return value
      }
      BEGIN { replaced = 0 }
      {
        line = $0
        sub(/\r$/, "", line)
        candidate = line
        sub(/^[[:space:]]*export[[:space:]]+/, "", candidate)
        if (candidate ~ /^[[:space:]]*#/ || candidate !~ /=/) {
          print line
          next
        }
        key = trim(substr(candidate, 1, index(candidate, "=") - 1))
        if (key == secret_key) {
          print secret_key "=" secret_name
          replaced = 1
          next
        }
        print line
      }
      END {
        if (replaced == 0) {
          print secret_key "=" secret_name
        }
      }
    ' "${env_file}" > "${update_tmp}"
    mv "${update_tmp}" "${env_file}"
  done

  chmod 600 "${env_file}"
  log "Updated generated secret names in ${env_file}"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      [[ -n "${ENV_FILE}" ]] || die "--env-file requires a value"
      shift 2
      ;;
    --write-env-file)
      WRITE_ENV_FILE="${2:-}"
      [[ -n "${WRITE_ENV_FILE}" ]] || die "--write-env-file requires a value"
      shift 2
      ;;
    --print-export)
      PRINT_EXPORT=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

ENV_FILE="$(resolve_env_file "${PROJECT_ROOT}" "${ENV_FILE}")"
[[ -s "${ENV_FILE}" ]] || die "env file is missing or empty: ${ENV_FILE}"

if [[ -n "${WRITE_ENV_FILE}" && "${WRITE_ENV_FILE}" != "${ENV_FILE}" ]]; then
  [[ -f "${WRITE_ENV_FILE}" ]] || die "--write-env-file target not found: ${WRITE_ENV_FILE}"
fi

command -v docker >/dev/null 2>&1 || die "docker not found"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum not found"
command -v awk >/dev/null 2>&1 || die "awk not found"

PAYLOAD_TMP="$(mktemp "${TMPDIR:-/tmp}/traefik-env-payload.XXXXXX")"
chmod 600 "${PAYLOAD_TMP}"

awk -v generated_keys="${GENERATED_SECRET_KEYS[*]}" '
  function trim(value) {
    sub(/^[[:space:]]+/, "", value)
    sub(/[[:space:]]+$/, "", value)
    return value
  }
  BEGIN {
    split(generated_keys, keys, " ")
    for (item in keys) {
      generated[keys[item]] = 1
    }
  }
  {
    line = $0
    sub(/\r$/, "", line)
    candidate = line
    sub(/^[[:space:]]*export[[:space:]]+/, "", candidate)
    if (candidate ~ /^[[:space:]]*#/ || candidate !~ /=/) {
      print line
      next
    }
    key = trim(substr(candidate, 1, index(candidate, "=") - 1))
    if (key in generated) {
      next
    }
    print line
  }
' "${ENV_FILE}" > "${PAYLOAD_TMP}"

secret_hash="$(sha256sum "${PAYLOAD_TMP}" | awk '{print substr($1, 1, 12)}')"
payload_secret_base="${TRAEFIK_APP_ENV_PAYLOAD_SECRET_BASE:-}"
if [[ -z "${payload_secret_base}" ]]; then
  payload_secret_base="$(read_env_var "TRAEFIK_APP_ENV_PAYLOAD_SECRET_BASE" "${ENV_FILE}")"
fi
if [[ -z "${payload_secret_base}" ]]; then
  payload_secret_base="${RUNTIME_ENV_SECRET_BASE:-}"
fi
if [[ -z "${payload_secret_base}" ]]; then
  payload_secret_base="$(read_env_var "RUNTIME_ENV_SECRET_BASE" "${ENV_FILE}")"
fi
if [[ -z "${payload_secret_base}" ]]; then
  payload_secret_base="traefik_app_env_payload"
fi
validate_secret_base "${payload_secret_base}"
secret_name="${payload_secret_base}_${secret_hash}"

create_or_reuse_secret "${secret_name}" "${PAYLOAD_TMP}" "runtime env payload secret"
remember_rendered_secret "${PAYLOAD_SECRET_KEY}" "${secret_name}"

if [[ -n "${WRITE_ENV_FILE}" ]]; then
  write_rendered_secrets_to_env_file "${WRITE_ENV_FILE}"
fi

for index in "${!RENDERED_SECRET_KEYS[@]}"; do
  log "Using ${RENDERED_SECRET_KEYS[${index}]}: ${RENDERED_SECRET_NAMES[${index}]}"
  printf '%s=%s\n' "${RENDERED_SECRET_KEYS[${index}]}" "${RENDERED_SECRET_NAMES[${index}]}"
done

if [[ "${PRINT_EXPORT}" == "true" ]]; then
  for index in "${!RENDERED_SECRET_KEYS[@]}"; do
    printf 'export %s=%q\n' "${RENDERED_SECRET_KEYS[${index}]}" "${RENDERED_SECRET_NAMES[${index}]}"
  done
fi
