import { toast } from "vue-sonner";
import { ApiError } from "./useApi";

const ERROR_KEY_MAP: Record<string, string> = {
  missing_authorization: "errors.missing_authorization",
  invalid_token: "errors.invalid_token",
  csrf_origin_mismatch: "errors.csrf_origin_mismatch",
  sign_up_disabled: "errors.sign_up_disabled",
  signup_disabled: "errors.sign_up_disabled",
  SIGN_UP_DISABLED: "errors.sign_up_disabled",
  user_not_found: "errors.user_not_found",
  invalid_body: "errors.invalid_body",
  invalid_refresh_token: "errors.invalid_refresh_token",
  rate_limited: "errors.rate_limited",
  auth_handler_error: "errors.auth_handler_error",
  stripe_not_configured: "errors.stripe_not_configured",
  checkout_session_failed: "errors.checkout_session_failed",
  portal_session_failed: "errors.portal_session_failed"
};

export const useNotify = () => {
  const { t } = useI18n();

  const success = (key: string, params?: Record<string, unknown>) => {
    toast.success(t(key, params));
  };

  const info = (key: string, params?: Record<string, unknown>) => {
    toast(t(key, params));
  };

  const error = (key: string, params?: Record<string, unknown>) => {
    toast.error(t(key, params));
  };

  const errorFrom = (err: unknown, fallbackKey = "errors.generic") => {
    if (err instanceof ApiError) {
      const mappedKey = ERROR_KEY_MAP[err.code];
      if (mappedKey) {
        toast.error(t(mappedKey));
        return;
      }
      toast.error(t("errors.request_failed_with_code", { code: err.code }));
      return;
    }
    if (err instanceof Error && err.message.trim().length > 0) {
      toast.error(err.message);
      return;
    }
    toast.error(t(fallbackKey));
  };

  return {
    success,
    info,
    error,
    errorFrom
  };
};
