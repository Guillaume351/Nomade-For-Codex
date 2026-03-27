import { loadConfig } from "./config.js";
import { createServer } from "./server.js";

const boot = (): void => {
  const config = loadConfig();
  const server = createServer();
  server.listen(config.port, () => {
    console.log(`[tunnel-gateway] listening on :${config.port}`);
  });
};

boot();
