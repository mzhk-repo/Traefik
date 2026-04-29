# Runbook: scripts (Traefik)

## `scripts/init-volumes.sh` (Категорія 1б, deploy-adjacent)

### Бізнес-логіка
- Ініціалізує директорію логів Traefik на host-машині за шляхом з `VOL_LOGS_PATH`.
- Створює `${VOL_LOGS_PATH}/traefik` через одноразовий контейнер `alpine`.
- Використовується у lifecycle деплою перед `docker compose config` та `docker stack deploy`.

### Ручний запуск (перевірений сценарій)
> Важливо: `env.dev.enc` у цьому репозиторії — у форматі `dotenv`, тому для `sops` потрібно явно вказати тип.

```bash
sops --decrypt --input-type dotenv --output-type dotenv env.dev.enc > /tmp/env.test
chmod 600 /tmp/env.test
ORCHESTRATOR_ENV_FILE=/tmp/env.test bash scripts/init-volumes.sh
echo $?
rm -f /tmp/env.test
```

Очікуваний результат:
- У виводі є рядок `Done: <VOL_LOGS_PATH>/traefik`
- `echo $?` повертає `0`

## `scripts/deploy-orchestrator-swarm.sh` (Swarm orchestrator)

### Бізнес-логіка
- Для `ORCHESTRATOR_MODE=swarm` виконує Swarm-деплой стека.
- Перед рендерингом compose-манифесту запускає `scripts/init-volumes.sh`.
- За відсутності `INFRA_REPO_PATH` пропускає ansible refresh secrets з informational-логом (це не помилка).

### Ручний запуск (мінімальна перевірка)
```bash
sops --decrypt --input-type dotenv --output-type dotenv env.dev.enc > /tmp/env.test
chmod 600 /tmp/env.test
ORCHESTRATOR_MODE=swarm ENVIRONMENT_NAME=development STACK_NAME=traefik ORCHESTRATOR_ENV_FILE=/tmp/env.test bash scripts/deploy-orchestrator-swarm.sh
echo $?
rm -f /tmp/env.test
```

Пояснення по логам:
- `INFRA_REPO_PATH is not set; skip ansible secrets refresh` — очікувана поведінка, якщо змінна не задана.
- `Running deploy-adjacent script: /opt/Traefik/scripts/init-volumes.sh` — службовий лог перед запуском `init-volumes.sh`.
