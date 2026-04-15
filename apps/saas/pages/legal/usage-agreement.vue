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
  seoTitle: "Nomade Usage Agreement (EULA)",
  seoDescription:
    "Nomade end-user usage agreement covering app access, App Store distribution terms, and permitted use.",
  title: "Usage Agreement (EULA)",
  summary: "This End User License Agreement governs the use of Nomade applications and associated hosted services.",
  lastUpdated: "April 15, 2026",
  sections: <LegalSection[]>[
    {
      title: "1. License grant",
      paragraphs: [
        "Nomade grants you a limited, non-exclusive, non-transferable, revocable license to use the application and related service interfaces in accordance with this agreement and applicable law."
      ]
    },
    {
      title: "2. Permitted use",
      bullets: [
        "Use the app for lawful account management and secure workspace access.",
        "Do not reverse engineer, exploit, or interfere with service integrity.",
        "Do not use the app to distribute malware, abuse infrastructure, or bypass authentication controls."
      ]
    },
    {
      title: "3. App Store distribution terms",
      paragraphs: [
        "For apps obtained via Apple App Store or similar marketplaces, the platform provider may impose additional terms. The platform provider is not responsible for maintenance, support, or warranty obligations unless explicitly required by law."
      ]
    },
    {
      title: "4. Data and permissions",
      paragraphs: [
        "The app may request permissions strictly required for product features, such as notifications, camera access for secure code scanning, and network access for authentication and synchronization. Data use is governed by the Privacy Policy."
      ]
    },
    {
      title: "5. Updates and availability",
      paragraphs: [
        "Nomade may release updates, patches, or feature changes to maintain security and performance. Certain features may vary by platform, account type, or jurisdiction."
      ]
    },
    {
      title: "6. Confidentiality expectations",
      paragraphs: [
        "Users must protect access credentials and avoid disclosing confidential workspace content through unauthorized channels. Additional confidentiality commitments are defined in the confidentiality terms."
      ]
    },
    {
      title: "7. Warranty disclaimer",
      paragraphs: [
        "To the extent permitted by law, the application is provided as-is and as-available, without implied warranties of merchantability, fitness for a particular purpose, or non-infringement."
      ]
    },
    {
      title: "8. Contact",
      contactLabel: "Usage agreement and app publication questions:",
      contactEmail: "legal@nomade.app"
    }
  ]
};

const frCopy = {
  seoTitle: "Accord d'utilisation Nomade (EULA)",
  seoDescription:
    "Accord d'utilisation final Nomade couvrant l'accès applicatif, les clauses App Store et les usages autorisés.",
  title: "Accord d'utilisation (EULA)",
  summary: "Ce contrat de licence utilisateur final régit l'usage des applications Nomade et des services hébergés associés.",
  lastUpdated: "15 avril 2026",
  sections: <LegalSection[]>[
    {
      title: "1. Octroi de licence",
      paragraphs: [
        "Nomade vous accorde une licence limitée, non exclusive, non transférable et révocable pour utiliser l'application et les interfaces de service associées conformément au présent accord et au droit applicable."
      ]
    },
    {
      title: "2. Usage autorisé",
      bullets: [
        "Utiliser l'application pour la gestion légitime des comptes et un accès sécurisé à l'espace de travail.",
        "Ne pas rétroconcevoir, exploiter ou perturber l'intégrité du service.",
        "Ne pas utiliser l'application pour diffuser des malwares, abuser de l'infrastructure ou contourner les contrôles d'authentification."
      ]
    },
    {
      title: "3. Clauses de distribution App Store",
      paragraphs: [
        "Pour les applications obtenues via l'Apple App Store ou des plateformes similaires, l'opérateur de la plateforme peut imposer des conditions supplémentaires. Cet opérateur n'est pas responsable de la maintenance, du support ou des garanties, sauf obligation légale expresse."
      ]
    },
    {
      title: "4. Données et permissions",
      paragraphs: [
        "L'application peut demander des permissions strictement nécessaires aux fonctionnalités, par exemple notifications, accès caméra pour le scan sécurisé de code et accès réseau pour l'authentification et la synchronisation. L'usage des données est encadré par la Politique de confidentialité."
      ]
    },
    {
      title: "5. Mises à jour et disponibilité",
      paragraphs: [
        "Nomade peut publier des mises à jour, correctifs ou évolutions pour maintenir sécurité et performance. Certaines fonctionnalités peuvent varier selon la plateforme, le type de compte ou la juridiction."
      ]
    },
    {
      title: "6. Exigences de confidentialité",
      paragraphs: [
        "Les utilisateurs doivent protéger leurs identifiants d'accès et éviter toute divulgation de contenu confidentiel via des canaux non autorisés. Les engagements complémentaires sont décrits dans les conditions de confidentialité."
      ]
    },
    {
      title: "7. Exclusion de garantie",
      paragraphs: [
        "Dans la limite permise par la loi, l'application est fournie en l'état et selon disponibilité, sans garantie implicite de qualité marchande, d'adéquation à un besoin particulier ou de non-contrefaçon."
      ]
    },
    {
      title: "8. Contact",
      contactLabel: "Questions sur l'accord d'utilisation et la publication applicative :",
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
