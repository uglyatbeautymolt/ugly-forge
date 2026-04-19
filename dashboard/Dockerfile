FROM node:20-alpine

WORKDIR /app

# Server-Dependencies installieren
COPY server/package.json ./server/
RUN cd server && npm install --production

# Server-Code kopieren
COPY server/ ./server/

# React Build kopieren (wird beim Docker Build eingebunden)
COPY client/dist/ ./client/dist/

# Static Files vom React Build servieren
RUN sed -i 's|// STATIC_FILES_PLACEHOLDER|app.use(express.static("/app/client/dist"));|' server/index.js 2>/dev/null || true

EXPOSE 3001

CMD ["node", "server/index.js"]
