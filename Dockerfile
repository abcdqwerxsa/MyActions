FROM node:20-slim AS builder

WORKDIR /app
COPY container/package.json .
RUN npm install --production && \
    rm -rf /root/.npm

FROM node:20-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    dumb-init \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/* \
    && rm -rf /usr/share/doc /usr/share/man /usr/share/locale /usr/share/info

WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY package.json .
COPY server.mjs .

EXPOSE 9222 8080

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.mjs"]
