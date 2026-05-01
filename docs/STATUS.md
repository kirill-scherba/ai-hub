# AI Hub — Статус проекта

## Текущее состояние: ✅ Релиз 1.0 (реализован полный цикл)

### Что реализовано

- [x] **Hub Server** (Go, port :8484)
  - HTTP REST API: create/list/get/delete/search tools
  - keyvalembd (libSQL + Ollama embeddings) для хранения и семантического поиска
  - Поддержка CORS, JSON responses
  - Флаги: --port, AI_HUB_PORT, AI_HUB_DATA_DIR

- [x] **generative-mcp-hub.pl** (Perl MCP сервер)
  - CLI-парсинг --hub-url и AI_HUB_SERVER_URL
  - 4 hub-инструмента: hub_publish, hub_search, hub_pull, hub_list
  - hub_check при старте (логирование подключения к Hub)
  - HTTP helpers (hub_http_get, hub_http_post) через curl
  - Все инструменты зарегистрированы в tools/list и tools/call

- [x] **Протокол Hub ↔ Client**
  - REST API: POST /tools, GET /tools, GET /tools/{name}, DELETE /tools/{name}, GET /search
  - Семантический поиск через Ollama embeddinggemma:latest
  - Публикация/импорт через JSON tool definition

- [x] **Тестирование полного цикла**
  - Create → List → Get → Search → Delete → Verify
  - Семантический поиск: score 0.58 для "hello" запроса
  - Все 6 шагов успешно пройдены

### Известные ограничения

- `/api/health` endpoint отсутствует (роутер обрабатывает только /tools и /search)
- Для работы семантического поиска требуется Ollama с моделью embeddinggemma:latest
- Perl MCP сервер требует curl для HTTP запросов к Hub

### Планы на будущее

- [ ] Добавить /api/health endpoint
- [ ] Добавить аутентификацию/API ключи
- [ ] Поддержка версионирования инструментов
- [ ] Web UI для просмотра инструментов
- [ ] Federation между несколькими Hub серверами