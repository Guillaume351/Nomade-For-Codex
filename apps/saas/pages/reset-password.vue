<script setup lang="ts">
definePageMeta({
  layout: "auth",
  middleware: ["guest-only"]
});

const route = useRoute();
const { t } = useI18n();
const { postJson } = useApi();
const { info, success, errorFrom, error } = useNotify();

const token = ref(typeof route.query.token === "string" ? route.query.token : "");
const newPassword = ref("");
const busy = ref(false);

const resetPassword = async () => {
  if (!token.value) {
    error("errors.missing_token");
    return;
  }
  busy.value = true;
  info("toasts.updatingPassword");
  try {
    await postJson("/api/auth/reset-password", {
      token: token.value,
      newPassword: newPassword.value
    });
    success("toasts.passwordUpdated");
    await navigateTo("/login");
  } catch (err) {
    errorFrom(err);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <section class="mx-auto max-w-xl">
    <div class="glass-panel p-6 md:p-8">
      <h1 class="text-3xl font-semibold tracking-tight">{{ t("auth.resetTitle") }}</h1>
      <p class="mt-2 text-sm text-muted-foreground">{{ t("auth.resetSubtitle") }}</p>

      <form class="mt-6 space-y-4" @submit.prevent="resetPassword">
        <div class="space-y-2">
          <label class="text-sm font-medium">{{ t("common.token") }}</label>
          <input
            v-model="token"
            type="text"
            required
            class="h-11 w-full rounded-xl border border-input bg-background px-3 font-mono text-xs focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            placeholder="token"
          />
        </div>
        <div class="space-y-2">
          <label class="text-sm font-medium">{{ t("auth.password") }}</label>
          <input
            v-model="newPassword"
            type="password"
            autocomplete="new-password"
            required
            minlength="8"
            class="h-11 w-full rounded-xl border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            placeholder="••••••••"
          />
        </div>

        <button
          type="submit"
          class="inline-flex h-11 w-full items-center justify-center rounded-xl bg-primary px-4 text-sm font-semibold text-primary-foreground transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="busy"
        >
          {{ t("auth.resetTitle") }}
        </button>
      </form>
      <p class="mt-5 text-sm text-muted-foreground">
        <NuxtLink to="/login">{{ t("auth.backToSignIn") }}</NuxtLink>
      </p>
    </div>
  </section>
</template>
