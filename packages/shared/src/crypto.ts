import { createHash, timingSafeEqual } from "node:crypto";

export const sha256 = (value: string): string => {
  return createHash("sha256").update(value).digest("hex");
};

export const safeEqual = (left: string, right: string): boolean => {
  const l = Buffer.from(left);
  const r = Buffer.from(right);
  if (l.length !== r.length) {
    return false;
  }
  return timingSafeEqual(l, r);
};
