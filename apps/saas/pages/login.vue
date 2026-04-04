<script setup lang="ts">
import { KeyRound, Sparkles, ExternalLink } from "lucide-vue-next";

definePageMeta({
  layout: "auth",
  middleware: ["guest-only"]
});

const route = useRoute();
const runtimeConfig = useRuntimeConfig();
const { t } = useI18n();
const { postJson } = useApi();
const { info, success, errorFrom, errorMessage } = useNotify();
const { waitForAuthenticatedSession } = useAuthFlow();

const email = ref(typeof route.query.email === "string" ? route.query.email : "");
const password = ref("");
const busy = ref(false);

const returnTo = computed(() =>
  typeof route.query.returnTo === "string" && route.query.returnTo.startsWith("/")
    ? route.query.returnTo
    : "/account"
);

const socialProviders = computed(() => ({
  google: Boolean(runtimeConfig.public.socialProviders?.google),
  apple: Boolean(runtimeConfig.public.socialProviders?.apple)
}));

const navigateAfterAuth = async () => {
  const hasSession = await waitForAuthenticatedSession();
  if (!hasSession) {
    throw new Error(t("errors.session_required"));
  }
  success("toasts.signedIn");
  await navigateTo(returnTo.value);
};

const signIn = async () => {
  busy.value = true;
  info("toasts.signingIn");
  try {
    await postJson("/api/auth/sign-in/email", {
      email: email.value.trim(),
      password: password.value,
      callbackURL: new URL(returnTo.value, window.location.origin).toString(),
      rememberMe: true
    });
    await navigateAfterAuth();
  } catch (error) {
    errorFrom(error);
  } finally {
    busy.value = false;
  }
};

const signInWithSocial = async (provider: "google" | "apple") => {
  busy.value = true;
  info("toasts.signingIn");
  try {
    const result = await postJson<{ url?: string | null }>("/api/auth/sign-in/social", {
      provider,
      callbackURL: new URL(returnTo.value, window.location.origin).toString(),
      errorCallbackURL: new URL(`/login?returnTo=${encodeURIComponent(returnTo.value)}`, window.location.origin).toString()
    });
    if (result.url) {
      window.location.href = result.url;
      return;
    }
    await navigateAfterAuth();
  } catch (error) {
    errorFrom(error);
  } finally {
    busy.value = false;
  }
};

const sendMagicLink = async () => {
  if (!email.value.trim()) {
    return;
  }
  busy.value = true;
  info("toasts.sendingMagicLink");
  try {
    await postJson("/api/auth/sign-in/magic-link", {
      email: email.value.trim(),
      callbackURL: new URL(returnTo.value, window.location.origin).toString(),
      errorCallbackURL: new URL(`/login?returnTo=${encodeURIComponent(returnTo.value)}`, window.location.origin).toString()
    });
    success("toasts.magicLinkSent");
  } catch (error) {
    errorFrom(error);
  } finally {
    busy.value = false;
  }
};

const resolveAuthCallbackMessage = (rawError: string): string => {
  const normalized = rawError.trim().toLowerCase();
  if (normalized.includes("sign_up_disabled") || normalized.includes("signup_disabled")) {
    return t("errors.sign_up_disabled");
  }
  if (normalized.includes("token") && normalized.includes("invalid")) {
    return t("errors.invalid_token");
  }
  if (normalized.includes("expired")) {
    return t("errors.magic_link_expired");
  }
  return t("errors.magic_link_failed");
};

onMounted(() => {
  if (typeof route.query.reason === "string" && route.query.reason === "auth_required") {
    info("errors.session_required");
  }
  if (typeof route.query.error === "string" && route.query.error.trim().length > 0) {
    const msg = resolveAuthCallbackMessage(route.query.error);
    errorMessage(msg);
  }
});
</script>

