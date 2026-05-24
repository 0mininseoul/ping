-- v0.3.25: allow room history playback for already-seen video messages.
-- History playback streams from private Storage, so receiver-readable rows must remain
-- storage-readable after ping_mark_message_seen changes status from uploaded to seen.

drop policy if exists "Ping videos sender receiver read" on storage.objects;
drop policy if exists "Ping videos room member read" on storage.objects;

create policy "Ping videos room member read"
    on storage.objects for select
    to authenticated
    using (
        bucket_id = 'ping-videos'
        and (
            -- Uploader self-read: sender path prefix = uid.
            (storage.foldername(name))[1] = auth.uid()::text
            or exists (
                select 1
                from public.messages m
                join public.room_members rm on rm.room_id = m.room_id
                where rm.user_id = auth.uid()
                  and m.status in ('uploaded', 'seen')
                  and (
                      m.video_url = storage.objects.name
                      or (m.sender_uid::text || '/' || m.video_id || '.mp4') = storage.objects.name
                  )
            )
        )
    );
