-- Phase B: capture mode + aspect ratio for screen+face messages
alter table public.messages
    add column if not exists capture_mode text not null default 'face_only'
        check (capture_mode in ('face_only', 'screen_face'));

alter table public.messages
    add column if not exists aspect_ratio real;

alter table public.messages
    drop constraint if exists aspect_ratio_range;

alter table public.messages
    add constraint aspect_ratio_range
        check (aspect_ratio is null or (aspect_ratio > 0 and aspect_ratio <= 8));

-- Update ping_create_message signature to accept capture mode + aspect ratio
drop function if exists public.ping_create_message(uuid, uuid, text, text, text, double precision, double precision);

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
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    sender uuid := auth.uid();
    new_id uuid;
begin
    if sender is null then
        raise exception 'auth required';
    end if;

    if capture_mode_text not in ('face_only', 'screen_face') then
        raise exception 'invalid capture_mode';
    end if;

    insert into public.messages(
        room_id, sender_uid, receiver_uid, sender_nickname,
        video_id, video_url, duration_ms,
        mirror_position, status,
        capture_mode, aspect_ratio
    ) values (
        room_uuid, sender, receiver_uid, sender_nickname_text,
        video_id_text, video_url_text, 3000,
        jsonb_build_object('xRatio', x_ratio, 'yRatio', y_ratio),
        'uploaded',
        capture_mode_text, aspect_ratio_value
    ) returning id into new_id;

    return new_id;
end;
$$;

grant execute on function public.ping_create_message(uuid, uuid, text, text, text, double precision, double precision, text, real) to authenticated;
