# Canonical Room Names Implementation Plan

## Goal

Make room titles consistent across macOS, Windows, iOS, and watchOS for the same Supabase identity.

## Contract

- `rooms.name` is the canonical display title all clients should render.
- For non-renamed rooms, the backend automatically sets `rooms.name` to the room members' nicknames joined by `, ` in join order, for example `A, B, C`.
- When a member is added, removed, or updates their nickname, only non-renamed rooms are refreshed.
- When a user renames a room from desktop, that name is custom and is preserved across future membership changes.
- iOS thread navigation titles must use the selected room's canonical name, not message sender nicknames.

## Implementation Steps

1. Add contract tests for the shared room model, iOS route/thread title behavior, and Supabase migration SQL.
2. Add a Supabase migration with `rooms.name_is_custom`, default-name helpers, automatic refresh hooks in room/member RPCs, and custom rename preservation.
3. Change `PingRoom.title(excluding:)` to return the canonical `name`.
4. Pass room names through iOS navigation routes and let `ThreadView` refresh the title from `ping_my_rooms()` when opened from a notification.
5. Include the migration in the test resource copy list.
6. Run tests/builds, push the migration, commit/push, and upload a new TestFlight build.
