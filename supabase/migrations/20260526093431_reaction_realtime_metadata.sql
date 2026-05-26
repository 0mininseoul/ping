-- Store denormalized reaction target metadata for room history refresh and
-- Supabase Realtime filters. Realtime cannot filter by joins, so the room and
-- canonical target identity must live on message_reactions itself.

alter table public.message_reactions
    add column if not exists room_id uuid references public.rooms(id) on delete cascade,
    add column if not exists target_kind text,
    add column if not exists target_id uuid;

create index if not exists reactions_room_idx
    on public.message_reactions (room_id);

create index if not exists reactions_target_idx
    on public.message_reactions (target_kind, target_id);

create or replace function public.ping_fill_message_reaction_metadata()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if (new.chat_message_id is null) = (new.video_message_id is null) then
        raise exception 'reaction target must be exactly one';
    end if;

    if new.chat_message_id is not null then
        select cm.room_id, 'chat'::text, new.chat_message_id
          into new.room_id, new.target_kind, new.target_id
          from public.chat_messages cm
         where cm.id = new.chat_message_id;
    else
        select m.room_id, 'video'::text, new.video_message_id
          into new.room_id, new.target_kind, new.target_id
          from public.messages m
         where m.id = new.video_message_id;
    end if;

    if new.room_id is null or new.target_kind is null or new.target_id is null then
        raise exception 'reaction target not found';
    end if;

    return new;
end;
$$;

drop trigger if exists fill_message_reaction_metadata on public.message_reactions;

create trigger fill_message_reaction_metadata
before insert or update on public.message_reactions
for each row
execute function public.ping_fill_message_reaction_metadata();

update public.message_reactions mr
   set room_id = cm.room_id,
       target_kind = 'chat',
       target_id = mr.chat_message_id
  from public.chat_messages cm
 where mr.chat_message_id = cm.id
   and (
        mr.room_id is null
        or mr.target_kind is null
        or mr.target_id is null
   );

update public.message_reactions mr
   set room_id = m.room_id,
       target_kind = 'video',
       target_id = mr.video_message_id
  from public.messages m
 where mr.video_message_id = m.id
   and (
        mr.room_id is null
        or mr.target_kind is null
        or mr.target_id is null
   );

do $$
begin
    if not exists (
        select 1
          from pg_constraint
         where conname = 'reactions_target_kind_valid'
           and conrelid = 'public.message_reactions'::regclass
    ) then
        alter table public.message_reactions
            add constraint reactions_target_kind_valid
            check (target_kind in ('chat', 'video')) not valid;
    end if;

    if not exists (
        select 1
          from pg_constraint
         where conname = 'reactions_target_metadata_consistent'
           and conrelid = 'public.message_reactions'::regclass
    ) then
        alter table public.message_reactions
            add constraint reactions_target_metadata_consistent
            check (
                (
                    target_kind = 'chat'
                    and chat_message_id is not null
                    and video_message_id is null
                    and target_id = chat_message_id
                )
                or (
                    target_kind = 'video'
                    and video_message_id is not null
                    and chat_message_id is null
                    and target_id = video_message_id
                )
            ) not valid;
    end if;
end;
$$;

alter table public.message_reactions validate constraint reactions_target_kind_valid;
alter table public.message_reactions validate constraint reactions_target_metadata_consistent;
alter table public.message_reactions alter column room_id set not null;
alter table public.message_reactions alter column target_kind set not null;
alter table public.message_reactions alter column target_id set not null;
alter table public.message_reactions replica identity full;

drop policy if exists reactions_select_member on public.message_reactions;
create policy reactions_select_member
    on public.message_reactions for select to authenticated
    using (
        exists (
            select 1
              from public.room_members rm
             where rm.room_id = message_reactions.room_id
               and rm.user_id = auth.uid()
        )
    );

drop policy if exists reactions_insert_own on public.message_reactions;
create policy reactions_insert_own
    on public.message_reactions for insert to authenticated
    with check (
        uid = auth.uid()
        and exists (
            select 1
              from public.room_members rm
             where rm.room_id = message_reactions.room_id
               and rm.user_id = auth.uid()
        )
    );

drop function if exists public.ping_message_reactions(uuid[], uuid[]);
drop function if exists public.ping_message_reactions(text[], text[]);

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
    select mr.target_kind,
           mr.target_id,
           mr.emoji,
           count(*)::int,
           bool_or(mr.uid = me)
      from public.message_reactions mr
      join public.room_members rm
        on rm.room_id = mr.room_id
       and rm.user_id = me
     where (
            mr.target_kind = 'chat'
            and mr.target_id = any(chat_uuids)
        )
        or (
            mr.target_kind = 'video'
            and mr.target_id = any(video_uuids)
        )
     group by mr.target_kind, mr.target_id, mr.emoji;
end;
$$;

grant execute on function public.ping_message_reactions(text[], text[]) to authenticated;

do $$
begin
    begin
        alter publication supabase_realtime add table public.message_reactions;
    exception
        when duplicate_object then
            null;
        when undefined_object then
            raise notice 'supabase_realtime publication missing; skipping message_reactions publication';
        when others then
            raise notice 'message_reactions publication add skipped: %', sqlerrm;
    end;
end;
$$;
