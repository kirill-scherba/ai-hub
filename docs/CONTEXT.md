# AI Hub — Context

## What is AI Hub?

AI Hub — это платформа для создания, обмена и поиска MCP инструментов между AI-ассистентами.

Состоит из двух компонентов:

### 1. **Hub Server** (Go)
- HTTP REST API сервер на Go с портом 8484
- Хранит инструменты в keyvalembd (libSQL + Ollama embeddings)
- Позволяет публиковать, искать (семантически), получать и удалять инструменты
- Endpoints:
  - `POST /tools` — создать/опубликовать инструмент
  - `GET /tools?prefix=` — список инструментов с опциональным префиксом
  - `GET /tools/{name}` — получить конкретный инструмент
  - `DELETE /tools/{name}` — удалить инструмент
  - `GET /search?q=...&limit=N` — семантический поиск по инструментам
- Флаги: `--port`, `AI_HUB_PORT`, `AI_HUB_DATA_DIR`

### 2. **generative-mcp-hub.pl** (Perl MCP сервер)
- MCP сервер, который работает через JSON-RPC 2.0 по stdin/stdout
- Позволяет AI генерировать новые MCP инструменты на Perl через Safe sandbox
- Инструменты:
  - `tool_generate` — создать новый инструмент
  - `tool_list` — список всех инструментов
  - `tool_export` / `tool_import` — экспорт/импорт JSON
  - `tool_remove` — удалить инструмент
  - **hub_publish** — опубликовать локальный инструмент на Hub Server
  - **hub_search** — семантический поиск инструментов на Hub
  - **hub_pull** — скачать инструмент с Hub и установить локально
  - **hub_list** — список инструментов на Hub
- Флаги: `--hub-url <URL>`, `AI_HUB_SERVER_URL`

## Архитектура

```
┌─────────────┐     HTTP/REST      ┌──────────────────┐
│  MCP Client  │ ◄──── JSON-RPC ───► │ generative-mcp-  │
│  (AI Assistant) │                  │ hub.pl (Perl)    │
└─────────────┘                     └────────┬─────────┘
                                              │ --hub-url http://host:8484
                                              ▼
                                    ┌──────────────────┐
                                    │  Hub Server (Go)  │
                                    │  port :8484        │
                                    │  keyvalembd        │
                                    │  + Ollama embeds   │
                                    └──────────────────┘
```

## Ключевые концепции

- **Tool definition** — JSON объект с name, description, inputSchema, code, created_at
- **Semantic search** — через Ollama embedding (модель embeddinggemma:latest)
- **Safe sandbox** — Perl Safe module для безопасного выполнения кода
- **Persistence** — инструменты сохраняются на диск (tools.json) и в keyvalembd (hub.db)