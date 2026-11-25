# SMTP TLS issuer

`scripts/issue-smtp-tls-certificate.sh` obtains the non-production certificate for
`smtp-int.ldubgd.edu.ua` through Certbot and Cloudflare DNS-01. It is independent
of the Traefik HTTP/Tunnel stack and does not use or expose `acme.json`.

The Cloudflare credentials file must be root-owned with mode `0600` and contain a
token scoped only to DNS record editing in the SMTP DNS zone. Certificate private
material remains in the protected state/output directories and is handed to the
smtp2graph TLS reconciler only through an approved deploy-adjacent procedure.
