<script setup lang="ts">
import { UserRound } from "lucide-vue-next";

const route = useRoute();
const { t, locale } = useI18n();
const { user, isAuthenticated, fetchSession } = useAuthSession();

await fetchSession();

interface NavItem {
  to: string;
  label: string;
}

const dashboardNavItems = computed<NavItem[]>(() => [
  { to: "/account", label: t("nav.account") },
  { to: "/devices", label: t("nav.devices") },
  { to: "/billing", label: t("nav.billing") }
]);

const marketingNavItems = computed<NavItem[]>(() => {
  const labels =
    locale.value === "fr"
      ? {
          features: "Fonctionnalités",
          openSource: "Open source",
          pricing: "Tarifs",
          legal: "Légal"
        }
      : {
          features: "Features",
          openSource: "Open Source",
          pricing: "Pricing",
          legal: "Legal"
        };
  return [
    { to: "/#features", label: labels.features },
    { to: "/#open-source", label: labels.openSource },
    { to: "/pricing", label: labels.pricing },
    { to: "/legal", label: labels.legal }
  ];
});

const navItems = computed<NavItem[]>(() =>
  isAuthenticated.value ? dashboardNavItems.value : marketingNavItems.value
);

const isPublicRoute = computed(() =>
  route.path === "/" || route.path === "/pricing" || route.path === "/legal" || route.path.startsWith("/legal/")
);

const logoTarget = computed(() => (isAuthenticated.value ? "/account" : "/"));

const isActive = (to: string): boolean => {
  if (to.startsWith("/#")) {
    return route.path === "/";
  }
  if (to === "/legal") {
    return route.path === "/legal" || route.path.startsWith("/legal/");
  }
  return route.path === to;
};

const showSignIn = computed(() => !isAuthenticated.value && route.path !== "/login");
const showSignUp = computed(() => !isAuthenticated.value && route.path !== "/signup");
</script>

<template>
  <header class="sticky top-0 z-30 border-b border-border/70 bg-background/70 backdrop-blur-md">
    <div class="container flex h-16 items-center justify-between gap-3">
      <NuxtLink :to="logoTarget" class="flex items-center gap-2 text-foreground no-underline">
        <span class="inline-flex h-9 w-9 items-center justify-center rounded-xl bg-primary/15 text-primary">
          <UserRound class="h-4 w-4" />
        </span>
        <span class="text-base font-semibold tracking-tight">Nomade</span>
      </NuxtLink>

      <nav class="hidden items-center gap-2 md:flex">
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
          v-if="showSignIn"
          to="/login"
          class="hidden rounded-xl border border-border/80 bg-card/90 px-3 py-2 text-sm font-medium text-muted-foreground transition hover:border-primary/50 hover:text-primary sm:inline-flex"
        >
          {{ t("auth.signIn") }}
        </NuxtLink>
        <NuxtLink
          v-if="showSignUp"
          to="/signup"
          class="inline-flex rounded-xl bg-primary px-3 py-2 text-xs font-semibold text-primary-foreground transition hover:opacity-90 sm:text-sm"
        >
          {{ t("auth.signUp") }}
        </NuxtLink>
        <NuxtLink
          v-if="isAuthenticated"
          to="/logout"
          class="inline-flex rounded-xl border border-border/80 bg-card/90 px-3 py-2 text-xs font-medium text-muted-foreground transition hover:border-primary/50 hover:text-primary sm:text-sm"
        >
          {{ t("auth.logout") }}
        </NuxtLink>
        <span
          v-if="isAuthenticated && user?.email && !isPublicRoute"
          class="hidden rounded-xl bg-muted px-3 py-2 text-xs font-medium text-muted-foreground lg:inline-flex"
        >
          {{ user.email }}
        </span>
      </div>
    </div>
  </header>
</template>
