# Quickstart (local)

## 1. Install and build
```bash
npm install
npm run build
npm test
```

## 2. Start backend services (one command)
```bash
npm run dev:up
npm run dev:logs
```

## 3. Login and pair agent
```bash
# device code start
curl -sX POST http://localhost:8080/auth/device/start | jq

# approve user code
curl -sX POST http://localhost:8080/auth/device/approve \
  -H 'content-type: application/json' \
  -d '{"userCode":"<USER_CODE>","email":"you@example.com"}'

# poll for access token
curl -sX POST http://localhost:8080/auth/device/poll \
  -H 'content-type: application/json' \
  -d '{"deviceCode":"<DEVICE_CODE>"}' | jq

# create pairing code
curl -sX POST http://localhost:8080/agents/pair \
  -H "authorization: Bearer <ACCESS_TOKEN>" | jq

# pair + run agent
npm run dev:agent -- pair --server-url http://localhost:8080 --pairing-code <PAIRING_CODE>
npm run dev:agent -- run
```

## 4. Stop backend services
```bash
npm run dev:down
```
