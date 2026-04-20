FROM node:20-alpine

WORKDIR /app

# Server-Dependencies installieren
COPY server/package.json ./server/
RUN cd server && npm install --production

# Server-Code kopieren
COPY server/ ./server/

# React Build kopieren
COPY client/dist/ ./client/dist/

EXPOSE 3001

CMD ["node", "server/index.js"]
