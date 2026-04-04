<script setup lang="ts">
const route = useRoute();
const name = ref('');
const email = ref(typeof route.query.email === 'string' ? route.query.email : '');
const password = ref('');
const busy = ref(false);
const notice = ref('');
const noticeError = ref(false);

const returnTo = computed(() => (typeof route.query.returnTo === 'string' && route.query.returnTo.startsWith('/')
  ? route.query.returnTo
  : '/account'));

const { postJson } = useApi();
const setNotice = (message: string, isError = false) => {
  notice.value = message;
  noticeError.value = isError;
};

const createAccount = async () => {
  busy.value = true;
  setNotice('Creating account...');
  try {
    await postJson('/api/auth/sign-up/email', {
      name: name.value.trim(),
      email: email.value.trim(),
      password: password.value,
      callbackURL: new URL(returnTo.value, window.location.origin).toString()
    });
    setNotice('Account created. Check your email to verify your address.');
  } catch (error) {
    setNotice(error instanceof Error ? error.message : 'Sign-up failed', true);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <main class="page">
    <section class="card">
      <h1>Create your Nomade account</h1>
      <p class="muted">Email verification is required before first sign-in.</p>
      <form class="row" @submit.prevent="createAccount">
        <input v-model="name" type="text" placeholder="Full name" required />
        <input v-model="email" type="email" placeholder="you@example.com" required />
        <input v-model="password" type="password" placeholder="Password (8+ chars)" required />
        <button class="primary" :disabled="busy" type="submit">Create account</button>
      </form>
      <div class="row" style="margin-top:0.75rem">
        <NuxtLink :to="`/login?returnTo=${encodeURIComponent(returnTo)}`">Back to sign-in</NuxtLink>
      </div>
      <p class="notice" :class="{ error: noticeError }">{{ notice }}</p>
    </section>
  </main>
</template>
