## Build the Go API binary (no secrets in build)
FROM golang:1.24-alpine AS builder

WORKDIR /src

COPY backend/go.mod backend/go.sum ./backend/
WORKDIR /src/backend
RUN go mod download

COPY backend/ ./

ARG TARGETOS=linux
ARG TARGETARCH=amd64

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
  go build -trimpath -ldflags="-s -w" -o /out/megaserver-api ./cmd/api

FROM alpine:3.20

RUN apk add --no-cache ca-certificates curl && update-ca-certificates

WORKDIR /app
COPY --from=builder /out/megaserver-api /app

COPY infra/docker/docker-entrypoint.sh /app/docker-entrypoint.sh

RUN --mount=type=secret,id=env_vars \
  cp /run/secrets/env_vars /app/.env && \
  chmod +x /app/docker-entrypoint.sh

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -fsS "http://localhost:4000/v1/healthcheck" || exit 1

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["/app/megaserver-api", "-port=4000", "-env=production"]