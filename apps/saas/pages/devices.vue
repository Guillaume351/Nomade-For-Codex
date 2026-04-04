<script setup lang="ts">
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

const items = ref<AgentItem[]>([]);
const error = ref('');
const { getJson } = useApi();

onMounted(async () => {
  try {
    const payload = await getJson<AgentsPayload>('/agents');
    items.value = Array.isArray(payload.items) ? payload.items : [];
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Unable to load devices';
    await navigateTo('/login?returnTo=%2Fdevices');
  }
});
</script>

<template>
  <main class="page">
    <section class="card">
      <h1>Devices</h1>
      <p class="muted">Registered agents for your account.</p>
      <p v-if="error" class="notice error">{{ error }}</p>
      <table>
        <thead>
          <tr>
            <th>Name</th>
            <th>ID</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="agent in items" :key="agent.id">
            <td>{{ agent.display_name || agent.name || 'Unnamed' }}</td>
            <td><code>{{ agent.id }}</code></td>
            <td>{{ agent.is_online ? 'online' : 'offline' }}</td>
          </tr>
          <tr v-if="items.length === 0">
            <td colspan="3" class="muted">No device paired yet.</td>
          </tr>
        </tbody>
      </table>
      <div class="row" style="margin-top:0.75rem">
        <NuxtLink to="/account">Back to account</NuxtLink>
      </div>
    </section>
  </main>
</template>
