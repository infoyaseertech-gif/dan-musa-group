-- =====================================================================
-- Dan Musa Group Staff Portal: database schema, security and rules
-- Run this once in Supabase: SQL Editor > New query > paste > Run.
-- =====================================================================

-- ---------- Core tables ----------
create table public.services (
  key    text primary key,
  name   text not null,
  prefix text not null unique,
  sort   int  not null default 0,
  is_store boolean not null default false      -- true for services that run a shop with stock
);
insert into public.services (key, name, prefix, sort, is_store) values
  ('tel','Phone and Accessories','TEL',1,true),
  ('tex','Textile','TEX',2,true),
  ('re' ,'Real Estate','RE',3,false),
  ('rec','Recycling','REC',4,false),
  ('oil','Oil and Gas','OIL',5,false),
  ('min','Mining','MIN',6,false),
  ('log','Logistics','LOG',7,false);

create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  name       text not null,
  username   text not null unique,
  role       text not null check (role in ('ceo','mgr','staff')),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

-- Which services each person is allowed to open (set by the CEO)
create table public.user_services (
  user_id uuid not null references public.profiles(id) on delete cascade,
  service text not null references public.services(key),
  primary key (user_id, service)
);

create table public.settings (
  id    int primary key default 1 check (id = 1),
  name  text, trade text, rc text, addr text, phone text, email text,
  bank  text not null default '',
  vat   numeric not null default 7.5,
  foot  text
);
insert into public.settings (id,name,trade,rc,addr,phone,email,bank,vat,foot) values
  (1,'Danmusa International Trade and Services Ltd','Dan Musa Group','7630923',
   '19B Rabah Road by NAFCLUB, Kaduna, Kaduna State, Nigeria','0814 046 7162',
   'danmusanigltd@gmail.com','',7.5,'Thank you for your business.');

create table public.counters (
  service text not null,
  kind    text not null,
  n       int  not null default 0,
  primary key (service, kind)
);

-- ---------- Security helper functions ----------
create or replace function public.is_ceo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'ceo' and active)
$$;

create or replace function public.me_active() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select active from profiles where id = auth.uid()), false)
$$;

-- true when the signed-in person may open this service
create or replace function public.has_svc(s text) returns boolean
language sql stable security definer set search_path = public as $$
  select s is not null and (
    is_ceo() or exists (
      select 1 from profiles p join user_services u on u.user_id = p.id
      where p.id = auth.uid() and p.active and u.service = s))
$$;

-- true for the CEO, or a manager who may open this service
create or replace function public.lead_for(s text) returns boolean
language sql stable security definer set search_path = public as $$
  select is_ceo() or (s is not null and exists (
      select 1 from profiles p join user_services u on u.user_id = p.id
      where p.id = auth.uid() and p.active and p.role = 'mgr' and u.service = s))
$$;

-- Document numbers such as DMG-OIL-INV-0001, never repeated
create or replace function public.next_no(p_service text, p_kind text) returns text
language plpgsql security definer set search_path = public as $$
declare v_n int; v_prefix text;
begin
  if p_kind not in ('INV','RCT') then raise exception 'Unknown document type'; end if;
  if not has_svc(p_service) then raise exception 'You do not have access to this service'; end if;
  select prefix into v_prefix from services where key = p_service;
  insert into counters (service, kind, n) values (p_service, p_kind, 1)
    on conflict (service, kind) do update set n = counters.n + 1
    returning n into v_n;
  return format('DMG-%s-%s-%s', v_prefix, p_kind, lpad(v_n::text, 4, '0'));
end $$;

-- ---------- Shops: Phone and Accessories, Textile (stock, sales, receipts) ----------
create table public.products (
  id         uuid primary key default gen_random_uuid(),
  service    text not null references public.services(key),
  sku        text unique,
  name       text not null,
  cat        text,
  brand      text,
  imei       text check (imei is null or imei ~ '^[0-9]{14,16}$'),   -- phones: one handset per product
  colour     text,
  unit       text not null default 'Piece' check (unit in ('Piece','Yard','Metre','Roll','Set')),
  cost       numeric not null default 0 check (cost >= 0),
  price      numeric not null default 0 check (price >= 0),
  min_stock  numeric(14,2) not null default 0,
  qty        numeric(14,2) not null default 0 check (qty >= 0),   -- changed only by stock_moves
  created_at timestamptz not null default now()
);

create unique index products_imei_key on public.products (imei) where imei is not null;

create table public.stock_moves (
  id         uuid primary key default gen_random_uuid(),
  service    text not null references public.services(key),
  date       date not null default current_date,
  product_id uuid not null references public.products(id),
  type       text not null check (type in ('in','sale','loss','return')),   -- loss = damaged or lost, return = customer return
  qty        numeric(14,2) not null check (qty > 0),
  cost       numeric,
  price      numeric,
  ref        text,
  created_by uuid not null default auth.uid() references public.profiles(id)
);

