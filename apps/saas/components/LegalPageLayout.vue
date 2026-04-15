<script setup lang="ts">
const props = defineProps<{
  title: string;
  summary: string;
  lastUpdated: string;
}>();

const { locale } = useI18n();

const copy = computed(() =>
  locale.value === "fr"
    ? {
        legal: "Légal",
        lastUpdated: "Dernière mise à jour",
        allLegalPages: "Toutes les pages légales",
        links: [
          { label: "Centre légal", href: "/legal" },
          { label: "Politique de confidentialité", href: "/legal/privacy" },
          { label: "Conditions d'utilisation", href: "/legal/terms" },
          { label: "Accord d'utilisation", href: "/legal/usage-agreement" },
          { label: "Confidentialité", href: "/legal/confidentiality" }
        ]
      }
    : {
        legal: "Legal",
        lastUpdated: "Last updated",
        allLegalPages: "All legal pages",
        links: [
          { label: "Legal hub", href: "/legal" },
          { label: "Privacy policy", href: "/legal/privacy" },
          { label: "Terms of service", href: "/legal/terms" },
          { label: "Usage agreement", href: "/legal/usage-agreement" },
          { label: "Confidentiality", href: "/legal/confidentiality" }
        ]
      }
);
</script>

<template>
  <div>
    <section class="border-b border-border/80 bg-card/35">
      <div class="container py-12 md:py-14">
        <p class="text-xs font-semibold uppercase tracking-[0.16em] text-primary">{{ copy.legal }}</p>
        <h1 class="mt-3 max-w-3xl text-4xl font-semibold tracking-tight md:text-5xl">{{ props.title }}</h1>
        <p class="mt-4 max-w-3xl text-base leading-relaxed text-muted-foreground md:text-lg">{{ props.summary }}</p>
        <p class="mt-5 text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
          {{ copy.lastUpdated }}: {{ props.lastUpdated }}
        </p>
      </div>
    </section>

    <section class="container py-10 md:py-14">
      <div class="grid items-start gap-6 lg:grid-cols-[0.72fr_0.28fr]">
        <article class="glass-panel space-y-8 p-6 md:p-8">
          <slot />
        </article>

        <aside class="glass-panel p-6">
          <p class="text-xs font-semibold uppercase tracking-[0.16em] text-muted-foreground">{{ copy.allLegalPages }}</p>
          <ul class="mt-4 grid gap-2 text-sm">
            <li v-for="item in copy.links" :key="item.href">
              <NuxtLink :to="item.href" class="no-underline">{{ item.label }}</NuxtLink>
            </li>
          </ul>
        </aside>
      </div>
    </section>
  </div>
  <MarketingFooter />
</template>
