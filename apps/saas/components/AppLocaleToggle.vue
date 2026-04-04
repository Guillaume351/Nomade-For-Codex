<script setup lang="ts">
import { Languages } from "lucide-vue-next";

const { locale, setLocale, t } = useI18n();

const toggleLocale = async () => {
  await setLocale(locale.value === "fr" ? "en" : "fr");
};
</script>

<template>
  <button
    type="button"
    class="inline-flex h-10 items-center gap-2 rounded-xl border border-border/80 bg-card/90 px-3 text-sm font-medium text-muted-foreground transition hover:border-primary/50 hover:text-primary"
    :title="t('common.language')"
    @click="toggleLocale"
  >
    <Languages class="h-4 w-4" />
    <span>{{ locale.toUpperCase() }}</span>
  </button>
</template>
