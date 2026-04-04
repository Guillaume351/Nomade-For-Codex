<script setup lang="ts">
definePageMeta({
  layout: "auth",
  middleware: ["guest-only"]
});

const email = ref("");
const busy = ref(false);
const { t } = useI18n();
const { postJson } = useApi();
const { info, success } = useNotify();

const sendLink = async () => {
  busy.value = true;
  info("toasts.sendingResetLink");
  try {
    await postJson("/api/auth/request-password-reset", {
      email: email.value.trim(),
      redirectTo: new URL("/reset-password", window.location.origin).toString()
    });
    success("toasts.resetLinkSent");
  } catch {
    success("toasts.resetLinkSent");
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <section class="mx-auto max-w-xl">
    <div class="glass-panel p-6 md:p-8">
      <h1 class="text-3xl font-semibold tracking-tight">{{ t("auth.forgotTitle") }}</h1>
      <p class="mt-2 text-sm text-muted-foreground">{{ t("auth.forgotSubtitle") }}</p>

      <form class="mt-6 space-y-4" @submit.prevent="sendLink">
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

        <button
          type="submit"
          class="inline-flex h-11 w-full items-center justify-center rounded-xl bg-primary px-4 text-sm font-semibold text-primary-foreground transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="busy"
        >
          {{ t("auth.sendResetLink") }}
        </button>
      </form>

      <p class="mt-5 text-sm text-muted-foreground">
        <NuxtLink to="/login">{{ t("auth.backToSignIn") }}</NuxtLink>
      </p>
    </div>
  </section>
</template>
