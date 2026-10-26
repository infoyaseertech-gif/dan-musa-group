// Supabase connection for the Dan Musa Group website and staff portal.
// The anon key is meant to be public; the database rules protect the data.
window.DMG_CONFIG = {
  url: "https://winlgtflhwiaraniwpts.supabase.co",
  anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndpbmxndGZsaHdpYXJhbml3cHRzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxODUzMjUsImV4cCI6MjA5NDc2MTMyNX0.Co0PPWjMtNeIIa8GSqkulgytzhwbm33p718HsPMECKU",
  schema: "danmusa",                // Dan Musa tables live in their own schema, apart from other sites
  emailDomain: "staff.danmusa.ng"   // staff usernames become username@this-domain
};

// Make every Supabase client on the site and portal use the Dan Musa schema.
// (This file loads right after the Supabase library on both pages.)
(function () {
  var S = window.supabase, C = window.DMG_CONFIG;
  if (!S || !S.createClient || !C.schema || S.__dmgSchema) return;
  var original = S.createClient;
  var patched = Object.assign({}, S, {
    __dmgSchema: true,
    createClient: function (url, key, options) {
      options = options || {};
      options.db = Object.assign({ schema: C.schema }, options.db || {});
      return original.call(S, url, key, options);
    }
  });
  window.supabase = patched;
})();
