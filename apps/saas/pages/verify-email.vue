<script setup lang="ts">
const route = useRoute();
const notice = ref('Verifying your email...');
const noticeError = ref(false);

const token = typeof route.query.token === 'string' ? route.query.token : '';
const returnTo = typeof route.query.returnTo === 'string' && route.query.returnTo.startsWith('/')
  ? route.query.returnTo
  : '/account';

const setNotice = (message: string, isError = false) => {
  notice.value = message;
  noticeError.value = isError;
};

onMounted(async () => {
  if (!token) {
    setNotice('Missing verification token.', true);
    return;
  }
  try {
    const callbackURL = new URL(returnTo, window.location.origin).toString();
    const response = await fetch(`/api/auth/verify-email?token=${encodeURIComponent(token)}&callbackURL=${encodeURIComponent(callbackURL)}`);
    const data = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    if (!response.ok) {
      const message =
        typeof data.message === 'string'
          ? data.message
          : typeof data.error === 'string'
            ? data.error
            : 'Verification failed';
      throw new Error(message);
    }
    await navigateTo(returnTo);
  } catch (error) {
    setNotice(error instanceof Error ? error.message : 'Verification failed', true);
  }
});
</script>

<template>
  <main class="page">
    <section class="card">
      <h1>Verify your email</h1>
      <p class="notice" :class="{ error: noticeError }">{{ notice }}</p>
      <p class="muted"><NuxtLink to="/login">Back to sign-in</NuxtLink></p>
    </section>
  </main>
</template>