<template>
  <section class="grid gap-6 lg:grid-cols-[1.05fr_1fr]">
    <div class="glass-panel relative overflow-hidden p-6 md:p-8">
      <div class="absolute -right-20 -top-20 h-56 w-56 rounded-full bg-primary/20 blur-3xl" />
      <div class="absolute -bottom-24 left-0 h-56 w-56 rounded-full bg-accent/20 blur-3xl" />
      <div class="relative space-y-5">
        <span class="inline-flex items-center gap-2 rounded-full border border-primary/30 bg-primary/10 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-primary">
          <Sparkles class="h-3.5 w-3.5" />
          Nomade SaaS
        </span>
        <h1 class="max-w-xl text-3xl font-semibold tracking-tight md:text-4xl">
          {{ t("auth.signInTitle") }}
        </h1>
        <p class="max-w-xl text-sm text-muted-foreground md:text-base">
          {{ t("auth.signInSubtitle") }}
        </p>
        <div class="grid gap-3 text-sm text-muted-foreground md:grid-cols-2">
          <div class="rounded-2xl border border-border/80 bg-background/60 p-4">
            <p class="font-medium text-foreground">{{ t("ui.deviceCodeReadyTitle") }}</p>
            <p class="mt-1">{{ t("ui.deviceCodeReadyBody") }}</p>
          </div>
          <div class="rounded-2xl border border-border/80 bg-background/60 p-4">
            <p class="font-medium text-foreground">{{ t("ui.magicLinkOptionTitle") }}</p>
            <p class="mt-1">{{ t("auth.magicLinkHint") }}</p>
          </div>
        </div>
      </div>
    </div>

    <div class="glass-panel p-6 md:p-8">
      <form class="space-y-4" @submit.prevent="signIn">
        <div class="space-y-2">
          <label class="text-sm font-medium">{{ t("auth.email") }}</label>
          <input
            v-model="email"
            type="email"
            autocomplete="email"
            required
            class="h-11 w-full rounded-xl border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            placeholder="you@example.com"
          />
        </div>

        <div class="space-y-2">
          <label class="text-sm font-medium">{{ t("auth.password") }}</label>
          <input
            v-model="password"
            type="password"
            autocomplete="current-password"
            required
            class="h-11 w-full rounded-xl border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            placeholder="••••••••"
          />
        </div>

        <button
          type="submit"
          class="inline-flex h-11 w-full items-center justify-center gap-2 rounded-xl bg-primary px-4 text-sm font-semibold text-primary-foreground transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="busy"
        >
          <KeyRound class="h-4 w-4" />
          {{ t("auth.signIn") }}
        </button>
      </form>

      <div class="mt-4 flex flex-wrap items-center gap-3 text-sm">
        <NuxtLink :to="`/signup?returnTo=${encodeURIComponent(returnTo)}`">{{ t("auth.signUp") }}</NuxtLink>
        <NuxtLink to="/forgot-password">{{ t("auth.forgotPassword") }}</NuxtLink>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-lg border border-border px-2.5 py-1.5 text-xs font-medium text-muted-foreground transition hover:border-primary/60 hover:text-primary disabled:opacity-60"
          :disabled="busy || !email"
          @click="sendMagicLink"
        >
          <ExternalLink class="h-3.5 w-3.5" />
          {{ t("auth.sendMagicLink") }}
        </button>
      </div>

      <div
        v-if="socialProviders.google || socialProviders.apple"
        class="mt-5 grid gap-2 border-t border-border/80 pt-5"
      >
        <button
          v-if="socialProviders.google"
          type="button"
          class="h-10 rounded-xl border border-border bg-background px-3 text-sm font-medium transition hover:border-primary/60 hover:text-primary disabled:opacity-60"
          :disabled="busy"
          @click="signInWithSocial('google')"
        >
          {{ t("auth.social.google") }}
        </button>
        <button
          v-if="socialProviders.apple"
          type="button"
          class="h-10 rounded-xl border border-border bg-background px-3 text-sm font-medium transition hover:border-primary/60 hover:text-primary disabled:opacity-60"
          :disabled="busy"
          @click="signInWithSocial('apple')"
        >
          {{ t("auth.social.apple") }}
        </button>
      </div>
    </div>
  </section>
</template>
