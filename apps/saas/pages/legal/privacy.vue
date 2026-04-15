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
  seoTitle: "Nomade Privacy Policy",
  seoDescription:
    "Nomade privacy policy describing data collection, usage, retention, and user rights across self-hosted and cloud modes.",
  title: "Privacy Policy",
  summary: "This policy explains how Nomade handles personal data for the SaaS service, website, and companion apps.",
  lastUpdated: "April 15, 2026",
  sections: <LegalSection[]>[
    {
      title: "1. Scope",
      paragraphs: [
        "This policy applies to Nomade cloud services, website flows, and mobile/web application accounts. For self-hosted deployments, operators control infrastructure and are responsible for their own data governance."
      ]
    },
    {
      title: "2. Data we process",
      bullets: [
        "Account identity data, such as email address and profile metadata.",
        "Authentication and security events, including session and device approval logs.",
        "Billing metadata needed to manage subscriptions and payments.",
        "Operational diagnostics and support communications provided by users."
      ]
    },
    {
      title: "3. Why we process data",
      bullets: [
        "Provide and secure account access across supported Nomade clients.",
        "Process subscriptions, invoicing, and customer support operations.",
        "Detect abuse, prevent unauthorized access, and maintain platform reliability.",
        "Comply with legal obligations and enforce contractual commitments."
      ]
    },
    {
      title: "4. Retention and deletion",
      paragraphs: [
        "Personal data is retained only for as long as needed to provide services, satisfy legal obligations, and resolve disputes. Users may request deletion of their cloud account data, subject to compliance and accounting requirements."
      ]
    },
    {
      title: "5. Security and confidentiality",
      paragraphs: [
        "Nomade applies technical and organizational controls designed to protect confidentiality, integrity, and availability of cloud-hosted personal data. These controls include authenticated access boundaries, encrypted transport, and limited internal access on a need-to-know basis."
      ]
    },
    {
      title: "6. International transfers",
      paragraphs: [
        "Where cross-border processing occurs, Nomade applies commercially reasonable safeguards to protect personal data and align with applicable privacy requirements in supported jurisdictions."
      ]
    },
    {
      title: "7. User rights",
      paragraphs: [
        "Subject to local law, users may request access, correction, portability, restriction, or deletion of personal data. Requests may be submitted through account support channels listed below."
      ]
    },
    {
      title: "8. Contact",
      contactLabel: "Privacy and data requests:",
      contactEmail: "privacy@nomade.app"
    }
  ]
};

const frCopy = {
  seoTitle: "Politique de confidentialité Nomade",
  seoDescription:
    "Politique de confidentialité Nomade : collecte, usage, rétention des données et droits utilisateurs en mode auto-hébergé ou cloud.",
  title: "Politique de confidentialité",
  summary:
    "Cette politique décrit la manière dont Nomade traite les données personnelles pour le service SaaS, le site web et les applications associées.",
  lastUpdated: "15 avril 2026",
  sections: <LegalSection[]>[
    {
      title: "1. Périmètre",
      paragraphs: [
        "Cette politique s'applique aux services cloud Nomade, aux parcours web et aux comptes applicatifs mobile/web. Pour les déploiements auto-hébergés, les opérateurs contrôlent l'infrastructure et assument leur propre gouvernance des données."
      ]
    },
    {
      title: "2. Données traitées",
      bullets: [
        "Données d'identité de compte, comme l'adresse e-mail et les métadonnées de profil.",
        "Événements d'authentification et de sécurité, y compris les journaux de session et d'approbation d'appareil.",
        "Métadonnées de facturation nécessaires à la gestion des abonnements et paiements.",
        "Diagnostics opérationnels et échanges de support fournis par les utilisateurs."
      ]
    },
    {
      title: "3. Finalités du traitement",
      bullets: [
        "Fournir et sécuriser l'accès aux comptes sur les clients Nomade supportés.",
        "Traiter les abonnements, la facturation et les opérations de support client.",
        "Détecter les abus, prévenir les accès non autorisés et maintenir la fiabilité de la plateforme.",
        "Respecter les obligations légales et faire appliquer les engagements contractuels."
      ]
    },
    {
      title: "4. Conservation et suppression",
      paragraphs: [
        "Les données personnelles sont conservées uniquement pendant la durée nécessaire pour fournir le service, satisfaire les obligations légales et résoudre les litiges. Les utilisateurs peuvent demander la suppression des données de leur compte cloud, sous réserve des obligations de conformité et comptables."
      ]
    },
    {
      title: "5. Sécurité et confidentialité",
      paragraphs: [
        "Nomade applique des mesures techniques et organisationnelles destinées à protéger la confidentialité, l'intégrité et la disponibilité des données personnelles hébergées en cloud. Ces mesures incluent des contrôles d'accès authentifiés, le chiffrement des flux et un accès interne limité au besoin d'en connaître."
      ]
    },
    {
      title: "6. Transferts internationaux",
      paragraphs: [
        "En cas de traitement transfrontalier, Nomade applique des garanties commercialement raisonnables afin de protéger les données personnelles et d'aligner le traitement avec les exigences de confidentialité applicables."
      ]
    },
    {
      title: "7. Droits des utilisateurs",
      paragraphs: [
        "Sous réserve du droit local, les utilisateurs peuvent demander l'accès, la rectification, la portabilité, la limitation ou la suppression de leurs données personnelles. Les demandes peuvent être transmises via les canaux de support indiqués ci-dessous."
      ]
    },
    {
      title: "8. Contact",
      contactLabel: "Demandes confidentialité et données :",
      contactEmail: "privacy@nomade.app"
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
