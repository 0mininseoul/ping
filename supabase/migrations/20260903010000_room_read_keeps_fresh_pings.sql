-- 룸을 여는 동작이 방금 도착한 핑의 알림을 취소하던 문제.
--
-- ping_mark_room_read는 그 룸의 'uploaded' 메시지를 전부 'seen'으로 바꾼다.
-- ping_incoming_messages는 'uploaded'만 반환하므로, 수신 폴링(10초 주기)이 집어가기
-- 전에 수신자가 룸을 열면 알림도 자동 재생도 영영 오지 않는다. 2026-09-03에 실제로
-- 그렇게 핑 하나가 통째로 사라졌다(도착 11초 뒤 룸 오픈).
--
-- 유예 시간 안에 도착한 메시지는 읽음 처리에서 제외해 알림 경로에 맡긴다.
-- 클라이언트 PingNotificationGrace.freshVideoWindow와 같은 값이어야 한다.

create or replace function public.ping_mark_room_read(room_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := ping_private.require_uid();
    current_map jsonb;
begin
    select last_read_chat_at
    into current_map
    from public.profiles
    where id = me;

    if current_map is null then
        current_map := '{}'::jsonb;
    end if;

    update public.profiles
       set last_read_chat_at = current_map || jsonb_build_object(room_uuid::text, to_jsonb(now()))
     where id = me;

    update public.messages
       set status = 'seen'
     where room_id = room_uuid
       and receiver_uid = me
       and status = 'uploaded'
       and expires_at > now()
       and coalesce(hidden_for_receiver, false) = false
       -- 방금 온 핑은 아직 알림이 뜨지 않았을 수 있으므로 건드리지 않는다.
       and created_at < now() - interval '60 seconds';
end;
$$;

grant execute on function public.ping_mark_room_read(uuid) to authenticated;
