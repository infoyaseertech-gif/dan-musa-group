// Supabase Edge Function: staff-admin
// Lets the CEO create staff logins and reset staff passwords from the portal.
// Only the CEO can call it. The service-role key stays on the server.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: caller } = await admin.auth.getUser(token);
    if (!caller?.user) return json({ error: "Please sign in again." }, 401);
    const { data: me } = await admin.from("profiles").select("role, active").eq("id", caller.user.id).single();
    if (!me || me.role !== "ceo" || !me.active) return json({ error: "Only the CEO can do this." }, 403);

    const body = await req.json();
    const password = String(body.password ?? "");
    if (password.length < 6) return json({ error: "Password must be at least 6 characters." }, 400);

    if (body.action === "reset") {
      const { data: target } = await admin.from("profiles").select("id").eq("id", body.user_id).single();
      if (!target) return json({ error: "Staff member not found." }, 404);
      const { error } = await admin.auth.admin.updateUserById(target.id, { password });
      return error ? json({ error: error.message }, 400) : json({ ok: true });
    }

    if (body.action === "create") {
      const uname = String(body.username ?? "").trim().toLowerCase();
      if (!body.name || !/^[a-z0-9._-]{3,30}$/.test(uname))
        return json({ error: "Username must be 3 to 30 letters, numbers, dots or dashes." }, 400);
      if (!["mgr", "staff"].includes(body.role)) return json({ error: "Role must be Staff or Manager." }, 400);
      const domain = Deno.env.get("EMAIL_DOMAIN") ?? "staff.danmusa.ng";
      const { data: created, error: e1 } = await admin.auth.admin.createUser({
        email: `${uname}@${domain}`, password, email_confirm: true,
      });
      if (e1) return json({ error: e1.message.includes("already") ? "That username is taken." : e1.message }, 400);
      const id = created.user.id;
      const { error: e2 } = await admin.from("profiles").insert({ id, name: String(body.name).trim(), username: uname, role: body.role });
      if (e2) { await admin.auth.admin.deleteUser(id); return json({ error: e2.message }, 400); }
      const rows = (Array.isArray(body.services) ? body.services : []).map((service: string) => ({ user_id: id, service }));
      if (rows.length) await admin.from("user_services").insert(rows);
      return json({ ok: true, id });
    }
    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
