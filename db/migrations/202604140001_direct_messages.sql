create extension if not exists pgcrypto;

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table if not exists public.conversation_participants (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (conversation_id, profile_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  text text not null check (char_length(trim(text)) > 0),
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists idx_conversation_participants_profile
  on public.conversation_participants(profile_id);

create index if not exists idx_conversation_participants_conversation
  on public.conversation_participants(conversation_id);

create index if not exists idx_messages_conversation_created
  on public.messages(conversation_id, created_at);

create index if not exists idx_messages_unread
  on public.messages(conversation_id, read_at)
  where read_at is null;

alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages enable row level security;

drop policy if exists conversations_select_participant on public.conversations;
create policy conversations_select_participant
  on public.conversations
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.conversation_participants cp
      join public.profiles p on p.id = cp.profile_id
      where cp.conversation_id = conversations.id
        and p.auth_user_id = auth.uid()
    )
  );

drop policy if exists conversations_insert_authenticated on public.conversations;
create policy conversations_insert_authenticated
  on public.conversations
  for insert
  to authenticated
  with check (true);

drop policy if exists conversation_participants_select_own on public.conversation_participants;
create policy conversation_participants_select_own
  on public.conversation_participants
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = conversation_participants.profile_id
        and p.auth_user_id = auth.uid()
    )
  );

drop policy if exists conversation_participants_insert_authenticated on public.conversation_participants;
create policy conversation_participants_insert_authenticated
  on public.conversation_participants
  for insert
  to authenticated
  with check (true);

drop policy if exists messages_select_participant on public.messages;
create policy messages_select_participant
  on public.messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.conversation_participants cp
      join public.profiles p on p.id = cp.profile_id
      where cp.conversation_id = messages.conversation_id
        and p.auth_user_id = auth.uid()
    )
  );

drop policy if exists messages_insert_sender_participant on public.messages;
create policy messages_insert_sender_participant
  on public.messages
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.profiles p
      where p.id = sender_id
        and p.auth_user_id = auth.uid()
    )
    and exists (
      select 1
      from public.conversation_participants cp
      where cp.conversation_id = messages.conversation_id
        and cp.profile_id = messages.sender_id
    )
  );

drop policy if exists messages_update_participant on public.messages;
create policy messages_update_participant
  on public.messages
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.conversation_participants cp
      join public.profiles p on p.id = cp.profile_id
      where cp.conversation_id = messages.conversation_id
        and p.auth_user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.conversation_participants cp
      join public.profiles p on p.id = cp.profile_id
      where cp.conversation_id = messages.conversation_id
        and p.auth_user_id = auth.uid()
    )
  );
