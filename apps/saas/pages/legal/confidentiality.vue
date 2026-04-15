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
      title: "3. Encryption scope (what is encrypted)",
      bullets: [
        "Client-to-service traffic is encrypted in transit using TLS.",
        "Stored credentials and auth secrets are protected as hashes or encrypted secrets.",
        "Cloud-managed storage may be encrypted at rest through infrastructure-layer controls."
      ]
    },
    {
      title: "4. Encryption limits (what is not encrypted by default)",
      bullets: [
        "Operational metadata (timestamps, IPs, request identifiers, plan status) may remain readable in backend systems.",
        "Some logs and observability records may contain non-content metadata for diagnostics and incident response.",
        "End-to-end encryption is not guaranteed by default for all service-side processing paths.",
        "In self-hosted mode, encryption at rest depends on your own database, disk, and key-management setup."
      ]
    },
    {
      title: "5. Security controls",
      bullets: [
        "Access management with role-based boundaries and authenticated workflows.",
        "Monitoring and audit trails for security and incident investigation.",
        "Controlled support access with scoped and time-bound handling procedures."
      ]
    },
    {
      title: "6. Subprocessors",
      paragraphs: [
        "Nomade may engage subprocessors for core infrastructure, billing, and support tooling. Nomade remains responsible for ensuring subprocessors are contractually bound to appropriate confidentiality and security obligations."
      ]
    },
    {
      title: "7. Incident notification",
      paragraphs: [
        "In the event of a confirmed breach affecting customer confidential data in Nomade-managed systems, Nomade will notify impacted customers without undue delay and provide relevant remediation updates."
      ]
    },
    {
      title: "8. Customer responsibilities",
      bullets: [
        "Use strong authentication hygiene and maintain access controls for your users.",
        "Do not upload data you are not authorized to process or disclose.",
        "Promptly report suspected account compromise or security anomalies."
      ]
    },
    {
      title: "9. Contact",
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
      title: "3. Périmètre de chiffrement (ce qui est chiffré)",
      bullets: [
        "Le trafic client-vers-service est chiffré en transit via TLS.",
        "Les identifiants stockés et secrets d'authentification sont protégés sous forme de hash ou secrets chiffrés.",
        "Le stockage cloud managé peut être chiffré au repos via des contrôles d'infrastructure."
      ]
    },
    {
      title: "4. Limites du chiffrement (ce qui n'est pas chiffré par défaut)",
      bullets: [
        "Les métadonnées opérationnelles (horodatage, IP, identifiants de requête, statut d'offre) peuvent rester lisibles dans les systèmes backend.",
        "Certains logs et données d'observabilité peuvent contenir des métadonnées non contenu pour diagnostic et réponse à incident.",
        "Le chiffrement de bout en bout n'est pas garanti par défaut sur tous les traitements côté service.",
        "En mode auto-hébergé, le chiffrement au repos dépend de votre configuration base de données, disque et gestion des clés."
      ]
    },
    {
      title: "5. Contrôles de sécurité",
      bullets: [
        "Gestion des accès avec périmètres par rôle et workflows authentifiés.",
        "Supervision et pistes d'audit pour les enquêtes sécurité et incident.",
        "Accès support contrôlé avec procédures bornées et limitées dans le temps."
      ]
    },
    {
      title: "6. Sous-traitants",
      paragraphs: [
        "Nomade peut faire intervenir des sous-traitants pour l'infrastructure centrale, la facturation et les outils de support. Nomade reste responsable de s'assurer qu'ils sont contractuellement tenus à des obligations adaptées de confidentialité et de sécurité."
      ]
    },
    {
      title: "7. Notification d'incident",
      paragraphs: [
        "En cas de violation confirmée affectant des données confidentielles client dans les systèmes managés par Nomade, Nomade informera les clients concernés sans délai excessif et partagera les mises à jour de remédiation pertinentes."
      ]
    },
    {
      title: "8. Responsabilités client",
      bullets: [
        "Appliquer une hygiène d'authentification robuste et maintenir des contrôles d'accès adaptés.",
        "Ne pas importer de données dont vous n'êtes pas autorisé à traiter ou divulguer.",
        "Signaler rapidement tout soupçon de compromission de compte ou anomalie de sécurité."
      ]
    },
    {
      title: "9. Contact",
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
