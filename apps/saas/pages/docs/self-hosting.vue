<script setup lang="ts">
import { CheckCircle2, Copy, ShieldCheck } from "lucide-vue-next";

definePageMeta({
  layout: "marketing"
});

const { locale } = useI18n();

const enCopy = {
  seoTitle: "Nomade Self-Hosting Documentation",
  seoDescription:
    "Deploy Nomade in self-hosted mode with infrastructure requirements, TLS guidance, environment setup, and operational checks.",
  badge: "Self-hosting documentation",
  title: "Run Nomade on your own infrastructure.",
  subtitle:
    "This guide covers a practical baseline for deploying Nomade in self-hosted mode with explicit security and encryption notes.",
  sections: {
    prerequisites: "1. Prerequisites",
    install: "2. Installation and startup",
    tls: "3. TLS and encryption requirements",
    env: "4. Minimal environment checklist",
    operations: "5. Operations and maintenance"
  },
  prerequisites: [
    "A Linux host or container platform with Docker/Compose or equivalent orchestration.",
    "A public domain name pointing to your reverse proxy or ingress endpoint.",
    "A managed database instance or reliable persistent storage layer.",
    "A secret-management method for auth keys, payment credentials, and API tokens."
  ],
  installSteps: [
    "Clone the Nomade repository and configure your deployment environment.",
    "Set production environment variables in your secret store or deployment manifest.",
    "Start services and verify health endpoints before exposing external traffic.",
    "Create an initial admin/operator account and test account sign-in and activation flow."
  ],
  tlsBullets: [
    "Always terminate HTTPS with TLS 1.2+ at your edge proxy or load balancer.",
    "Force HTTP-to-HTTPS redirects and enable HSTS where applicable.",
    "Encrypt database and volume storage at rest using cloud/provider-native controls or disk encryption.",
    "Rotate certificates and secrets regularly, and revoke immediately after suspected compromise."
  ],
  envBullets: [
    "Set application base URL and backend API URL to your production domains.",
    "Configure auth provider secrets and email delivery credentials.",
    "Set billing provider keys only if you enable managed billing workflows.",
    "Enable structured logs and audit retention according to your compliance requirements."
  ],
  operationsBullets: [
    "Monitor auth errors, login approval failures, and abnormal request patterns.",
    "Back up databases and critical configuration on a scheduled cadence.",
    "Test restore procedures and disaster recovery before production incidents.",
    "Keep runtime dependencies patched and track security advisories."
  ],
  cta: "See legal and privacy pages"
};

const frCopy = {
  seoTitle: "Documentation self-hosting Nomade",
  seoDescription:
    "Déployez Nomade en auto-hébergement avec prérequis infrastructure, guide TLS, configuration d'environnement et contrôles opérationnels.",
  badge: "Documentation self-hosting",
  title: "Exécutez Nomade sur votre propre infrastructure.",
  subtitle:
    "Ce guide couvre une base pratique pour déployer Nomade en mode auto-hébergé, avec des notes explicites sur sécurité et chiffrement.",
  sections: {
    prerequisites: "1. Prérequis",
    install: "2. Installation et démarrage",
    tls: "3. Exigences TLS et chiffrement",
    env: "4. Checklist minimale d'environnement",
    operations: "5. Exploitation et maintenance"
  },
  prerequisites: [
    "Un hôte Linux ou une plateforme conteneurisée avec Docker/Compose ou orchestration équivalente.",
    "Un nom de domaine public pointant vers votre reverse-proxy ou endpoint d'ingress.",
    "Une base de données managée ou une couche de stockage persistant fiable.",
    "Une méthode de gestion des secrets pour clés d'authentification, credentials de paiement et tokens API."
  ],
  installSteps: [
    "Clonez le dépôt Nomade et préparez votre environnement de déploiement.",
    "Définissez les variables d'environnement de production dans votre coffre de secrets ou manifeste.",
    "Démarrez les services puis validez les endpoints de santé avant d'ouvrir le trafic externe.",
    "Créez un premier compte opérateur/admin et testez la connexion ainsi que le flux d'activation."
  ],
  tlsBullets: [
    "Terminez systématiquement HTTPS avec TLS 1.2+ au niveau proxy edge ou load balancer.",
    "Forcez les redirections HTTP vers HTTPS et activez HSTS lorsque pertinent.",
    "Chiffrez la base de données et les volumes au repos via les contrôles cloud/fournisseur ou chiffrement disque.",
    "Faites tourner certificats et secrets régulièrement, et révoquez immédiatement en cas de compromission suspectée."
  ],
  envBullets: [
    "Définissez l'URL applicative et l'URL API backend vers vos domaines de production.",
    "Configurez les secrets de fournisseurs d'authentification et les credentials d'envoi email.",
    "Définissez les clés de paiement uniquement si vous activez les workflows de billing managé.",
    "Activez les logs structurés et la rétention d'audit selon vos obligations de conformité."
  ],
  operationsBullets: [
    "Surveillez les erreurs d'auth, échecs d'approbation de connexion et schémas de requêtes anormaux.",
    "Sauvegardez bases de données et configuration critique à fréquence planifiée.",
    "Testez les procédures de restauration et reprise après sinistre avant incident de production.",
    "Maintenez les dépendances runtime à jour et suivez les avis de sécurité."
  ],
  cta: "Voir les pages légales et confidentialité"
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
          <Copy class="h-3.5 w-3.5" />
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
        <article class="feature-card">
          <h2 class="text-xl font-semibold tracking-tight">{{ copy.sections.prerequisites }}</h2>
          <ul class="mt-4 grid gap-2 text-sm leading-relaxed text-muted-foreground">
            <li v-for="item in copy.prerequisites" :key="item">{{ item }}</li>
          </ul>
        </article>
        <article class="feature-card">
          <h2 class="text-xl font-semibold tracking-tight">{{ copy.sections.install }}</h2>
          <ul class="mt-4 grid gap-2 text-sm leading-relaxed text-muted-foreground">
            <li v-for="item in copy.installSteps" :key="item">{{ item }}</li>
          </ul>
        </article>
        <article class="feature-card">
          <h2 class="text-xl font-semibold tracking-tight">{{ copy.sections.tls }}</h2>
          <ul class="mt-4 grid gap-2 text-sm leading-relaxed text-muted-foreground">
            <li v-for="item in copy.tlsBullets" :key="item">{{ item }}</li>
          </ul>
        </article>
        <article class="feature-card">
          <h2 class="text-xl font-semibold tracking-tight">{{ copy.sections.env }}</h2>
          <ul class="mt-4 grid gap-2 text-sm leading-relaxed text-muted-foreground">
            <li v-for="item in copy.envBullets" :key="item">{{ item }}</li>
          </ul>
        </article>
      </div>
      <article class="feature-card mt-4">
        <h2 class="text-xl font-semibold tracking-tight">{{ copy.sections.operations }}</h2>
        <ul class="mt-4 grid gap-2 text-sm leading-relaxed text-muted-foreground">
          <li v-for="item in copy.operationsBullets" :key="item">{{ item }}</li>
        </ul>
      </article>
    </section>

    <section class="container pb-2">
      <div class="glass-panel p-6 md:p-8">
        <NuxtLink
          to="/legal"
          class="inline-flex h-11 items-center justify-center gap-2 rounded-xl bg-primary px-5 text-sm font-semibold text-primary-foreground no-underline transition hover:opacity-90"
        >
          <ShieldCheck class="h-4 w-4" />
          {{ copy.cta }}
        </NuxtLink>
      </div>
    </section>
  </div>
  <MarketingFooter />
</template>
