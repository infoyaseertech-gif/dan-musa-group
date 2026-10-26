-- =====================================================================
-- ADMIN EMERGENCY RECOVERY (use only if the Admin is locked out)
-- Run in Supabase: SQL Editor > New query. Change the words in CAPITALS,
-- then run ONE block at a time.
-- =====================================================================

-- A. Set a new password for the Admin (default admin login: ceo@staff.danmusa.ng)
update auth.users
set encrypted_password = extensions.crypt('NEW_PASSWORD_HERE', extensions.gen_salt('bf')),
    updated_at = now()
where email = 'ceo@staff.danmusa.ng';

-- B. Change the Admin login name (keeps the password)
--    Example: from 'ceo' to 'admin'. Sign in afterwards with the new name.
update auth.users set email = 'NEWNAME@staff.danmusa.ng', updated_at = now()
where email = 'ceo@staff.danmusa.ng';
update public.profiles set username = 'NEWNAME' where username = 'ceo';

-- C. Make an existing person an Admin (full access)
update public.profiles set role = 'ceo' where username = 'THEIR_LOGIN_NAME';

-- D. Open an Admin account that was closed by mistake (use the Admin's current login name)
update public.profiles set active = true where username = 'ceo';
