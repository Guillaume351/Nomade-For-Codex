import { describe, expect, it } from "vitest";
import { hasOption, parseCliArgs, readOption } from "./cli-args.js";

describe("parseCliArgs", () => {
  it("defaults to run command", () => {
    const parsed = parseCliArgs([]);
    expect(parsed.command).toBe("run");
  });

  it("parses command and mixed option styles", () => {
    const parsed = parseCliArgs([
      "start",
      "--config",
      "/tmp/config.json",
      "--keep-awake=active",
      "--open-browser"
    ]);

    expect(parsed.command).toBe("start");
    expect(readOption(parsed.options, "config")).toBe("/tmp/config.json");
    expect(readOption(parsed.options, "keep-awake")).toBe("active");
    expect(hasOption(parsed.options, "open-browser")).toBe(true);
  });

  it("supports -h and positional passthrough after --", () => {
    const parsed = parseCliArgs(["run", "-h", "--", "--not-an-option"]);
    expect(hasOption(parsed.options, "help")).toBe(true);
    expect(parsed.positionals).toEqual(["--not-an-option"]);
  });
});
