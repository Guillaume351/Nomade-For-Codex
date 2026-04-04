<script setup lang="ts">
definePageMeta({
  middleware: ["require-auth"]
});

interface MePayload {
  id: string;
  email: string;
}

interface EntitlementsPayload {
  planCode: string;
  maxAgents: number;
  currentAgents: number;
  subscriptionStatus: string;
}

const route = useRoute();
const { t } = useI18n();
const { getJson } = useApi();
const { errorFrom, success } = useNotify();

const me = ref<MePayload | null>(null);
const entitlements = ref<EntitlementsPayload | null>(null);
const loading = ref(true);

const loadAccount = async () => {
  loading.value = true;
  try {
    const [mePayload, entitlementsPayload] = await Promise.all([
      getJson<MePayload>("/me"),
      getJson<EntitlementsPayload>("/me/entitlements")
    ]);
    me.value = mePayload;
    entitlements.value = entitlementsPayload;
  } catch (err) {
    errorFrom(err);
    await navigateTo(`/login?returnTo=${encodeURIComponent("/account")}`);
  } finally {
    loading.value = false;
  }
};

await loadAccount();

onMounted(() => {
  if (typeof route.query.billing === "string") {
    if (route.query.billing === "success") {
      success("billing.checkoutSuccess");
      return;
    }
    success("billing.checkoutCancel");
  }
});
</script>

<template>
  <section class="grid gap-6 lg:grid-cols-[1.1fr_0.9fr]">
    <div class="glass-panel p-6 md:p-8">
      <h1 class="text-3xl font-semibold tracking-tight">{{ t("account.title") }}</h1>
      <p class="mt-2 text-sm text-muted-foreground">{{ t("account.subtitle") }}</p>

      <div
        v-if="me?.email"
        class="mt-5 inline-flex rounded-xl border border-border/80 bg-muted/60 px-3 py-2 text-xs font-medium text-muted-foreground"
      >
        {{ t("account.signedInAs", { email: me.email }) }}
      </div>

      <div class="mt-6 grid gap-3 sm:grid-cols-3">
        <div class="rounded-2xl border border-border/80 bg-background/80 p-4">
          <p class="text-xs uppercase tracking-wide text-muted-foreground">{{ t("account.plan") }}</p>
          <p class="mt-2 text-2xl font-semibold">{{ entitlements?.planCode ?? "—" }}</p>
        </div>
        <div class="rounded-2xl border border-border/80 bg-background/80 p-4">
          <p class="text-xs uppercase tracking-wide text-muted-foreground">{{ t("account.quota") }}</p>
          <p class="mt-2 text-2xl font-semibold">
            {{ entitlements ? `${entitlements.currentAgents}/${entitlements.maxAgents}` : "—" }}
          </p>
        </div>
        <div class="rounded-2xl border border-border/80 bg-background/80 p-4">
          <p class="text-xs uppercase tracking-wide text-muted-foreground">{{ t("account.subscriptionStatus") }}</p>
          <p class="mt-2 text-2xl font-semibold">{{ entitlements?.subscriptionStatus ?? "—" }}</p>
        </div>
      </div>
    </div>

    <div class="glass-panel p-6 md:p-8">
      <h2 class="text-xl font-semibold tracking-tight">{{ t("ui.quickActionsTitle") }}</h2>
      <p class="mt-2 text-sm text-muted-foreground">{{ t("ui.quickActionsSubtitle") }}</p>
      <div class="mt-6 grid gap-3">
        <NuxtLink
          to="/devices"
          class="inline-flex h-11 items-center justify-between rounded-xl border border-border bg-background px-4 text-sm font-medium text-foreground no-underline transition hover:border-primary/60 hover:text-primary"
        >
          <span>{{ t("nav.devices") }}</span>
          <span aria-hidden="true">→</span>
        </NuxtLink>
        <NuxtLink
          to="/billing"
          class="inline-flex h-11 items-center justify-between rounded-xl border border-border bg-background px-4 text-sm font-medium text-foreground no-underline transition hover:border-primary/60 hover:text-primary"
        >
          <span>{{ t("nav.billing") }}</span>
          <span aria-hidden="true">→</span>
        </NuxtLink>
        <NuxtLink
          to="/activate"
          class="inline-flex h-11 items-center justify-between rounded-xl border border-border bg-background px-4 text-sm font-medium text-foreground no-underline transition hover:border-primary/60 hover:text-primary"
        >
          <span>{{ t("auth.activateTitle") }}</span>
          <span aria-hidden="true">→</span>
        </NuxtLink>
      </div>
      <p v-if="loading" class="mt-5 text-sm text-muted-foreground">{{ t("common.loading") }}</p>
    </div>
  </section>
</template>
