-- v0.3.32: Supabase blocks direct deletion from storage.objects in Postgres functions.
-- The app removes the video object through the Storage API after this RPC deletes message rows.
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
begin
    if me is null then raise exception 'auth required'; end if;

    select sender_uid, receiver_uid, video_url
      into owner_uid, recipient_uid, video_path
      from public.messages
     where id = message_uuid;

    if owner_uid is null then
        return 'missing';
    end if;

    if owner_uid = me then
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

create or replace function public.ping_delete_message(message_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    perform public.ping_remove_video_message(message_uuid);
end;
$$;

grant execute on function public.ping_delete_message(uuid) to authenticated;
