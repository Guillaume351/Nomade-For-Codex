<script setup lang="ts">
import { ArrowRight, CheckCircle2, ShieldCheck } from "lucide-vue-next";

definePageMeta({
  layout: "marketing"
});

const { locale } = useI18n();

const enCopy = {
  seoTitle: "Nomade Pricing | Free Self-Hosted and Managed Cloud Plans",
  seoDescription:
    "Compare Nomade plans: self-hosted with no Nomade subscription, cloud free tier with 1 paired device, and paid managed cloud upgrades.",
  heroBadge: "Pricing",
  heroTitle: "Self-host free. Cloud starts free.",
  heroSubtitle:
    "Self-host has no Nomade subscription fee. Nomade Cloud includes a free tier with 1 paired device per account, then paid upgrades for more capacity and support.",
  plans: {
    selfHosted: {
      kicker: "Self-hosted (Open source)",
      price: "Free",
      subtitle: "No Nomade subscription required",
      bullets: [
        "Run on your infra with full control.",
        "Use your own endpoint in the app.",
        "Limits are controlled by your server settings (for example FREE_MAX_AGENTS)."
      ],
      cta: "Read self-host docs"
    },
    cloudPro: {
      kicker: "Nomade Cloud",
      price: "Free tier + paid upgrade",
      subtitle: "Cloud Free: 1 paired device/account",
      bullets: [
        "Start at no cost on Nomade-managed infrastructure.",
        "Free tier includes 1 paired device per account.",
        "Hosted control plane managed by Nomade.",
        "Upgrade when you need more devices and priority support."
      ],
      cta: "Upgrade to Cloud Pro"
    }
  },
  comparisonTitle: "Plan comparison",
  comparisonSubtitle: "Same core product. Different ownership of infrastructure, limits, and support.",
  tableHeaders: {
    capability: "Capability",
    selfHosted: "Self-hosted (Free)",
    cloudPro: "Cloud Pro (Paid)"
  },
  rows: [
    { capability: "License cost", selfHosted: "Free", cloudPro: "Paid subscription" },
    { capability: "Cloud free tier", selfHosted: "Not applicable", cloudPro: "1 paired device per account" },
    { capability: "Open-source core", selfHosted: "Included", cloudPro: "Included" },
    { capability: "Deployment model", selfHosted: "Your infrastructure", cloudPro: "Nomade managed cloud" },
    { capability: "Subscription required", selfHosted: "No", cloudPro: "Only above cloud free tier" },
    { capability: "Billing and invoicing", selfHosted: "Self-managed", cloudPro: "Included" },
    { capability: "Operational maintenance", selfHosted: "Self-managed", cloudPro: "Managed by Nomade" },
    { capability: "Priority support", selfHosted: "Community / self-service", cloudPro: "Included" },
    { capability: "Compliance document bundle", selfHosted: "Included templates", cloudPro: "Included" },
    {
      capability: "Best for",
      selfHosted: "Engineering-first teams",
      cloudPro: "Teams prioritizing speed and convenience"
    }
  ]
};

const frCopy = {
  seoTitle: "Tarifs Nomade | Auto-hébergé gratuit et cloud managé",
  seoDescription:
    "Comparez les offres Nomade : auto-hébergement sans abonnement Nomade, cloud gratuit avec 1 appareil appairé, puis upgrade cloud payante.",
  heroBadge: "Tarifs",
  heroTitle: "Self-host gratuit. Cloud gratuit au départ.",
  heroSubtitle:
    "L'auto-hébergement n'impose aucun abonnement Nomade. Le cloud Nomade inclut une offre gratuite avec 1 appareil appairé par compte, puis des upgrades payantes pour plus de capacité et de support.",
  plans: {
    selfHosted: {
      kicker: "Auto-hébergé (Open source)",
      price: "Gratuit",
      subtitle: "Aucun abonnement Nomade requis",
      bullets: [
        "Déploiement sur votre infrastructure avec contrôle total.",
        "Utilisez votre propre endpoint dans l'app.",
        "Les limites sont pilotées par votre configuration serveur (ex: FREE_MAX_AGENTS)."
      ],
      cta: "Lire la doc self-host"
    },
    cloudPro: {
      kicker: "Nomade Cloud",
      price: "Offre gratuite + upgrade payante",
      subtitle: "Cloud gratuit : 1 appareil appairé/compte",
      bullets: [
        "Commencez sans coût sur l'infra managée Nomade.",
        "L'offre gratuite inclut 1 appareil appairé par compte.",
        "Plan de contrôle hébergé et opéré par Nomade.",
        "Upgrade quand vous avez besoin de plus d'appareils et d'un support prioritaire."
      ],
      cta: "Passer à Cloud Pro"
    }
  },
  comparisonTitle: "Comparaison des offres",
  comparisonSubtitle: "Même noyau produit. Différence sur l'infrastructure, les limites et le support.",
  tableHeaders: {
    capability: "Capacité",
    selfHosted: "Auto-hébergé (Gratuit)",
    cloudPro: "Cloud Pro (Payant)"
  },
  rows: [
    { capability: "Coût de licence", selfHosted: "Gratuit", cloudPro: "Abonnement payant" },
    { capability: "Offre cloud gratuite", selfHosted: "Non applicable", cloudPro: "1 appareil appairé par compte" },
    { capability: "Noyau open source", selfHosted: "Inclus", cloudPro: "Inclus" },
    { capability: "Modèle de déploiement", selfHosted: "Votre infrastructure", cloudPro: "Cloud Nomade managé" },
    { capability: "Abonnement requis", selfHosted: "Non", cloudPro: "Uniquement au-dessus de l'offre cloud gratuite" },
    { capability: "Facturation et paiement", selfHosted: "Auto-géré", cloudPro: "Inclus" },
    { capability: "Maintenance opérationnelle", selfHosted: "Auto-géré", cloudPro: "Pris en charge par Nomade" },
    { capability: "Support prioritaire", selfHosted: "Communauté / self-service", cloudPro: "Inclus" },
    { capability: "Bundle de conformité", selfHosted: "Templates inclus", cloudPro: "Inclus" },
    {
      capability: "Idéal pour",
      selfHosted: "Équipes orientées ingénierie",
      cloudPro: "Équipes privilégiant vitesse et simplicité"
    }
  ]
};

