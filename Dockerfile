# 🐪 Generative MCP Hub — Docker Image
# Multi-stage build: Alpine + Perl + curl + JSON module

FROM perl:5.40-slim-bookworm AS builder

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        ca-certificates \
        curl \
        && \
    rm -rf /var/lib/apt/lists/*

RUN cpanm --quiet --notest JSON

FROM perl:5.40-slim-bookworm

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        ca-certificates \
        curl \
        && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/lib/perl5 /usr/local/lib/perl5

WORKDIR /opt/ai-hub

COPY generative-mcp-hub.pl .
COPY tools.json .

ENV AI_HUB_SKIP_HUB=1

ENTRYPOINT ["perl", "/opt/ai-hub/generative-mcp-hub.pl"]