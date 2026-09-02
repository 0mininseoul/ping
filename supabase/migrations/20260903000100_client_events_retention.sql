-- client_events가 470MB까지 불어나 Free 플랜 500MB 한도를 거의 채웠다.
-- 원인은 데스크톱이 10초마다 Realtime에 다시 붙으면서 좀비 상태 모니터가 쌓여
-- realtime_disconnected를 1,488,725건 남긴 것이다(클라이언트 쪽에서 함께 수정).
-- 서버에도 안전망을 둔다: 진단 이벤트는 짧게, 제품 지표는 90일만 보관한다.

-- 1) 누수로 쌓인 연결 진단 이벤트를 걷어낸다. 제품 지표는 건드리지 않는다.
delete from public.client_events
where event_name in ('realtime_disconnected', 'realtime_reconnected');

-- 2) 정리 RPC에 보관 기간을 추가한다. 앱 실행 시 best-effort로 호출된다.
create or replace function public.ping_cleanup_expired_data()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    msg_record record;
    chat_record record;
begin
    for msg_record in
        select m.id, m.video_url, m.sender_uid
        from public.messages m
        where m.created_at < now() - interval '30 days'
    loop
        delete from storage.objects
        where bucket_id = 'ping-videos' and name = msg_record.video_url;
        delete from public.messages where id = msg_record.id;
    end loop;

    for chat_record in
        select cm.id, cm.media_path
        from public.chat_messages cm
        where cm.created_at < now() - interval '30 days'
    loop
        if chat_record.media_path is not null then
            delete from storage.objects
            where bucket_id = 'ping-media'
              and name = chat_record.media_path;
        end if;
        delete from public.chat_messages where id = chat_record.id;
    end loop;

    delete from public.message_reactions
    where chat_message_id is null and video_message_id is null;

    delete from public.invitations where expires_at < now();
    delete from public.invite_links where expires_at < now();

    -- 진단 이벤트는 추세만 필요하므로 짧게 보관한다.
    delete from public.client_events
    where created_at < now() - interval '7 days'
      and event_name in ('realtime_disconnected', 'realtime_reconnected');

    delete from public.client_events
    where created_at < now() - interval '90 days';
end;
$$;

grant execute on function public.ping_cleanup_expired_data() to authenticated;

-- 3) 보관 기간 정리가 순차 스캔을 타지 않도록 한다.
create index if not exists client_events_created_at_idx
    on public.client_events (created_at);
