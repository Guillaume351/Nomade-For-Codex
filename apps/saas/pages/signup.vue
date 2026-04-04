<script setup lang="ts">
definePageMeta({
  layout: "auth",
  middleware: ["guest-only"]
});

const route = useRoute();
const { t } = useI18n();
const { postJson } = useApi();
const { info, success, errorFrom } = useNotify();

const name = ref("");
const email = ref(typeof route.query.email === "string" ? route.query.email : "");
const password = ref("");
const busy = ref(false);

const returnTo = computed(() =>
  typeof route.query.returnTo === "string" && route.query.returnTo.startsWith("/")
    ? route.query.returnTo
    : "/account"
);

const createAccount = async () => {
  busy.value = true;
  info("toasts.creatingAccount");
  try {
    await postJson("/api/auth/sign-up/email", {
      name: name.value.trim(),
      email: email.value.trim(),
      password: password.value,
      callbackURL: new URL(returnTo.value, window.location.origin).toString()
    });
    success("toasts.accountCreated");
  } catch (error) {
    errorFrom(error);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <section class="mx-auto max-w-xl">
    <div class="glass-panel p-6 md:p-8">
      <h1 class="text-3xl font-semibold tracking-tight">{{ t("auth.signupTitle") }}</h1>
      <p class="mt-2 text-sm text-muted-foreground">{{ t("auth.signupSubtitle") }}</p>

      <form class="mt-6 space-y-4" @submit.prevent="createAccount">
        <div class="space-y-2">
          <label class="text-sm font-medium">{{ t("auth.name") }}</label>
          <input
            v-model="name"
            type="text"
            required
            autocomplete="name"
            class="h-11 w-full rounded-xl border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            placeholder="Jane Doe"
          />
        </div>
        <div class="space-y-2">
          <label class="text-sm font-medium">{{ t("auth.email") }}</label>
          <input
            v-model="email"
            type="email"
            required
            autocomplete="email"
            class="h-11 w-full rounded-xl border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            placeholder="you@example.com"
          />
        </div>
        <div class="space-y-2">
          <label class="text-sm font-medium">{{ t("auth.password") }}</label>
          <input
            v-model="password"
            type="password"
            required
            autocomplete="new-password"
            minlength="8"
            class="h-11 w-full rounded-xl border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            placeholder="At least 8 characters"
          />
        </div>
        <button
          type="submit"
          class="inline-flex h-11 w-full items-center justify-center rounded-xl bg-primary px-4 text-sm font-semibold text-primary-foreground transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="busy"
        >
          {{ t("auth.signUp") }}
        </button>
      </form>

      <p class="mt-5 text-sm text-muted-foreground">
        {{ t("auth.alreadyHaveAccount") }}
        <NuxtLink :to="`/login?returnTo=${encodeURIComponent(returnTo)}`">{{ t("auth.backToSignIn") }}</NuxtLink>
      </p>
    </div>
  </section>
</template>
