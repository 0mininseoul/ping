-- v0.3.6: Allow sender to always read their own chat messages even if not in room_members
-- (Safety net for cases where room_members entry was not created automatically.)

drop policy if exists chat_messages_select_member on public.chat_messages;
create policy chat_messages_select_member_or_sender
on public.chat_messages for select to authenticated
using (
    sender_uid = auth.uid()
    or exists (
        select 1 from public.room_members
        where room_id = chat_messages.room_id and user_id = auth.uid()
    )
);

-- Relax ping_room_chat_messages: room_members OR has sent chat OR has sent ping in room
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
    ) and not exists (
        select 1 from public.chat_messages where room_id = room_uuid and sender_uid = me
    ) and not exists (
        select 1 from public.messages where room_id = room_uuid and sender_uid = me
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

-- Same relaxation for ping_room_messages (video) — same symptom possible
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
    if me is null then raise exception 'auth required'; end if;
    if not exists (
        select 1 from public.room_members where room_id = room_uuid and user_id = me
    ) and not exists (
        select 1 from public.messages where room_id = room_uuid and (sender_uid = me or receiver_uid = me)
    ) and not exists (
        select 1 from public.chat_messages where room_id = room_uuid and sender_uid = me
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
