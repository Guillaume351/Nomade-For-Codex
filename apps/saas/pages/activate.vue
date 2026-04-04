<script setup lang="ts">
const route = useRoute();
const userCode = ref(typeof route.query.user_code === 'string' ? route.query.user_code : '');
const notice = ref('');
const noticeError = ref(false);
const busy = ref(false);
const me = ref<string | null>(null);
const { postJson, getJson } = useApi();

const setNotice = (message: string, isError = false) => {
  notice.value = message;
  noticeError.value = isError;
};

onMounted(async () => {
  try {
    const session = await getJson<{ user?: { email?: string } | null }>('/api/auth/get-session');
    if (!session?.user?.email) {
      throw new Error('auth_required');
    }
    me.value = session.user.email;
  } catch {
    const returnTo = `/activate${route.fullPath.includes('?') ? route.fullPath.slice(route.fullPath.indexOf('?')) : ''}`;
    await navigateTo(`/login?returnTo=${encodeURIComponent(returnTo)}`);
  }
});

const approve = async () => {
  const normalized = userCode.value.trim().toUpperCase();
  if (!normalized) {
    setNotice('Missing user code.', true);
    return;
  }
  busy.value = true;
  setNotice('Approving login...');
  try {
    await postJson('/auth/device/approve', { userCode: normalized });
    setNotice('Login approved. You can return to your terminal/app.');
  } catch (error) {
    setNotice(error instanceof Error ? error.message : 'Approval failed', true);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <main class="page">
    <section class="card">
      <h1>Activate Device Login</h1>
      <p v-if="me" class="muted">Signed in as <code>{{ me }}</code>.</p>
      <form class="row" @submit.prevent="approve">
        <input v-model="userCode" type="text" placeholder="ABCD1234" required />
        <button class="primary" :disabled="busy" type="submit">Approve login</button>
      </form>
      <p class="muted">Copy the code displayed in your terminal if the field is empty.</p>
      <p class="notice" :class="{ error: noticeError }">{{ notice }}</p>
    </section>
  </main>
</template>