const copy = computed(() => (locale.value === "fr" ? frCopy : enCopy));

useSeoMeta({
  title: () => copy.value.seoTitle,
  description: () => copy.value.seoDescription
});
</script>

<template>
  <div class="pb-16 md:pb-20">
    <section class="border-b border-border/80 bg-card/35">
      <div class="container py-14 md:py-16">
        <span
          class="inline-flex items-center gap-2 rounded-full border border-primary/35 bg-primary/10 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-primary"
        >
          <ShieldCheck class="h-3.5 w-3.5" />
          {{ copy.heroBadge }}
        </span>
        <h1 class="mt-5 max-w-3xl text-4xl font-semibold tracking-tight md:text-5xl">
          {{ copy.heroTitle }}
        </h1>
        <p class="mt-5 max-w-3xl text-base leading-relaxed text-muted-foreground md:text-lg">
          {{ copy.heroSubtitle }}
        </p>
      </div>
    </section>

    <section class="container py-10 md:py-14">
      <div class="grid gap-4 lg:grid-cols-2">
        <article class="glass-panel p-6 md:p-8">
          <p class="text-xs font-semibold uppercase tracking-[0.16em] text-primary">{{ copy.plans.selfHosted.kicker }}</p>
          <h2 class="mt-2 text-3xl font-semibold tracking-tight">{{ copy.plans.selfHosted.price }}</h2>
          <p class="mt-1 text-sm text-muted-foreground">{{ copy.plans.selfHosted.subtitle }}</p>
          <ul class="mt-6 grid gap-3 text-sm text-muted-foreground">
            <li v-for="item in copy.plans.selfHosted.bullets" :key="item" class="inline-flex items-start gap-2">
              <CheckCircle2 class="mt-0.5 h-4 w-4 shrink-0 text-primary" />
              <span>{{ item }}</span>
            </li>
          </ul>
          <NuxtLink
            to="/docs/self-hosting"
            class="mt-7 inline-flex h-11 items-center justify-center rounded-xl border border-border bg-card/90 px-5 text-sm font-semibold text-foreground no-underline transition hover:border-primary/50 hover:text-primary"
          >
            {{ copy.plans.selfHosted.cta }}
          </NuxtLink>
        </article>

        <article class="glass-panel relative overflow-hidden border-primary/35 p-6 md:p-8">
          <div class="pointer-events-none absolute -right-14 -top-14 h-44 w-44 rounded-full bg-primary/18 blur-3xl" />
          <p class="relative text-xs font-semibold uppercase tracking-[0.16em] text-primary">{{ copy.plans.cloudPro.kicker }}</p>
          <h2 class="relative mt-2 text-3xl font-semibold tracking-tight">{{ copy.plans.cloudPro.price }}</h2>
          <p class="relative mt-1 text-sm text-muted-foreground">{{ copy.plans.cloudPro.subtitle }}</p>
          <ul class="relative mt-6 grid gap-3 text-sm text-muted-foreground">
            <li v-for="item in copy.plans.cloudPro.bullets" :key="item" class="inline-flex items-start gap-2">
              <CheckCircle2 class="mt-0.5 h-4 w-4 shrink-0 text-primary" />
              <span>{{ item }}</span>
            </li>
          </ul>
          <NuxtLink
            to="/billing"
            class="relative mt-7 inline-flex h-11 items-center justify-center gap-2 rounded-xl bg-primary px-5 text-sm font-semibold text-primary-foreground no-underline transition hover:opacity-90"
          >
            {{ copy.plans.cloudPro.cta }}
            <ArrowRight class="h-4 w-4" />
          </NuxtLink>
        </article>
      </div>
    </section>

    <section class="container pb-12 md:pb-16">
      <div class="glass-panel overflow-hidden">
        <div class="border-b border-border/80 px-6 py-5 md:px-8">
          <h2 class="text-2xl font-semibold tracking-tight">{{ copy.comparisonTitle }}</h2>
          <p class="mt-2 text-sm text-muted-foreground">
            {{ copy.comparisonSubtitle }}
          </p>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full min-w-[680px] border-collapse">
            <thead>
              <tr class="bg-muted/35 text-left">
                <th class="px-6 py-4 text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground md:px-8">
                  {{ copy.tableHeaders.capability }}
                </th>
                <th class="px-6 py-4 text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground md:px-8">
                  {{ copy.tableHeaders.selfHosted }}
                </th>
                <th class="px-6 py-4 text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground md:px-8">
                  {{ copy.tableHeaders.cloudPro }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in copy.rows" :key="row.capability" class="border-t border-border/70">
                <td class="px-6 py-4 text-sm font-medium text-foreground md:px-8">{{ row.capability }}</td>
                <td class="px-6 py-4 text-sm text-muted-foreground md:px-8">{{ row.selfHosted }}</td>
                <td class="px-6 py-4 text-sm text-muted-foreground md:px-8">{{ row.cloudPro }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>
  </div>
  <MarketingFooter />
</template>
