<script setup lang="ts">
definePageMeta({
  middleware: ["require-auth"]
});

const route = useRoute();
const { t } = useI18n();
const { postJson } = useApi();
const { user, fetchSession } = useAuthSession();
const { info, success, errorFrom, error } = useNotify();

await fetchSession();

const busy = ref(false);
const userCode = ref(typeof route.query.user_code === "string" ? route.query.user_code : "");

const approve = async () => {
  const normalized = userCode.value.trim().toUpperCase();
  if (!normalized) {
    error("errors.missing_user_code");
    return;
  }
  busy.value = true;
  info("toasts.approvingLogin");
  try {
    await postJson("/auth/device/approve", { userCode: normalized });
    success("toasts.loginApproved");
  } catch (err) {
    errorFrom(err);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <section class="mx-auto max-w-2xl">
    <div class="glass-panel p-6 md:p-8">
      <h1 class="text-3xl font-semibold tracking-tight">{{ t("auth.activateTitle") }}</h1>
      <p class="mt-2 text-sm text-muted-foreground">{{ t("auth.activateSubtitle") }}</p>

      <p v-if="user?.email" class="mt-4 inline-flex rounded-xl bg-muted px-3 py-2 text-xs font-medium text-muted-foreground">
        {{ t("account.signedInAs", { email: user.email }) }}
      </p>

      <form class="mt-6 space-y-4" @submit.prevent="approve">
        <div class="space-y-2">
          <label class="text-sm font-medium">{{ t("auth.userCode") }}</label>
          <input
            v-model="userCode"
            type="text"
            required
            class="h-14 w-full rounded-2xl border border-input bg-background px-4 text-center font-mono text-xl tracking-[0.35em] uppercase focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            placeholder="ABCD1234"
          />
        </div>
        <button
          type="submit"
          class="inline-flex h-11 w-full items-center justify-center rounded-xl bg-primary px-4 text-sm font-semibold text-primary-foreground transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="busy"
        >
          {{ t("auth.approveLogin") }}
        </button>
      </form>
    </div>
  </section>
</template>
