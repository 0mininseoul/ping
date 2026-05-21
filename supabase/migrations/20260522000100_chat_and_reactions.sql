-- Spec G: chat + reactions + reply

-- 1. profiles 확장 (read marker)
alter table public.profiles
    add column if not exists last_read_chat_at jsonb not null default '{}'::jsonb;

-- 2. chat_messages
create table if not exists public.chat_messages (
    id uuid primary key default gen_random_uuid(),
    room_id uuid not null references public.rooms(id) on delete cascade,
    sender_uid uuid not null references public.profiles(id) on delete cascade,
    sender_nickname text not null,
    body text not null check (char_length(body) > 0 and char_length(body) <= 2000),
    reply_to_chat_id uuid references public.chat_messages(id) on delete set null,
    reply_to_video_id uuid references public.messages(id) on delete set null,
    created_at timestamptz not null default now(),
    constraint chat_reply_target_xor check (
        reply_to_chat_id is null or reply_to_video_id is null
    )
);

create index if not exists chat_messages_room_created_at_idx
    on public.chat_messages (room_id, created_at desc);
create index if not exists chat_messages_sender_idx
    on public.chat_messages (sender_uid, created_at desc);

alter table public.chat_messages enable row level security;

create policy chat_messages_select_member
    on public.chat_messages for select to authenticated
    using (
        exists (
            select 1 from public.room_members
            where room_id = chat_messages.room_id and user_id = auth.uid()
        )
    );

create policy chat_messages_insert_member
    on public.chat_messages for insert to authenticated
    with check (
        sender_uid = auth.uid()
        and exists (
            select 1 from public.room_members
            where room_id = chat_messages.room_id and user_id = auth.uid()
        )
    );

create policy chat_messages_delete_sender
    on public.chat_messages for delete to authenticated
    using (sender_uid = auth.uid());

-- 3. message_reactions
create table if not exists public.message_reactions (
    id uuid primary key default gen_random_uuid(),
    chat_message_id uuid references public.chat_messages(id) on delete cascade,
    video_message_id uuid references public.messages(id) on delete cascade,
    uid uuid not null references public.profiles(id) on delete cascade,
    emoji text not null check (char_length(emoji) <= 16),
    created_at timestamptz not null default now(),
    constraint reaction_target_xor check (
        (chat_message_id is null) <> (video_message_id is null)
    ),
    unique (chat_message_id, uid, emoji),
    unique (video_message_id, uid, emoji)
);

create index if not exists reactions_chat_idx on public.message_reactions (chat_message_id) where chat_message_id is not null;
create index if not exists reactions_video_idx on public.message_reactions (video_message_id) where video_message_id is not null;

alter table public.message_reactions enable row level security;

create policy reactions_select_member
    on public.message_reactions for select to authenticated
    using (
        case
            when chat_message_id is not null then exists (
                select 1 from public.chat_messages cm
                join public.room_members rm on rm.room_id = cm.room_id
                where cm.id = chat_message_id and rm.user_id = auth.uid()
            )
            when video_message_id is not null then exists (
                select 1 from public.messages m
                join public.room_members rm on rm.room_id = m.room_id
                where m.id = video_message_id and rm.user_id = auth.uid()
            )
            else false
        end
    );

create policy reactions_insert_own
    on public.message_reactions for insert to authenticated
    with check (uid = auth.uid());

create policy reactions_delete_own
    on public.message_reactions for delete to authenticated
    using (uid = auth.uid());

