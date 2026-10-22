-- =====================================================================
-- Dan Musa Group: clean reset
-- Use ONLY on a new project that has no real data yet.
-- It removes everything schema.sql created, so schema.sql can be run again.
-- =====================================================================
drop table if exists public.activity_log, public.documents, public.announcements, public.tasks,
  public.customers, public.receipts, public.invoices, public.records, public.sales,
  public.stock_moves, public.products, public.counters, public.settings,
  public.user_services, public.profiles, public.services cascade;

drop function if exists public.is_ceo(), public.me_active(), public.has_svc(text), public.lead_for(text),
  public.next_no(text,text), public.complete_sale(jsonb), public.has_any_svc(), public.is_lead_any(),
  public.apply_stock_move(), public.apply_receipt(), public.stamp_log(), public.guard_task(),
  public.guard_ceo() cascade;

do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    execute 'drop policy if exists docs_read on storage.objects';
    execute 'drop policy if exists docs_add on storage.objects';
    execute 'drop policy if exists docs_del on storage.objects';
  end if;
end $$;
