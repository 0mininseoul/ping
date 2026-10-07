# Optional account key implementation plan

> For agentic workers: use superpowers:executing-plans in this session. User authorization already includes implementation. No subagents or post-code verification.

**Goal:** Keep nickname-only onboarding and add optional nickname/key account reuse.

**Architecture:** A private credential registry and rate limiter support one new endpoint in the existing Vercel project. The broker preserves each original Supabase UID and issues independent standard Auth sessions. Windows stores accepted sessions atomically and restarts its account coordinator.

**Tech Stack:** Postgres, Supabase Auth, existing Node/Vercel API, WinUI 3/.NET.

**Spec:** `docs/superpowers/specs/2026-10-07-optional-account-key.ko.md`

## Global constraints

- Anonymous first use; no public tag or user email flow.
- Keys set only in Settings; 12–128 characters, exact comparison.
- Preserve UID, account catalog, rooms, messages and existing RLS.
- No automatic verification, delegated review or validation CI.

## Implementation tasks

### Task 1: Broker and database

- [ ] Add private credentials/rate-limit tables and service-role-only registry, lookup, status, and limiter RPCs; sync nickname using a profile trigger.
- [ ] Add `/api/account-key` actions `status`, `set`, `login`. Verify owner tokens on set/status; use standard Auth sign-in for new independent sessions.
- [ ] Keep internal Auth password stable, protect pepper, bound requests, and fail closed when configuration is missing.
- [ ] Commit as `feat(auth): add optional account key broker`.

### Task 2: Native account flow

- [ ] Add Core broker calls and a redacted portable-session type, with UID/project checks and atomic session import.
- [ ] Add a shared existing-account dialog; expose it through the small onboarding link and Settings.
- [ ] Add Settings-only key setup/change dialog and status. Serialize account transitions; retain authenticated session on local persistence failure.
- [ ] Commit as `feat(windows): add optional account key connection`.

### Task 3: Delivery record

- [ ] Update AGENTS/spec and document required existing-project deployment/configuration.
- [ ] Record actual deployment limitations and no-verification state, then commit documentation.

## Failure conditions carried into implementation

Wrong credentials keep the current account. Duplicate nicknames keep public behavior; ambiguous name/key pairs fail. Missing backend shows an actionable service error. Save failure keeps the authenticated session for retry. Nickname updates change login lookup without changing UID.

Ruling: native implementation proceeds under the user's explicit request; the general skill's repeated approval, test and review gates are superseded by that request and no-post-code-verification preference.
