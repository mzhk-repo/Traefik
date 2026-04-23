# CHANGELOG 2026 VOL 01

Статус: `active`
Відкрито: `2026-04-19`
Контекст: продовження Фази 8.


# 2026-04-17 — ROADMAP Phase 8 rewritten: CI/CD Integration with SOPS decrypt in GitHub Actions + per-repo orchestration scripts

- **Context:** На основі детального аналізу requirement-ів для Фази 8 (voir Phase 8 CI/CD flow) потрібно було переписати ROADMAP Фаза 8, щоб явно описати архітектуру: спільний SOPS age key у GitHub Environment Secrets, дешифрування env.dev.enc/env.prod.enc в CI runtime в-memory, Ansible playbook --tags secrets для Docker Secrets, per-repo orchestration скрипти як місце для app-specific логіки, та ранбуки як source of truth для manual ops.
- **Change:** Повністю переписано розділ "## Фаза 8 — CI/CD Integration (Shared GitHub Actions Workflow)" у `docs/ROADMAP.md` з наступними деталями:
  - **Архітектурні принципи:** 5 пунктів про розподіл відповідально (runbooks + CI automation, SOPS key scoping, Environment Secrets для dev/prod розділення, per-repo scripts vs shared workflow orchestration)
  - **8.1 GitHub Environment Secrets:** явна таблиця з dev + prod Environment mappings (SOPS_AGE_KEY як спільний, SERVER_HOST як різний)
  - **8.2 Shared Workflow Enhancement:** new bash код для SOPS install + decrypt step, Ansible checkout, per-repo orchestration script invocation через SSH, cleanup step для rm /tmp/env.decrypted
  - **8.3 Per-Repo Orchestration Script:** детальний template bash-скрипт (git fetch/checkout, Ansible --tags secrets invocation, docker compose config + stack deploy, force service update, smoke-check, cleanup)
  - **8.4 Per-Repo main.yml:** YAML приклад з `use_ansible: true` і параметрами для dev/prod jobs
  - **8.5 Ansible Playbook:** примітка що `playbooks/swarm.yml --tags secrets` вже готова (no changes)
  - **8.6 Documentation: docs/CI-CD.md:** нова документація (須創 в Фазі 8)
  - **Залежності, ризики, DoD, чекліст:** узгоджено з узгодженими вимогами (БЕЗ apt update/upgrade, force redeploy як per-repo logic, no duplication runbooks-CI)
- **Verification:** Оновлений ROADMAP містить: явну diff від попередньої версії (более коротке описання SOPS流 у старій версії), детальні YAML/bash приклади для CI integraton, посилання на per-repo orchestration як місце для app-specific деплою-логіки, 5 архітектурних принципів, явні GitHub UI steps та per-repo поточання.
- **Docs:** Оновлено також таблицю у розділі "Структура docs/" для явного посилання на `CI-CD.md` (Фаза 8) із деталізованим описом flow.
- **Notes:** Це чисто планова/документаційна зміна без інфраструктурних модифікацій; фактична імплементація (Ansible playbook updates, shared-ci-cd.yml rewrite, per-repo script creation) залишається на рівні Фази 8 under DoD execution notes.

