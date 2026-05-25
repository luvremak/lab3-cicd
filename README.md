# Лабораторна робота №3 — CI/CD

Налаштування CI/CD для застосунку з Лабораторної роботи №1: автоматичне
тестування, статичний аналіз, збірка контейнера, публікація в GitHub
Container Registry, розгортання на віртуальній машині через self-hosted
runner та автоматична верифікація розгортання.

## Структура

```
lab3-cicd/
├── .github/
│   └── workflows/
│       └── ci-cd.yml             головний пайплайн (5 job-ів)
├── app/                          код застосунку з ЛР1
├── tests/                        pytest-тести (22 тести, ~94% покриття)
│   ├── conftest.py               фікстури (TestClient + PostgreSQL)
│   ├── test_config.py            unit-тести config.py
│   ├── test_health.py            тести /health/* ендпоінтів
│   ├── test_items.py             тести /items (CRUD + content negotiation)
│   └── test_root.py              тести кореневого / ендпоінту
├── deploy/
│   ├── target-node-setup.sh      провіжен Ubuntu VM-target node
│   └── deploy.sh                 запускається з runner-а через SSH
├── runner/
│   └── setup-runner.sh           провіжен Ubuntu VM з self-hosted runner-ом
├── verify/
│   └── verify.sh                 пост-deploy smoke-тести
├── Dockerfile                    production-образ застосунку
├── entrypoint.sh                 міграція БД + uvicorn
├── requirements.txt              runtime-залежності
├── requirements-dev.txt          лінтери, pytest, coverage
├── pyproject.toml                ruff/mypy/pytest/coverage конфіг
├── .hadolint.yaml                конфіг лінтера Dockerfile
├── .yamllint.yaml                конфіг лінтера YAML
└── README.md
```

## Пайплайн — 5 job-ів

| # | Job | Запускається | Що робить |
|---|---|---|---|
| 1 | **Lint** | push в main, теги `v*`, PR → main | ruff + mypy (Python), hadolint (Dockerfile), shellcheck (shell), yamllint (YAML) |
| 2 | **Test** | те саме, після Lint | pytest + coverage проти реальної PostgreSQL; падає, якщо покриття < 40%; вивантажує HTML-звіт як артефакт |
| 3 | **Build** | тільки на push (не на PR), після Lint+Test | збирає Docker-образ і пушить у GHCR. Теги: `latest` + `sha-<hash>` на push в main, `stable` + `<tag>` на анотовані теги |
| 4 | **Deploy** | тільки на анотовані теги `v*`, після Build, на **self-hosted runner-і** | SCP-ить `deploy.sh` на target node і запускає через SSH; скрипт оновлює `.env` і робить `systemctl restart mywebapp.service` |
| 5 | **Verify** | тільки на анотовані теги, після Deploy, на self-hosted runner-і | запускає `verify.sh` на target node, перевіряє availability + правила nginx + round-trip БД |

## Швидкий старт

### 1. Локально — запустити тести

```bash
# Підняти PostgreSQL (наприклад через docker)
docker run -d --name pg-test \
  -e POSTGRES_DB=mywebapp -e POSTGRES_USER=mywebapp \
  -e POSTGRES_PASSWORD=testpass -p 5432:5432 \
  postgres:16-alpine

# Встановити dev-залежності
pip install -r requirements.txt -r requirements-dev.txt

# Прогнати тести з покриттям
MYWEBAPP_TEST_DB_HOST=127.0.0.1 MYWEBAPP_TEST_DB_PASSWORD=testpass \
  pytest --cov=app --cov-report=term --cov-fail-under=40

# Прогнати лінтери
ruff check app tests
mypy app
```

### 2. GitHub — налаштувати репозиторій

1. **Створити публічний репозиторій** `lab3-cicd` (або з іншою назвою) і запушити цей код.
2. **Захистити main гілку**: Settings → Branches → Add rule → main:
   - Require status checks: Lint, Test
   - Require a pull request before merging
3. **Підняти target node** (Ubuntu 24.04 Server VM): запустити `sudo bash deploy/target-node-setup.sh` на ній.
4. **Підняти runner VM** (окрема Ubuntu 24.04 Server): запустити `sudo bash runner/setup-runner.sh`, далі вручну виконати команду `./config.sh --token ...` яку дає GitHub (Settings → Actions → Runners → New self-hosted runner).
5. **Додати в репо GitHub Secrets** (Settings → Secrets and variables → Actions):
   - `TARGET_HOST` — IP/hostname target node
   - `TARGET_USER` — `deploy`
   - `TARGET_SSH_KEY` — приватний ключ runner-а (публічну частину прописати в `/home/deploy/.ssh/authorized_keys` на target node)

