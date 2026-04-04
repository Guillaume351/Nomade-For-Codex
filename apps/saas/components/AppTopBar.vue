<script setup lang="ts">
import { UserRound } from "lucide-vue-next";

const route = useRoute();
const { t } = useI18n();
const { user, isAuthenticated, fetchSession } = useAuthSession();

await fetchSession();

const navItems = computed(() => [
  { to: "/account", label: t("nav.account") },
  { to: "/devices", label: t("nav.devices") },
  { to: "/billing", label: t("nav.billing") }
]);

const isActive = (to: string): boolean => route.path === to;
</script>

<template>
  <header class="sticky top-0 z-30 border-b border-border/70 bg-background/70 backdrop-blur-md">
    <div class="container flex h-16 items-center justify-between gap-3">
      <NuxtLink to="/account" class="flex items-center gap-2 text-foreground no-underline">
        <span class="inline-flex h-9 w-9 items-center justify-center rounded-xl bg-primary/15 text-primary">
          <UserRound class="h-4 w-4" />
        </span>
        <span class="text-base font-semibold tracking-tight">Nomade</span>
      </NuxtLink>

      <nav v-if="isAuthenticated" class="hidden items-center gap-2 md:flex">
        <NuxtLink
          v-for="item in navItems"
          :key="item.to"
          :to="item.to"
          class="rounded-xl px-3 py-2 text-sm font-medium transition no-underline"
          :class="
            isActive(item.to)
              ? 'bg-primary/15 text-primary'
              : 'text-muted-foreground hover:bg-muted hover:text-foreground'
          "
        >
          {{ item.label }}
        </NuxtLink>
      </nav>

      <div class="flex items-center gap-2">
        <AppLocaleToggle />
        <AppThemeToggle />
        <NuxtLink
          v-if="isAuthenticated"
          to="/logout"
          class="hidden rounded-xl border border-border/80 bg-card/90 px-3 py-2 text-sm font-medium text-muted-foreground transition hover:border-primary/50 hover:text-primary md:inline-flex"
        >
          {{ t("auth.logout") }}
        </NuxtLink>
        <span
          v-if="isAuthenticated && user?.email"
          class="hidden rounded-xl bg-muted px-3 py-2 text-xs font-medium text-muted-foreground lg:inline-flex"
        >
          {{ user.email }}
        </span>
      </div>
    </div>
  </header>
</template>
