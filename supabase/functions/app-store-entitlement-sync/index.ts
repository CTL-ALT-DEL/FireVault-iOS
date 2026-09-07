import { createClient } from "npm:@supabase/supabase-js@2";
import {
  deriveSubscriptionState,
  FIREVAULT_PRODUCT_IDS,
  verifyRenewalInfo,
  verifyTransaction,
} from "../_shared/app-store.ts";

type SyncRequest = {
  signedTransaction?: unknown;
  signedRenewalInfo?: unknown;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authorization = request.headers.get("authorization");
    if (!authorization?.toLowerCase().startsWith("bearer ")) {
      return json({ error: "Authentication required" }, 401);
    }

    const admin = adminClient();
    const { data: userData, error: userError } = await admin.auth.getUser(
      authorization.slice(7),
    );
    const user = userData.user;
    if (userError || !user) return json({ error: "Invalid or expired session" }, 401);

    const body = await request.json().catch(() => ({})) as SyncRequest;
    const signedTransaction = typeof body.signedTransaction === "string"
      ? body.signedTransaction.trim()
      : "";
    if (!signedTransaction || signedTransaction.length > 50_000) {
      return json({ error: "A signed App Store transaction is required" }, 400);
    }
    const signedRenewalInfo = typeof body.signedRenewalInfo === "string"
      ? body.signedRenewalInfo.trim()
      : "";
    if (signedRenewalInfo.length > 50_000) {
      return json({ error: "The signed renewal information is too large" }, 400);
    }

    const { transaction, environment } = await verifyTransaction(signedTransaction);
    if (!transaction.productId || !FIREVAULT_PRODUCT_IDS.has(transaction.productId)) {
      return json({ error: "Transaction is not for a FireVault subscription" }, 400);
    }
    if (!transaction.originalTransactionId || !transaction.transactionId) {
      return json({ error: "Verified transaction is missing its identifiers" }, 400);
    }

    const appAccountToken = normalizedUUID(transaction.appAccountToken);
    if (transaction.appAccountToken && !appAccountToken) {
      return json({ error: "Verified transaction has an invalid account token" }, 400);
    }
    if (appAccountToken && appAccountToken !== user.id.toLowerCase()) {
      return json({ error: "This purchase belongs to a different FireVault account" }, 403);
    }

    const { data: existingBinding, error: bindingError } = await admin
      .from("user_subscription_access")
      .select("user_id")
      .eq("original_transaction_id", transaction.originalTransactionId)
      .maybeSingle();
    if (bindingError) throw bindingError;
    if (existingBinding && existingBinding.user_id !== user.id) {
      return json({ error: "This purchase is already linked to another FireVault account" }, 409);
    }

    const renewal = await verifyRenewalInfo(signedRenewalInfo || undefined, environment);
    if (renewal?.originalTransactionId &&
      renewal.originalTransactionId !== transaction.originalTransactionId) {
      return json({ error: "Renewal information does not match the transaction" }, 400);
    }
    if (renewal?.productId && renewal.productId !== transaction.productId) {
      return json({ error: "Renewal product does not match the transaction" }, 400);
    }

    const state = deriveSubscriptionState(transaction, renewal);
    const sourceSignedAt = new Date(
      Math.max(
        transaction.signedDate ?? Date.now(),
        renewal?.signedDate ?? 0,
      ),
    ).toISOString();
    const { data: updated, error: updateError } = await admin.rpc(
      "upsert_app_store_subscription_access",
      {
        p_user_id: user.id,
        p_product_id: transaction.productId,
        p_status: state.status,
        p_environment: environment,
        p_original_transaction_id: transaction.originalTransactionId,
        p_latest_transaction_id: transaction.transactionId,
        p_app_account_token: appAccountToken,
        p_expires_at: state.expiresAt,
        p_grace_period_expires_at: state.gracePeriodExpiresAt,
        p_revoked_at: state.revokedAt,
        p_auto_renew_enabled: state.autoRenewEnabled,
        p_offer_type: transaction.offerType ?? null,
        p_source_signed_at: sourceSignedAt,
      },
    );
    if (updateError) throw updateError;

    return json({
      ok: true,
      updated: Boolean(updated),
      status: state.status,
      productID: transaction.productId,
      expiresAt: state.expiresAt,
      environment,
    });
  } catch (error) {
    console.error("App Store entitlement sync failed", error);
    return json({ error: "The App Store purchase could not be verified" }, 400);
  }
});

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

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
