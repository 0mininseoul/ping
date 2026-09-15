-- 룸 멤버가 룸의 영상을 실제로 내려받을 수 있게 한다.
--
-- 기존 정책 "Ping videos room member read"는 이름과 달리 룸 범위가 아니었다.
-- 정책의 EXISTS 서브쿼리가 호출자 권한으로 실행되는 탓에, 그 안에서 읽는
-- public.messages에 messages 자신의 RLS가 또 적용됐다:
--     (sender_uid = auth.uid()) OR (receiver_uid = auth.uid())
-- 그래서 "내가 보내지도 받지도 않은" 행은 서브쿼리에 아예 보이지 않았고,
-- room_members 조인은 아무 효과가 없었다. 결과적으로 정책은 "내가 주고받은 영상"과
-- 정확히 같은 범위였다.
--
-- 타임라인을 룸 전체로 넓히자(20260915000100) 이 구멍이 드러났다. 남이 남에게 보낸
-- 자동 회신이 목록에는 뜨는데 내려받기는 404가 났고, 클라이언트는 그 404를
-- "영상이 만료되어 더 이상 재생할 수 없어요"로 표시했다.
--
-- 존재 판정을 SECURITY DEFINER 함수로 옮겨 messages RLS를 우회한다. 범위는 함수 안에서
-- rm.user_id = auth.uid()로 직접 묶으므로, 호출자가 속한 룸 밖으로는 넓어지지 않는다.

create or replace function public.ping_can_read_video_object(object_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.messages m
        join public.room_members rm on rm.room_id = m.room_id
        where rm.user_id = auth.uid()
          and m.status in ('uploaded', 'seen')
          and (
              m.video_url = object_name
              or (m.sender_uid::text || '/' || m.video_id || '.mp4') = object_name
          )
    );
$$;

revoke all on function public.ping_can_read_video_object(text) from public;
grant execute on function public.ping_can_read_video_object(text) to authenticated;

drop policy if exists "Ping videos room member read" on storage.objects;

create policy "Ping videos room member read"
    on storage.objects for select
    to authenticated
    using (
        bucket_id = 'ping-videos'
        and (
            -- 업로더 본인 (sender path prefix = uid)
            (storage.foldername(name))[1] = auth.uid()::text
            or public.ping_can_read_video_object(name)
        )
    );
