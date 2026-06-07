-- User-specific room ordering plus unread metadata for all room lists.

alter table public.room_members
    add column if not exists room_order integer;

create index if not exists room_members_user_room_order_idx
    on public.room_members (user_id, room_order)
    where room_order is not null;

with ordered_memberships as (
    select
        rm.room_id,
        rm.user_id,
        (row_number() over (
            partition by rm.user_id
            order by r.name, rm.created_at, rm.room_id
        ) - 1)::integer as room_order
    from public.room_members rm
    join public.rooms r on r.id = rm.room_id
    where rm.room_order is null
)
update public.room_members as rm_update
set room_order = ordered_memberships.room_order
from ordered_memberships
where rm_update.room_id = ordered_memberships.room_id
  and rm_update.user_id = ordered_memberships.user_id
  and rm_update.room_order is null;

drop function if exists public.ping_my_rooms();

create or replace function public.ping_my_rooms()
returns table (
    id text,
    name text,
    searchable_name text,
    owner_uid text,
    member_uids text[],
    member_nicknames jsonb,
    status text,
    created_at timestamptz,
    room_order integer,
    unread_count integer,
    latest_unread_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    current_uid uuid;
    read_map jsonb;
begin
    current_uid := ping_private.require_uid();

    select p.last_read_chat_at
    into read_map
    from public.profiles p
    where p.id = current_uid;

    if read_map is null then
        read_map := '{}'::jsonb;
    end if;

    return query
    with my_memberships as (
        select
            rm.room_id,
            rm.room_order,
            rm.created_at as membership_created_at
        from public.room_members rm
        where rm.user_id = current_uid
    ),
    chat_unread as (
        select
            cm.room_id,
            count(*)::integer as unread_count,
            max(cm.created_at) as latest_unread_at
        from public.chat_messages cm
        join my_memberships mm on mm.room_id = cm.room_id
        where cm.sender_uid <> current_uid
          and cm.created_at > coalesce(
                (read_map ->> cm.room_id::text)::timestamptz,
                'epoch'::timestamptz
              )
        group by cm.room_id
    ),
    video_unread as (
        select
            m.room_id,
            count(*)::integer as unread_count,
            max(m.created_at) as latest_unread_at
        from public.messages m
        join my_memberships mm on mm.room_id = m.room_id
        where m.receiver_uid = current_uid
          and m.status = 'uploaded'
          and m.expires_at > now()
          and coalesce(m.hidden_for_receiver, false) = false
        group by m.room_id
    )
    select
        rs.id,
        rs.name,
        rs.searchable_name,
        rs.owner_uid,
        rs.member_uids,
        rs.member_nicknames,
        rs.status,
        rs.created_at,
        mm.room_order,
        coalesce(chat_unread.unread_count, 0) + coalesce(video_unread.unread_count, 0) as unread_count,
        coalesce(
            greatest(chat_unread.latest_unread_at, video_unread.latest_unread_at),
            coalesce(chat_unread.latest_unread_at, video_unread.latest_unread_at)
        ) as latest_unread_at
    from ping_private.room_summary_rows(
        array(select my_memberships.room_id from my_memberships)
    ) rs
    join my_memberships mm on mm.room_id::text = rs.id
    left join chat_unread on chat_unread.room_id = mm.room_id
    left join video_unread on video_unread.room_id = mm.room_id
    order by (coalesce(chat_unread.unread_count, 0) + coalesce(video_unread.unread_count, 0) > 0) desc,
             coalesce(
                greatest(chat_unread.latest_unread_at, video_unread.latest_unread_at),
                coalesce(chat_unread.latest_unread_at, video_unread.latest_unread_at)
             ) desc nulls last,
             mm.room_order asc nulls last,
             rs.name;
end;
$$;

grant execute on function public.ping_my_rooms() to authenticated;

create or replace function public.ping_reorder_my_rooms(room_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    current_uid uuid;
    provided_count integer;
    valid_count integer;
begin
    current_uid := ping_private.require_uid();

    if room_ids is null then
        return;
    end if;

    select count(*)
    into provided_count
    from unnest(room_ids) as requested(room_id);

    select count(*)
    into valid_count
    from (
        select distinct requested.room_id
        from unnest(room_ids) as requested(room_id)
        join public.room_members rm
          on rm.room_id = requested.room_id
         and rm.user_id = current_uid
    ) as valid_rooms;

    if provided_count <> valid_count then
        raise exception 'room_order_contains_unknown_room' using errcode = '42501';
    end if;

    update public.room_members as rm_update
    set room_order = requested.ordinality::integer - 1
    from (
        select room_id, min(ordinality) as ordinality
        from unnest(room_ids) with ordinality as requested(room_id, ordinality)
        group by room_id
    ) as requested
    where rm_update.user_id = current_uid
      and rm_update.room_id = requested.room_id;
end;
$$;

grant execute on function public.ping_reorder_my_rooms(uuid[]) to authenticated;
