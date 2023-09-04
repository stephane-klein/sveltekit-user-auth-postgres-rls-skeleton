FROM node:18-alpine
RUN npm install -g pnpm@8.7.0

WORKDIR /app
COPY . .
RUN pnpm install --frozen-lockfile --no-optional
RUN pnpm run build

FROM node:18-alpine
RUN npm install -g pnpm@8.7.0

WORKDIR /app

COPY --from=0 /app/package.json ./
COPY --from=0 /app/pnpm-lock.yaml ./

RUN pnpm install --frozen-lockfile --no-optional

COPY --from=0 /app/build ./
COPY ./docker-entrypoint.sh /docker-entrypoint.sh
COPY ./migrations/ /app/migrations/
RUN echo -e '{\n}\n' > /app/.gmrc

ENV SHADOW_DATABASE_URL=""
ENV ROOT_DATABASE_URL=""

EXPOSE 3000
ENTRYPOINT ["sh"]
CMD ["/docker-entrypoint.sh"]
