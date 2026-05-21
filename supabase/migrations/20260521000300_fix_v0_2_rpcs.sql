-- Phase A0/B/C fix: ping_create_message and ping_room_messages were redefined
-- with wrong column names. The actual messages table uses x_ratio/y_ratio
-- (not mirror_position) and room_members uses user_id (not uid). This migration
-- re-redefines the RPCs to match the real schema while preserving v0.2 features
-- (capture_mode, aspect_ratio, 30-day expires_at, profiles.last_used_room_id update,
-- ping_private.require_uid() auth, cannot_send_to_self, not_room_members guard).

drop function if exists public.ping_create_message(uuid, uuid, text, text, text, double precision, double precision);
drop function if exists public.ping_create_message(uuid, uuid, text, text, text, double precision, double precision, text, real);

create or replace function public.ping_create_message(
    room_uuid uuid,
    receiver_uid uuid,
    sender_nickname_text text,
    video_id_text text,
    video_url_text text,
    x_ratio double precision,
    y_ratio double precision,
    capture_mode_text text default 'face_only',
    aspect_ratio_value real default null
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
        aspect_ratio
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
        now() + interval '30 days',
        capture_mode_text,
        aspect_ratio_value
    )
    returning id into message_id;

    update public.profiles
    set last_used_room_id = room_uuid
    where id = current_uid;

    return message_id;
end;
$$;

grant execute on function public.ping_create_message(uuid, uuid, text, text, text, double precision, double precision, text, real) to authenticated;

-- Fix ping_room_messages: room_members uses user_id, not uid
create or replace function public.ping_room_messages(
    room_uuid uuid,
    before_ts timestamptz default null,
    page_limit int default 50
) returns setof public.messages
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then
        raise exception 'auth required';
    end if;

    if not exists (
        select 1 from public.room_members where room_id = room_uuid and user_id = me
    ) then
        raise exception 'not a member';
    end if;

    return query
    select * from public.messages
    where room_id = room_uuid
      and (receiver_uid = me or sender_uid = me)
      and (before_ts is null or created_at < before_ts)
      and (hidden_for_receiver = false or sender_uid = me)
    order by created_at desc
    limit page_limit;
end;
$$;

grant execute on function public.ping_room_messages(uuid, timestamptz, int) to authenticated;
