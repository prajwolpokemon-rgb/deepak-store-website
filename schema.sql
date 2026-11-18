-- DEEPAK STORE Supabase schema. Run in Supabase SQL Editor.
-- Before launch: create the owner account using Supabase Auth with prajwolpokemon@gmail.com,
-- then insert that user's UUID into public.admin_users (see README). Never store passwords here.

create extension if not exists pgcrypto;

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.packages (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  details text,
  price integer not null check (price > 0),
  badge text,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  package_id uuid references public.packages(id) on delete set null,
  package_name text not null,
  price integer not null check (price > 0),
  player_uid text not null,
  server text not null check (server = 'Bangladesh'),
  customer_name text,
  contact text not null,
  payment_method text not null check (payment_method in ('esewa_qr','esewa_transaction')),
  transaction_id text,
  payment_proof_path text,
  status text not null default 'pending' check (status in ('pending','processing','completed','rejected')),
  created_at timestamptz not null default now()
);

create table if not exists public.store_settings (
  key text primary key,
  value text not null default ''
);

create or replace function public.is_store_admin()
returns boolean language sql stable security definer
set search_path = public
as $$ select exists(select 1 from public.admin_users where user_id = auth.uid()); $$;

alter table public.admin_users enable row level security;
alter table public.packages enable row level security;
alter table public.orders enable row level security;
alter table public.store_settings enable row level security;

drop policy if exists "admins read admin list" on public.admin_users;
create policy "admins read admin list" on public.admin_users for select to authenticated using (public.is_store_admin());

drop policy if exists "public read active packages" on public.packages;
create policy "public read active packages" on public.packages for select to anon, authenticated using (active or public.is_store_admin());
drop policy if exists "admins manage packages" on public.packages;
create policy "admins manage packages" on public.packages for all to authenticated using (public.is_store_admin()) with check (public.is_store_admin());

drop policy if exists "customers create own orders" on public.orders;
create policy "customers create own orders" on public.orders for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "customers read own orders" on public.orders;
create policy "customers read own orders" on public.orders for select to authenticated using (auth.uid() = user_id or public.is_store_admin());
drop policy if exists "admins update orders" on public.orders;
create policy "admins update orders" on public.orders for update to authenticated using (public.is_store_admin()) with check (public.is_store_admin());

drop policy if exists "public read support settings" on public.store_settings;
create policy "public read support settings" on public.store_settings for select to anon, authenticated using (key in ('whatsapp','support_email','esewa_qr_url') or public.is_store_admin());
drop policy if exists "admins manage settings" on public.store_settings;
create policy "admins manage settings" on public.store_settings for all to authenticated using (public.is_store_admin()) with check (public.is_store_admin());

-- Storage buckets. Payment proofs private; store assets public (QR image only).
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('payment-proofs','payment-proofs',false,5242880,array['image/png','image/jpeg','image/webp'])
on conflict (id) do nothing;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('store-assets','store-assets',true,5242880,array['image/png','image/jpeg','image/webp'])
on conflict (id) do nothing;

drop policy if exists "customers upload own payment proofs" on storage.objects;
create policy "customers upload own payment proofs" on storage.objects for insert to authenticated
with check (bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "customers and admins read payment proofs" on storage.objects;
create policy "customers and admins read payment proofs" on storage.objects for select to authenticated
using (bucket_id='payment-proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_store_admin()));
drop policy if exists "admins upload store assets" on storage.objects;
create policy "admins upload store assets" on storage.objects for insert to authenticated
with check (bucket_id='store-assets' and public.is_store_admin());
drop policy if exists "admins update store assets" on storage.objects;
create policy "admins update store assets" on storage.objects for update to authenticated
using (bucket_id='store-assets' and public.is_store_admin()) with check (bucket_id='store-assets' and public.is_store_admin());
drop policy if exists "public view store assets" on storage.objects;
create policy "public view store assets" on storage.objects for select to anon, authenticated using (bucket_id='store-assets');

-- Optional starter packages from the previous demo. Replace prices with your verified Matrix rates + margin.
insert into public.packages(name,details,price,badge,sort_order)
select 'Weekly Lite','Weekly Lite membership',50,'MEMBERSHIP',1
where not exists(select 1 from public.packages);
insert into public.packages(name,details,price,badge,sort_order)
select 'Normal Weekly Membership','Normal Weekly Membership',170,'POPULAR',2
where not exists(select 1 from public.packages);
