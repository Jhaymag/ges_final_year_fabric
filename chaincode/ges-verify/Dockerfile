FROM golang:1.22-alpine AS build
WORKDIR /chaincode
COPY . .
RUN go build -o ges-verify .

FROM alpine:3.18
WORKDIR /chaincode
COPY --from=build /chaincode/ges-verify .
ENV CHAINCODE_ID=""
ENV CHAINCODE_ADDRESS="0.0.0.0:9999"
EXPOSE 9999
CMD ["./ges-verify"]
