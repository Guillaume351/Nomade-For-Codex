<script setup lang="ts">
import {
  AppWindow,
  ArrowRight,
  CheckCircle2,
  GitBranch,
  LockKeyhole,
  ServerCog,
  ShieldCheck,
  Sparkles
} from "lucide-vue-next";

definePageMeta({
  layout: "marketing"
});

const { locale } = useI18n();
const { fetchSession, isAuthenticated } = useAuthSession();
await fetchSession();
if (isAuthenticated.value) {
  await navigateTo("/account");
}

const enCopy = {
  seoTitle: "Nomade | High-End AI Access Control for Teams",
  seoDescription:
    "Nomade gives your team secure AI workspace access with open-source self-hosting and managed SaaS billing.",
  ogTitle: "Nomade",
  ogDescription:
    "Secure AI workspace access with free self-hosting, premium managed cloud, and compliance-ready legal docs.",
  hero: {
    badge: "Open Source + SaaS",
    title: "A clean, premium control plane for AI access.",
    subtitle:
      "Nomade is fully free when self-hosted and open source by design. Use cloud only when you want managed billing, support, and operations.",
    ctaPrimary: "Start now",
    ctaSecondary: "See pricing",
    footnote: "Free forever if self-hosted. No feature lock on the open-source core."
  },
  why: {
    title: "Why teams pick Nomade",
    deploymentLabel: "Deployment model",
    deploymentValue: "Self-hosted or managed cloud",
    complianceLabel: "Compliance readiness",
    complianceValue: "Privacy + usage agreements included",
    accessLabel: "Access assurance",
    accessValue: "Device-based activation flows"
  },
  sections: {
    featuresKicker: "Core features",
    featuresTitle: "Simple surface, serious control underneath.",
    openSourceKicker: "Open source mode",
    openSourceTitle: "Fully free when self-hosted.",
    managedKicker: "Managed cloud mode",
    managedTitle: "Pay only for convenience and operations.",
    legalKicker: "Legal and App Store readiness",
    legalTitle: "Publish-ready legal pages, from privacy to usage agreements.",
    legalBody:
      "Nomade includes a complete legal surface for SaaS operations and app distribution, including confidentiality commitments and end-user usage terms.",
    ctaKicker: "Get started",
    ctaTitle: "Launch free on your infrastructure, upgrade only when it makes sense.",
    ctaPrimary: "Create account",
    ctaSecondary: "Compare plans"
  },
  featureItems: [
    {
      title: "Secure Session Continuity",
      description: "Keep mobile, terminal, and browser sessions in sync with controlled identity context."
    },
    {
      title: "Device Activation Flow",
      description: "Approve sign-ins with explicit user-code validation for high-trust workspace entry."
    },
    {
      title: "Self-Hosted by Default",
      description: "Run Nomade on your infrastructure at zero license cost with full source visibility."
    },
    {
      title: "Cloud Billing When Needed",
      description: "Move to managed cloud for convenience, usage controls, and vendor-backed operations."
    },
    {
      title: "Granular Access Governance",
      description: "Map users, plans, and device entitlements without exposing internal infrastructure details."
    },
    {
      title: "Open Source Core",
      description: "Audit the codebase, propose improvements, and ship your own extensions confidently."
    }
  ],
  openSourceBullets: [
    "No platform fee for self-hosted deployments.",
    "Source access for internal review, customization, and contribution.",
    "Deploy on your own cloud, on-prem, or private network edge."
  ],
  managedBullets: [
    "Hosted control plane, billing automation, and support workflows.",
    "Reduced operational burden for teams that prefer managed infrastructure.",
    "Same product DNA, with premium support and managed reliability."
  ],
  legalDocs: [
    {
      title: "Privacy policy",
      description: "Covers personal data handling, retention, and user rights.",
      href: "/legal/privacy"
    },
    {
      title: "Terms of service",
      description: "Defines service scope, subscriptions, and legal responsibilities.",
      href: "/legal/terms"
    },
    {
      title: "Usage agreement",
      description: "App Store and end-user license terms for product usage.",
      href: "/legal/usage-agreement"
    },
    {
      title: "Confidentiality terms",
      description: "Defines confidential data handling and security obligations.",
      href: "/legal/confidentiality"
    }
  ]
};

