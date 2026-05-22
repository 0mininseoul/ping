-- Switch chat_ids / video_ids params to text[] for reliable PostgREST array handling
drop function if exists public.ping_message_reactions(uuid[], uuid[]);

create or replace function public.ping_message_reactions(
    chat_ids text[],
    video_ids text[]
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
    chat_uuids uuid[];
    video_uuids uuid[];
begin
    if me is null then raise exception 'auth required'; end if;

    chat_uuids := coalesce(
        (select array_agg(s::uuid) from unnest(chat_ids) s where s is not null and s <> ''),
        ARRAY[]::uuid[]
    );
    video_uuids := coalesce(
        (select array_agg(s::uuid) from unnest(video_ids) s where s is not null and s <> ''),
        ARRAY[]::uuid[]
    );

    return query
    select 'chat'::text, chat_message_id, emoji,
           count(*)::int,
           bool_or(uid = me)
    from public.message_reactions
    where chat_message_id = any(chat_uuids)
    group by chat_message_id, emoji

    union all

    select 'video'::text, video_message_id, emoji,
           count(*)::int,
           bool_or(uid = me)
    from public.message_reactions
    where video_message_id = any(video_uuids)
    group by video_message_id, emoji;
end;
$$;

grant execute on function public.ping_message_reactions(text[], text[]) to authenticated;
