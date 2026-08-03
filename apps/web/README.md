# Personal Tracker

Локальное web-приложение для прохождения 90-дневного плана английского языка: 03.08.2026–31.10.2026.

## Запуск

```bash
npm install
npm run dev
```

Откройте `http://localhost:3000`.

Проверки качества:

```bash
npm run lint
npm run build
```

## Что реализовано

- Dashboard с weighted overall progress, текущим днём, streak, временем и балансом навыков.
- Seed-данные всех 90 дней в `src/lib/roadmap.ts`; структурированные типы в `src/lib/types.ts`.
- Roadmap в режимах карты и списка, фильтры по навыкам и статусам.
- Страница дня: цель, теория, поисковые запросы, задания, autosave-черновики, timer и завершение только после обязательных задач.
- Локальные базы выражений, ошибок, writing и speaking history.
- Контрольные точки D7/D14/D21/D30/D44/D60/D74/D89/D90.
- Аналитика с графиками Recharts, weighted progress, skill balance и временем.
- JSON export/import, reset с подтверждением, command palette, горячие клавиши и light/dark theme.
- Zustand persist с версией локального хранилища и мягким восстановлением повреждённых данных.

## Архитектура

- `src/app/page.tsx` — client shell и feature-экраны.
- `src/lib/types.ts` — доменная модель, подготовленная для будущего API/Prisma.
- `src/lib/roadmap.ts` — seed-генератор 90 дней, отдельно от UI.
- `src/store/use-english-store.ts` — Zustand store, persistence и бизнес-правила completion/streak/review.
- `src/app/globals.css` — responsive design system без внешнего backend.

## Аудит ТЗ и осознанные границы MVP

Технический риск исходного ТЗ — слишком большой объём для одной неделимой реализации: 90 полноценных учебных материалов, аудиозапись, PDF, IndexedDB, тесты и полноценный backend-ready слой одновременно. В этом MVP данные и результаты уже работают локально, а внешние ресурсы открываются поисковыми ссылками без зависимости от платных API. Учебные дни seed-ятся структурированно и имеют понятные задания, но контент внешних ресурсов не копируется в приложение.

Следующим безопасным этапом можно вынести feature-компоненты из `page.tsx` в отдельные модули, добавить IndexedDB для больших голосовых файлов, unit/integration tests и слой repository для подключения PostgreSQL/Prisma.
