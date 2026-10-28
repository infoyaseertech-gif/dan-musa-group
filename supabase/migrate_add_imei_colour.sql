-- Dan Musa Group: phone details (IMEI, colour) on products.
-- Safe to run more than once. Already applied to the live danmusa schema.
-- If your tables live in the public schema, change danmusa to public.
alter table danmusa.products add column if not exists imei text;
alter table danmusa.products add column if not exists colour text;
alter table danmusa.products drop constraint if exists products_imei_format;
alter table danmusa.products add constraint products_imei_format check (imei is null or imei ~ '^[0-9]{14,16}$');
create unique index if not exists products_imei_key on danmusa.products (imei) where imei is not null;
