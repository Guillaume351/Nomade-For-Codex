import { createWsProxyHandler } from '../../../../utils/ws-proxy';

export default createWsProxyHandler((requestUrl) => `${requestUrl.pathname}${requestUrl.search}`);
