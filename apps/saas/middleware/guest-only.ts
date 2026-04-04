export default defineNuxtRouteMiddleware(async (to) => {
  const { fetchSession, isAuthenticated } = useAuthSession();
  await fetchSession();
  if (isAuthenticated.value) {
    const preferred =
      typeof to.query.returnTo === "string" && to.query.returnTo.startsWith("/")
        ? to.query.returnTo
        : "/account";
    return navigateTo(preferred);
  }
});
