import { createWsProxyHandler } from '../utils/ws-proxy';

export default createWsProxyHandler((requestUrl) => `/ws${requestUrl.search}`);
