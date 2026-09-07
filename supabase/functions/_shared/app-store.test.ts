import {
  assertEquals,
} from "jsr:@std/assert@1";
import { deriveSubscriptionState } from "./app-store.ts";

Deno.test("current transaction is active", () => {
  const now = Date.UTC(2026, 8, 6);
  const state = deriveSubscriptionState(
    { expiresDate: now + 60_000, revocationDate: undefined },
    null,
    now,
  );

  assertEquals(state.status, "active");
  assertEquals(state.revokedAt, null);
});

Deno.test("grace period permits access after the transaction expires", () => {
  const now = Date.UTC(2026, 8, 6);
  const state = deriveSubscriptionState(
    { expiresDate: now - 60_000, revocationDate: undefined },
    {
      gracePeriodExpiresDate: now + 60_000,
      isInBillingRetryPeriod: true,
      autoRenewStatus: 1,
    },
    now,
  );

  assertEquals(state.status, "grace_period");
  assertEquals(state.autoRenewEnabled, true);
});

Deno.test("revocation always removes access", () => {
  const now = Date.UTC(2026, 8, 6);
  const state = deriveSubscriptionState(
    { expiresDate: now + 60_000, revocationDate: now - 1_000 },
    {
      gracePeriodExpiresDate: now + 120_000,
      isInBillingRetryPeriod: false,
      autoRenewStatus: 0,
    },
    now,
  );

  assertEquals(state.status, "revoked");
  assertEquals(state.autoRenewEnabled, false);
});

Deno.test("billing retry without grace does not grant paid access", () => {
  const now = Date.UTC(2026, 8, 6);
  const state = deriveSubscriptionState(
    { expiresDate: now - 60_000, revocationDate: undefined },
    {
      gracePeriodExpiresDate: undefined,
      isInBillingRetryPeriod: true,
      autoRenewStatus: 1,
    },
    now,
  );

  assertEquals(state.status, "billing_retry");
});
