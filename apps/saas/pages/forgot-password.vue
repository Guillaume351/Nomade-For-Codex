<script setup lang="ts">
const email = ref('');
const notice = ref('');
const busy = ref(false);
const { postJson } = useApi();

const sendLink = async () => {
  busy.value = true;
  notice.value = 'Sending reset link...';
  try {
    await postJson('/api/auth/request-password-reset', {
      email: email.value.trim(),
      redirectTo: new URL('/reset-password', window.location.origin).toString()
    });
    notice.value = 'If the account exists, a reset link has been sent.';
  } catch {
    notice.value = 'If the account exists, a reset link has been sent.';
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <main class="page">
    <section class="card">
      <h1>Forgot password</h1>
      <p class="muted">Enter your email and we&apos;ll send a reset link.</p>
      <form class="row" @submit.prevent="sendLink">
        <input v-model="email" type="email" placeholder="you@example.com" required />
        <button class="primary" :disabled="busy" type="submit">Send reset link</button>
      </form>
      <div class="row" style="margin-top:0.75rem">
        <NuxtLink to="/login">Back to sign-in</NuxtLink>
      </div>
      <p class="notice">{{ notice }}</p>
    </section>
  </main>
</template>
