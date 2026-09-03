-- 영상 핑을 도착 즉시 전달하기 위해 messages를 Realtime publication에 넣는다.
--
-- 지금까지 영상은 10초 폴링으로만 왔다(체감 ~7초). chat_messages만 publication에
-- 있어서 messages INSERT는 구독할 방법이 없었다. 수신자는 INSERT 신호만 받고
-- 본문은 기존 ping_incoming_messages RPC로 다시 읽으므로, 중복 제거와 RLS 경로는
-- 그대로 유지된다.
--
-- SELECT 정책이 sender_uid/receiver_uid 본인으로 제한돼 있어 Realtime도 같은
-- 범위만 흘려보낸다. INSERT만 구독하므로 replica identity는 기본값으로 충분하다.

do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'messages'
    ) then
        alter publication supabase_realtime add table public.messages;
    end if;
end
$$;
