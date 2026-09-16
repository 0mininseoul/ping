-- v0.3.77: 보낸 사람의 "모두에게서 삭제"는 보낸 뒤 5분 안에만 허용한다.
-- 앱의 SentMessageDeletionPolicy.window와 같은 값이다. 앱 메뉴만 숨기면 구버전 앱이
-- 오래된 메시지를 계속 지울 수 있으므로 서버가 최종 판단한다.
-- 받은 사람의 "나에게서 숨기기"는 삭제가 아니므로 제한하지 않는다.
-- 운영 DB는 storage.objects 직접 삭제를 막는다. 영상·사진 파일 정리는 지금처럼 클라이언트 몫이다.

create or replace function public.ping_remove_video_message(message_uuid uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    owner_uid uuid;
    recipient_uid uuid;
    video_path text;
    sent_at timestamptz;
begin
    if me is null then raise exception 'auth required'; end if;

    select sender_uid, receiver_uid, video_url, created_at
      into owner_uid, recipient_uid, video_path, sent_at
      from public.messages
     where id = message_uuid;

    if owner_uid is null then
        return 'missing';
    end if;

    if owner_uid = me then
        if sent_at < now() - interval '5 minutes' then
            raise exception 'delete_window_expired' using errcode = '42501';
        end if;

        -- Storage object deletion happens through the Storage API in the client.
        delete from public.messages
         where sender_uid = me
           and video_url = video_path;

        return 'deleted';
    elsif recipient_uid = me then
        update public.messages
           set hidden_for_receiver = true
         where id = message_uuid
           and receiver_uid = me;

        return 'hidden';
    end if;

    raise exception 'message_not_accessible' using errcode = '42501';
end;
$$;

grant execute on function public.ping_remove_video_message(uuid) to authenticated;

create or replace function public.ping_delete_chat(chat_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    owner uuid;
    sent_at timestamptz;
begin
    if me is null then raise exception 'auth required'; end if;

    select sender_uid, created_at
      into owner, sent_at
      from public.chat_messages
     where id = chat_uuid;

    if owner is null then return; end if;
    if owner <> me then raise exception 'only sender can delete'; end if;
    if sent_at < now() - interval '5 minutes' then
        raise exception 'delete_window_expired' using errcode = '42501';
    end if;

    delete from public.chat_messages where id = chat_uuid;
end;
$$;

grant execute on function public.ping_delete_chat(uuid) to authenticated;
