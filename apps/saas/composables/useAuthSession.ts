interface SessionUser {
  id: string;
  email: string;
  name?: string | null;
  image?: string | null;
}

interface AuthSessionPayload {
  user?: SessionUser | null;
  session?: Record<string, unknown> | null;
}

const emptySession: AuthSessionPayload = {
  user: null,
  session: null
};

export const useAuthSession = () => {
  const session = useState<AuthSessionPayload>("auth-session", () => emptySession);
  const hydrated = useState<boolean>("auth-session-hydrated", () => false);

  const fetchSession = async (force = false): Promise<AuthSessionPayload> => {
    if (hydrated.value && !force) {
      return session.value;
    }
    try {
      const headers = process.server ? useRequestHeaders(["cookie"]) : undefined;
      const payload = await $fetch<AuthSessionPayload>("/api/auth/get-session", {
        method: "GET",
        headers,
        credentials: "include"
      });
      session.value = payload ?? emptySession;
    } catch {
      session.value = emptySession;
    } finally {
      hydrated.value = true;
    }
    return session.value;
  };

  const clearSession = () => {
    session.value = emptySession;
    hydrated.value = true;
  };

  return {
    session: computed(() => session.value),
    user: computed(() => session.value.user ?? null),
    isAuthenticated: computed(() => Boolean(session.value.user?.id)),
    fetchSession,
    clearSession
  };
};
