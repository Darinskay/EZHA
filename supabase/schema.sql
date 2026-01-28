-- Apply this schema in Supabase SQL editor or via Supabase CLI.
-- The schema enables RLS and the minimum tables for profiles + food entries.

create extension if not exists "pgcrypto";

create table if not exists public.profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    calories_target numeric not null default 0,
    protein_target numeric not null default 0,
    carbs_target numeric not null default 0,
    fat_target numeric not null default 0,
    active_target_id uuid,
    active_date date not null default current_date,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.daily_targets (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
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
    ai_source text not null default 'unknown' check (ai_source in ('food_photo', 'label_photo', 'text', 'unknown', 'library')),
    ai_notes text not null default '',
    created_at timestamptz not null default now()
);

create table if not exists public.food_entry_items (
    id uuid primary key default gen_random_uuid(),
    entry_id uuid not null references public.food_entries(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    grams numeric not null check (grams > 0),
    calories numeric not null default 0,
    protein numeric not null default 0,
    carbs numeric not null default 0,
    fat numeric not null default 0,
    ai_confidence numeric check (ai_confidence between 0 and 1),
    ai_notes text not null default '',
    created_at timestamptz not null default now()
);

create table if not exists public.daily_summaries (
    user_id uuid not null references auth.users(id) on delete cascade,
    date date not null,
    calories numeric not null default 0,
    protein numeric not null default 0,
    carbs numeric not null default 0,
    fat numeric not null default 0,
    calories_target numeric not null default 0,
    protein_target numeric not null default 0,
    carbs_target numeric not null default 0,
    fat_target numeric not null default 0,
    daily_target_id uuid,
    daily_target_name text,
    has_data boolean not null default true,
    created_at timestamptz not null default now(),
    primary key (user_id, date)
);

create table if not exists public.saved_foods (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    unit_type text not null check (unit_type in ('per_100g', 'per_serving')),
    serving_size numeric,
    serving_unit text,
    calories_per_100g numeric not null default 0,
    protein_per_100g numeric not null default 0,
    carbs_per_100g numeric not null default 0,
    fat_per_100g numeric not null default 0,
    calories_per_serving numeric not null default 0,
    protein_per_serving numeric not null default 0,
    carbs_per_serving numeric not null default 0,
    fat_per_serving numeric not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.saved_foods add column if not exists calories_per_100g numeric not null default 0;
alter table public.saved_foods add column if not exists protein_per_100g numeric not null default 0;
alter table public.saved_foods add column if not exists carbs_per_100g numeric not null default 0;
alter table public.saved_foods add column if not exists fat_per_100g numeric not null default 0;
alter table public.saved_foods add column if not exists calories_per_serving numeric not null default 0;
alter table public.saved_foods add column if not exists protein_per_serving numeric not null default 0;
alter table public.saved_foods add column if not exists carbs_per_serving numeric not null default 0;
alter table public.saved_foods add column if not exists fat_per_serving numeric not null default 0;

create index if not exists food_entries_user_date_idx on public.food_entries (user_id, date);
create index if not exists food_entry_items_entry_idx on public.food_entry_items (entry_id);
create index if not exists food_entry_items_user_idx on public.food_entry_items (user_id);
create index if not exists profiles_updated_at_idx on public.profiles (updated_at);
create index if not exists daily_targets_user_name_idx on public.daily_targets (user_id, name);
create index if not exists daily_summaries_user_date_idx on public.daily_summaries (user_id, date);
create index if not exists saved_foods_user_name_idx on public.saved_foods (user_id, name);

alter table public.profiles enable row level security;
alter table public.daily_targets enable row level security;
alter table public.food_entries enable row level security;
alter table public.food_entry_items enable row level security;
alter table public.daily_summaries enable row level security;
alter table public.saved_foods enable row level security;

create policy "Profiles select" on public.profiles
    for select using (auth.uid() = user_id);

create policy "Profiles insert" on public.profiles
    for insert with check (auth.uid() = user_id);

create policy "Profiles update" on public.profiles
    for update using (auth.uid() = user_id);

create policy "Daily targets all" on public.daily_targets
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Food entries all" on public.food_entries
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Food entry items all" on public.food_entry_items
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Daily summaries all" on public.daily_summaries
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Saved foods all" on public.saved_foods
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

create or replace function public.set_daily_targets_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

drop trigger if exists daily_targets_updated_at on public.daily_targets;
create trigger daily_targets_updated_at
    before update on public.daily_targets
    for each row execute function public.set_daily_targets_updated_at();

create or replace function public.set_saved_foods_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

drop trigger if exists saved_foods_updated_at on public.saved_foods;
create trigger saved_foods_updated_at
    before update on public.saved_foods
    for each row execute function public.set_saved_foods_updated_at();
