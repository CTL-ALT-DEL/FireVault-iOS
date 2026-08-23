import { createClient } from "npm:@supabase/supabase-js@2.95.0";

const json = (body: Record<string, unknown>, status: number) =>
  Response.json(body, { status });

const nullableAttributionColumns = [
  ["admin_audit_log", "admin_user_id"],
  ["beta_cohorts", "created_by"],
  ["beta_cohorts", "updated_by"],
  ["enterprise_service_areas", "created_by"],
  ["enterprise_service_areas", "updated_by"],
  ["feature_flags", "updated_by"],
  ["integration_health_checks", "checked_by"],
  ["message_templates", "created_by"],
  ["message_templates", "updated_by"],
  ["organization_audit_log", "actor_user_id"],
  ["organization_feature_overrides", "updated_by"],
  ["organization_invitations", "invited_by"],
  ["organization_licenses", "created_by"],
  ["organization_members", "updated_by"],
  ["organization_usage_limits", "updated_by"],
  ["organizations", "created_by"],
  ["organizations", "updated_by"],
  ["plan_entitlements", "updated_by"],
  ["platform_announcements", "created_by"],
  ["platform_announcements", "updated_by"],
  ["platform_integrations", "updated_by"],
  ["platform_settings", "updated_by"],
  ["release_builds", "created_by"],
  ["release_rollouts", "created_by"],
  ["release_rollouts", "updated_by"],
  ["technician_groups", "created_by"],
  ["technician_groups", "updated_by"],
  ["tester_feedback", "created_by"],
  ["tester_feedback", "updated_by"],
] as const;

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceRoleKey) return json({ error: "Server configuration error" }, 500);

  const token = authorization.slice("Bearer ".length);
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error: userError } = await userClient.auth.getUser(token);
  if (userError || !user) return json({ error: "Unauthorized" }, 401);

  const admin = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // This non-null audit relationship intentionally blocks self-service deletion.
  // Support can reassign or remove the diagnostic record after reviewing it.
  const { count: diagnosticCount, error: diagnosticError } = await admin
    .from("admin_diagnostic_runs")
    .select("id", { count: "exact", head: true })
    .eq("started_by", user.id);
  if (diagnosticError) return json({ error: "Account dependency check failed" }, 500);
  if ((diagnosticCount ?? 0) > 0) {
    return json({ error: "This account requires support-assisted deletion" }, 409);
  }

  const [{ data: csvFiles, error: csvError }, { data: tripFiles, error: tripError }] = await Promise.all([
    admin.from("csv_import_jobs").select("storage_path").eq("user_id", user.id),
    admin.from("trip_log_files").select("bucket_id,storage_path").eq("user_id", user.id),
  ]);
  if (csvError || tripError) return json({ error: "File cleanup check failed" }, 500);

  const filesByBucket = new Map<string, string[]>();
  const append = (bucket: string, path: string | null) => {
    if (!path) return;
    filesByBucket.set(bucket, [...(filesByBucket.get(bucket) ?? []), path]);
  };
  for (const row of csvFiles ?? []) append("csv-imports", row.storage_path);
  for (const row of tripFiles ?? []) append(row.bucket_id, row.storage_path);

  for (const [bucket, paths] of filesByBucket) {
    for (let start = 0; start < paths.length; start += 100) {
      const { error } = await admin.storage.from(bucket).remove(paths.slice(start, start + 100));
      if (error) return json({ error: "File cleanup failed" }, 500);
    }
  }

  // Preserve shared operational history without retaining a foreign key to the user.
  for (const [table, column] of nullableAttributionColumns) {
    const { error } = await admin.from(table).update({ [column]: null }).eq(column, user.id);
    if (error) return json({ error: "Account dependency cleanup failed" }, 500);
  }

  const { error: deletionError } = await admin.auth.admin.deleteUser(user.id);
  if (deletionError) return json({ error: "Account deletion failed" }, 500);
  return new Response(null, { status: 204 });
});
