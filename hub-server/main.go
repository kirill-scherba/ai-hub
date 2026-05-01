// Hub Server — HTTP REST API server for AI Hub tool marketplace.
// Uses keyvalembd (libSQL + Ollama embeddings) for storage and semantic search.
//
// Usage:
//   go run .                    # default port 8484
//   go run . --port 9090        # custom port
//   AI_HUB_PORT=9090 go run .   # via env
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path"
	"strconv"
	"strings"

	"github.com/kirill-scherba/keyvalembd"
)

var kv *keyvalembd.KeyValueEmbd

// toolDefinition represents a tool stored on the hub.
type toolDefinition struct {
	Name        string      `json:"name"`
	Description string      `json:"description"`
	InputSchema interface{} `json:"inputSchema"`
	Code        string      `json:"code"`
	Source      string      `json:"source,omitempty"`
	CreatedAt   string      `json:"created_at"`
	EmbedText   string      `json:"-"`
}

const toolsPrefix = "tools/"

// getPort returns the port from flag, env, or default.
func getPort() int {
	port := flag.Int("port", 0, "HTTP server port")
	flag.Parse()
	if *port > 0 {
		return *port
	}
	if envPort := os.Getenv("AI_HUB_PORT"); envPort != "" {
		if p, err := strconv.Atoi(envPort); err == nil && p > 0 {
			return p
		}
	}
	return 8484
}

// ---- handlers ----

// handleList returns all tools with optional prefix filter.
// GET /tools?prefix=
func handleList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	prefix := toolsPrefix + r.URL.Query().Get("prefix")
	var tools []toolDefinition
	for key := range kv.List(prefix) {
		value, err := kv.Get(key)
		if err != nil {
			continue
		}
		var t toolDefinition
		if err := json.Unmarshal(value, &t); err != nil {
			continue
		}
		tools = append(tools, t)
	}
	if tools == nil {
		tools = []toolDefinition{}
	}
	writeJSON(w, http.StatusOK, tools)
}

// handleGet returns a single tool by name.
// GET /tools/{name}
func handleGet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	name := strings.TrimPrefix(r.URL.Path, "/tools/")
	if name == "" {
		http.Error(w, "Missing tool name", http.StatusBadRequest)
		return
	}
	value, err := kv.Get(toolsPrefix + name)
	if err != nil {
		http.Error(w, "Tool not found", http.StatusNotFound)
		return
	}
	var t toolDefinition
	if err := json.Unmarshal(value, &t); err != nil {
		http.Error(w, "Internal error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, t)
}

// handleCreate publishes a new tool.
// POST /tools  (body = JSON tool definition)
func handleCreate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Cannot read body", http.StatusBadRequest)
		return
	}
	var t toolDefinition
	if err := json.Unmarshal(body, &t); err != nil {
		http.Error(w, "Invalid JSON: "+err.Error(), http.StatusBadRequest)
		return
	}
	if t.Name == "" {
		http.Error(w, "Missing required field: name", http.StatusBadRequest)
		return
	}
	key := toolsPrefix + t.Name
	// Build embed text from name + description
	embedText := fmt.Sprintf("name: %s\ndescription: %s", t.Name, t.Description)
	t.EmbedText = embedText
	value, _ := json.Marshal(t)
	_, err = kv.SetWithEmbedding(key, value, embedText)
	if err != nil {
		http.Error(w, "Storage error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	log.Printf("Created tool: %s", t.Name)
	writeJSON(w, http.StatusCreated, map[string]string{"status": "created", "name": t.Name})
}

// handleDelete removes a tool by name.
// DELETE /tools/{name}
func handleDelete(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	name := strings.TrimPrefix(r.URL.Path, "/tools/")
	if name == "" {
		http.Error(w, "Missing tool name", http.StatusBadRequest)
		return
	}
	if err := kv.Del(toolsPrefix + name); err != nil {
		http.Error(w, "Delete error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	log.Printf("Deleted tool: %s", name)
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted", "name": name})
}

// handleSearch performs semantic search over tools.
// GET /search?q=...&limit=10
func handleSearch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	query := r.URL.Query().Get("q")
	if query == "" {
		http.Error(w, "Missing query parameter: q", http.StatusBadRequest)
		return
	}
	limitStr := r.URL.Query().Get("limit")
	limit := 10
	if limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 {
			limit = l
		}
	}
	results, err := kv.SearchSemantic(query, limit)
	if err != nil {
		// If embedder not ready, fall back to prefix search
		log.Printf("Semantic search failed (embedder may be unavailable): %v", err)
		writeJSON(w, http.StatusOK, []keyvalembd.SearchResult{})
		return
	}
	writeJSON(w, http.StatusOK, results)
}

// ---- helpers ----

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// ---- router ----

func router(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	cleanPath := strings.TrimSuffix(r.URL.Path, "/")

	switch {
	case cleanPath == "/tools" || cleanPath == "/tools/":
		switch r.Method {
		case http.MethodGet:
			handleList(w, r)
		case http.MethodPost:
			handleCreate(w, r)
		default:
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	case strings.HasPrefix(cleanPath, "/tools/"):
		switch r.Method {
		case http.MethodGet:
			handleGet(w, r)
		case http.MethodDelete:
			handleDelete(w, r)
		default:
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	case cleanPath == "/search" || strings.HasPrefix(cleanPath, "/search"):
		handleSearch(w, r)
	default:
		http.Error(w, "Not found", http.StatusNotFound)
	}
}

func main() {
	port := getPort()

	// Determine data directory
	dataDir := os.Getenv("AI_HUB_DATA_DIR")
	if dataDir == "" {
		home, err := os.UserHomeDir()
		if err == nil {
			dataDir = path.Join(home, ".ai-hub")
		} else {
			dataDir = "./ai-hub-data"
		}
	}
	os.MkdirAll(dataDir, 0755)
	dbPath := path.Join(dataDir, "hub.db")

	var err error
	kv, err = keyvalembd.New(dbPath)
	if err != nil {
		log.Fatalf("Failed to initialise keyvalembd: %v", err)
	}
	defer kv.Close()

	addr := fmt.Sprintf(":%d", port)
	log.Printf("🚀 AI Hub Server starting on %s", addr)
	log.Printf("   Data directory: %s", dataDir)
	log.Printf("   Embeddings: %s", map[bool]string{true: "enabled", false: "unavailable (Ollama?)"}[kv != nil])

	http.HandleFunc("/", router)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}