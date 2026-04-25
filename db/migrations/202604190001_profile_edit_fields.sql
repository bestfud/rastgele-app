alter table public.profiles
  add column if not exists cover_url text,
  add column if not exists website_url text,
  add column if not exists instagram text,
  add column if not exists x_handle text,
  add column if not exists youtube text,
  add column if not exists tiktok text;
