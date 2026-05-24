-- v0.3.24: sender-controlled local save permission for video messages.

alter table public.messages
    add column if not exists allows_local_save boolean not null default false;

drop function if exists public.ping_create_message(uuid, uuid, text, text, text, double precision, double precision);
drop function if exists public.ping_create_message(uuid, uuid, text, text, text, double precision, double precision, text, real);
drop function if exists public.ping_create_message(uuid, uuid, text, text, text, double precision, double precision, text, real, boolean);

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
        now() + interval '30 days',
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

grant execute on function public.ping_create_message(uuid, uuid, text, text, text, double precision, double precision, text, real, boolean) to authenticated;

drop function if exists public.ping_incoming_messages();

create or replace function public.ping_incoming_messages()
returns table (
    id text,
    room_id text,
    sender_uid text,
    receiver_uid text,
    sender_nickname text,
    video_id text,
    video_url text,
    duration_ms integer,
    mirror_position jsonb,
    status text,
    created_at timestamptz,
    expires_at timestamptz,
    capture_mode text,
    aspect_ratio real,
    hidden_for_receiver boolean,
    allows_local_save boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    current_uid uuid;
begin
    current_uid := ping_private.require_uid();

    return query
        select
            m.id::text,
            m.room_id::text,
            m.sender_uid::text,
            m.receiver_uid::text,
            m.sender_nickname,
            m.video_id,
            m.video_url,
            m.duration_ms,
            jsonb_build_object('xRatio', m.x_ratio, 'yRatio', m.y_ratio),
            m.status,
            m.created_at,
            m.expires_at,
            m.capture_mode,
            m.aspect_ratio,
            m.hidden_for_receiver,
            m.allows_local_save
        from public.messages m
        where m.receiver_uid = current_uid
          and m.status = 'uploaded'
          and m.expires_at > now()
          and m.hidden_for_receiver = false
        order by m.created_at desc;
end;
$$;

grant execute on function public.ping_incoming_messages() to authenticated;

drop function if exists public.ping_get_message(uuid);

create or replace function public.ping_get_message(message_uuid uuid)
returns table (
    id text,
    room_id text,
    sender_uid text,
    receiver_uid text,
    sender_nickname text,
    video_id text,
    video_url text,
    duration_ms integer,
    mirror_position jsonb,
    status text,
    created_at timestamptz,
    expires_at timestamptz,
    capture_mode text,
    aspect_ratio real,
    hidden_for_receiver boolean,
    allows_local_save boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    current_uid uuid;
begin
    current_uid := ping_private.require_uid();

    return query
        select
            m.id::text,
            m.room_id::text,
            m.sender_uid::text,
            m.receiver_uid::text,
            m.sender_nickname,
            m.video_id,
            m.video_url,
            m.duration_ms,
            jsonb_build_object('xRatio', m.x_ratio, 'yRatio', m.y_ratio),
            m.status,
            m.created_at,
            m.expires_at,
            m.capture_mode,
            m.aspect_ratio,
            m.hidden_for_receiver,
            m.allows_local_save
        from public.messages m
        where m.id = message_uuid
          and m.expires_at > now()
          and (m.hidden_for_receiver = false or m.sender_uid = current_uid)
          and (
              m.sender_uid = current_uid
              or (m.receiver_uid = current_uid and m.status = 'uploaded')
          );
end;
$$;

grant execute on function public.ping_get_message(uuid) to authenticated;

drop function if exists public.ping_room_messages(uuid, timestamptz, int);

create or replace function public.ping_room_messages(
    room_uuid uuid,
    before_ts timestamptz default null,
    page_limit int default 50
) returns table (
    id uuid,
    room_id uuid,
    sender_uid uuid,
    receiver_uid uuid,
    sender_nickname text,
    video_id text,
    video_url text,
    duration_ms integer,
    mirror_position jsonb,
    status text,
    created_at timestamptz,
    expires_at timestamptz,
    capture_mode text,
    aspect_ratio real,
    hidden_for_receiver boolean,
    allows_local_save boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
    me uuid := auth.uid();
begin
    if me is null then raise exception 'auth required'; end if;
    if not exists (
        select 1 from public.room_members rm where rm.room_id = room_uuid and rm.user_id = me
    ) and not exists (
        select 1 from public.messages mm where mm.room_id = room_uuid and (mm.sender_uid = me or mm.receiver_uid = me)
    ) and not exists (
        select 1 from public.chat_messages cm where cm.room_id = room_uuid and cm.sender_uid = me
    ) then
        raise exception 'not a member';
    end if;

    return query
    select
        m.id,
        m.room_id,
        m.sender_uid,
        m.receiver_uid,
        m.sender_nickname,
        m.video_id,
        m.video_url,
        m.duration_ms,
        jsonb_build_object('xRatio', m.x_ratio, 'yRatio', m.y_ratio) as mirror_position,
        m.status,
        m.created_at,
        m.expires_at,
        m.capture_mode,
        m.aspect_ratio,
        m.hidden_for_receiver,
        m.allows_local_save
    from public.messages m
    where m.room_id = room_uuid
      and (m.receiver_uid = me or m.sender_uid = me)
      and (before_ts is null or m.created_at < before_ts)
      and (m.hidden_for_receiver = false or m.sender_uid = me)
    order by m.created_at desc
    limit page_limit;
end;
$$;

grant execute on function public.ping_room_messages(uuid, timestamptz, int) to authenticated;
