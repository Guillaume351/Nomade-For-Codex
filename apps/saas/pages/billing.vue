<script setup lang="ts">
definePageMeta({
  middleware: ["require-auth"]
});

interface BillingSessionPayload {
  id: string;
  url?: string | null;
}

const busy = ref(false);
const { t } = useI18n();
const { postJson } = useApi();
const { info, errorFrom } = useNotify();

const startCheckout = async () => {
  busy.value = true;
  info("toasts.checkoutStarting");
  try {
    const payload = await postJson<BillingSessionPayload>("/billing/checkout-session", {});
    if (!payload.url) {
      throw new Error("checkout_url_missing");
    }
    window.location.href = payload.url;
  } catch (err) {
    errorFrom(err);
  } finally {
    busy.value = false;
  }
};

const openPortal = async () => {
  busy.value = true;
  info("toasts.portalOpening");
  try {
    const payload = await postJson<BillingSessionPayload>("/billing/portal-session", {});
    if (!payload.url) {
      throw new Error("portal_url_missing");
    }
    window.location.href = payload.url;
  } catch (err) {
    errorFrom(err);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <section class="mx-auto max-w-3xl">
    <div class="glass-panel p-6 md:p-8">
      <h1 class="text-3xl font-semibold tracking-tight">{{ t("billing.title") }}</h1>
      <p class="mt-2 text-sm text-muted-foreground">{{ t("billing.subtitle") }}</p>

      <div class="mt-6 grid gap-3 sm:grid-cols-2">
        <button
          type="button"
          class="inline-flex h-11 items-center justify-center rounded-xl bg-primary px-4 text-sm font-semibold text-primary-foreground transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="busy"
          @click="startCheckout"
        >
          {{ t("billing.upgrade") }}
        </button>
        <button
          type="button"
          class="inline-flex h-11 items-center justify-center rounded-xl border border-border bg-background px-4 text-sm font-semibold text-foreground transition hover:border-primary/60 hover:text-primary disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="busy"
          @click="openPortal"
        >
          {{ t("billing.portal") }}
        </button>
      </div>

      <div class="mt-5 text-sm">
        <NuxtLink to="/account">{{ t("common.backToAccount") }}</NuxtLink>
      </div>
    </div>
  </section>
</template>
