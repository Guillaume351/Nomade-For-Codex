export default defineNuxtRouteMiddleware(async (to) => {
  const { fetchSession, isAuthenticated } = useAuthSession();
  await fetchSession();
  if (isAuthenticated.value) {
    return;
  }

  const returnTo = encodeURIComponent(to.fullPath || to.path || "/account");
  return navigateTo(`/login?returnTo=${returnTo}`);
});