create table public.sales (
  id         uuid primary key default gen_random_uuid(),
  no         text not null unique,
  service    text not null references public.services(key),
  date       date not null default current_date,
  customer   text,
  phone      text,
  method     text,
  lines      jsonb not null,
  total      numeric not null check (total >= 0),
  created_by uuid not null default auth.uid() references public.profiles(id)
);

-- ---------- Records for the other services ----------
create table public.records (
  id         uuid primary key default gen_random_uuid(),
  service    text not null references public.services(key),
  date       date not null default current_date,
  data       jsonb not null,
  status     text not null default 'Pending' check (status in ('Pending','Approved')),
  created_by uuid not null default auth.uid() references public.profiles(id)
);

-- ---------- Invoices and receipts (all services) ----------
create table public.invoices (
  id         uuid primary key default gen_random_uuid(),
  no         text not null unique,
  service    text not null references public.services(key),
  date       date not null,
  due        date,
  customer   text not null,
  phone      text, addr text,
  items      jsonb not null,
  sub        numeric not null,
  vat        numeric not null default 0,
  vat_rate   numeric not null default 0,
  total      numeric not null,
  paid       numeric not null default 0,                    -- changed only by receipts
  notes      text,
  created_by uuid not null default auth.uid() references public.profiles(id)
);

create table public.receipts (
  id         uuid primary key default gen_random_uuid(),
  no         text not null unique,
  service    text not null references public.services(key),
  date       date not null,
  customer   text,
  descr      text,
  amt        numeric not null check (amt > 0),
  method     text,
  ref        text,
  sale_id    uuid references public.sales(id),
  inv_id     uuid references public.invoices(id),
  created_by uuid not null default auth.uid() references public.profiles(id)
);

