<script setup lang="ts">
definePageMeta({
  layout: "auth"
});

const route = useRoute();
const { t } = useI18n();
const { info, success, errorFrom, error } = useNotify();
const { waitForAuthenticatedSession } = useAuthFlow();

const loading = ref(true);
const token = typeof route.query.token === "string" ? route.query.token : "";
const returnTo =
  typeof route.query.returnTo === "string" && route.query.returnTo.startsWith("/")
    ? route.query.returnTo
    : "/account";

onMounted(async () => {
  if (!token) {
    error("errors.missing_token");
    loading.value = false;
    return;
  }
  info("toasts.verifyingEmail");
  try {
    const callbackURL = new URL(returnTo, window.location.origin).toString();
    const response = await fetch(
      `/api/auth/verify-email?token=${encodeURIComponent(token)}&callbackURL=${encodeURIComponent(callbackURL)}`,
      { credentials: "include" }
    );
    const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    if (!response.ok) {
      const message =
        typeof payload.message === "string"
          ? payload.message
          : typeof payload.error === "string"
            ? payload.error
            : t("errors.generic");
      throw new Error(message);
    }
    await waitForAuthenticatedSession();
    success("toasts.emailVerified");
    await navigateTo(returnTo);
  } catch (err) {
    errorFrom(err);
    loading.value = false;
  }
});
</script>

<template>
  <section class="mx-auto max-w-xl">
    <div class="glass-panel p-6 md:p-8">
      <h1 class="text-3xl font-semibold tracking-tight">{{ t("auth.verifyTitle") }}</h1>
      <p class="mt-2 text-sm text-muted-foreground">{{ t("auth.verifySubtitle") }}</p>
      <div class="mt-6 rounded-2xl border border-border/80 bg-muted/60 px-4 py-3 text-sm text-muted-foreground">
        {{ loading ? t("common.loading") : t("auth.backToSignIn") }}
      </div>
      <p class="mt-5 text-sm text-muted-foreground">
        <NuxtLink to="/login">{{ t("auth.backToSignIn") }}</NuxtLink>
      </p>
    </div>
  </section>
</template>
