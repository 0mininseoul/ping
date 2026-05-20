-- Phase A0.2: clip duration 2s → 3s
alter table public.messages alter column duration_ms set default 3000;

drop function if exists public.ping_create_message(uuid, uuid, text, text, text, double precision, double precision);

create or replace function public.ping_create_message(
    room_uuid uuid,
    receiver_uid uuid,
    sender_nickname_text text,
    video_id_text text,
    video_url_text text,
    x_ratio double precision,
    y_ratio double precision
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

    insert into public.messages(
        room_id, sender_uid, receiver_uid, sender_nickname,
        video_id, video_url, duration_ms,
        mirror_position, status
    ) values (
        room_uuid, sender, receiver_uid, sender_nickname_text,
        video_id_text, video_url_text, 3000,
        jsonb_build_object('xRatio', x_ratio, 'yRatio', y_ratio),
        'uploaded'
    ) returning id into new_id;

    return new_id;
end;
$$;

grant execute on function public.ping_create_message(uuid, uuid, text, text, text, double precision, double precision) to authenticated;
