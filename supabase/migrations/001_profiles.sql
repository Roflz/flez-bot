-- flez-bot: profiles table + RLS for Supabase Auth (Option A)
-- Run this in your Supabase project SQL editor after enabling Auth.

-- Public profile per auth user (email, display_name, subscription_tier)
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  subscription_tier text not null default 'free' check (subscription_tier in ('free', 'paid'))
);

-- RLS: users can only read/update their own profile
alter table public.profiles enable row level security;

create policy "Users can read own profile"
  on public.profiles for select
  using (auth.uid() = user_id);

create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = user_id);

-- Service role can insert/update for trigger and admin; anon/authenticated cannot insert
-- (inserts happen via trigger only)
create policy "Service role can manage profiles"
  on public.profiles for all
  using (auth.role() = 'service_role');

-- Trigger: create profile row when a new user signs up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (user_id, email, display_name, subscription_tier)
  values (
    new.id,
    new.raw_user_meta_data->>'email',
    coalesce(new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    'free'
  )
  on conflict (user_id) do update set
    email = coalesce(excluded.email, profiles.email),
    display_name = coalesce(excluded.display_name, profiles.display_name);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Optional: allow authenticated users to insert their own profile if trigger missed
create policy "Users can insert own profile"
  on public.profiles for insert
  with check (auth.uid() = user_id);
