import nodemailer from "nodemailer";
import { betterAuth, type BetterAuthOptions } from "better-auth";
import { magicLink } from "better-auth/plugins/magic-link";
import type { Pool } from "pg";
import { type Config } from "./config.js";

export interface BetterAuthRuntime {
  auth: ReturnType<typeof betterAuth>;
  socialProviders: {
    google: boolean;
    apple: boolean;
  };
}

interface AuthMail {
  kind: "verification" | "reset_password" | "magic_link";
  to: string;
  subject: string;
  html: string;
  text: string;
}

const normalizeBaseUrl = (value: string): string => value.replace(/\/$/, "");

const buildWebUrl = (baseUrl: string, path: string, params?: Record<string, string>): string => {
  const url = new URL(path, `${normalizeBaseUrl(baseUrl)}/`);
  if (params) {
    for (const [key, value] of Object.entries(params)) {
      if (value.trim().length > 0) {
        url.searchParams.set(key, value);
      }
    }
  }
  return url.toString();
};

const isSecureUrl = (value: string): boolean => value.trim().toLowerCase().startsWith("https://");

const maskEmail = (value: string): string => {
  const trimmed = value.trim();
  const at = trimmed.indexOf("@");
  if (at <= 1) {
    return "***";
  }
  const local = trimmed.slice(0, at);
  const domain = trimmed.slice(at + 1);
  return `${local[0]}***@${domain}`;
};

const errorToMessage = (error: unknown): string => {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
};

const htmlMailTemplate = (params: { title: string; intro: string; ctaLabel: string; ctaUrl: string }): string => `<!doctype html>
<html>
  <body style="font-family: ui-sans-serif, system-ui, sans-serif; background:#f6f7fb; margin:0; padding:24px; color:#111827;">
    <div style="max-width:560px; margin:0 auto; background:#ffffff; border:1px solid #e5e7eb; border-radius:14px; padding:20px;">
      <h1 style="margin:0 0 12px; font-size:22px;">${params.title}</h1>
      <p style="line-height:1.5; margin:0 0 20px; color:#374151;">${params.intro}</p>
      <a href="${params.ctaUrl}" style="display:inline-block; text-decoration:none; background:#111827; color:#ffffff; padding:10px 16px; border-radius:10px; font-weight:600;">${params.ctaLabel}</a>
      <p style="line-height:1.4; margin:16px 0 0; color:#6b7280; font-size:13px;">If the button does not work, copy and paste this URL into your browser:<br />${params.ctaUrl}</p>
    </div>
  </body>
</html>`;

const createMailSender = (config: Config): ((mail: AuthMail) => Promise<void>) => {
  if (config.authEmailMode === "log") {
    return async (mail) => {
      console.log("[auth-mail:log]", {
        kind: mail.kind,
        to: maskEmail(mail.to),
        subject: mail.subject,
        text: mail.text
      });
    };
  }

  const transport = nodemailer.createTransport({
    host: config.smtpHost,
    port: config.smtpPort,
    secure: config.smtpSecure,
    auth:
      config.smtpUser && config.smtpPass
        ? {
            user: config.smtpUser,
            pass: config.smtpPass
          }
        : undefined
  });

  void transport
    .verify()
    .then(() => {
      console.log("[auth-mail:smtp] transporter verified", {
        host: config.smtpHost,
        port: config.smtpPort,
        secure: config.smtpSecure,
        hasAuth: Boolean(config.smtpUser && config.smtpPass)
      });
    })
    .catch((error) => {
      console.error("[auth-mail:smtp] transporter verify failed", {
        host: config.smtpHost,
        port: config.smtpPort,
        secure: config.smtpSecure,
        error: errorToMessage(error)
      });
    });

  return async (mail) => {
    const startedAt = Date.now();
    if (config.authDebugLogs) {
      console.log("[auth-mail:smtp] sending", {
        kind: mail.kind,
        to: maskEmail(mail.to),
        subject: mail.subject,
        host: config.smtpHost,
        port: config.smtpPort,
        secure: config.smtpSecure
      });
    }
    try {
      const result = await transport.sendMail({
        from: config.smtpFrom,
        to: mail.to,
        subject: mail.subject,
        text: mail.text,
        html: mail.html
      });
      if (config.authDebugLogs) {
        console.log("[auth-mail:smtp] sent", {
          kind: mail.kind,
          to: maskEmail(mail.to),
          messageId: result.messageId,
          accepted: result.accepted,
          rejected: result.rejected,
          response: result.response,
          durationMs: Date.now() - startedAt
        });
      }
    } catch (error) {
      console.error("[auth-mail:smtp] send failed", {
        kind: mail.kind,
        to: maskEmail(mail.to),
        host: config.smtpHost,
        port: config.smtpPort,
        secure: config.smtpSecure,
        error: errorToMessage(error)
      });
      throw error;
    }
  };
};

