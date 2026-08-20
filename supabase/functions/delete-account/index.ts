import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const authorization = request.headers.get("Authorization");
  if (!authorization) return new Response("Unauthorized", { status: 401 });
  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error } = await anon.auth.getUser();
  if (error || !user) return new Response("Unauthorized", { status: 401 });

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { error: deletionError } = await admin.auth.admin.deleteUser(user.id);
  if (deletionError) return Response.json({ error: "Account deletion failed" }, { status: 500 });
  return new Response(null, { status: 204 });
});
