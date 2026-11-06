FROM node:24.9.0-bookworm-slim
WORKDIR /opt/ponynotes-agent
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund
COPY src ./src
COPY PI-LICENSE.txt ./PI-LICENSE.txt
RUN mkdir /data && chown node:node /data
USER node
ENV HOST=0.0.0.0 PORT=4319 PONYNOTES_AGENT_DATA=/data
EXPOSE 4319
CMD ["node", "src/server.mjs"]
