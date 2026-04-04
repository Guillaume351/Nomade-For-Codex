<script setup lang="ts">
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

const me = ref<MePayload | null>(null);
const entitlements = ref<EntitlementsPayload | null>(null);
const notice = ref('');

const { getJson } = useApi();

const loadAccount = async () => {
  try {
    me.value = await getJson<MePayload>('/me');
    entitlements.value = await getJson<EntitlementsPayload>('/me/entitlements');
  } catch {
    await navigateTo('/login?returnTo=%2Faccount');
  }
};

onMounted(async () => {
  await loadAccount();
  if (typeof useRoute().query.billing === 'string') {
    notice.value = useRoute().query.billing === 'success'
      ? 'Billing action completed.'
      : 'Billing flow canceled.';
  }
});
</script>

<template>
  <main class="page">
    <section class="card">
      <h1>Account</h1>
      <p v-if="me" class="muted">Signed in as <code>{{ me.email }}</code>.</p>
      <table v-if="entitlements">
        <tbody>
          <tr><th>Plan</th><td>{{ entitlements.planCode }}</td></tr>
          <tr><th>Device quota</th><td>{{ entitlements.currentAgents }}/{{ entitlements.maxAgents }}</td></tr>
          <tr><th>Status</th><td>{{ entitlements.subscriptionStatus }}</td></tr>
        </tbody>
      </table>
      <div class="row" style="margin-top:0.75rem">
        <NuxtLink to="/devices">Manage devices</NuxtLink>
        <NuxtLink to="/billing">Billing</NuxtLink>
        <NuxtLink to="/logout">Sign out</NuxtLink>
      </div>
      <p class="notice">{{ notice }}</p>
    </section>
  </main>
</template>
