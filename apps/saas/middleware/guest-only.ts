export default defineNuxtRouteMiddleware(async (to) => {
  if (typeof to.query.error === "string") {
    return;
  }
  const { fetchSession, isAuthenticated } = useAuthSession();
  await fetchSession(true);
  if (isAuthenticated.value) {
    const requested =
      typeof to.query.returnTo === "string" && to.query.returnTo.startsWith("/")
        ? to.query.returnTo
        : "/account";
    const guestOnlyPaths = new Set(["/login", "/signup", "/forgot-password", "/reset-password", "/verify-email"]);
    const preferred = guestOnlyPaths.has(requested) ? "/account" : requested;
    return navigateTo(preferred);
  }
});
