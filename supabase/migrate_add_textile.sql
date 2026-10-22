-- =====================================================================
-- Dan Musa Group: add the Textile shop to a database that already has
-- the earlier schema (keeps all existing data).
-- If you have NOT run schema.sql yet, skip this file and run schema.sql instead.
-- Run once in Supabase: SQL Editor > New query > paste > Run.
-- =====================================================================
begin;

-- 1. Services: mark shops and add Textile
alter table public.services add column if not exists is_store boolean not null default false;
insert into public.services (key, name, prefix, sort, is_store) values ('tex','Textile','TEX',2,true)
  on conflict (key) do nothing;
update public.services set is_store = true where key in ('tel','tex');
update public.services set sort = case key when 'tel' then 1 when 'tex' then 2 when 're' then 3
  when 'rec' then 4 when 'oil' then 5 when 'min' then 6 when 'log' then 7 else sort end;

-- 2. Products: service, unit of sale, decimal quantities
alter table public.products add column if not exists service text references public.services(key);
update public.products set service = 'tel' where service is null;
alter table public.products alter column service set not null;
alter table public.products add column if not exists unit text not null default 'Piece';
alter table public.products drop constraint if exists products_unit_check;
alter table public.products add constraint products_unit_check check (unit in ('Piece','Yard','Metre','Roll','Set'));
alter table public.products alter column qty type numeric(14,2);
alter table public.products alter column min_stock type numeric(14,2);

-- 3. Stock movements and sales carry their service
alter table public.stock_moves add column if not exists service text references public.services(key);
update public.stock_moves m set service = p.service from public.products p where p.id = m.product_id and m.service is null;
alter table public.stock_moves alter column service set not null;
alter table public.stock_moves alter column qty type numeric(14,2);
alter table public.sales drop constraint if exists sales_service_check;
alter table public.sales alter column service drop default;

-- 4. Rules
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

create or replace function public.guard_shop() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from services where key = new.service and is_store) then
    raise exception 'This service does not run a shop';
  end if;
  return new;
end $$;
drop trigger if exists trg_shop_products on public.products;
create trigger trg_shop_products before insert on public.products
  for each row execute function public.guard_shop();

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
              (l->>'price')::numeric, p->>'id', auth.uid());
    v_total := v_total + (l->>'qty')::numeric * (l->>'price')::numeric;
  end loop;
  insert into sales (id, no, service, date, customer, phone, method, lines, total, created_by)
    values ((p->>'id')::uuid, p->>'no', v_svc, (p->>'date')::date, p->>'customer', p->>'phone',
            p->>'method', p->'lines', v_total, auth.uid());
  insert into receipts (id, no, service, date, customer, descr, amt, method, ref, sale_id, created_by)
    values ((p->>'receipt_id')::uuid, p->>'no', v_svc, (p->>'date')::date, p->>'customer',
            p->>'descr', v_total, p->>'method', '', (p->>'id')::uuid, auth.uid());
end $$;

-- 5. Access rights
revoke insert, update on public.products from authenticated;
grant insert (id,service,sku,name,cat,brand,unit,cost,price,min_stock) on public.products to authenticated;
grant update (sku,name,cat,brand,unit,cost,price,min_stock) on public.products to authenticated;
revoke insert on public.stock_moves from authenticated;
grant insert (id,service,date,product_id,type,qty,cost,price,ref,created_by) on public.stock_moves to authenticated;

-- 6. Row security: scoped to each shop's service
drop policy if exists prod_sel on public.products;   drop policy if exists prod_ins on public.products;
drop policy if exists prod_upd on public.products;   drop policy if exists mv_sel on public.stock_moves;
drop policy if exists mv_ins on public.stock_moves;  drop policy if exists sale_sel on public.sales;
create policy prod_sel on public.products for select using (has_svc(service));
create policy prod_ins on public.products for insert with check (lead_for(service));
create policy prod_upd on public.products for update using (lead_for(service)) with check (lead_for(service));
create policy mv_sel on public.stock_moves for select using (has_svc(service));
create policy mv_ins on public.stock_moves for insert with check (created_by = auth.uid() and (
  (type = 'in' and has_svc(service)) or (type in ('loss','return') and lead_for(service))));
create policy sale_sel on public.sales for select using (has_svc(service));

commit;
