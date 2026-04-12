import { createHmac } from "node:crypto";
import { safeEqual } from "@nomade/shared";

export interface StripeCheckoutSessionRequest {
  secretKey: string;
  customerId: string;
  priceId: string;
  successUrl: string;
  cancelUrl: string;
}

export interface StripePortalSessionRequest {
  secretKey: string;
  customerId: string;
  returnUrl: string;
}

const formEncode = (entries: Record<string, string>): string => {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(entries)) {
    params.set(key, value);
  }
  return params.toString();
};

const stripePost = async <T>(params: {
  secretKey: string;
  path: string;
  body: Record<string, string>;
}): Promise<T> => {
  const response = await fetch(`https://api.stripe.com/v1/${params.path}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${params.secretKey}`,
      "content-type": "application/x-www-form-urlencoded"
    },
    body: formEncode(params.body)
  });
  const raw = await response.text();
  if (!response.ok) {
    throw new Error(`stripe_${params.path}_failed:${response.status}:${raw}`);
  }
  return JSON.parse(raw) as T;
};

export const createStripeCustomer = async (params: {
  secretKey: string;
  email: string;
  userId: string;
}): Promise<{ id: string }> => {
  return stripePost<{ id: string }>({
    secretKey: params.secretKey,
    path: "customers",
    body: {
      email: params.email,
      "metadata[user_id]": params.userId
    }
  });
};

export const createStripeCheckoutSession = async (
  params: StripeCheckoutSessionRequest
): Promise<{ id: string; url?: string | null }> => {
  return stripePost<{ id: string; url?: string | null }>({
    secretKey: params.secretKey,
    path: "checkout/sessions",
    body: {
      mode: "subscription",
      customer: params.customerId,
      "line_items[0][price]": params.priceId,
      "line_items[0][quantity]": "1",
      success_url: params.successUrl,
      cancel_url: params.cancelUrl,
      "allow_promotion_codes": "true"
    }
  });
};

export const createStripePortalSession = async (
  params: StripePortalSessionRequest
): Promise<{ id: string; url?: string | null }> => {
  return stripePost<{ id: string; url?: string | null }>({
    secretKey: params.secretKey,
    path: "billing_portal/sessions",
    body: {
      customer: params.customerId,
      return_url: params.returnUrl
    }
  });
};

const parseStripeSignatureHeader = (raw: string | undefined): { timestamp: string; signature: string } | null => {
  if (!raw) {
    return null;
  }
  const parts = raw.split(",");
  let timestamp = "";
  let signature = "";
  for (const part of parts) {
    const [k, v] = part.trim().split("=");
    if (k === "t" && v) {
      timestamp = v;
    }
    if (k === "v1" && v) {
      signature = v;
    }
  }
  if (!timestamp || !signature) {
    return null;
  }
  return { timestamp, signature };
};

export const verifyStripeWebhookSignature = (params: {
  rawBody: Buffer;
  stripeSignatureHeader: string | undefined;
  webhookSecret: string;
}): boolean => {
  const parsed = parseStripeSignatureHeader(params.stripeSignatureHeader);
  if (!parsed) {
    return false;
  }
  const signedPayload = `${parsed.timestamp}.${params.rawBody.toString("utf8")}`;
  const expected = createHmac("sha256", params.webhookSecret).update(signedPayload).digest("hex");
  return safeEqual(expected, parsed.signature);
};

export const verifyRevenueCatWebhookAuthorization = (params: {
  authorizationHeader: string | undefined;
  webhookAuth: string;
}): boolean => {
  const received = params.authorizationHeader?.trim() ?? "";
  const expected = params.webhookAuth.trim();
  if (!received || !expected) {
    return false;
  }
  return safeEqual(received, expected);
};
