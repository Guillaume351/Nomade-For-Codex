<script setup lang="ts">
const route = useRoute();
const token = ref(typeof route.query.token === 'string' ? route.query.token : '');
const newPassword = ref('');
const notice = ref('');
const noticeError = ref(false);
const busy = ref(false);
const { postJson } = useApi();

const setNotice = (message: string, isError = false) => {
  notice.value = message;
  noticeError.value = isError;
};

const resetPassword = async () => {
  if (!token.value) {
    setNotice('Missing reset token.', true);
    return;
  }
  busy.value = true;
  setNotice('Updating password...');
  try {
    await postJson('/api/auth/reset-password', {
      token: token.value,
      newPassword: newPassword.value
    });
    await navigateTo('/login');
  } catch (error) {
    setNotice(error instanceof Error ? error.message : 'Reset failed', true);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <main class="page">
    <section class="card">
      <h1>Reset password</h1>
      <p class="muted">Choose a new password for your account.</p>
      <form class="row" @submit.prevent="resetPassword">
        <input v-model="token" type="text" placeholder="Reset token" required />
        <input v-model="newPassword" type="password" placeholder="New password" required />
        <button class="primary" :disabled="busy" type="submit">Update password</button>
      </form>
      <div class="row" style="margin-top:0.75rem">
        <NuxtLink to="/login">Back to sign-in</NuxtLink>
      </div>
      <p class="notice" :class="{ error: noticeError }">{{ notice }}</p>
    </section>
  </main>
</template>
