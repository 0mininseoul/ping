-- v0.3.12: storage read 정책을 receiver_uid 단독 매칭에서 룸 멤버 전체로 확장.
-- receiver_uid mismatch / 다른 anonymous session 등 edge case 안전망.
-- room_members join으로 그룹 채팅 + 다자 룸 모두 커버.

drop policy if exists "Ping videos sender receiver read" on storage.objects;
drop policy if exists "Ping videos room member read" on storage.objects;

create policy "Ping videos room member read"
    on storage.objects for select
    to authenticated
    using (
        bucket_id = 'ping-videos'
        and (
            -- 업로더 본인 (sender path prefix = uid)
            (storage.foldername(name))[1] = auth.uid()::text
            or exists (
                select 1
                from public.messages m
                join public.room_members rm on rm.room_id = m.room_id
                where rm.user_id = auth.uid()
                  and m.status = 'uploaded'
                  and (
                      m.video_url = storage.objects.name
                      or (m.sender_uid::text || '/' || m.video_id || '.mp4') = storage.objects.name
                  )
            )
        )
    );
