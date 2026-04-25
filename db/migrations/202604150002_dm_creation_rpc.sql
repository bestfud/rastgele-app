create or replace function public.create_or_get_dm_conversation(target_profile_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_current_profile_id uuid;
  v_target_profile_id uuid;
  v_conversation_id uuid;
  v_lock_key text;
begin
  v_current_profile_id := public.current_profile_id();

  if v_current_profile_id is null then
    raise exception 'Current profile could not be resolved.';
  end if;

  if target_profile_id is null then
    raise exception 'Target profile is required.';
  end if;

  if target_profile_id = v_current_profile_id then
    raise exception 'You cannot create a direct message with yourself.';
  end if;

  select p.id
    into v_target_profile_id
  from public.profiles p
  where p.id = target_profile_id
  limit 1;

  if v_target_profile_id is null then
    raise exception 'Target profile was not found.';
  end if;

  if not exists (
    select 1
    from public.follows f
    where (
      f.follower_id = v_current_profile_id
      and f.following_id = v_target_profile_id
    ) or (
      f.follower_id = v_target_profile_id
      and f.following_id = v_current_profile_id
    )
  ) then
    raise exception 'At least one side must follow the other to send a message.';
  end if;

  v_lock_key := format(
    'dm:%s:%s',
    least(v_current_profile_id::text, v_target_profile_id::text),
    greatest(v_current_profile_id::text, v_target_profile_id::text)
  );
  perform pg_advisory_xact_lock(hashtextextended(v_lock_key, 0));

  select c.id
    into v_conversation_id
  from public.conversations c
  join public.conversation_participants cp
    on cp.conversation_id = c.id
  group by c.id, c.created_at
  having count(*) = 2
    and count(*) filter (
      where cp.profile_id = v_current_profile_id
    ) = 1
    and count(*) filter (
      where cp.profile_id = v_target_profile_id
    ) = 1
  order by c.created_at asc
  limit 1;

  if v_conversation_id is not null then
    return v_conversation_id;
  end if;

  insert into public.conversations (created_by_profile_id)
  values (v_current_profile_id)
  returning id into v_conversation_id;

  insert into public.conversation_participants (conversation_id, profile_id)
  values
    (v_conversation_id, v_current_profile_id),
    (v_conversation_id, v_target_profile_id);

  return v_conversation_id;
end;
$$;

revoke all on function public.create_or_get_dm_conversation(uuid) from public;
grant execute on function public.create_or_get_dm_conversation(uuid) to authenticated;

drop policy if exists conversation_participants_select_own on public.conversation_participants;
drop policy if exists conversation_participants_select_participant on public.conversation_participants;
create policy conversation_participants_select_participant
  on public.conversation_participants
  for select
  to authenticated
  using (
    public.is_conversation_participant(conversation_id)
  );

drop policy if exists conversation_participants_insert_authenticated on public.conversation_participants;
drop policy if exists conversation_participants_insert_creator_flow on public.conversation_participants;
