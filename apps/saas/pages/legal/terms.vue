<script setup lang="ts">
definePageMeta({
  layout: "marketing"
});

const { locale } = useI18n();

interface LegalSection {
  title: string;
  paragraphs?: string[];
  bullets?: string[];
  contactLabel?: string;
  contactEmail?: string;
}

const enCopy = {
  seoTitle: "Nomade Terms of Service",
  seoDescription: "Nomade terms of service covering account usage, subscriptions, service limits, and legal obligations.",
  title: "Terms of Service",
  summary: "These terms govern the use of Nomade cloud services, website, and related product components.",
  lastUpdated: "April 15, 2026",
  sections: <LegalSection[]>[
    {
      title: "1. Acceptance",
      paragraphs: [
        "By creating an account or using Nomade services, you agree to these Terms of Service. If you use Nomade on behalf of an organization, you represent that you have authority to bind that organization."
      ]
    },
    {
      title: "2. Service modes",
      bullets: [
        "Self-hosted mode is provided as open-source software and is free to run on your own infrastructure.",
        "Cloud Pro is a paid managed offering that includes hosting, billing, and support services."
      ]
    },
    {
      title: "3. Accounts and security",
      paragraphs: [
        "You are responsible for account credentials and all activity under your account. You must promptly notify Nomade of suspected unauthorized use or security incidents tied to your account."
      ]
    },
    {
      title: "4. Billing and subscription",
      paragraphs: [
        "Paid plans are billed according to the pricing and billing terms shown at checkout. Subscription fees are non-refundable except where required by law. Plan changes may alter features, limits, or support scope."
      ]
    },
    {
      title: "5. Acceptable use",
      bullets: [
        "Do not misuse services, attempt unauthorized access, or disrupt availability.",
        "Do not use Nomade in violation of applicable law, sanctions, or export controls.",
        "Do not submit unlawful, infringing, or malicious content through service interfaces."
      ]
    },
    {
      title: "6. Intellectual property",
      paragraphs: [
        "Nomade retains rights in hosted services, trademarks, and proprietary materials. Open-source components are governed by their respective license terms."
      ]
    },
    {
      title: "7. Disclaimer and limitation of liability",
      paragraphs: [
        "To the maximum extent permitted by law, services are provided on an as-available basis without guarantees of uninterrupted operation. Nomade is not liable for indirect, incidental, special, consequential, or punitive damages arising from service use."
      ]
    },
    {
      title: "8. Suspension and termination",
      paragraphs: [
        "Nomade may suspend or terminate access for material breaches, security risks, or legal requirements. You may stop using services at any time and terminate your account through support channels."
      ]
    },
    {
      title: "9. Contact",
      contactLabel: "Legal inquiries:",
      contactEmail: "legal@nomade.app"
    }
  ]
};

const frCopy = {
  seoTitle: "Conditions d'utilisation Nomade",
  seoDescription:
    "Conditions d'utilisation Nomade couvrant l'usage des comptes, les abonnements, les limites de service et les obligations légales.",
  title: "Conditions d'utilisation",
  summary: "Ces conditions régissent l'usage des services cloud Nomade, du site web et des composants produits associés.",
  lastUpdated: "15 avril 2026",
  sections: <LegalSection[]>[
    {
      title: "1. Acceptation",
      paragraphs: [
        "En créant un compte ou en utilisant les services Nomade, vous acceptez les présentes Conditions d'utilisation. Si vous utilisez Nomade pour le compte d'une organisation, vous déclarez disposer du pouvoir de l'engager."
      ]
    },
    {
      title: "2. Modes de service",
      bullets: [
        "Le mode auto-hébergé est fourni en logiciel open source et peut être exécuté gratuitement sur votre infrastructure.",
        "Cloud Pro est une offre managée payante incluant hébergement, facturation et support."
      ]
    },
    {
      title: "3. Comptes et sécurité",
      paragraphs: [
        "Vous êtes responsable des identifiants de compte et de toute activité associée. Vous devez notifier rapidement Nomade en cas d'usage non autorisé suspecté ou d'incident de sécurité lié à votre compte."
      ]
    },
    {
      title: "4. Facturation et abonnement",
      paragraphs: [
        "Les offres payantes sont facturées selon les conditions affichées au moment du paiement. Les frais d'abonnement sont non remboursables sauf obligation légale contraire. Les changements d'offre peuvent modifier fonctionnalités, limites ou niveau de support."
      ]
    },
    {
      title: "5. Usage acceptable",
      bullets: [
        "Ne pas détourner les services, tenter des accès non autorisés ou perturber la disponibilité.",
        "Ne pas utiliser Nomade en violation du droit applicable, des sanctions ou des contrôles export.",
        "Ne pas transmettre de contenu illégal, contrefaisant ou malveillant via les interfaces du service."
      ]
    },
    {
      title: "6. Propriété intellectuelle",
      paragraphs: [
        "Nomade conserve les droits sur les services hébergés, marques et éléments propriétaires. Les composants open source restent régis par leurs licences respectives."
      ]
    },
    {
      title: "7. Exclusion de garantie et limitation de responsabilité",
      paragraphs: [
        "Dans la limite permise par la loi, les services sont fournis en l'état et selon disponibilité, sans garantie de continuité. Nomade n'est pas responsable des dommages indirects, accessoires, spéciaux, consécutifs ou punitifs liés à l'usage du service."
      ]
    },
    {
      title: "8. Suspension et résiliation",
      paragraphs: [
        "Nomade peut suspendre ou résilier l'accès en cas de manquement matériel, de risque de sécurité ou d'obligation légale. Vous pouvez cesser d'utiliser le service à tout moment et demander la clôture de compte via le support."
      ]
    },
    {
      title: "9. Contact",
      contactLabel: "Questions juridiques :",
      contactEmail: "legal@nomade.app"
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
  <LegalPageLayout :title="copy.title" :summary="copy.summary" :last-updated="copy.lastUpdated">
    <section v-for="section in copy.sections" :key="section.title" class="space-y-3">
      <h2 class="text-2xl font-semibold tracking-tight">{{ section.title }}</h2>
      <p v-for="paragraph in section.paragraphs ?? []" :key="paragraph" class="text-sm leading-relaxed text-muted-foreground">
        {{ paragraph }}
      </p>
      <ul v-if="section.bullets?.length" class="grid gap-2 text-sm leading-relaxed text-muted-foreground">
        <li v-for="bullet in section.bullets" :key="bullet">{{ bullet }}</li>
      </ul>
      <p v-if="section.contactLabel && section.contactEmail" class="text-sm leading-relaxed text-muted-foreground">
        {{ section.contactLabel }}
        <a :href="`mailto:${section.contactEmail}`">{{ section.contactEmail }}</a>
      </p>
    </section>
  </LegalPageLayout>
</template>
