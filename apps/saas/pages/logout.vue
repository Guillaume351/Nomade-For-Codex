<script setup lang="ts">
onMounted(async () => {
  await fetch('/api/auth/sign-out', { method: 'POST' }).catch(() => null);
  await navigateTo('/login');
});
</script>

<template>
  <main class="page">
    <section class="card">
      <h1>Signing out</h1>
      <p class="muted">Ending your session...</p>
    </section>
  </main>
</template>
