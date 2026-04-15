<script setup lang="ts">
const { locale } = useI18n();

const copy = computed(() =>
  locale.value === "fr"
    ? {
        summary: "Accès IA à haute fiabilité avec un mode auto-hébergé entièrement gratuit et une option cloud managée.",
        product: "Produit",
        features: "Fonctionnalités",
        openSource: "Open source",
        pricing: "Tarifs",
        legal: "Légal",
        privacy: "Politique de confidentialité",
        terms: "Conditions d'utilisation",
        usage: "Accord d'utilisation",
        confidentiality: "Confidentialité"
      }
    : {
        summary: "High-trust AI workspace access with a fully free self-hosted mode and a managed cloud option.",
        product: "Product",
        features: "Features",
        openSource: "Open source",
        pricing: "Pricing",
        legal: "Legal",
        privacy: "Privacy policy",
        terms: "Terms of service",
        usage: "Usage agreement",
        confidentiality: "Confidentiality"
      }
);
</script>

<template>
  <footer class="border-t border-border/80 bg-card/60">
    <div class="container grid gap-8 py-10 md:grid-cols-[1.4fr_1fr_1fr] md:py-12">
      <div>
        <p class="text-sm font-semibold tracking-wide text-foreground">Nomade</p>
        <p class="mt-3 max-w-md text-sm text-muted-foreground">
          {{ copy.summary }}
        </p>
      </div>

      <div>
        <p class="text-xs font-semibold uppercase tracking-[0.16em] text-muted-foreground">{{ copy.product }}</p>
        <ul class="mt-3 space-y-2 text-sm">
          <li><NuxtLink to="/#features" class="no-underline">{{ copy.features }}</NuxtLink></li>
          <li><NuxtLink to="/#open-source" class="no-underline">{{ copy.openSource }}</NuxtLink></li>
          <li><NuxtLink to="/pricing" class="no-underline">{{ copy.pricing }}</NuxtLink></li>
        </ul>
      </div>

      <div>
        <p class="text-xs font-semibold uppercase tracking-[0.16em] text-muted-foreground">{{ copy.legal }}</p>
        <ul class="mt-3 space-y-2 text-sm">
          <li><NuxtLink to="/legal/privacy" class="no-underline">{{ copy.privacy }}</NuxtLink></li>
          <li><NuxtLink to="/legal/terms" class="no-underline">{{ copy.terms }}</NuxtLink></li>
          <li><NuxtLink to="/legal/usage-agreement" class="no-underline">{{ copy.usage }}</NuxtLink></li>
          <li><NuxtLink to="/legal/confidentiality" class="no-underline">{{ copy.confidentiality }}</NuxtLink></li>
        </ul>
      </div>
    </div>
  </footer>
</template>
