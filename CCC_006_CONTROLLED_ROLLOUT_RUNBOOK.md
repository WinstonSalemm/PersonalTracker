# CCC-006 — controlled internal rollout

## Delivered controls

- Account-scoped server flags: `captureCoreV2Shadow` and `captureMoneyV2`.
  Both are false unless an operator enables them for an individual user.
- A remote-rollout mobile build (`CAPTURE_V2_REMOTE_ROLLOUT=true`) fetches the
  current flags before each new capture decision (30-second in-memory TTL).
  Failure to fetch is fail-closed: the new capture follows V1.
- A disable takes effect for new captures at the next successful flag refresh.
  It does **not** delete or block already committed local V2 Money/outbox rows;
  those continue through the idempotent V2 delivery path.
- The only server telemetry is an allow-listed event name.  It contains no raw
  capture text, money amount, description, account/category, or capture ID.

## Deployment order

1. Apply Prisma migration
   `20260811110000_ccc006_capture_rollout_flags` with the API deployment.
2. Deploy the API.  Do not enable any flag yet; the default is V1.
3. Produce an internal mobile build with:

   ```text
   --dart-define=CAPTURE_V2_REMOTE_ROLLOUT=true
   --dart-define=PT_API_BASE_URL=<approved-api-url>
   --dart-define=PT_ENVIRONMENT=staging
   ```

4. Authenticate the selected internal account, then enable only
   `captureMoneyV2` for its `userId` through
   `PUT /api/v2/admin/capture/rollout`.  The endpoint accepts only a configured
   beta operator and body `{ userId, capability, enabled }`.
5. Leave every other account and every other domain flag disabled.

## Observation and recovery

- Observe the operator-only
  `GET /api/v2/admin/capture/rollout/observation?userId=<selected-user-id>`
  response. It returns only the selected account's two rollout flags and
  aggregate event/count/last-seen values; it never returns capture text,
  amounts, descriptions, account/category IDs, capture IDs or correlation IDs.
  Expected normal sequence is review opened → committed locally → sync
  acknowledged. Retryable and permanent sync failure events are separate.
- Ask the internal user to complete one normal sequence: obtain the flag while
  connected, create and confirm a Money record offline, reconnect, and verify
  exactly one Money transaction plus `sync acknowledged`.
- For an immediate rollout stop, set `captureMoneyV2` to `false` for that
  account.  New captures return to V1; do not delete the scoped database or
  canonical outbox.
- For a retryable delivery failure, restore connectivity/authentication and
  foreground the app; the existing periodic/foreground worker retries it.
- For a permanent delivery failure, preserve the local canonical record and
  its error code for investigation.  Do not manually delete database rows or
  re-submit with a new capture ID, because that would defeat idempotency.

## Acceptance boundary

The implementation, API build and automated tests are complete.  CCC-006 is
not **accepted** until one selected internal account completes the documented
offline/reconnect cycle without unreconciled records.  No second domain adapter
is part of this rollout.
