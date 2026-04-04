<script setup lang="ts">
const route = useRoute();
const email = ref(typeof route.query.email === 'string' ? route.query.email : '');
const password = ref('');
const notice = ref('');
const noticeError = ref(false);
const busy = ref(false);
const runtimeConfig = useRuntimeConfig();

const returnTo = computed(() => (typeof route.query.returnTo === 'string' && route.query.returnTo.startsWith('/')
  ? route.query.returnTo
  : '/account'));

const socialProviders = computed(() => ({
  google: Boolean(runtimeConfig.public.socialProviders?.google),
  apple: Boolean(runtimeConfig.public.socialProviders?.apple)
}));

const { postJson } = useApi();

const setNotice = (message: string, isError = false) => {
  notice.value = message;
  noticeError.value = isError;
};

const signIn = async () => {
  busy.value = true;
  setNotice('Signing in...');
  try {
    await postJson('/api/auth/sign-in/email', {
      email: email.value.trim(),
      password: password.value,
      callbackURL: new URL(returnTo.value, window.location.origin).toString(),
      rememberMe: true
    });
    await navigateTo(returnTo.value);
  } catch (error) {
    setNotice(error instanceof Error ? error.message : 'Sign in failed', true);
  } finally {
    busy.value = false;
  }
};

const signInWithSocial = async (provider: 'google' | 'apple') => {
  busy.value = true;
  setNotice(`Redirecting to ${provider}...`);
  try {
    const result = await postJson<{ url?: string | null }>('/api/auth/sign-in/social', {
      provider,
      callbackURL: new URL(returnTo.value, window.location.origin).toString(),
      errorCallbackURL: new URL(`/login?returnTo=${encodeURIComponent(returnTo.value)}`, window.location.origin).toString()
    });
    if (result.url) {
      window.location.href = result.url;
      return;
    }
    await navigateTo(returnTo.value);
  } catch (error) {
    setNotice(error instanceof Error ? error.message : 'Social sign in failed', true);
  } finally {
    busy.value = false;
  }
};

const sendMagicLink = async () => {
  busy.value = true;
  setNotice('Sending magic link...');
  try {
    await postJson('/api/auth/sign-in/magic-link', {
      email: email.value.trim(),
      callbackURL: new URL(returnTo.value, window.location.origin).toString(),
      errorCallbackURL: new URL(`/login?returnTo=${encodeURIComponent(returnTo.value)}`, window.location.origin).toString()
    });
    setNotice('Magic link sent if the account exists.');
  } catch (error) {
    setNotice(error instanceof Error ? error.message : 'Magic link failed', true);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <main class="page">
    <section class="card">
      <h1>Sign in to Nomade</h1>
      <p class="muted">Use your email/password or request a magic link.</p>
      <form class="row" @submit.prevent="signIn">
        <input v-model="email" type="email" placeholder="you@example.com" required />
        <input v-model="password" type="password" placeholder="Password" required />
        <button class="primary" :disabled="busy" type="submit">Sign in</button>
      </form>
      <div class="row" style="margin-top:0.75rem">
        <button :disabled="busy || !email" type="button" @click="sendMagicLink">Send magic link</button>
        <NuxtLink :to="`/signup?returnTo=${encodeURIComponent(returnTo)}`">Create account</NuxtLink>
        <NuxtLink to="/forgot-password">Forgot password?</NuxtLink>
      </div>
      <div v-if="socialProviders.google || socialProviders.apple" class="row" style="margin-top:0.75rem">
        <button
          v-if="socialProviders.google"
          type="button"
          :disabled="busy"
          @click="signInWithSocial('google')"
        >
          Continue with Google
        </button>
        <button
          v-if="socialProviders.apple"
          type="button"
          :disabled="busy"
          @click="signInWithSocial('apple')"
        >
          Continue with Apple
        </button>
      </div>
      <p class="notice" :class="{ error: noticeError }">{{ notice }}</p>
    </section>
  </main>
</template>
