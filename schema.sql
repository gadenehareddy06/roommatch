-- RoomMatch Supabase schema. Paste into Supabase > SQL Editor > Run.
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  name text, role text not null default 'tenant' check (role in ('owner','tenant')),
  created_at timestamptz default now());

create function handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles(id, name, role)
  values (new.id, new.raw_user_meta_data->>'name', coalesce(new.raw_user_meta_data->>'role','tenant'));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

create table properties (
  id bigint generated always as identity primary key,
  owner_id uuid not null references profiles(id) on delete cascade,
  title text not null, description text, locality text, city text not null, state text not null,
  property_type text not null, rent int not null check (rent > 0), deposit int check (deposit >= 0),
  furnishing text, available_from date, status text not null default 'Available' check (status in ('Available','Rented')),
  suitable_for text[] not null default '{}', amenities text[] not null default '{}',
  created_at timestamptz default now(), updated_at timestamptz default now());
create index on properties (state, city);

create table favorites (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  property_id bigint not null references properties(id) on delete cascade,
  created_at timestamptz default now(), unique (user_id, property_id));

create table inquiries (
  id bigint generated always as identity primary key,
  property_id bigint not null references properties(id) on delete cascade,
  tenant_id uuid not null references profiles(id) on delete cascade,
  message text not null check (length(message) >= 5), move_in_date date, contact_pref text,
  status text not null default 'Sent' check (status in ('Sent','Viewed','Responded','Closed')),
  created_at timestamptz default now(), updated_at timestamptz default now());

alter table profiles enable row level security;
alter table properties enable row level security;
alter table favorites enable row level security;
alter table inquiries enable row level security;

create policy "own profile read" on profiles for select using (id = auth.uid());
create policy "own profile update" on profiles for update using (id = auth.uid()) with check (id = auth.uid() and role = (select role from profiles where id = auth.uid()));

create policy "anyone can view listings" on properties for select using (true);
create policy "owners add listings" on properties for insert with check (owner_id = auth.uid() and (select role from profiles where id = auth.uid()) = 'owner');
create policy "owners edit own listings" on properties for update using (owner_id = auth.uid());
create policy "owners delete own listings" on properties for delete using (owner_id = auth.uid());

create policy "own favorites" on favorites for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "tenants send inquiries" on inquiries for insert with check (tenant_id = auth.uid());
create policy "tenant or owner reads inquiries" on inquiries for select using (
  tenant_id = auth.uid() or exists (select 1 from properties p where p.id = property_id and p.owner_id = auth.uid()));
create policy "owner updates inquiry status" on inquiries for update using (
  exists (select 1 from properties p where p.id = property_id and p.owner_id = auth.uid()));
