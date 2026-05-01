# 🐪 AI Hub Server — Docker Image
# Multi-stage: Go build + distroless runtime

FROM golang:1.23-bookworm AS builder

WORKDIR /build

COPY go.mod go.sum ./
COPY main.go ./
RUN go mod download

RUN go build -o /hub-server .

FROM gcr.io/distroless/base-debian12

COPY --from=builder /hub-server /hub-server

EXPOSE 8484

ENTRYPOINT ["/hub-server"]