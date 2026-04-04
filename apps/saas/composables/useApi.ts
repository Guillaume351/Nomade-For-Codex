export const useApi = () => {
  const postJson = async <T>(path: string, payload: Record<string, unknown>): Promise<T> => {
    const response = await fetch(path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload)
    });
    const data = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    if (!response.ok) {
      const message =
        typeof data.message === "string"
          ? data.message
          : typeof data.error === "string"
            ? data.error
            : `request_failed_${response.status}`;
      throw new Error(message);
    }
    return data as T;
  };

  const getJson = async <T>(path: string): Promise<T> => {
    const response = await fetch(path, {
      method: "GET",
      headers: { "accept": "application/json" }
    });
    const data = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    if (!response.ok) {
      const message =
        typeof data.message === "string"
          ? data.message
          : typeof data.error === "string"
            ? data.error
            : `request_failed_${response.status}`;
      throw new Error(message);
    }
    return data as T;
  };

  return {
    postJson,
    getJson
  };
};
