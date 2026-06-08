-- v0.3.40: reduce server-side video retention for Supabase Free plan.
-- Ping video messages are transient; keep new remote videos available for 24h,
-- then let the existing app-start cleanup RPC remove metadata and Storage objects.

create or replace function public.ping_create_message(
    room_uuid uuid,
    receiver_uid uuid,
    sender_nickname_text text,
    video_id_text text,
    video_url_text text,
    x_ratio double precision,
    y_ratio double precision,
    capture_mode_text text default 'face_only',
    aspect_ratio_value real default null,
    allows_local_save_value boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
    message_id uuid;
begin
    current_uid := ping_private.require_uid();

    if receiver_uid = current_uid then
        raise exception 'cannot_send_to_self' using errcode = '23514';
    end if;

    if not exists (
        select 1 from public.room_members
        where room_id = room_uuid and user_id = current_uid
    ) or not exists (
        select 1 from public.room_members
        where room_id = room_uuid and user_id = receiver_uid
    ) then
        raise exception 'not_room_members' using errcode = '42501';
    end if;

    if capture_mode_text not in ('face_only', 'screen_face') then
        raise exception 'invalid_capture_mode' using errcode = '22023';
    end if;

    insert into public.messages (
        room_id,
        sender_uid,
        receiver_uid,
        sender_nickname,
        video_id,
        video_url,
        duration_ms,
        x_ratio,
        y_ratio,
        status,
        expires_at,
        capture_mode,
        aspect_ratio,
        allows_local_save
    )
    values (
        room_uuid,
        current_uid,
        receiver_uid,
        sender_nickname_text,
        video_id_text,
        video_url_text,
        3000,
        x_ratio,
        y_ratio,
        'uploaded',
        now() + interval '1 day',
        capture_mode_text,
        aspect_ratio_value,
        allows_local_save_value
    )
    returning id into message_id;

    update public.profiles
    set last_used_room_id = room_uuid
    where id = current_uid;

    return message_id;
end;
$$;

grant execute on function public.ping_create_message(
    uuid,
    uuid,
    text,
    text,
    text,
    double precision,
    double precision,
    text,
    real,
    boolean
) to authenticated;

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
        where m.expires_at <= now()
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
end;
$$;

grant execute on function public.ping_cleanup_expired_data() to authenticated;
