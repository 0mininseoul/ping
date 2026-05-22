-- v0.3.11: storage read policy의 expires_at 조건 제거.
-- v0.2 이전 영상은 expires_at = created_at + 1 day로 저장되어 어제 영상도 만료 처리.
-- cleanup은 이미 30d 정책으로 변경됐으므로 RLS는 receiver_uid + status 기준만으로 충분.

drop policy if exists "Ping videos sender receiver read" on storage.objects;
create policy "Ping videos sender receiver read"
    on storage.objects for select
    to authenticated
    using (
        bucket_id = 'ping-videos'
        and (
            (storage.foldername(name))[1] = auth.uid()::text
            or exists (
                select 1
                from public.messages m
                where m.status = 'uploaded'
                  and m.receiver_uid = auth.uid()
                  and (
                      m.video_url = storage.objects.name
                      or (m.sender_uid::text || '/' || m.video_id || '.mp4') = storage.objects.name
                  )
            )
        )
    );
