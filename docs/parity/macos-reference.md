# macOS Reference Contract for Windows Parity

This document captures the macOS behavior Windows must match.

## App lifecycle

- macOS is an accessory/menu-bar app, not a normal document app.
- Launch initializes status item, notifications, account switching, hotkeys, updater/backend bootstrap.
- Camera is not prewarmed at launch.
- Notification permission is not requested at launch.
- Quitting tears down observers/tasks, camera, realtime subscriptions, windows, playback cache, and transient state.

## Menu/tray commands

macOS status menu includes:

- disabled `Ping` header
- `영상 보내기`
- `화면+얼굴 보내기`
- `내 룸…`
- `설정…`
- `라이트/다크 전환`
- `업데이트 확인…`
- `종료`

Windows tray commands should map to the same product actions. `Open Ping` should restore the shell/home state, not jump into a secondary debug/history window.

## Incoming video playback

- Incoming video observer yields `VideoMessage`s.
- Duplicate/expired/missing-date messages are suppressed through an account-scoped ledger.
- Video is prefetched before notification.
- Notification title: `{senderNickname}님이 영상을 보냈습니다`.
- Notification user info includes `messageId` and `room_id`.
- Clicking notification calls the same playback path as direct incoming playback.
- Face-only playback is `200x200`, circular, floating, transparent, keyboard-driven.
- Screen+face playback uses long side `480` and message aspect ratio.
- Playback position is denormalized from `mirrorPosition`, centered, then clamped to visible work area.
- First playback auto-plays, marks seen, pauses at end, and starts a 10s close timeout.
- Return replays; Space opens expanded playback; Esc closes.

## Video message schema

`VideoMessage` fields:

- `id`
- `room_id`
- `sender_uid`
- `receiver_uid`
- `sender_nickname`
- `video_id`
- `video_url`
- `duration_ms`
- `mirror_position` with inner keys `xRatio`, `yRatio`
- `status` (`uploaded`, `seen`)
- `created_at`
- `expires_at`
- `capture_mode` (`face_only`, `screen_face`)
- `aspect_ratio`
- `allows_local_save`

Windows must keep exact key names and enum wire values.

## Send RPC contract

`ping_create_message` body:

- `room_uuid`
- `receiver_uid`
- `sender_nickname_text`
- `video_id_text`
- `video_url_text`
- `x_ratio`
- `y_ratio`
- `capture_mode_text`
- `aspect_ratio_value`
- `allows_local_save_value`

Storage object path: `{senderUid}/{videoId}.mp4`.

Private downloads use Supabase authenticated object route:

```text
/storage/v1/object/authenticated/{bucket}/{path}
```

## Room timeline

- Timeline is mixed video + chat.
- IDs are internally prefixed: `video:{id}` and `chat:{id}`.
- Items without `createdAt` are dropped.
- Items sort oldest-first and group by calendar day.
- Room load concurrently fetches videos and chats.
- New realtime chat/video events should update the currently selected room without manual reload.
- Empty state: `아직 기록 없음`.
- Own messages align right, incoming align left.
- Face-only thumbnails are circular; screen+face thumbnails are rounded rectangles.

## Capture mirror

State machine:

- `idle`
- `recording`
- `reviewing(URL)`
- `uploading`
- `failed(String)`

Face-only window: `200x200`. Screen+face long side: `480`. Mirror is borderless, transparent, floating, movable, and position-persisted.

Keyboard:

- Return: idle/failed starts recording; reviewing sends.
- Backspace/Delete: redo from review.
- Escape: close and discard review temp.
- Tab: cycle partner.
- 1-9: select partner.
- 0/A: all active rooms.

Hints:

- Idle/camera ready: `↵ 녹화 · Esc`
- Recording: countdown
- Reviewing: `↵ 보내기 · ⌫ 다시 · Esc`
- Uploading: `전송 중...`

Screen+face PIP diameter/padding scales from shortest side; it is not fixed pixels.
