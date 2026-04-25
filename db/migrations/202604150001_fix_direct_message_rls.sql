create or replace function public.current_profile_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.id
  from public.profiles p
  where p.auth_user_id = auth.uid()
  limit 1
$$;

grant execute on function public.current_profile_id() to authenticated;

create or replace function public.is_conversation_participant(target_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = target_conversation_id
      and cp.profile_id = public.current_profile_id()
  )
$$;

grant execute on function public.is_conversation_participant(uuid) to authenticated;

alter table public.conversations
  add column if not exists created_by_profile_id uuid references public.profiles(id) on delete set null;

alter table public.conversations
  alter column created_by_profile_id set default public.current_profile_id();

create index if not exists idx_conversations_created_by_profile
  on public.conversations(created_by_profile_id);

drop policy if exists conversations_select_participant on public.conversations;
create policy conversations_select_participant
  on public.conversations
  for select
  to authenticated
  using (
    public.is_conversation_participant(id)
    or created_by_profile_id = public.current_profile_id()
  );

drop policy if exists conversations_insert_authenticated on public.conversations;
create policy conversations_insert_authenticated
  on public.conversations
  for insert
  to authenticated
  with check (
    created_by_profile_id is not null
    and created_by_profile_id = public.current_profile_id()
  );

drop policy if exists conversation_participants_select_own on public.conversation_participants;
create policy conversation_participants_select_participant
  on public.conversation_participants
  for select
  to authenticated
  using (
    public.is_conversation_participant(conversation_id)
    or exists (
      select 1
      from public.conversations c
      where c.id = conversation_participants.conversation_id
        and c.created_by_profile_id = public.current_profile_id()
    )
  );

drop policy if exists conversation_participants_insert_authenticated on public.conversation_participants;
create policy conversation_participants_insert_creator_flow
  on public.conversation_participants
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.conversations c
      where c.id = conversation_participants.conversation_id
        and c.created_by_profile_id = public.current_profile_id()
    )
    and (
      conversation_participants.profile_id = public.current_profile_id()
      or public.is_conversation_participant(conversation_participants.conversation_id)
    )
    and (
      select count(*)
      from public.conversation_participants cp
      where cp.conversation_id = conversation_participants.conversation_id
    ) < 2
  );

drop policy if exists messages_select_participant on public.messages;
create policy messages_select_participant
  on public.messages
  for select
  to authenticated
  using (
    public.is_conversation_participant(conversation_id)
  );

drop policy if exists messages_insert_sender_participant on public.messages;
create policy messages_insert_sender_participant
  on public.messages
  for insert
  to authenticated
  with check (
    sender_id = public.current_profile_id()
    and public.is_conversation_participant(conversation_id)
  );

drop policy if exists messages_update_participant on public.messages;
create policy messages_update_participant
  on public.messages
  for update
  to authenticated
  using (
    public.is_conversation_participant(conversation_id)
  )
  with check (
    public.is_conversation_participant(conversation_id)
  );
