# CCC-005 — post-Money decision gate

## Decision

**Select `None / pause`: do not add a second domain adapter.  Continue with
Money hardening and a controlled internal V2 rollout only.**

This is an explicit scope decision, not a claim that Work, Sport or English
are unsuitable products.  It prevents a second adapter from being selected on
synthetic test traffic rather than real usage and correction evidence.

## Evidence reviewed

### Reliability — verified

- Local canonical Money tests cover exact UZS amounts, rollback points, 100
  repeated deliveries, 12 concurrent local commits, edit/delete lifecycle and
  scope isolation.
- The restart test keeps a retryable V2 outbox item across database reopen and
  acknowledges it once.
- Staging API verification created one exact `5,000,000 UZS` transaction,
  rejected a foreign account reference, and returned one committed result plus
  idempotent responses under sequential and concurrent retries.
- The deployed production API passed `/ready`, `/health`, migration boot and
  unauthenticated V2-route protection.  This verifies deployment plumbing,
  not a user capture on a device.

### Correction and retention — not yet measured

- The Money review permits a user to change account and category before save;
  salary/card suggestions remain suggestions until that confirmation.
- There is no redacted production metric yet for review edits, abandoned
  reviews, successful retries or retention.  No physical Android
  offline/reconnect cycle is currently available.

### Candidate comparison

| Candidate | Required evidence | Current result |
| --- | --- | --- |
| Work / Sales | Repeated interactions, measurable contact ambiguity, approved narrow contract | Not collected |
| Sport | Repeated capture need beyond manual sets and reviewed safety contract | Not collected |
| English | Repeated capture need tied to a defined progress model | Not collected |
| Another domain | Repeated high-frequency job and retention evidence | Not collected |
| None / pause | Money still lacks correction and retention telemetry | **Selected** |

## CCC-005 disposition

The decision gate is complete with **Money hardening / controlled rollout** as
the only approved next step.  No Work, Sport, English or other-domain adapter
is authorized by this decision.

## CCC-006 entry criteria

CCC-006 may add account-scoped rollout controls, redacted diagnostics and a
support/recovery runbook.  It must keep V1 as the fallback for *new* captures,
leave already committed/outboxed V2 Money records deliverable, and must not
enable a second domain.

Its final acceptance remains contingent on a real internal account completing
an offline/reconnect cycle without unreconciled records; that runtime proof is
not substituted by automated or staging evidence.
