# Traefik

Окремий Docker-стек для `Traefik` (ingress reverse proxy) для DSpace.

## Архітектура трафіку

`Cloudflare Tunnel -> Traefik -> dspace-angular / dspace`

Стек працює в зовнішній Docker-мережі `proxy-net`. Traefik не публікує HTTP entrypoint на host-порт; Cloudflare Tunnel має бути підключений до тієї ж Docker-мережі та звертатися до Traefik напряму як до Docker-сервісу.

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

## Логи

Traefik пише service log і access log у `${VOL_LOGS_PATH}/traefik`.

Access log не збирає всі успішні запити. За замовчуванням логуються тільки:
- HTTP `5xx`;
- запити з retry attempts;
- запити довші за `TRAEFIK_ACCESSLOG_MIN_DURATION` (`5s` за замовчуванням).

Дефолтний фільтр status code: `TRAEFIK_ACCESSLOG_STATUS_CODES=500-599`.

Під час Swarm deploy `scripts/install-logrotate.sh` встановлює host logrotate policy для `${VOL_LOGS_PATH}/traefik/*.log` у `/etc/logrotate.d/traefik`. Дефолт: `su root root`, `daily`, `maxsize 100M`, `rotate 14`, `compress`, `copytruncate`.

## Перевірка

```bash
docker run --rm --network proxy-net curlimages/curl:latest \
  -H 'Host: <DSPACE_HOSTNAME>' http://traefik/

docker run --rm --network proxy-net curlimages/curl:latest \
  -H 'Host: <DSPACE_HOSTNAME>' http://traefik/server/api/core/sites
```

Очікування: HTTP `200` для UI і API.

## Traefik Dashboard через Cloudflare Zero Trust (Azure AD)

У цьому стеку локальний `basic auth` для dashboard вимкнено — автентифікація має виконуватись у Cloudflare Access.

1. У Cloudflare Zero Trust додай **Access Application** (Self-hosted) для домену dashboard:
	- Domain: `traefik.pinokew.buzz` (або значення `TRAEFIK_DASHBOARD_HOST`)
	- Policy: `Allow` для Azure AD identity provider (потрібні групи/користувачі)
2. У Tunnel (`Public Hostname`) налаштуй маршрут на Traefik:
	- Hostname: `traefik.pinokew.buzz`
	- Service: `http://traefik:80`
	- `HTTP Host Header`: `traefik.pinokew.buzz`
3. Перезапусти стек:

```bash
docker compose up -d
```

Після цього вхід у dashboard буде через Cloudflare Access (Azure AD), без локального логіна Traefik.