const frCopy = {
  seoTitle: "Nomade | Contrôle d'accès IA haut de gamme pour équipes",
  seoDescription:
    "Nomade offre un accès sécurisé à vos espaces IA avec auto-hébergement open source et facturation SaaS managée.",
  ogTitle: "Nomade",
  ogDescription:
    "Accès IA sécurisé avec auto-hébergement gratuit, cloud premium managé et pages légales prêtes pour la conformité.",
  hero: {
    badge: "Open source + SaaS",
    title: "Une surface premium et épurée pour contrôler l'accès IA.",
    subtitle:
      "Nomade est entièrement gratuit en auto-hébergement et pensé open source. Le cloud payant n'est utile que si vous voulez l'exploitation managée, la facturation et le support.",
    ctaPrimary: "Commencer",
    ctaSecondary: "Voir les tarifs",
    footnote: "Gratuit à vie en auto-hébergement. Aucun verrouillage de fonctionnalités sur le noyau open source."
  },
  why: {
    title: "Pourquoi les équipes choisissent Nomade",
    deploymentLabel: "Modèle de déploiement",
    deploymentValue: "Auto-hébergé ou cloud managé",
    complianceLabel: "Niveau de conformité",
    complianceValue: "Confidentialité + accords d'utilisation inclus",
    accessLabel: "Assurance d'accès",
    accessValue: "Flux d'activation par appareil"
  },
  sections: {
    featuresKicker: "Fonctionnalités clés",
    featuresTitle: "Une interface simple, un contrôle solide en profondeur.",
    openSourceKicker: "Mode open source",
    openSourceTitle: "Entièrement gratuit en auto-hébergement.",
    managedKicker: "Mode cloud managé",
    managedTitle: "Payez seulement pour la simplicité opérationnelle.",
    legalKicker: "Préparation légale et App Store",
    legalTitle: "Pages légales prêtes à publier, de la confidentialité à l'accord d'utilisation.",
    legalBody:
      "Nomade inclut une surface légale complète pour les opérations SaaS et la distribution applicative, y compris les engagements de confidentialité et les conditions d'usage utilisateur.",
    ctaKicker: "Démarrer",
    ctaTitle: "Lancez gratuitement sur votre infrastructure, puis passez au cloud seulement si nécessaire.",
    ctaPrimary: "Créer un compte",
    ctaSecondary: "Comparer les offres"
  },
  featureItems: [
    {
      title: "Continuité sécurisée des sessions",
      description: "Synchronisez mobile, terminal et navigateur avec un contexte d'identité maîtrisé."
    },
    {
      title: "Flux d'activation appareil",
      description: "Validez les connexions via un code utilisateur explicite pour une entrée à haute confiance."
    },
    {
      title: "Auto-hébergé par défaut",
      description: "Exécutez Nomade sur votre infrastructure sans coût de licence, avec visibilité complète du code."
    },
    {
      title: "Facturation cloud à la demande",
      description: "Passez au cloud managé pour la simplicité, le pilotage d'usage et l'exploitation opérationnelle."
    },
    {
      title: "Gouvernance d'accès granulaire",
      description: "Pilotez utilisateurs, offres et quotas d'appareils sans exposer vos détails d'infrastructure."
    },
    {
      title: "Noyau open source",
      description: "Auditez le code, proposez des améliorations et livrez vos extensions avec confiance."
    }
  ],
  openSourceBullets: [
    "Aucun frais de plateforme pour les déploiements auto-hébergés.",
    "Accès au code source pour audit interne, personnalisation et contribution.",
    "Déployez sur votre cloud, on-premise ou réseau privé edge."
  ],
  managedBullets: [
    "Plan de contrôle hébergé, automatisation de la facturation et flux de support.",
    "Moins de charge opérationnelle pour les équipes qui veulent du managé.",
    "Même ADN produit, avec support premium et fiabilité opérée."
  ],
  legalDocs: [
    {
      title: "Politique de confidentialité",
      description: "Décrit la gestion des données personnelles, la rétention et les droits utilisateurs.",
      href: "/legal/privacy"
    },
    {
      title: "Conditions d'utilisation",
      description: "Définit le périmètre du service, les abonnements et les responsabilités légales.",
      href: "/legal/terms"
    },
    {
      title: "Accord d'utilisation",
      description: "Conditions d'usage final et clauses de publication App Store.",
      href: "/legal/usage-agreement"
    },
    {
      title: "Conditions de confidentialité",
      description: "Précise le traitement des informations confidentielles et les obligations de sécurité.",
      href: "/legal/confidentiality"
    }
  ]
};

