import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";
import { verifyRevenueCatWebhookAuthorization, verifyStripeWebhookSignature } from "./billing.js";

describe("verifyStripeWebhookSignature", () => {
  it("accepts valid Stripe-style signatures", () => {
    const secret = "whsec_test";
    const body = Buffer.from(JSON.stringify({ id: "evt_1", type: "customer.subscription.updated" }));
    const timestamp = "1710000000";
    const signedPayload = `${timestamp}.${body.toString("utf8")}`;
    const signature = createHmac("sha256", secret).update(signedPayload).digest("hex");
    const valid = verifyStripeWebhookSignature({
      rawBody: body,
      stripeSignatureHeader: `t=${timestamp},v1=${signature}`,
      webhookSecret: secret
    });
    expect(valid).toBe(true);
  });

  it("rejects invalid signatures", () => {
    const valid = verifyStripeWebhookSignature({
      rawBody: Buffer.from("{}"),
      stripeSignatureHeader: "t=1710000000,v1=deadbeef",
      webhookSecret: "whsec_test"
    });
    expect(valid).toBe(false);
  });
});

describe("verifyRevenueCatWebhookAuthorization", () => {
  it("accepts matching authorization header", () => {
    const valid = verifyRevenueCatWebhookAuthorization({
      authorizationHeader: "Bearer rc_test",
      webhookAuth: "Bearer rc_test"
    });
    expect(valid).toBe(true);
  });

  it("rejects mismatched authorization header", () => {
    const valid = verifyRevenueCatWebhookAuthorization({
      authorizationHeader: "Bearer other",
      webhookAuth: "Bearer rc_test"
    });
    expect(valid).toBe(false);
  });
});
