import { loadConfig } from "./config.js";
import { createServer } from "./server.js";

const boot = async (): Promise<void> => {
  const config = loadConfig();
  const server = await createServer();
  server.listen(config.port, () => {
    console.log(`[control-api] listening on :${config.port}`);
  });
};

boot().catch((error) => {
  console.error("[control-api] fatal", error);
  process.exit(1);
});