const copy = computed(() => (locale.value === "fr" ? frCopy : enCopy));

const featureIcons = [ShieldCheck, AppWindow, ServerCog, Sparkles, LockKeyhole, GitBranch];

const features = computed(() =>
  copy.value.featureItems.map((item, index) => ({
    title: item.title,
    description: item.description,
    icon: featureIcons[index]
  }))
);

useSeoMeta({
  title: () => copy.value.seoTitle,
  description: () => copy.value.seoDescription,
  ogTitle: () => copy.value.ogTitle,
  ogDescription: () => copy.value.ogDescription
});
</script>

<template>
  <div class="pb-16 md:pb-20">
    <section class="relative overflow-hidden border-b border-border/80">
      <div class="pointer-events-none absolute inset-0">
        <div class="marketing-orb marketing-orb-one" />
        <div class="marketing-orb marketing-orb-two" />
      </div>
      <div class="container relative grid gap-10 py-14 md:grid-cols-[1.08fr_0.92fr] md:py-20">
        <div class="animate-in fade-in slide-in-from-bottom-3 duration-700">
          <span
            class="inline-flex items-center gap-2 rounded-full border border-primary/35 bg-primary/10 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-primary"
          >
            <CheckCircle2 class="h-3.5 w-3.5" />
            {{ copy.hero.badge }}
          </span>
          <h1 class="mt-5 max-w-2xl text-4xl font-semibold tracking-tight text-foreground md:text-6xl">
            {{ copy.hero.title }}
          </h1>
          <p class="mt-5 max-w-2xl text-base leading-relaxed text-muted-foreground md:text-lg">
            {{ copy.hero.subtitle }}
          </p>
          <div class="mt-8 flex flex-wrap items-center gap-3">
            <NuxtLink
              to="/signup"
              class="inline-flex h-11 items-center justify-center gap-2 rounded-xl bg-primary px-5 text-sm font-semibold text-primary-foreground no-underline transition hover:opacity-90"
            >
              {{ copy.hero.ctaPrimary }}
              <ArrowRight class="h-4 w-4" />
            </NuxtLink>
            <NuxtLink
              to="/pricing"
              class="inline-flex h-11 items-center justify-center rounded-xl border border-border bg-card/80 px-5 text-sm font-semibold text-foreground no-underline transition hover:border-primary/50 hover:text-primary"
            >
              {{ copy.hero.ctaSecondary }}
            </NuxtLink>
          </div>
          <p class="mt-4 text-sm text-muted-foreground">
            {{ copy.hero.footnote }}
          </p>
        </div>

        <div class="animate-in fade-in slide-in-from-bottom-3 duration-700 md:delay-150">
          <div class="glass-panel h-full p-6 md:p-7">
            <p class="text-xs font-semibold uppercase tracking-[0.16em] text-muted-foreground">{{ copy.why.title }}</p>
            <div class="mt-5 grid gap-4">
              <div class="marketing-metric">
                <p class="text-xs uppercase tracking-[0.14em] text-muted-foreground">{{ copy.why.deploymentLabel }}</p>
                <p class="mt-1 text-2xl font-semibold tracking-tight text-foreground">{{ copy.why.deploymentValue }}</p>
              </div>
              <div class="marketing-metric">
                <p class="text-xs uppercase tracking-[0.14em] text-muted-foreground">{{ copy.why.complianceLabel }}</p>
                <p class="mt-1 text-2xl font-semibold tracking-tight text-foreground">{{ copy.why.complianceValue }}</p>
              </div>
              <div class="marketing-metric">
                <p class="text-xs uppercase tracking-[0.14em] text-muted-foreground">{{ copy.why.accessLabel }}</p>
                <p class="mt-1 text-2xl font-semibold tracking-tight text-foreground">{{ copy.why.accessValue }}</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <section id="features" class="container py-14 md:py-16">
      <div class="max-w-3xl animate-in fade-in slide-in-from-bottom-2 duration-700">
        <p class="text-xs font-semibold uppercase tracking-[0.16em] text-primary">{{ copy.sections.featuresKicker }}</p>
        <h2 class="mt-3 text-3xl font-semibold tracking-tight md:text-4xl">{{ copy.sections.featuresTitle }}</h2>
      </div>
      <div class="mt-8 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        <article
          v-for="(feature, index) in features"
          :key="feature.title"
          class="feature-card animate-in fade-in slide-in-from-bottom-2 duration-700"
          :style="{ animationDelay: `${index * 70}ms` }"
        >
          <span class="inline-flex h-10 w-10 items-center justify-center rounded-xl bg-primary/12 text-primary">
            <component :is="feature.icon" class="h-5 w-5" />
          </span>
          <h3 class="mt-4 text-lg font-semibold tracking-tight">{{ feature.title }}</h3>
          <p class="mt-2 text-sm leading-relaxed text-muted-foreground">{{ feature.description }}</p>
        </article>
      </div>
    </section>

    <section id="open-source" class="border-y border-border/80 bg-card/45 py-14 md:py-16">
      <div class="container grid gap-6 lg:grid-cols-2">
        <article class="glass-panel p-6 md:p-8">
          <p class="text-xs font-semibold uppercase tracking-[0.16em] text-primary">{{ copy.sections.openSourceKicker }}</p>
          <h3 class="mt-3 text-2xl font-semibold tracking-tight">{{ copy.sections.openSourceTitle }}</h3>
          <ul class="mt-5 grid gap-3 text-sm text-muted-foreground">
            <li v-for="item in copy.openSourceBullets" :key="item" class="inline-flex items-start gap-2">
              <CheckCircle2 class="mt-0.5 h-4 w-4 shrink-0 text-primary" />
              <span>{{ item }}</span>
            </li>
          </ul>
        </article>

        <article class="glass-panel p-6 md:p-8">
          <p class="text-xs font-semibold uppercase tracking-[0.16em] text-primary">{{ copy.sections.managedKicker }}</p>
          <h3 class="mt-3 text-2xl font-semibold tracking-tight">{{ copy.sections.managedTitle }}</h3>
          <ul class="mt-5 grid gap-3 text-sm text-muted-foreground">
            <li v-for="item in copy.managedBullets" :key="item" class="inline-flex items-start gap-2">
              <CheckCircle2 class="mt-0.5 h-4 w-4 shrink-0 text-primary" />
              <span>{{ item }}</span>
            </li>
          </ul>
        </article>
      </div>
    </section>

    <section class="container py-14 md:py-16">
      <div class="max-w-3xl">
        <p class="text-xs font-semibold uppercase tracking-[0.16em] text-primary">{{ copy.sections.legalKicker }}</p>
        <h2 class="mt-3 text-3xl font-semibold tracking-tight md:text-4xl">
          {{ copy.sections.legalTitle }}
        </h2>
        <p class="mt-4 text-sm leading-relaxed text-muted-foreground md:text-base">
          {{ copy.sections.legalBody }}
        </p>
      </div>
      <div class="mt-8 grid gap-4 md:grid-cols-2">
        <NuxtLink
          v-for="doc in copy.legalDocs"
          :key="doc.href"
          :to="doc.href"
          class="feature-card no-underline"
        >
          <h3 class="text-lg font-semibold tracking-tight text-foreground">{{ doc.title }}</h3>
          <p class="mt-2 text-sm leading-relaxed text-muted-foreground">{{ doc.description }}</p>
        </NuxtLink>
      </div>
    </section>

    <section class="container pb-2">
      <div class="glass-panel p-6 md:p-8">
        <div class="flex flex-col gap-5 md:flex-row md:items-center md:justify-between">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.16em] text-primary">{{ copy.sections.ctaKicker }}</p>
            <h2 class="mt-2 text-2xl font-semibold tracking-tight md:text-3xl">
              {{ copy.sections.ctaTitle }}
            </h2>
          </div>
          <div class="flex flex-wrap gap-3">
            <NuxtLink
              to="/signup"
              class="inline-flex h-11 items-center justify-center rounded-xl bg-primary px-5 text-sm font-semibold text-primary-foreground no-underline transition hover:opacity-90"
            >
              {{ copy.sections.ctaPrimary }}
            </NuxtLink>
            <NuxtLink
              to="/pricing"
              class="inline-flex h-11 items-center justify-center rounded-xl border border-border bg-card/80 px-5 text-sm font-semibold text-foreground no-underline transition hover:border-primary/50 hover:text-primary"
            >
              {{ copy.sections.ctaSecondary }}
            </NuxtLink>
          </div>
        </div>
      </div>
    </section>
  </div>
  <MarketingFooter />
</template>
