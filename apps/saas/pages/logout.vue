<script setup lang="ts">
const { t } = useI18n();
const { success } = useNotify();
const { clearSession } = useAuthSession();

onMounted(async () => {
  await fetch("/api/auth/sign-out", { method: "POST", credentials: "include" }).catch(() => null);
  clearSession();
  success("toasts.loggedOut");
  await navigateTo("/login");
});
</script>

<template>
  <section class="mx-auto max-w-xl">
    <div class="glass-panel p-6 md:p-8">
      <h1 class="text-3xl font-semibold tracking-tight">{{ t("ui.logoutTitle") }}</h1>
      <p class="mt-2 text-sm text-muted-foreground">{{ t("ui.logoutSubtitle") }}</p>
    </div>
  </section>
</template>
