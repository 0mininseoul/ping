# Room Chat Polish

## Requirements
- Opening one notification for a room clears all delivered chat notifications for that same room.
- Opening the room manager with Option+O lands on the newest timeline item, not the oldest.
- Chat sends with Enter; Shift+Enter inserts a newline.
- Room chat supports image attachments from an attach button and Finder drag/drop.

## Implementation Plan
1. Add regression coverage for notification cleanup, latest-scroll timing, Enter routing, image attach/drop UI, image attachment decoding, and Supabase Storage/RLS contracts.
2. Extend `chat_messages` with nullable image metadata and add a private `ping-media` bucket with owner upload and room-member read policies.
3. Upload selected/dropped local images before inserting the chat row, then render private image attachments through the existing cache/download path.
4. Clear delivered notifications by `room_id` when a chat notification is opened and mark the room read as before.
5. Verify with Supabase migration push, Xcode build/test, local app install, release artifact generation, and deploy.
