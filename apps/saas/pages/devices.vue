<script setup lang="ts">
definePageMeta({
  middleware: ["require-auth"]
});

interface AgentItem {
  id: string;
  name?: string;
  display_name?: string;
  is_online?: boolean;
  created_at?: string;
  last_seen_at?: string | null;
}

interface AgentsPayload {
  items: AgentItem[];
}

const { t } = useI18n();
const { getJson } = useApi();
const { errorFrom } = useNotify();

const loading = ref(true);
const items = ref<AgentItem[]>([]);

const loadDevices = async () => {
  loading.value = true;
  try {
    const payload = await getJson<AgentsPayload>("/agents");
    items.value = Array.isArray(payload.items) ? payload.items : [];
  } catch (err) {
    errorFrom(err);
    await navigateTo(`/login?returnTo=${encodeURIComponent("/devices")}`);
  } finally {
    loading.value = false;
  }
};

await loadDevices();
</script>

<template>
  <section class="glass-panel p-6 md:p-8">
    <h1 class="text-3xl font-semibold tracking-tight">{{ t("devices.title") }}</h1>
    <p class="mt-2 text-sm text-muted-foreground">{{ t("devices.subtitle") }}</p>

    <div class="mt-6 overflow-x-auto rounded-2xl border border-border/80 bg-background/80">
      <table class="min-w-full divide-y divide-border/80">
        <thead class="bg-muted/40">
          <tr class="text-left">
            <th class="px-4 py-3 text-xs font-semibold uppercase tracking-wide text-muted-foreground">{{ t("devices.name") }}</th>
            <th class="px-4 py-3 text-xs font-semibold uppercase tracking-wide text-muted-foreground">{{ t("devices.id") }}</th>
            <th class="px-4 py-3 text-xs font-semibold uppercase tracking-wide text-muted-foreground">{{ t("devices.state") }}</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-border/70">
          <tr v-for="agent in items" :key="agent.id">
            <td class="px-4 py-3 text-sm font-medium">
              {{ agent.display_name || agent.name || t("devices.unnamed") }}
            </td>
            <td class="px-4 py-3 text-xs text-muted-foreground">
              <code class="rounded bg-muted px-2 py-1">{{ agent.id }}</code>
            </td>
            <td class="px-4 py-3 text-sm">
              <span
                class="inline-flex rounded-full px-2.5 py-1 text-xs font-semibold"
                :class="agent.is_online ? 'bg-primary/15 text-primary' : 'bg-muted text-muted-foreground'"
              >
                {{ agent.is_online ? t("devices.online") : t("devices.offline") }}
              </span>
            </td>
          </tr>
          <tr v-if="!loading && items.length === 0">
            <td colspan="3" class="px-4 py-8 text-center text-sm text-muted-foreground">{{ t("devices.empty") }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <p v-if="loading" class="mt-5 text-sm text-muted-foreground">{{ t("common.loading") }}</p>
    <div class="mt-5">
      <NuxtLink to="/account">{{ t("common.backToAccount") }}</NuxtLink>
    </div>
  </section>
</template>