-- 4. RPC: send chat
create or replace function public.ping_send_chat(
    room_uuid uuid,
    body_text text,
    reply_chat_uuid uuid default null,
    reply_video_uuid uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    nickname_value text;
    new_id uuid;
begin
    if me is null then raise exception 'auth required'; end if;

    if reply_chat_uuid is not null and reply_video_uuid is not null then
        raise exception 'reply target must be exactly one';
    end if;

    if char_length(body_text) = 0 or char_length(body_text) > 2000 then
        raise exception 'invalid body length';
    end if;

    if not exists (
        select 1 from public.room_members where room_id = room_uuid and user_id = me
    ) then
        raise exception 'not a member';
    end if;

    if reply_chat_uuid is not null and not exists (
        select 1 from public.chat_messages where id = reply_chat_uuid and room_id = room_uuid
    ) then
        raise exception 'reply chat not in this room';
    end if;

    if reply_video_uuid is not null and not exists (
        select 1 from public.messages where id = reply_video_uuid and room_id = room_uuid
    ) then
        raise exception 'reply video not in this room';
    end if;

    select profiles.nickname into nickname_value from public.profiles where id = me;
    if nickname_value is null then nickname_value := 'unknown'; end if;

    insert into public.chat_messages(room_id, sender_uid, sender_nickname, body, reply_to_chat_id, reply_to_video_id)
    values (room_uuid, me, nickname_value, body_text, reply_chat_uuid, reply_video_uuid)
    returning id into new_id;

    return new_id;
end;
$$;

grant execute on function public.ping_send_chat(uuid, text, uuid, uuid) to authenticated;

-- 5. RPC: toggle reaction
create or replace function public.ping_react(
    target_kind text,
    target_uuid uuid,
    emoji_text text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    is_member boolean;
    existing_id uuid;
begin
    if me is null then raise exception 'auth required'; end if;
    if target_kind not in ('chat', 'video') then
        raise exception 'invalid target_kind';
    end if;
    if char_length(emoji_text) = 0 or char_length(emoji_text) > 16 then
        raise exception 'invalid emoji';
    end if;

    if target_kind = 'chat' then
        select exists (
            select 1 from public.chat_messages cm
            join public.room_members rm on rm.room_id = cm.room_id
            where cm.id = target_uuid and rm.user_id = me
        ) into is_member;
    else
        select exists (
            select 1 from public.messages m
            join public.room_members rm on rm.room_id = m.room_id
            where m.id = target_uuid and rm.user_id = me
        ) into is_member;
    end if;

    if not is_member then
        raise exception 'not a member of the target room';
    end if;

    if target_kind = 'chat' then
        select id into existing_id from public.message_reactions
        where chat_message_id = target_uuid and uid = me and emoji = emoji_text;
    else
        select id into existing_id from public.message_reactions
        where video_message_id = target_uuid and uid = me and emoji = emoji_text;
    end if;

    if existing_id is not null then
        delete from public.message_reactions where id = existing_id;
        return false;
    end if;

    if target_kind = 'chat' then
        insert into public.message_reactions(chat_message_id, uid, emoji)
        values (target_uuid, me, emoji_text);
    else
        insert into public.message_reactions(video_message_id, uid, emoji)
        values (target_uuid, me, emoji_text);
    end if;
    return true;
end;
$$;

grant execute on function public.ping_react(text, uuid, text) to authenticated;

-- 6. RPC: room chat messages (pagination)
create or replace function public.ping_room_chat_messages(
    room_uuid uuid,
    before_ts timestamptz default null,
    page_limit int default 50
) returns setof public.chat_messages
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then raise exception 'auth required'; end if;
    if not exists (
        select 1 from public.room_members where room_id = room_uuid and user_id = me
    ) then
        raise exception 'not a member';
    end if;

    return query
    select * from public.chat_messages
    where room_id = room_uuid
      and (before_ts is null or created_at < before_ts)
    order by created_at desc
    limit page_limit;
end;
$$;

grant execute on function public.ping_room_chat_messages(uuid, timestamptz, int) to authenticated;

-- 7. RPC: message reactions aggregated
create or replace function public.ping_message_reactions(
    chat_ids uuid[],
    video_ids uuid[]
) returns table (
    target_kind text,
    target_id uuid,
    emoji text,
    total_count int,
    my_reacted boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then raise exception 'auth required'; end if;

    return query
    select 'chat'::text, chat_message_id, emoji,
           count(*)::int,
           bool_or(uid = me)
    from public.message_reactions
    where chat_message_id = any(chat_ids)
    group by chat_message_id, emoji

    union all

    select 'video'::text, video_message_id, emoji,
           count(*)::int,
           bool_or(uid = me)
    from public.message_reactions
    where video_message_id = any(video_ids)
    group by video_message_id, emoji;
end;
$$;

grant execute on function public.ping_message_reactions(uuid[], uuid[]) to authenticated;

-- 8. RPC: mark room read
create or replace function public.ping_mark_room_read(room_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    current_map jsonb;
begin
    if me is null then raise exception 'auth required'; end if;

    select last_read_chat_at into current_map from public.profiles where id = me;
    if current_map is null then current_map := '{}'::jsonb; end if;

    update public.profiles
       set last_read_chat_at = current_map || jsonb_build_object(room_uuid::text, to_jsonb(now()))
     where id = me;
end;
$$;

grant execute on function public.ping_mark_room_read(uuid) to authenticated;

-- 9. RPC: unread chat counts
create or replace function public.ping_unread_chat_counts()
returns table (room_id uuid, unread_count int)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    read_map jsonb;
begin
    if me is null then raise exception 'auth required'; end if;
    select last_read_chat_at into read_map from public.profiles where id = me;
    if read_map is null then read_map := '{}'::jsonb; end if;

    return query
    select cm.room_id,
           count(*)::int as unread_count
    from public.chat_messages cm
    join public.room_members rm on rm.room_id = cm.room_id and rm.user_id = me
    where cm.sender_uid <> me
      and cm.created_at > coalesce(
            (read_map ->> cm.room_id::text)::timestamptz,
            'epoch'::timestamptz
          )
    group by cm.room_id;
end;
$$;

grant execute on function public.ping_unread_chat_counts() to authenticated;

-- 10. RPC: delete chat (sender only)
create or replace function public.ping_delete_chat(chat_uuid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    owner uuid;
begin
    if me is null then raise exception 'auth required'; end if;
    select sender_uid into owner from public.chat_messages where id = chat_uuid;
    if owner is null then return; end if;
    if owner <> me then raise exception 'only sender can delete'; end if;
    delete from public.chat_messages where id = chat_uuid;
end;
$$;

grant execute on function public.ping_delete_chat(uuid) to authenticated;

-- 11. Cleanup: extend to chat
create or replace function public.ping_cleanup_expired_data()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    msg_record record;
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

    delete from public.chat_messages where created_at < now() - interval '30 days';

    delete from public.message_reactions
    where chat_message_id is null and video_message_id is null;

    delete from public.invitations where expires_at < now();
    delete from public.invite_links where expires_at < now();
end;
$$;

-- 12. Realtime publication
do $$
begin
    begin
        execute 'alter publication supabase_realtime add table public.chat_messages';
    exception when others then
        raise notice 'chat_messages publication add skipped: %', sqlerrm;
    end;
    begin
        execute 'alter publication supabase_realtime add table public.message_reactions';
    exception when others then
        raise notice 'message_reactions publication add skipped: %', sqlerrm;
    end;
end$$;
