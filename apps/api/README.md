# Personal Tracker API

Отдельный безопасный API-сервис для синхронизации локального English / Money / Sales Tracker с PostgreSQL на Railway.

Локальное приложение не зависит от этого сервиса: при пустом API URL, выключенной синхронизации или недоступном Railway данные продолжают жить в localStorage и остаются доступны для локального JSON-экспорта.

## Быстрый локальный запуск

1. Создайте PostgreSQL и скопируйте `.env.example` в `.env`.
2. Задайте `DATABASE_URL`, два разных секрета JWT длиной не менее 32 символов, `ADMIN_EMAIL`, `ADMIN_PASSWORD` длиной не менее 12 символов и отдельный `SNAPSHOT_READONLY_TOKEN`.
3. Выполните:

```bash
npm install
npm run prisma:generate
npx prisma migrate dev --name init
npm run prisma:seed
npm run dev
```

Проверки: `GET http://localhost:4000/health`, `GET http://localhost:4000/ready`, OpenAPI UI: `/docs`.

## Railway

Создайте один новый Railway project, добавьте PostgreSQL service и подключите этот репозиторий как API service. Railway должен получить `DATABASE_URL` от PostgreSQL и переменные из `.env.example`. Build command и healthcheck уже заданы в `railway.toml`; `npm start` сначала выполняет `prisma migrate deploy`, затем запускает API.

Не коммитьте `.env`. `SNAPSHOT_READONLY_TOKEN` должен быть отдельным read-only токеном, а `SNAPSHOT_USER_ID` — UUID пользователя, напечатанный seed-скриптом. В production задайте `APP_ORIGINS` только URL приложения, например `https://your-app.example`.

## Основные endpoints

- `POST /api/v1/auth/login`, `POST /api/v1/auth/refresh`, `POST /api/v1/auth/logout`, `GET /api/v1/auth/check`
- `POST /api/v1/sync/batch`, `GET /api/v1/sync/status`
- `GET /api/v1/transactions`, `/transactions/summary`, `/accounts`, `/obligations`
- `GET /api/v1/english/progress`, `/english/summary`
- `GET /api/v1/leads`, `/calls`, `/followups`, `/sales/summary`
- `GET /api/v1/dashboard/summary`
- `GET /api/v1/assistant/snapshot`
- `GET /api/v1/export/assistant.json`

Все endpoints кроме health/readiness/login/refresh/docs требуют JWT. Snapshot разрешает JWT или отдельный `SNAPSHOT_READONLY_TOKEN`; обычный frontend token не выдаётся в коде приложения.

## Примеры

```bash
curl -X POST https://api.example.com/api/v1/auth/login \
  -H "content-type: application/json" \
  -d '{"email":"owner@example.com","password":"..."}'

curl "https://api.example.com/api/v1/assistant/snapshot?from=2026-08-01&to=2026-08-31&mode=summary" \
  -H "authorization: Bearer $SNAPSHOT_READONLY_TOKEN"
```

По умолчанию snapshot агрегированный и скрывает имена, телефоны, контрагентов и любые секретные поля. `mode=full` разрешает личный полный экспорт, но секреты всё равно удаляются. ChatGPT автоматически к API не подключается: snapshot скачивается пользователем и передаётся в чат вручную.

## Idempotency и аудит

Каждая локальная запись передаётся со стабильным UUID в поле `id`; сервер хранит его как `clientId` и делает upsert. Повторная отправка не создаёт дубль. `SyncEvent` фиксирует последний payload hash и время синхронизации. AuditLog хранит только действие, метод, маршрут и request id — не содержимое финансовых или контактных записей.

## Тесты

```bash
npm test
npm run build
```

Unit-тесты покрывают расчёты денег, звонков, weighted pipeline, диапазоны дат и удаление секретов/PII из snapshot. PostgreSQL integration smoke-check выполняется отдельно после подключения `DATABASE_URL`.
