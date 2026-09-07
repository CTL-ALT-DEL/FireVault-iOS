import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  deriveSubscriptionState,
  FIREVAULT_PRODUCT_IDS,
  verifyNotification,
  verifyRenewalInfo,
  verifyTransaction,
} from "../_shared/app-store.ts";

type NotificationRequest = { signedPayload?: unknown };

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const body = await request.json().catch(() => ({})) as NotificationRequest;
    const signedPayload = typeof body.signedPayload === "string" ? body.signedPayload.trim() : "";
    if (!signedPayload || signedPayload.length > 100_000) {
      return json({ error: "A signedPayload is required" }, 400);
    }

    const admin = adminClient();
    const { notification, environment } = await verifyNotification(signedPayload);
    const notificationUUID = normalizedUUID(notification.notificationUUID);
    if (!notificationUUID) throw new Error("Verified notification has no valid UUID");

    const { data: prior, error: priorError } = await admin
      .from("app_store_notification_events")
      .select("notification_uuid")
      .eq("notification_uuid", notificationUUID)
      .maybeSingle();
    if (priorError) throw priorError;
    if (prior) return json({ ok: true, duplicate: true });

    const signedTransaction = notification.data?.signedTransactionInfo;
    if (!signedTransaction) {
      await recordEvent(admin, {
        notificationUUID,
        notificationType: stringValue(notification.notificationType),
        subtype: stringValue(notification.subtype),
        environment,
        signedAt: isoDate(notification.signedDate),
      });
      return json({ ok: true, processed: false });
    }

    const verified = await verifyTransaction(signedTransaction);
    if (verified.environment !== environment) throw new Error("Notification environment mismatch");
    const transaction = verified.transaction;
    if (!transaction.productId || !FIREVAULT_PRODUCT_IDS.has(transaction.productId)) {
      throw new Error("Notification is not for a FireVault subscription");
    }
    if (!transaction.originalTransactionId || !transaction.transactionId) {
      throw new Error("Verified transaction is missing its identifiers");
    }

    const renewal = await verifyRenewalInfo(notification.data?.signedRenewalInfo, environment);
    if (renewal?.originalTransactionId &&
      renewal.originalTransactionId !== transaction.originalTransactionId) {
      throw new Error("Renewal information does not match the transaction");
    }
    if (renewal?.productId && renewal.productId !== transaction.productId) {
      throw new Error("Renewal product does not match the transaction");
    }
    const userID = await resolveUserID(admin, transaction.appAccountToken, transaction.originalTransactionId);
    const state = deriveSubscriptionState(transaction, renewal);

    if (userID) {
      const { error: updateError } = await admin.rpc("upsert_app_store_subscription_access", {
        p_user_id: userID,
        p_product_id: transaction.productId,
        p_status: state.status,
        p_environment: environment,
        p_original_transaction_id: transaction.originalTransactionId,
        p_latest_transaction_id: transaction.transactionId,
        p_app_account_token: normalizedUUID(transaction.appAccountToken),
        p_expires_at: state.expiresAt,
        p_grace_period_expires_at: state.gracePeriodExpiresAt,
        p_revoked_at: state.revokedAt,
        p_auto_renew_enabled: state.autoRenewEnabled,
        p_offer_type: transaction.offerType ?? null,
        p_source_signed_at: isoDate(notification.signedDate ?? transaction.signedDate) ?? new Date().toISOString(),
      });
      if (updateError) throw updateError;
    }

    await recordEvent(admin, {
      notificationUUID,
      notificationType: stringValue(notification.notificationType),
      subtype: stringValue(notification.subtype),
      environment,
      signedAt: isoDate(notification.signedDate),
      userID,
      originalTransactionID: transaction.originalTransactionId,
      latestTransactionID: transaction.transactionId,
    });

    return json({ ok: true, processed: Boolean(userID) });
  } catch (error) {
    console.error("App Store notification verification failed", error);
    // Non-2xx responses cause Apple to retry production V2 notifications.
    return json({ error: "Notification could not be verified or processed" }, 500);
  }
});

async function resolveUserID(
  admin: SupabaseClient,
  rawAppAccountToken: string | undefined,
  originalTransactionID: string,
): Promise<string | null> {
  const appAccountToken = normalizedUUID(rawAppAccountToken);
  if (rawAppAccountToken && !appAccountToken) throw new Error("Invalid appAccountToken");
  if (appAccountToken) {
    const { data, error } = await admin.auth.admin.getUserById(appAccountToken);
    if (error || !data.user) throw new Error("appAccountToken does not identify a FireVault user");
    return data.user.id;
  }

  const { data, error } = await admin
    .from("user_subscription_access")
    .select("user_id")
    .eq("original_transaction_id", originalTransactionID)
    .maybeSingle();
  if (error) throw error;
  return data?.user_id ?? null;
}

async function recordEvent(
  admin: SupabaseClient,
  event: {
    notificationUUID: string;
    notificationType: string | null;
    subtype: string | null;
    environment: string;
    signedAt: string | null;
    userID?: string | null;
    originalTransactionID?: string | null;
    latestTransactionID?: string | null;
  },
) {
  const { error } = await admin.from("app_store_notification_events").insert({
    notification_uuid: event.notificationUUID,
    notification_type: event.notificationType,
    subtype: event.subtype,
    environment: event.environment,
    signed_at: event.signedAt,
    user_id: event.userID ?? null,
    original_transaction_id: event.originalTransactionID ?? null,
    latest_transaction_id: event.latestTransactionID ?? null,
  });
  // A concurrent retry may win the idempotency race; that is already processed.
  if (error && error.code !== "23505") throw error;
}

function adminClient() {
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) throw new Error("Supabase server configuration is incomplete");
  return createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function normalizedUUID(value: string | undefined): string | null {
  const normalized = value?.trim().toLowerCase() ?? "";
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(normalized)
    ? normalized
    : null;
}

function isoDate(milliseconds: number | undefined): string | null {
  return milliseconds && Number.isFinite(milliseconds)
    ? new Date(milliseconds).toISOString()
    : null;
}

function stringValue(value: unknown): string | null {
  return value === undefined || value === null ? null : String(value);
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
}
