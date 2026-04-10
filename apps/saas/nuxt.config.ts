const googleSocialEnabled = Boolean(process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET);
const appleSocialEnabled = Boolean(process.env.APPLE_CLIENT_ID && process.env.APPLE_CLIENT_SECRET);

export default defineNuxtConfig({
  compatibilityDate: "2026-04-04",
  devtools: { enabled: false },
  modules: ["@nuxtjs/tailwindcss", "@nuxtjs/color-mode", "@nuxtjs/i18n"],
  css: ["~/assets/css/main.css"],
  colorMode: {
    preference: "system",
    fallback: "light",
    classSuffix: "",
    storageKey: "nomade-color-mode"
  },
  i18n: {
    strategy: "no_prefix",
    defaultLocale: "en",
    lazy: true,
    langDir: "locales",
    locales: [
      { code: "en", language: "en-US", file: "en.json", name: "English" },
      { code: "fr", language: "fr-FR", file: "fr.json", name: "Français" }
    ],
    detectBrowserLanguage: {
      useCookie: true,
      cookieKey: "nomade-locale",
      alwaysRedirect: false,
      redirectOn: "root"
    },
    bundle: {
      optimizeTranslationDirective: false
    }
  },
  runtimeConfig: {
    authDebugLogs: (process.env.AUTH_DEBUG_LOGS || "false").toLowerCase() === "true",
    httpAccessLogs: (process.env.HTTP_ACCESS_LOGS || "true").toLowerCase() === "true",
    public: {
      appName: "Nomade",
      socialProviders: {
        google: googleSocialEnabled,
        apple: appleSocialEnabled
      }
    }
  },
  nitro: {
    experimental: {
      websocket: true
    }
  }
});
