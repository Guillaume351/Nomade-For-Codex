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
  seoTitle: "Nomade Confidentiality and Data Handling Terms",
  seoDescription:
    "Nomade confidentiality commitments and data processing safeguards for hosted services and support operations.",
  title: "Confidentiality and Data Handling",
  summary: "These terms describe how confidential information is handled in Nomade cloud operations and support workflows.",
  lastUpdated: "April 15, 2026",
  sections: <LegalSection[]>[
    {
      title: "1. Confidential information",
      paragraphs: [
        "Confidential information includes non-public business, technical, operational, and account-related information disclosed by customers through Nomade services or support channels."
      ]
    },
    {
      title: "2. Purpose limitation",
      paragraphs: [
        "Nomade uses confidential information only to provide, secure, maintain, and support contracted services. Access is restricted to personnel and subprocessors with a legitimate operational need."
      ]
    },
    {
      title: "3. Security controls",
      bullets: [
        "Access management with role-based boundaries and authenticated workflows.",
        "Encryption in transit for service and API communication paths.",
        "Monitoring and audit trails for security and incident investigation.",
        "Controlled support access with scoped and time-bound handling procedures."
      ]
    },
    {
      title: "4. Subprocessors",
      paragraphs: [
        "Nomade may engage subprocessors for core infrastructure, billing, and support tooling. Nomade remains responsible for ensuring subprocessors are contractually bound to appropriate confidentiality and security obligations."
      ]
    },
    {
      title: "5. Incident notification",
      paragraphs: [
        "In the event of a confirmed breach affecting customer confidential data in Nomade-managed systems, Nomade will notify impacted customers without undue delay and provide relevant remediation updates."
      ]
    },
    {
      title: "6. Customer responsibilities",
      bullets: [
        "Use strong authentication hygiene and maintain access controls for your users.",
        "Do not upload data you are not authorized to process or disclose.",
        "Promptly report suspected account compromise or security anomalies."
      ]
    },
    {
      title: "7. Contact",
      contactLabel: "Security and confidentiality inquiries:",
      contactEmail: "security@nomade.app"
    }
  ]
};

const frCopy = {
  seoTitle: "Confidentialité et traitement des données Nomade",
  seoDescription:
    "Engagements de confidentialité Nomade et garanties de traitement des données pour les services hébergés et opérations de support.",
  title: "Confidentialité et traitement des données",
  summary:
    "Ces conditions décrivent la gestion des informations confidentielles dans les opérations cloud et les flux de support Nomade.",
  lastUpdated: "15 avril 2026",
  sections: <LegalSection[]>[
    {
      title: "1. Information confidentielle",
      paragraphs: [
        "L'information confidentielle inclut toute information non publique de nature métier, technique, opérationnelle ou liée aux comptes, transmise par les clients via les services ou canaux de support Nomade."
      ]
    },
    {
      title: "2. Limitation de finalité",
      paragraphs: [
        "Nomade utilise les informations confidentielles uniquement pour fournir, sécuriser, maintenir et supporter les services contractés. L'accès est limité aux personnels et sous-traitants disposant d'un besoin opérationnel légitime."
      ]
    },
    {
      title: "3. Contrôles de sécurité",
      bullets: [
        "Gestion des accès avec périmètres par rôle et workflows authentifiés.",
        "Chiffrement en transit pour les flux service et API.",
        "Supervision et pistes d'audit pour les enquêtes sécurité et incident.",
        "Accès support contrôlé avec procédures bornées et limitées dans le temps."
      ]
    },
    {
      title: "4. Sous-traitants",
      paragraphs: [
        "Nomade peut faire intervenir des sous-traitants pour l'infrastructure centrale, la facturation et les outils de support. Nomade reste responsable de s'assurer qu'ils sont contractuellement tenus à des obligations adaptées de confidentialité et de sécurité."
      ]
    },
    {
      title: "5. Notification d'incident",
      paragraphs: [
        "En cas de violation confirmée affectant des données confidentielles client dans les systèmes managés par Nomade, Nomade informera les clients concernés sans délai excessif et partagera les mises à jour de remédiation pertinentes."
      ]
    },
    {
      title: "6. Responsabilités client",
      bullets: [
        "Appliquer une hygiène d'authentification robuste et maintenir des contrôles d'accès adaptés.",
        "Ne pas importer de données dont vous n'êtes pas autorisé à traiter ou divulguer.",
        "Signaler rapidement tout soupçon de compromission de compte ou anomalie de sécurité."
      ]
    },
    {
      title: "7. Contact",
      contactLabel: "Questions sécurité et confidentialité :",
      contactEmail: "security@nomade.app"
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