-- ---------- Customers (shared by everyone who can open a service) ----------
create table public.customers (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  phone      text,
  addr       text,
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create or replace function public.has_any_svc() returns boolean
language sql stable security definer set search_path = public as $$
  select is_ceo() or exists (
    select 1 from profiles p join user_services u on u.user_id = p.id
    where p.id = auth.uid() and p.active)
$$;
create or replace function public.is_lead_any() returns boolean
language sql stable security definer set search_path = public as $$
  select is_ceo() or exists (select 1 from profiles where id = auth.uid() and role = 'mgr' and active)
$$;

-- ---------- Office tools ----------
create table public.tasks (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  assignee   uuid not null references public.profiles(id),
  service    text references public.services(key),
  due        date,
  status     text not null default 'To do' check (status in ('To do','In progress','Done')),
  created_by uuid not null default auth.uid() references public.profiles(id)
);

create table public.announcements (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  body       text not null,
  scope      text not null default 'all',      -- 'all' or a service key
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.documents (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  type       text,
  service    text not null references public.services(key),
  expiry     date,
  file_path  text,
  created_by uuid not null default auth.uid() references public.profiles(id)
);

create table public.activity_log (
  id        uuid primary key default gen_random_uuid(),
  at        timestamptz not null default now(),
  user_name text,
  action    text not null
);

-- ---------- Automatic rules (triggers) ----------
-- Stock changes only through stock movements, and never below zero.
create or replace function public.apply_stock_move() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_name text; v_qty numeric; v_svc text;
begin
  select name, qty, service into v_name, v_qty, v_svc from products where id = new.product_id for update;
  if v_svc is distinct from new.service then raise exception 'Product and stock movement are in different services'; end if;
  if new.type in ('sale','loss') and v_qty < new.qty then
    raise exception 'Not enough stock for %. Only % left.', v_name, v_qty;
  end if;
  update products set qty = qty + case when new.type in ('in','return') then new.qty else -new.qty end
    where id = new.product_id;
  return new;
end $$;
create trigger trg_stock_move before insert on public.stock_moves
  for each row execute function public.apply_stock_move();

-- Only services marked as shops can hold products.
create or replace function public.guard_shop() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from services where key = new.service and is_store) then
    raise exception 'This service does not run a shop';
  end if;
  return new;
end $$;
create trigger trg_shop_products before insert on public.products
  for each row execute function public.guard_shop();

-- A payment receipt raises the invoice's paid amount and can never exceed the total.
create or replace function public.apply_receipt() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_total numeric; v_paid numeric; v_service text;
begin
  if new.inv_id is not null then
    select total, paid, service into v_total, v_paid, v_service from invoices where id = new.inv_id for update;
    if v_service is distinct from new.service then raise exception 'Receipt and invoice are in different services'; end if;
    if v_paid + new.amt > v_total then raise exception 'Payment is more than the balance on the invoice'; end if;
    update invoices set paid = paid + new.amt where id = new.inv_id;
  end if;
  return new;
end $$;
create trigger trg_receipt before insert on public.receipts
  for each row execute function public.apply_receipt();

-- The activity log always records the real signed-in name.
create or replace function public.stamp_log() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.user_name := coalesce((select name from profiles where id = auth.uid()), 'Unknown');
  new.at := now();
  return new;
end $$;
create trigger trg_log before insert on public.activity_log
  for each row execute function public.stamp_log();

-- Staff can move their own task forward but cannot rewrite it.
create or replace function public.guard_task() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not lead_for(old.service) and
     (new.title, new.assignee, new.service, new.due, new.created_by)
       is distinct from (old.title, old.assignee, old.service, old.due, old.created_by) then
    raise exception 'You can only change the status of a task';
  end if;
  return new;
end $$;
create trigger trg_task before update on public.tasks
  for each row execute function public.guard_task();

-- Completing a sale is one all-or-nothing step: stock out, sale record and receipt.
create or replace function public.complete_sale(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare l jsonb; v_total numeric := 0; v_svc text := p->>'service';
begin
  if not exists (select 1 from services where key = v_svc and is_store) then
    raise exception 'This service does not run a shop';
  end if;
  if not has_svc(v_svc) then raise exception 'You do not have access to this service'; end if;
  for l in select * from jsonb_array_elements(p->'lines') loop
    insert into stock_moves (service, date, product_id, type, qty, price, ref, created_by)
      values (v_svc, (p->>'date')::date, (l->>'pid')::uuid, 'sale', (l->>'qty')::numeric,
              (l->>'price')::numeric, p->>'id', auth.uid());          -- the stock rule runs here
    v_total := v_total + (l->>'qty')::numeric * (l->>'price')::numeric;
  end loop;
  insert into sales (id, no, service, date, customer, phone, method, lines, total, created_by)
    values ((p->>'id')::uuid, p->>'no', v_svc, (p->>'date')::date, p->>'customer', p->>'phone',
            p->>'method', p->'lines', v_total, auth.uid());
  insert into receipts (id, no, service, date, customer, descr, amt, method, ref, sale_id, created_by)
    values ((p->>'receipt_id')::uuid, p->>'no', v_svc, (p->>'date')::date, p->>'customer',
            p->>'descr', v_total, p->>'method', '', (p->>'id')::uuid, auth.uid());
end $$;

-- The last active CEO can never be closed out or demoted.
create or replace function public.guard_ceo() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.role = 'ceo' and (new.active = false or new.role <> 'ceo')
     and not exists (select 1 from profiles where role = 'ceo' and active and id <> old.id) then
    raise exception 'There must always be one active CEO';
  end if;
  return new;
end $$;
create trigger trg_ceo before update on public.profiles
  for each row execute function public.guard_ceo();

-- ---------- Access rights (grants) ----------
revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, public;
grant usage on schema public to authenticated;
grant execute on function public.is_ceo(), public.me_active(), public.has_svc(text),
  public.lead_for(text), public.next_no(text,text), public.complete_sale(jsonb),
  public.has_any_svc(), public.is_lead_any() to authenticated;

grant select on customers to authenticated;
grant insert (id,name,phone,addr,created_by) on customers to authenticated;
grant delete on customers to authenticated;
grant select on services, profiles, user_services, settings, products, stock_moves, sales, records,
  invoices, receipts, tasks, announcements, documents, activity_log to authenticated;
grant insert (id,service,sku,name,cat,brand,unit,cost,price,min_stock) on products to authenticated;
grant update (sku,name,cat,brand,unit,cost,price,min_stock) on products to authenticated;
grant insert (id,service,date,product_id,type,qty,cost,price,ref,created_by) on stock_moves to authenticated;
grant insert (id,service,date,data,status,created_by) on records to authenticated;
grant update (status) on records to authenticated;
grant delete on records to authenticated;
grant insert (id,no,service,date,due,customer,phone,addr,items,sub,vat,vat_rate,total,notes,created_by) on invoices to authenticated;
grant delete on invoices to authenticated;
grant insert (id,no,service,date,customer,descr,amt,method,ref,sale_id,inv_id,created_by) on receipts to authenticated;
grant insert (id,title,assignee,service,due,status,created_by) on tasks to authenticated;
grant update (status) on tasks to authenticated;
grant delete on tasks to authenticated;
grant insert (id,title,body,scope,created_by,created_at) on announcements to authenticated;
grant delete on announcements to authenticated;
grant insert (id,name,type,service,expiry,file_path,created_by) on documents to authenticated;
grant delete on documents to authenticated;
grant insert (id,action) on activity_log to authenticated;
grant update (name,role,active) on profiles to authenticated;
grant insert, delete on user_services to authenticated;
grant update (name,trade,rc,addr,phone,email,bank,vat,foot) on settings to authenticated;

-- ---------- Row level security: who can see and change which rows ----------
alter table public.services      enable row level security;
alter table public.profiles      enable row level security;
alter table public.user_services enable row level security;
alter table public.settings      enable row level security;
alter table public.counters      enable row level security;
alter table public.products      enable row level security;
alter table public.stock_moves   enable row level security;
alter table public.sales         enable row level security;
alter table public.records       enable row level security;
alter table public.invoices      enable row level security;
alter table public.receipts      enable row level security;
alter table public.tasks         enable row level security;
alter table public.announcements enable row level security;
alter table public.documents     enable row level security;
alter table public.activity_log  enable row level security;
alter table public.customers     enable row level security;

create policy services_sel on services for select using (me_active());
create policy settings_sel on settings for select using (me_active());
create policy settings_upd on settings for update using (is_ceo()) with check (is_ceo());

create policy prof_sel on profiles for select using (me_active());
create policy prof_upd on profiles for update using (is_ceo()) with check (is_ceo());
create policy us_sel on user_services for select
  using (is_ceo() or user_id = auth.uid() or has_svc(service));
create policy us_ins on user_services for insert with check (is_ceo());
create policy us_del on user_services for delete using (is_ceo());

-- Shops (Phone and Accessories, Textile): everything is scoped to the service
create policy prod_sel on products for select using (has_svc(service));
create policy prod_ins on products for insert with check (lead_for(service));
create policy prod_upd on products for update using (lead_for(service)) with check (lead_for(service));
create policy mv_sel on stock_moves for select using (has_svc(service));
create policy mv_ins on stock_moves for insert with check (created_by = auth.uid() and (
  (type = 'in' and has_svc(service)) or (type in ('loss','return') and lead_for(service))));
create policy sale_sel on sales for select using (has_svc(service));

-- Records: staff enter them as Pending; only managers and the CEO approve
create policy rec_sel on records for select using (has_svc(service));
create policy rec_ins on records for insert
  with check (has_svc(service) and created_by = auth.uid() and (status = 'Pending' or lead_for(service)));
create policy rec_upd on records for update using (lead_for(service)) with check (lead_for(service));
create policy rec_del on records for delete using (lead_for(service));

-- Invoices and receipts
create policy inv_sel on invoices for select using (has_svc(service));
create policy inv_ins on invoices for insert with check (has_svc(service) and created_by = auth.uid());
create policy inv_del on invoices for delete using (lead_for(service) and paid = 0);
create policy rct_sel on receipts for select using (has_svc(service));
create policy rct_ins on receipts for insert with check (has_svc(service) and created_by = auth.uid());

create policy cust_sel on customers for select using (has_any_svc());
create policy cust_ins on customers for insert with check (has_any_svc() and created_by = auth.uid());
create policy cust_del on customers for delete using (is_lead_any());

-- Tasks, announcements, documents, activity
create policy task_sel on tasks for select
  using (is_ceo() or assignee = auth.uid() or created_by = auth.uid() or lead_for(service));
create policy task_ins on tasks for insert
  with check (created_by = auth.uid() and (is_ceo() or lead_for(service)));
create policy task_upd on tasks for update
  using (assignee = auth.uid() or lead_for(service)) with check (assignee = auth.uid() or lead_for(service));
create policy task_del on tasks for delete using (lead_for(service));

create policy ann_sel on announcements for select using (me_active() and (scope = 'all' or has_svc(scope)));
create policy ann_ins on announcements for insert
  with check (created_by = auth.uid() and ((scope = 'all' and is_ceo()) or lead_for(scope)));
create policy ann_del on announcements for delete using (created_by = auth.uid() or is_ceo());

create policy doc_sel on documents for select using (has_svc(service));
create policy doc_ins on documents for insert with check (has_svc(service) and created_by = auth.uid());
create policy doc_del on documents for delete using (lead_for(service));

create policy log_sel on activity_log for select using (is_ceo());
create policy log_ins on activity_log for insert with check (me_active());

-- ---------- Private file storage for documents ----------
-- Files live in the 'documents' bucket under <service>/<file>. Only people with
-- access to that service can see or add files; managers and the CEO can delete.
do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    insert into storage.buckets (id, name, public) values ('documents','documents',false)
      on conflict (id) do nothing;
    execute $p$create policy docs_read on storage.objects for select
      using (bucket_id = 'documents' and public.has_svc(split_part(name,'/',1)))$p$;
    execute $p$create policy docs_add on storage.objects for insert
      with check (bucket_id = 'documents' and public.has_svc(split_part(name,'/',1)))$p$;
    execute $p$create policy docs_del on storage.objects for delete
      using (bucket_id = 'documents' and public.lead_for(split_part(name,'/',1)))$p$;
  end if;
end $$;
