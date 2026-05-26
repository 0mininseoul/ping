-- v0.3.29: deleting a sent video removes every receiver row that shares the uploaded object.
create or replace function public.ping_delete_message(message_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    owner_uid uuid;
    video_path text;
begin
    if me is null then raise exception 'auth required'; end if;

    select sender_uid, video_url
      into owner_uid, video_path
      from public.messages
     where id = message_uuid;

    if owner_uid is null then return; end if;
    if owner_uid <> me then
        raise exception 'only sender can delete';
    end if;

    delete from public.messages
     where sender_uid = me
       and video_url = video_path;

    delete from storage.objects
     where bucket_id = 'ping-videos'
       and name = video_path;
end;
$$;

grant execute on function public.ping_delete_message(uuid) to authenticated;
