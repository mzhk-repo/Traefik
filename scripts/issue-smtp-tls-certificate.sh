#!/usr/bin/env bash
# Category 1b: issue or renew a non-production SMTP TLS certificate through Cloudflare DNS-01.
set -euo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 64; }
log() { printf '[smtp-tls-issuer] %s\n' "$*" >&2; }
usage() { cat <<'USAGE'
Usage: scripts/issue-smtp-tls-certificate.sh --env-file FILE [--apply]

The credentials file is a Certbot Cloudflare INI file with mode 0600. This
script never reads .env files or emits certificate private material.
USAGE
}

env_file='' environment='' email='' credentials='' state_dir='' output_dir='' apply=false token_file=''
while (($#)); do
  case "$1" in
    --environment) environment=${2:-}; shift 2 ;;
    --env-file) env_file=${2:-}; shift 2 ;;
    --email) email=${2:-}; shift 2 ;;
    --credentials-file) credentials=${2:-}; shift 2 ;;
    --state-dir) state_dir=${2:-}; shift 2 ;;
    --output-dir) output_dir=${2:-}; shift 2 ;;
    --apply) apply=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unsupported argument: $1" ;;
  esac
done
if [[ -n "$env_file" ]]; then
  [[ "$env_file" = /* && -f "$env_file" && ! -L "$env_file" ]] || die 'env file must be an absolute regular non-symlink file.'
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || die 'invalid env syntax.'
    key=${BASH_REMATCH[1]}; value=${BASH_REMATCH[2]}
    case "$key" in
      DEPLOY_ENVIRONMENT) environment=$value ;;
      TLS_ACME_EMAIL) email=$value ;;
      TLS_ACME_STATE_DIR) state_dir=$value ;;
      TLS_OUTPUT_DIR) output_dir=$value ;;
      CLOUDFLARE_DNS_API_TOKEN) cloudflare_token=$value ;;
      CLOUDFLARE_ZONE_ID) cloudflare_zone_id=$value ;;
      SMTP_TLS_FQDN) fqdn=$value ;;
      *) continue ;;
    esac
  done < "$env_file"
  [[ -n "${cloudflare_token:-}" && "$cloudflare_token" != REPLACE_WITH_SOPS_ENCRYPTED_SECRET ]] || die 'CLOUDFLARE_DNS_API_TOKEN is required.'
  [[ -n "${cloudflare_zone_id:-}" && "$cloudflare_zone_id" != REPLACE_WITH_CLOUDFLARE_ZONE_ID ]] || die 'CLOUDFLARE_ZONE_ID is required.'
  token_file=$(mktemp /dev/shm/smtp2graph-cloudflare.XXXXXX); chmod 600 "$token_file"
  printf 'dns_cloudflare_api_token = %s\n' "$cloudflare_token" > "$token_file"
  unset cloudflare_token
  credentials=$token_file
  trap 'rm -f -- "$token_file"' EXIT
fi
[[ "$environment" == non-production ]] || die 'only --environment non-production is permitted.'
[[ "$email" == *@* && -n "$credentials" && -n "$state_dir" && -n "$output_dir" ]] || die 'email, credentials, state and output paths are required.'
[[ "$credentials" = /* && -f "$credentials" && ! -L "$credentials" ]] || die 'credentials file must be an absolute regular non-symlink file.'
[[ "$(stat -c '%a' "$credentials")" == 600 ]] || die 'credentials file mode must be 0600.'
[[ "$apply" == true ]] || { log 'validation passed; use --apply to contact the ACME service.'; exit 0; }
command -v certbot >/dev/null || die 'certbot with the dns-cloudflare plugin is required.'
install -d -m 0700 "$state_dir" "$output_dir"
fqdn=${fqdn:-smtp-int.ldubgd.edu.ua}
certbot certonly --non-interactive --agree-tos --email "$email" --dns-cloudflare --dns-cloudflare-credentials "$credentials" --config-dir "$state_dir/config" --work-dir "$state_dir/work" --logs-dir "$state_dir/logs" --cert-name "$fqdn" -d "$fqdn"
live_dir="$state_dir/config/live/$fqdn"
install -m 0644 "$live_dir/fullchain.pem" "$output_dir/fullchain.pem"
install -m 0600 "$live_dir/privkey.pem" "$output_dir/privkey.pem"
fingerprint=$(openssl x509 -in "$output_dir/fullchain.pem" -noout -fingerprint -sha256 | cut -d= -f2)
expiry=$(openssl x509 -in "$output_dir/fullchain.pem" -noout -enddate | cut -d= -f2-)
umask 077
printf 'fqdn=%s\nfingerprint_sha256=%s\nnot_after=%s\n' "$fqdn" "$fingerprint" "$expiry" > "$output_dir/metadata.env"
log 'certificate material and non-sensitive metadata refreshed.'
