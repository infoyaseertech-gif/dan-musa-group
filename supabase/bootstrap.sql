-- =====================================================================
-- Run AFTER schema.sql, once, to create the first account (the CEO).
-- 1. In Supabase open Authentication > Users > Add user > Create new user.
--    Email:    ceo@staff.danmusa.ng     (or any email you prefer)
--    Password: choose a strong password. Tick "Auto Confirm User".
-- 2. Then run this query (change the email if you used another one):
-- =====================================================================
insert into public.profiles (id, name, username, role)
select id, 'Chief Executive', 'ceo', 'ceo'
from auth.users
where email = 'ceo@staff.danmusa.ng';
