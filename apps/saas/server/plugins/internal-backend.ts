import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { internalBackendAddress } from '../utils/internal-backend';

const startInternalBackendServer = async (): Promise<void> => {
  if (globalThis.__nomadeInternalBackendServer) {
    return;
  }
  if (globalThis.__nomadeInternalBackendServerStart) {
    await globalThis.__nomadeInternalBackendServerStart;
    return;
  }

  globalThis.__nomadeInternalBackendServerStart = (async () => {
    const serverModulePath = resolve(process.cwd(), 'services/control-api/dist/server.js');
    if (!existsSync(serverModulePath)) {
      throw new Error(
        `Internal backend dist not found at ${serverModulePath}. Build services/control-api before starting Nuxt.`
      );
    }

    const serverModuleUrl = pathToFileURL(serverModulePath).href;
    const { createServer } = await import(serverModuleUrl);
    const server = await createServer();

    await new Promise<void>((resolveStart, rejectStart) => {
      const onError = (error: Error): void => {
        server.off('listening', onListening);
        rejectStart(error);
      };
      const onListening = (): void => {
        server.off('error', onError);
        resolveStart();
      };
      server.once('error', onError);
      server.once('listening', onListening);
      server.listen(internalBackendAddress.port, internalBackendAddress.host);
    });

    globalThis.__nomadeInternalBackendServer = server;
    console.log(
      `[saas] embedded backend listening on http://${internalBackendAddress.host}:${internalBackendAddress.port}`
    );
  })().finally(() => {
    globalThis.__nomadeInternalBackendServerStart = undefined;
  });

  await globalThis.__nomadeInternalBackendServerStart;
};

export default defineNitroPlugin(() => {
  void startInternalBackendServer().catch((error) => {
    const message = error instanceof Error ? error.message : String(error);
    console.error('[saas] embedded backend failed', { error: message });
  });
});
