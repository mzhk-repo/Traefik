# Traefik

Окремий Docker-стек для `Traefik` (ingress reverse proxy) для DSpace.

## Архітектура трафіку

`Cloudflare Tunnel -> Traefik -> dspace-angular / dspace`

Стек працює в зовнішній Docker-мережі `proxy-net`.

## Швидкий старт

```bash
cp .env.example .env
# відредагуй домен/доступ до dashboard при потребі
# за потреби онови CSP для зовнішніх інтеграцій, напр. Matomo, через CSP_REPORT_ONLY_POLICY

docker compose up -d
docker compose ps
```

## Вимоги

- Мережа `proxy-net` повинна існувати (створюється DSpace-стеком).
- Контейнери DSpace (`dspace`, `dspace-angular`) мають бути у тій же мережі `proxy-net`.

## Перевірка

```bash
curl -H 'Host: <DSPACE_HOSTNAME>' http://127.0.0.1:8080/
curl -H 'Host: <DSPACE_HOSTNAME>' http://127.0.0.1:8080/server/api/core/sites
```

Очікування: HTTP `200` для UI і API.

## Traefik Dashboard через Cloudflare Zero Trust (Azure AD)

У цьому стеку локальний `basic auth` для dashboard вимкнено — автентифікація має виконуватись у Cloudflare Access.

1. У Cloudflare Zero Trust додай **Access Application** (Self-hosted) для домену dashboard:
	- Domain: `traefik.pinokew.buzz` (або значення `TRAEFIK_DASHBOARD_HOST`)
	- Policy: `Allow` для Azure AD identity provider (потрібні групи/користувачі)
2. У Tunnel (`Public Hostname`) налаштуй маршрут на Traefik:
	- Hostname: `traefik.pinokew.buzz`
	- Service: `http://127.0.0.1:8080` (або твій локальний порт Traefik)
	- `HTTP Host Header`: `traefik.pinokew.buzz`
3. Перезапусти стек:

```bash
docker compose up -d
```

Після цього вхід у dashboard буде через Cloudflare Access (Azure AD), без локального логіна Traefik.
