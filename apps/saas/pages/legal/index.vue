<script setup lang="ts">
import { ArrowRight, FileCheck2, ShieldCheck } from "lucide-vue-next";

definePageMeta({
  layout: "marketing"
});

const { locale } = useI18n();

const enCopy = {
  seoTitle: "Nomade Legal Center",
  seoDescription:
    "Access Nomade legal documents for privacy, terms of service, usage agreements, and confidentiality commitments.",
  badge: "Legal center",
  title: "Everything needed for legal clarity.",
  subtitle:
    "This section centralizes the policies and agreements typically required for SaaS operations and App Store publication, including confidentiality and usage terms.",
  readDocument: "Read document",
  docs: [
    {
      title: "Privacy Policy",
      summary: "How personal data is collected, used, retained, and protected.",
      href: "/legal/privacy"
    },
    {
      title: "Terms of Service",
      summary: "Core SaaS terms covering subscriptions, responsibilities, and service boundaries.",
      href: "/legal/terms"
    },
    {
      title: "Usage Agreement",
      summary: "End-user agreement for web/mobile use, including App Store publication clauses.",
      href: "/legal/usage-agreement"
    },
    {
      title: "Confidentiality Terms",
      summary: "Confidential data handling commitments and practical security safeguards.",
      href: "/legal/confidentiality"
    }
  ],
  noteKicker: "Compliance note",
  noteTitle: "App listing and legal references in one place.",
  noteBody: "Use these URLs directly for privacy and terms references in app stores and onboarding flows.",
  noteCta: "View pricing"
};

const frCopy = {
  seoTitle: "Centre légal Nomade",
  seoDescription:
    "Accédez aux documents légaux Nomade pour la confidentialité, les conditions d'utilisation, l'accord d'usage et les engagements de confidentialité.",
  badge: "Centre légal",
  title: "Tout le nécessaire pour une base légale claire.",
  subtitle:
    "Cette section centralise les politiques et accords généralement requis pour l'exploitation SaaS et la publication App Store, y compris la confidentialité et les conditions d'usage.",
  readDocument: "Lire le document",
  docs: [
    {
      title: "Politique de confidentialité",
      summary: "Comment les données personnelles sont collectées, utilisées, conservées et protégées.",
      href: "/legal/privacy"
    },
    {
      title: "Conditions d'utilisation",
      summary: "Conditions SaaS principales couvrant abonnements, responsabilités et limites du service.",
      href: "/legal/terms"
    },
    {
      title: "Accord d'utilisation",
      summary: "Accord utilisateur web/mobile incluant les clauses de publication App Store.",
      href: "/legal/usage-agreement"
    },
    {
      title: "Conditions de confidentialité",
      summary: "Engagements de traitement confidentiel et protections de sécurité applicables.",
      href: "/legal/confidentiality"
    }
  ],
  noteKicker: "Note conformité",
  noteTitle: "Références légales centralisées pour la publication applicative.",
  noteBody: "Utilisez directement ces URL pour les références de confidentialité et de conditions dans les stores et les parcours d'onboarding.",
  noteCta: "Voir les tarifs"
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
      <div class="container py-12 md:py-14">
        <span
          class="inline-flex items-center gap-2 rounded-full border border-primary/35 bg-primary/10 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-primary"
        >
          <FileCheck2 class="h-3.5 w-3.5" />
          {{ copy.badge }}
        </span>
        <h1 class="mt-5 max-w-3xl text-4xl font-semibold tracking-tight md:text-5xl">{{ copy.title }}</h1>
        <p class="mt-5 max-w-3xl text-base leading-relaxed text-muted-foreground md:text-lg">
          {{ copy.subtitle }}
        </p>
      </div>
    </section>

    <section class="container py-10 md:py-14">
      <div class="grid gap-4 md:grid-cols-2">
        <NuxtLink
          v-for="doc in copy.docs"
          :key="doc.href"
          :to="doc.href"
          class="feature-card no-underline"
        >
          <h2 class="text-xl font-semibold tracking-tight text-foreground">{{ doc.title }}</h2>
          <p class="mt-2 text-sm leading-relaxed text-muted-foreground">{{ doc.summary }}</p>
          <span class="mt-5 inline-flex items-center gap-2 text-sm font-semibold text-primary">
            {{ copy.readDocument }}
            <ArrowRight class="h-4 w-4" />
          </span>
        </NuxtLink>
      </div>
    </section>

    <section class="container pb-2">
      <div class="glass-panel p-6 md:p-8">
        <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.16em] text-primary">{{ copy.noteKicker }}</p>
            <h2 class="mt-2 text-2xl font-semibold tracking-tight">{{ copy.noteTitle }}</h2>
            <p class="mt-2 text-sm text-muted-foreground">
              {{ copy.noteBody }}
            </p>
          </div>
          <NuxtLink
            to="/pricing"
            class="inline-flex h-11 items-center justify-center gap-2 rounded-xl border border-border bg-card/80 px-5 text-sm font-semibold text-foreground no-underline transition hover:border-primary/50 hover:text-primary"
          >
            <ShieldCheck class="h-4 w-4" />
            {{ copy.noteCta }}
          </NuxtLink>
        </div>
      </div>
    </section>
  </div>
  <MarketingFooter />
</template>
