FROM node:20-alpine

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci --omit=dev

# Copy compiled output
COPY dist/ ./dist/

EXPOSE 19000

ENV NODE_ENV=production
ENV AGENTCOCKPIT_PORT=19000

CMD ["node", "dist/server.js"]
