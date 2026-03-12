# Traefik

Окремий Docker-стек для `Traefik` (ingress reverse proxy) для DSpace.

## Архітектура трафіку

`Cloudflare Tunnel -> Traefik -> dspace-angular / dspace`

Стек працює в зовнішній Docker-мережі `proxy-net`.

## Швидкий старт

```bash
cp .env.example .env
# відредагуй домен/доступ до dashboard при потребі

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
