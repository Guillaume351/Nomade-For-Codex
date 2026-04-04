<script setup lang="ts">
import { MoonStar, SunMedium, Monitor } from "lucide-vue-next";

const colorMode = useColorMode();
const { t } = useI18n();

const modes: Array<"light" | "dark" | "system"> = ["light", "dark", "system"];

const currentModeIndex = computed(() => {
  const current = colorMode.preference as "light" | "dark" | "system";
  return modes.indexOf(current);
});

const nextMode = () => {
  const current = currentModeIndex.value;
  colorMode.preference = modes[(current + 1) % modes.length] ?? "system";
};

const icon = computed(() => {
  if (colorMode.preference === "light") return SunMedium;
  if (colorMode.preference === "dark") return MoonStar;
  return Monitor;
});
</script>

<template>
  <button
    type="button"
    class="inline-flex h-10 w-10 items-center justify-center rounded-xl border border-border/80 bg-card/90 text-muted-foreground transition hover:border-primary/50 hover:text-primary"
    :title="t('common.theme')"
    @click="nextMode"
  >
    <component :is="icon" class="h-4 w-4" />
  </button>
</template>
