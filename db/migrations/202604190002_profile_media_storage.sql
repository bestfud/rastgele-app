alter table public.profiles
  add column if not exists cover_url text;

insert into storage.buckets (id, name, public)
values
  ('avatars', 'avatars', true),
  ('covers', 'covers', true)
on conflict (id) do nothing;

drop policy if exists "authenticated_can_view_avatars" on storage.objects;
create policy "authenticated_can_view_avatars"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'avatars');

drop policy if exists "authenticated_can_upload_avatars" on storage.objects;
create policy "authenticated_can_upload_avatars"
  on storage.objects
  for insert
  to authenticated
  with check (bucket_id = 'avatars');

drop policy if exists "authenticated_can_update_avatars" on storage.objects;
create policy "authenticated_can_update_avatars"
  on storage.objects
  for update
  to authenticated
  using (bucket_id = 'avatars')
  with check (bucket_id = 'avatars');

drop policy if exists "authenticated_can_view_covers" on storage.objects;
create policy "authenticated_can_view_covers"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'covers');

drop policy if exists "authenticated_can_upload_covers" on storage.objects;
create policy "authenticated_can_upload_covers"
  on storage.objects
  for insert
  to authenticated
  with check (bucket_id = 'covers');

drop policy if exists "authenticated_can_update_covers" on storage.objects;
create policy "authenticated_can_update_covers"
  on storage.objects
  for update
  to authenticated
  using (bucket_id = 'covers')
  with check (bucket_id = 'covers');
