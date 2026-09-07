import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

type SubscriptionRow = {
  status: string;
  expires_at: string | null;
  grace_period_expires_at: string | null;
  revoked_at: string | null;
};

export type PaidAccessDecision = {
  allowed: boolean;
  enforcementEnabled: boolean;
  reason: "ROLLOUT" | "ACTIVE" | "GRACE_PERIOD" | "SUBSCRIPTION_REQUIRED";
};

export async function paidAccessDecision(
  admin: SupabaseClient,
  userID: string,
  now = new Date(),
): Promise<PaidAccessDecision> {
  const { data: settings, error: settingsError } = await admin
    .from("subscription_enforcement_settings")
    .select("enabled")
    .eq("singleton", true)
    .single();
  if (settingsError) throw settingsError;
  if (!settings.enabled) {
    return { allowed: true, enforcementEnabled: false, reason: "ROLLOUT" };
  }

  const { data, error } = await admin
    .from("user_subscription_access")
    .select("status,expires_at,grace_period_expires_at,revoked_at")
    .eq("user_id", userID)
    .maybeSingle();
  if (error) throw error;
  const access = data as SubscriptionRow | null;
  if (!access || access.revoked_at) {
    return { allowed: false, enforcementEnabled: true, reason: "SUBSCRIPTION_REQUIRED" };
  }

  const timestamp = now.getTime();
  if (access.status === "active" && future(access.expires_at, timestamp)) {
    return { allowed: true, enforcementEnabled: true, reason: "ACTIVE" };
  }
  if (access.status === "grace_period" && future(access.grace_period_expires_at, timestamp)) {
    return { allowed: true, enforcementEnabled: true, reason: "GRACE_PERIOD" };
  }
  return { allowed: false, enforcementEnabled: true, reason: "SUBSCRIPTION_REQUIRED" };
}

function future(value: string | null, now: number): boolean {
  if (!value) return false;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) && timestamp > now;
}
