export const useAuthFlow = () => {
  const { fetchSession, isAuthenticated } = useAuthSession();

  const waitForAuthenticatedSession = async () => {
    for (let i = 0; i < 6; i += 1) {
      await fetchSession(true);
      if (isAuthenticated.value) {
        return true;
      }
      await new Promise((resolve) => setTimeout(resolve, 180));
    }
    return false;
  };

  return {
    waitForAuthenticatedSession
  };
};
