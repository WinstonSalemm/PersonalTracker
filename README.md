# Personal Tracker

Личный local-first рабочий трекер в одном репозитории:

- `apps/web` — веб-приложение с English Roadmap, Money Tracker и Sales.
- `apps/api` — необязательный TypeScript API для PostgreSQL/Railway, синхронизации и безопасного snapshot-экспорта.

Локальный режим остаётся основным: данные интерфейса сохраняются в браузере и не пропадают, если API выключен или недоступен. API не даёт ChatGPT автоматический доступ — snapshot скачивается вручную и передаётся в чат пользователем.

## Локальный запуск интерфейса

```bash
npm install --prefix apps/web
npm run dev:web
```

Откройте `http://localhost:3000`.

Проверки интерфейса:

```bash
npm run lint:web
npm run build:web
```

## Локальный запуск API

Инструкция по PostgreSQL, Prisma, Railway и endpoint-ам находится в [apps/api/README.md](apps/api/README.md).

```bash
npm install --prefix apps/api
npm run build:api
npm run test:api
```

API можно разворачивать отдельным Railway-сервисом из каталога `apps/api`; локальное web-приложение при этом продолжает работать автономно.

## Структура

```text
PersonalTracker/
├─ apps/
│  ├─ web/   # English Roadmap + Money Tracker + Sales
│  └─ api/   # optional REST API + Prisma + PostgreSQL
├─ package.json
└─ README.md
```
