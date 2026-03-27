import { describe, expect, it } from "vitest";
import { extractTunnelSlug } from "./slug.js";

describe("extractTunnelSlug", () => {
  it("extracts a valid subdomain", () => {
    expect(extractTunnelSlug("abc123.preview.localhost", "preview.localhost")).toBe("abc123");
  });

  it("rejects nested subdomains", () => {
    expect(extractTunnelSlug("a.b.preview.localhost", "preview.localhost")).toBeNull();
  });

  it("rejects unknown domains", () => {
    expect(extractTunnelSlug("abc.example.com", "preview.localhost")).toBeNull();
  });
});
