# ---- Stage 1: Build ----
# Compiles the Go binary in a full Go toolchain image. This stage is thrown
# away after the build, so its size doesn't affect the final image.
# Using "latest" (not a pinned minor version) so this always satisfies
# whatever Go version go.mod declares, without needing manual bumps here
# every time the local Go SDK/toolchain version changes.
FROM golang:alpine AS builder
WORKDIR /app
# Copy go.mod/go.sum first so dependency downloads are cached separately
# from source code changes (faster rebuilds while iterating).
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
# CGO_ENABLED=0 produces a static binary that runs on the minimal runtime
# image below without needing glibc/libc compatibility.
RUN CGO_ENABLED=0 GOOS=linux go build -o ai-tutor-backend .
# ---- Stage 2: Run ----
# Alpine is ~5MB vs. golang's ~800MB - this is the image that actually
# ships and runs in production/Render/Docker Compose.
FROM alpine:3.19
WORKDIR /app
# Required for the Go binary to make outbound HTTPS/TLS calls and to resolve
# hostnames correctly (e.g. connecting to a "postgres" service by name).
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/ai-tutor-backend .
COPY --from=builder /app/migrations ./migrations
EXPOSE 8080
CMD ["./ai-tutor-backend"]
