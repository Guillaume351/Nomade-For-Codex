const googleSocialEnabled = Boolean(process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET);
const appleSocialEnabled = Boolean(process.env.APPLE_CLIENT_ID && process.env.APPLE_CLIENT_SECRET);

export default defineNuxtConfig({
  compatibilityDate: "2026-04-04",
  devtools: { enabled: false },
  css: ["~/assets/css/main.css"],
  runtimeConfig: {
    compatBackendUrl: process.env.COMPAT_BACKEND_URL || "http://127.0.0.1:8080",
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
