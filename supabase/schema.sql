-- Apply this schema in Supabase SQL editor or via Supabase CLI.
-- The schema enables RLS and the minimum tables for profiles + food entries.

create extension if not exists "pgcrypto";

create table if not exists public.profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    calories_target numeric not null default 0,
    protein_target numeric not null default 0,
    carbs_target numeric not null default 0,
    fat_target numeric not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.food_entries (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    date date not null,
    input_type text not null check (input_type in ('photo', 'text', 'photo+text')),
    input_text text,
    image_path text,
    calories numeric not null default 0,
    protein numeric not null default 0,
    carbs numeric not null default 0,
    fat numeric not null default 0,
    ai_confidence numeric check (ai_confidence between 0 and 1),
    ai_source text not null default 'unknown' check (ai_source in ('food_photo', 'label_photo', 'text', 'unknown')),
    ai_notes text not null default '',
    created_at timestamptz not null default now()
);

create index if not exists food_entries_user_date_idx on public.food_entries (user_id, date);
create index if not exists profiles_updated_at_idx on public.profiles (updated_at);

alter table public.profiles enable row level security;
alter table public.food_entries enable row level security;

create policy "Profiles select" on public.profiles
    for select using (auth.uid() = user_id);

create policy "Profiles insert" on public.profiles
    for insert with check (auth.uid() = user_id);

create policy "Profiles update" on public.profiles
    for update using (auth.uid() = user_id);

create policy "Food entries all" on public.food_entries
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.set_profiles_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at
    before update on public.profiles
    for each row execute function public.set_profiles_updated_at();
