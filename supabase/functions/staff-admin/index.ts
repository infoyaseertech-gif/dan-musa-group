// Supabase Edge Function: staff-admin
// Account management that needs the secret service key, so it runs on the server:
//   create : the Admin (CEO) adds a staff member, manager or another Admin
//   reset  : the Admin sets a new password for anyone
//   rename : change a login name (and display name).
//            The Admin can change anyone's; everyone else can change only their own.
//            Changing your own login name needs your current password.
// The service-role key never reaches the browser.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const NAME_RE = /^[a-z0-9._-]{3,30}$/;
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const validLogin = (v: string) => NAME_RE.test(v) || EMAIL_RE.test(v);
const toEmail = (login: string, domain: string) => (login.includes("@") ? login : `${login}@${domain}`);
const BAD_LOGIN = "Login name must be 3 to 30 letters, numbers, dots or dashes, or a full email address.";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const domain = Deno.env.get("EMAIL_DOMAIN") ?? "staff.danmusa.ng";

    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: caller } = await admin.auth.getUser(token);
    if (!caller?.user) return json({ error: "Please sign in again." }, 401);
    const { data: me } = await admin.from("profiles").select("id, role, active, username").eq("id", caller.user.id).single();
    if (!me || !me.active) return json({ error: "Your access is closed." }, 403);
    const isAdmin = me.role === "ceo";

    const body = await req.json();
    const action = body.action;

    // ---------- reset a password (Admin only) ----------
    if (action === "reset") {
      if (!isAdmin) return json({ error: "Only the Admin can do this." }, 403);
      const password = String(body.password ?? "");
      if (password.length < 6) return json({ error: "Password must be at least 6 characters." }, 400);
      const { data: target } = await admin.from("profiles").select("id").eq("id", body.user_id).single();
      if (!target) return json({ error: "Staff member not found." }, 404);
      const { error } = await admin.auth.admin.updateUserById(target.id, { password });
      return error ? json({ error: error.message }, 400) : json({ ok: true });
    }

    // ---------- create an account (Admin only) ----------
    if (action === "create") {
      if (!isAdmin) return json({ error: "Only the Admin can do this." }, 403);
      const login = String(body.username ?? "").trim().toLowerCase();
      const password = String(body.password ?? "");
      if (!body.name || !validLogin(login)) return json({ error: BAD_LOGIN }, 400);
      if (password.length < 6) return json({ error: "Password must be at least 6 characters." }, 400);
      if (!["ceo", "mgr", "staff"].includes(body.role)) return json({ error: "Role must be Staff, Manager or Admin." }, 400);
      const { data: taken } = await admin.from("profiles").select("id").eq("username", login).maybeSingle();
      if (taken) return json({ error: "That login name is taken." }, 400);

      const { data: created, error: e1 } = await admin.auth.admin.createUser({
        email: toEmail(login, domain), password, email_confirm: true,
      });
      if (e1) return json({ error: e1.message.includes("already") ? "That login name is taken." : e1.message }, 400);
      const id = created.user.id;
      const { error: e2 } = await admin.from("profiles").insert({ id, name: String(body.name).trim(), username: login, role: body.role });
      if (e2) { await admin.auth.admin.deleteUser(id); return json({ error: e2.message }, 400); }
      if (body.role !== "ceo") {
        const rows = (Array.isArray(body.services) ? body.services : []).map((service: string) => ({ user_id: id, service }));
        if (rows.length) await admin.from("user_services").insert(rows);
      }
      return json({ ok: true, id });
    }

    // ---------- change a login name and/or display name ----------
    if (action === "rename") {
      const targetId = isAdmin && body.user_id ? String(body.user_id) : me.id;
      if (!isAdmin && body.user_id && body.user_id !== me.id) return json({ error: "You can only change your own login name." }, 403);

      // changing your own details needs your current password
      if (targetId === me.id) {
        const anon = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!);
        const { error } = await anon.auth.signInWithPassword({
          email: caller.user.email!, password: String(body.current_password ?? ""),
        });
        if (error) return json({ error: "Current password is not correct." }, 400);
      }

      const { data: target } = await admin.from("profiles").select("id, username, name").eq("id", targetId).single();
      if (!target) return json({ error: "Staff member not found." }, 404);

      const login = String(body.username ?? "").trim().toLowerCase();
      const name = String(body.name ?? "").trim();
      let email: string | undefined;

      if (login && login !== target.username) {
        if (!validLogin(login)) return json({ error: BAD_LOGIN }, 400);
        const { data: taken } = await admin.from("profiles").select("id").eq("username", login).neq("id", targetId).maybeSingle();
        if (taken) return json({ error: "That login name is already used." }, 400);

        const { data: old } = await admin.auth.admin.getUserById(targetId);
        email = toEmail(login, domain);
        const { error: e1 } = await admin.auth.admin.updateUserById(targetId, { email, email_confirm: true });
        if (e1) return json({ error: e1.message.includes("already") ? "That login name is already used." : e1.message }, 400);
        const changes: Record<string, string> = { username: login };
        if (name) changes.name = name;
        const { error: e2 } = await admin.from("profiles").update(changes).eq("id", targetId);
        if (e2) {
          if (old?.user?.email) await admin.auth.admin.updateUserById(targetId, { email: old.user.email, email_confirm: true });
          return json({ error: e2.message }, 400);
        }
      } else if (name && name !== target.name) {
        const { error } = await admin.from("profiles").update({ name }).eq("id", targetId);
        if (error) return json({ error: error.message }, 400);
      }
      return json({ ok: true, username: login || target.username, email });
    }

    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
