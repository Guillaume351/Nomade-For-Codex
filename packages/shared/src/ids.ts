import { randomBytes, randomUUID } from "node:crypto";

export const newId = (): string => randomUUID();

export const randomCode = (length: number): string => {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = randomBytes(length);
  let out = "";
  for (let i = 0; i < length; i += 1) {
    out += alphabet[bytes[i] % alphabet.length];
  }
  return out;
};

export const randomToken = (prefix: string): string => {
  return `${prefix}_${randomBytes(24).toString("hex")}`;
};

export const randomSlug = (): string => {
  return randomBytes(5).toString("hex");
};
