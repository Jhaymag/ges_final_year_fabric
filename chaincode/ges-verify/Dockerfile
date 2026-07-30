# 1. Use the exact version to eliminate toolchain downloads
FROM golang:1.22.3-alpine AS build
WORKDIR /chaincode

ENV GOTOOLCHAIN=local

# 2. Copy only dependency files first to maximize layer caching
COPY go.mod ./
# Uncomment the line below if you have a go.sum file
COPY go.sum ./

# 3. Pre-download dependencies using the BuildKit cache
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# 4. Copy the rest of your source code (only invalidates layers below this)
COPY . .
ENV GOTOOLCHAIN=local
# 5. Build using both compiler and module caches
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    go build -o ges-verify .

# Final minimal deployment stage
FROM alpine:3.18
WORKDIR /chaincode
COPY --from=build /chaincode/ges-verify .
ENV CHAINCODE_ID=""
ENV CHAINCODE_ADDRESS="0.0.0.0:9999"
EXPOSE 9999
CMD ["./ges-verify"]
