<script setup lang="ts">
import { Toaster } from "vue-sonner";

const colorMode = useColorMode();
const toastTheme = computed(() => (colorMode.value === "dark" ? "dark" : "light"));
</script>

<template>
  <NuxtLoadingIndicator color="hsl(var(--primary))" />
  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
  <Toaster
    close-button
    rich-colors
    :theme="toastTheme"
    position="top-right"
    :duration="3600"
    :expand="true"
  />
</template>
