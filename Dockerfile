# SSH Bastion for K8s Tenant Platform
# Proxies SSH connections from users to their development environment containers

FROM golang:1.24-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the bastion binary
RUN CGO_ENABLED=0 GOOS=linux go build -o /ssh-bastion ./cmd/ssh-bastion

# Final image
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

COPY --from=builder /ssh-bastion /usr/local/bin/ssh-bastion

EXPOSE 2222

ENTRYPOINT ["ssh-bastion"]