export const createBetterAuthRuntime = (params: { config: Config; pool: Pool }): BetterAuthRuntime => {
  const { config, pool } = params;
  const sendMail = createMailSender(config);

  const googleEnabled = Boolean(config.googleClientId && config.googleClientSecret);
  const appleEnabled = Boolean(config.appleClientId && config.appleClientSecret);

  const socialProviders: NonNullable<BetterAuthOptions["socialProviders"]> = {};
  if (googleEnabled) {
    socialProviders.google = {
      clientId: config.googleClientId!,
      clientSecret: config.googleClientSecret!
    };
  }
  if (appleEnabled) {
    socialProviders.apple = {
      clientId: config.appleClientId!,
      clientSecret: config.appleClientSecret!,
      ...(config.appleBundleId ? { appBundleIdentifier: config.appleBundleId } : {})
    };
  }

  console.log("[auth] better-auth configured", {
    baseUrl: normalizeBaseUrl(config.appBaseUrl),
    emailMode: config.authEmailMode,
    smtpHost: config.smtpHost,
    smtpPort: config.smtpPort,
    smtpSecure: config.smtpSecure,
    debugLogs: config.authDebugLogs,
    socialProviders: {
      google: googleEnabled,
      apple: appleEnabled
    }
  });

  const authOptions: BetterAuthOptions = {
    appName: "Nomade",
    secret: config.betterAuthSecret,
    baseURL: normalizeBaseUrl(config.appBaseUrl),
    basePath: "/api/auth",
    trustedOrigins: [normalizeBaseUrl(config.appBaseUrl)],
    database: pool,
    advanced: {
      useSecureCookies: isSecureUrl(config.appBaseUrl),
      trustedProxyHeaders: true,
      defaultCookieAttributes: {
        path: "/",
        httpOnly: true,
        sameSite: "lax",
        secure: isSecureUrl(config.appBaseUrl)
      }
    },
    user: {
      modelName: "users",
      fields: {
        name: "name",
        email: "email",
        emailVerified: "email_verified",
        image: "image",
        createdAt: "created_at",
        updatedAt: "updated_at"
      }
    },
    session: {
      modelName: "auth_sessions",
      fields: {
        expiresAt: "expires_at",
        token: "token",
        createdAt: "created_at",
        updatedAt: "updated_at",
        ipAddress: "ip_address",
        userAgent: "user_agent",
        userId: "user_id"
      }
    },
    account: {
      modelName: "auth_accounts",
      fields: {
        accountId: "account_id",
        providerId: "provider_id",
        userId: "user_id",
        accessToken: "access_token",
        refreshToken: "refresh_token",
        idToken: "id_token",
        accessTokenExpiresAt: "access_token_expires_at",
        refreshTokenExpiresAt: "refresh_token_expires_at",
        createdAt: "created_at",
        updatedAt: "updated_at"
      }
    },
    verification: {
      modelName: "auth_verifications",
      fields: {
        identifier: "identifier",
        value: "value",
        expiresAt: "expires_at",
        createdAt: "created_at",
        updatedAt: "updated_at"
      }
    },
    emailAndPassword: {
      enabled: true,
      autoSignIn: false,
      requireEmailVerification: true,
      sendResetPassword: async (data) => {
        const resetUrl = buildWebUrl(config.appBaseUrl, "/web/reset-password", { token: data.token });
        await sendMail({
          kind: "reset_password",
          to: data.user.email,
          subject: "Reset your Nomade password",
          text: `Reset your Nomade password: ${resetUrl}`,
          html: htmlMailTemplate({
            title: "Reset your password",
            intro: "Use the button below to set a new password for your Nomade account.",
            ctaLabel: "Reset password",
            ctaUrl: resetUrl
          })
        });
      }
    },
    emailVerification: {
      sendOnSignUp: true,
      sendOnSignIn: true,
      sendVerificationEmail: async (data) => {
        const verifyUrl = buildWebUrl(config.appBaseUrl, "/web/verify-email", { token: data.token });
        await sendMail({
          kind: "verification",
          to: data.user.email,
          subject: "Verify your Nomade email",
          text: `Verify your email address: ${verifyUrl}`,
          html: htmlMailTemplate({
            title: "Verify your email",
            intro: "Confirm your email address to finish signing in to Nomade.",
            ctaLabel: "Verify email",
            ctaUrl: verifyUrl
          })
        });
      }
    },
    socialProviders: Object.keys(socialProviders).length > 0 ? socialProviders : undefined,
    plugins: [
      magicLink({
        disableSignUp: true,
        sendMagicLink: async (data) => {
          await sendMail({
            kind: "magic_link",
            to: data.email,
            subject: "Your Nomade magic link",
            text: `Sign in to Nomade: ${data.url}`,
            html: htmlMailTemplate({
              title: "Sign in with magic link",
              intro: "Use this one-time link to sign in to Nomade.",
              ctaLabel: "Sign in",
              ctaUrl: data.url
            })
          });
        }
      })
    ]
  };

  return {
    auth: betterAuth(authOptions),
    socialProviders: {
      google: googleEnabled,
      apple: appleEnabled
    }
  };
};
