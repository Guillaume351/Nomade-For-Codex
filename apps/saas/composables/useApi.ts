export class ApiError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(params: { message: string; code: string; status: number }) {
    super(params.message);
    this.name = "ApiError";
    this.status = params.status;
    this.code = params.code;
  }
}

const extractErrorCode = (payload: Record<string, unknown>, status: number): string => {
  if (typeof payload.error === "string" && payload.error.trim().length > 0) {
    return payload.error.trim();
  }
  if (typeof payload.code === "string" && payload.code.trim().length > 0) {
    return payload.code.trim();
  }
  return `request_failed_${status}`;
};

const extractMessage = (payload: Record<string, unknown>, fallback: string): string => {
  if (typeof payload.message === "string" && payload.message.trim().length > 0) {
    return payload.message.trim();
  }
  if (typeof payload.error === "string" && payload.error.trim().length > 0) {
    return payload.error.trim();
  }
  return fallback;
};

export const useApi = () => {
  const forwardedHeaders = process.server
    ? Object.fromEntries(
        Object.entries(useRequestHeaders(["cookie", "origin", "referer", "user-agent"])).filter(
          (entry): entry is [string, string] => typeof entry[1] === "string"
        )
      )
    : undefined;

  const request = async <T>(
    path: string,
    params: {
      method: "GET" | "POST" | "PATCH" | "PUT" | "DELETE";
      payload?: Record<string, unknown>;
    }
  ): Promise<T> => {
    const response = await fetch(path, {
      method: params.method,
      headers: {
        ...(forwardedHeaders ?? {}),
        accept: "application/json",
        ...(params.payload ? { "content-type": "application/json" } : {})
      },
      credentials: "include",
      body: params.payload ? JSON.stringify(params.payload) : undefined
    });

    const raw = await response.text();
    let data = {} as Record<string, unknown>;
    if (raw.length > 0) {
      try {
        data = JSON.parse(raw) as Record<string, unknown>;
      } catch {
        data = {};
      }
    }

    if (!response.ok) {
      throw new ApiError({
        message: extractMessage(data, `request_failed_${response.status}`),
        code: extractErrorCode(data, response.status),
        status: response.status
      });
    }

    return data as T;
  };

  const postJson = async <T>(path: string, payload: Record<string, unknown>): Promise<T> =>
    request<T>(path, { method: "POST", payload });

  const patchJson = async <T>(path: string, payload: Record<string, unknown>): Promise<T> =>
    request<T>(path, { method: "PATCH", payload });

  const getJson = async <T>(path: string): Promise<T> => request<T>(path, { method: "GET" });

  return {
    postJson,
    patchJson,
    getJson
  };
};
