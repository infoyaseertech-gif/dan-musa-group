# Dan Musa Group Staff Portal: live version (Phase 3)

This folder turns the staff portal preview into a real system with a shared database,
secure logins and server-enforced access.

```
supabase/schema.sql                      database, rules and security (run once)
supabase/bootstrap.sql                   creates the CEO account (run once)
supabase/functions/staff-admin/index.ts  lets the CEO add staff and reset their passwords
web/index.html                           the public website, with the staff sign-in
web/portal/index.html                    the staff portal (opens at /portal/)
web/config.js                            your Supabase address and public key (both pages read it)
web/assets/                              your logo files (the logo is already built into every page)
```

## What is enforced by the database (not just hidden in the screen)
- A person can only read or change data for the services the CEO ticked for them.
- Staff entries start as Pending. Only managers (for their own service) and the CEO can approve.
- Stock can never go below zero. A sale saves stock, sale record and receipt together or not at all.
- A payment can never exceed the invoice balance. Receipts and sales cannot be edited or deleted.
- Document numbers (invoices and receipts) are issued by the database and never repeat.
- Closed accounts see nothing. The last active CEO cannot be closed out.
- Staff cannot read the activity record. Every log line carries the real signed-in name.
- Uploaded files sit in a private store and are opened with short-lived links.

## Setup (about 30 minutes)

### 1. Create the database
1. Go to supabase.com, create a project. Choose the region closest to Nigeria. Save the database password.
2. Open **SQL Editor > New query**, paste all of `supabase/schema.sql`, click **Run**.

### 2. Create the CEO account
1. **Authentication > Users > Add user > Create new user**.
   Email `ceo@staff.danmusa.ng`, a strong password, tick **Auto Confirm User**.
2. In **SQL Editor** run `supabase/bootstrap.sql`.
3. **Authentication > Sign In / Providers > Email**: turn **off** "Allow new users to sign up".

### 3. Deploy the staff-admin function
```bash
npm install -g supabase
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy staff-admin
```
(Optional) to use a different login domain: `supabase secrets set EMAIL_DOMAIN=yourdomain.ng`
and set the same value in `web/config.js`.

### 4. Connect and deploy the website
1. **Project Settings > API**: copy the Project URL and the `anon public` key into `web/config.js`.
   The anon key is meant to be public. Never put the `service_role` key in the website.
2. Deploy the `web` folder to Vercel (`cd web && vercel`, or import the repo and set the root directory to `web`).
   No build step is needed. The website and the portal must stay on the same address (the portal lives
   at `/portal/`), because that is how the website's sign-in carries straight into the portal.
3. Add your own domain in Vercel (for example `danmusa.ng`) when you are ready.

### How the website and portal are linked
- The website has a **Staff login** button in the header and footer. Staff sign in there and are taken to `/portal/`.
- If someone is already signed in, the website offers **Continue to the staff portal**.
- Signing out in the portal returns to its own sign-in screen, which has a **Back to the website** link.

### 5. First use
1. Sign in with username `ceo`.
2. **Settings**: enter the bank details and confirm the company details printed on invoices.
3. **Staff > Add staff** for each person, ticking the services they may open. Change this later in **Service access**.
4. In **Phone and Accessories > Inventory** (as manager or CEO) add the real products and opening stock.

## Things to know
- Staff sign in with a username. Behind the scenes it is `username@staff.danmusa.ng`; no real mailbox is needed.
- The CEO can reset any staff password from **Staff > Reset password**. Staff can change their own under **Account**.
- Check your Supabase plan for automatic backups. The portal's **Settings > Download backup** saves the data you can see.
- The portal refreshes every minute and when you return to the tab, so two people see each other's updates.
- Customers are saved automatically from sales and invoices and can be picked from a list. Managers and the CEO
  can adjust stock for damaged, lost or returned items, and every adjustment is recorded with its reason.
- Not built yet: refund receipts, email or SMS alerts, online payment, and a mobile app (the portal works in the phone browser).


## Your logo
The Danmusa logo is built into the website, the portal sign-in, the portal menu, the browser tab icon, and the top of every invoice and receipt (including downloaded copies). To change it later, replace the logo in the page files or ask for an update.


## Repository and deployment (quick reference)
```
dan-musa-group/
  web/                    <- the website. Deploy THIS folder (Vercel "Root Directory" = web)
    index.html            public website + staff sign-in
    portal/index.html     staff portal (opens at /portal/)
    config.js             Supabase address and public key
    vercel.json           security headers
  supabase/               database, security rules and the staff-admin function
```
- Keep the GitHub repository **private**.
- `config.js` holds only the public (anon) key, so it is safe to commit. **Never** commit the `service_role` key,
  database password or any `.env` file.
- Every push to the `main` branch redeploys the site automatically on Vercel.
