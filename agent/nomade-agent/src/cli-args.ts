export interface ParsedCliArgs {
  command: string;
  options: Map<string, string | true>;
  positionals: string[];
}

const isOptionToken = (value: string): boolean => value.startsWith("--");

export const parseCliArgs = (argv: string[]): ParsedCliArgs => {
  const options = new Map<string, string | true>();
  const positionals: string[] = [];

  let command = "run";
  let cursor = 0;
  const first = argv[0];
  if (first && !first.startsWith("-")) {
    command = first;
    cursor = 1;
  }

  while (cursor < argv.length) {
    const token = argv[cursor];
    if (token === "--") {
      positionals.push(...argv.slice(cursor + 1));
      break;
    }

    if (token === "-h") {
      options.set("help", true);
      cursor += 1;
      continue;
    }

    if (!isOptionToken(token)) {
      positionals.push(token);
      cursor += 1;
      continue;
    }

    const withoutPrefix = token.slice(2);
    const eqIndex = withoutPrefix.indexOf("=");
    if (eqIndex >= 0) {
      const key = withoutPrefix.slice(0, eqIndex).trim();
      const value = withoutPrefix.slice(eqIndex + 1);
      if (key.length > 0) {
        options.set(key, value);
      }
      cursor += 1;
      continue;
    }

    const key = withoutPrefix.trim();
    const next = argv[cursor + 1];
    if (!next || next.startsWith("-")) {
      if (key.length > 0) {
        options.set(key, true);
      }
      cursor += 1;
      continue;
    }

    if (key.length > 0) {
      options.set(key, next);
    }
    cursor += 2;
  }

  return {
    command,
    options,
    positionals
  };
};

export const readOption = (options: Map<string, string | true>, name: string): string | undefined => {
  const value = options.get(name);
  return typeof value === "string" ? value : undefined;
};

export const hasOption = (options: Map<string, string | true>, name: string): boolean => {
  return options.has(name);
};
