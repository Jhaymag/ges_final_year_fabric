FROM golang:1.22-alpine AS build
WORKDIR /chaincode
COPY . .
# Add cache mounts for the Go toolchain and module caches
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    go build -o ges-verify .

FROM alpine:3.18
WORKDIR /chaincode
COPY --from=build /chaincode/ges-verify .
ENV CHAINCODE_ID=""
ENV CHAINCODE_ADDRESS="0.0.0.0:9999"
EXPOSE 9999
CMD ["./ges-verify"]
