-- Keep the metadata trigger helper private to triggers and make the Realtime
-- dependency fail closed if publication wiring is missing.

revoke all on function public.ping_fill_message_reaction_metadata()
    from public, anon, authenticated;

do $$
begin
    begin
        alter publication supabase_realtime add table public.message_reactions;
    exception
        when duplicate_object then
            null;
    end;

    if not exists (
        select 1
          from pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public'
           and tablename = 'message_reactions'
    ) then
        raise exception 'message_reactions must be in supabase_realtime publication';
    end if;
end;
$$;
