# VAISASTRAM — Deployment Guide

This guide describes how to deploy VAISASTRAM cleanly, reproducibly, and securely using Docker, Docker Compose, or Kamal.

---

## 1. Deployment Architecture

```
Internet / Reverse Proxy (HTTPS :443)
           |
           v
  Thruster / Puma (HTTP :80) [Rails 8 / Propshaft / Solid Queue]
     |                 |
     | (SQL / Queue)   | (Inference Calls)
     v                 v
PostgreSQL 16     AI Providers (Local Ollama or Cloud Gemini/Groq)
```

- **Web Server**: Puma 6+ fronted by Thruster for asset acceleration and HTTP caching.
- **Background Jobs**: Solid Queue running in-database with `queue` migrations.
- **Caching**: Solid Cache running in-database with `cache` migrations.
- **WebSocket/Turbo Streams**: Solid Cable running in-database.
- **Database**: PostgreSQL 16+.

---

## 2. Environment Configuration Matrix

Ensure the following environment variables are set in production:

| Variable | Required? | Example Value | Description |
| :--- | :--- | :--- | :--- |
| `RAILS_ENV` | Yes | `production` | Rails environment |
| `DATABASE_URL` | Yes | `postgres://user:pass@host:5432/vaisastram_prod` | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Yes | `(hex string)` | Secret key base for sessions |
| `AI_PROVIDER_MODE` | No | `cloud` (default) or `hybrid` | Inference strategy |
| `AI_PRIMARY_PROVIDER` | No | `openai` (or `gemini`) | Primary provider identifier |
| `AI_FALLBACK_PROVIDER` | No | `grok` (or `groq`) | Fallback provider identifier |
| `AI_FALLBACK_ENABLED` | No | `true` | Enable/disable multi-tier fallback |
| `OPENAI_API_KEY` | Conditional | `sk-proj-...` | OpenAI API key (for GPT-4o, etc.) |
| `OPENAI_MODEL` | No | `gpt-4o` | OpenAI model identifier |
| `XAI_API_KEY` | Conditional | `xai-...` | xAI API key (for Grok models) |
| `XAI_MODEL` | No | `grok-2-latest` | xAI Grok model identifier |
| `GEMINI_API_KEY` | Conditional | `AIzaSy...` | Required if Gemini is selected |
| `GEMINI_MODEL` | No | `gemini-3.8-flash` | Gemini model name |
| `GROQ_API_KEY` | No | `gsk_...` | Secondary cloud fallback |
| `GROQ_MODEL` | No | `llama-3.3-70b-versatile` | Groq model name |
| `OLLAMA_BASE_URL` | Conditional | `http://ollama-host:11434` | Required if mode is `local` or `hybrid` |
| `RAILS_FORCE_SSL` | No | `true` | Enforces HTTPS and secure cookies |
| `RAILS_ASSUME_SSL`| No | `true` | Informs Rails that proxy handles SSL termination |

---

## 3. Deployment Options

### Option A: Local Production Testing via Docker Compose

```bash
# 1. Copy environment template
cp .env.example .env

# 2. Build and launch services
docker compose up --build -d

# 3. Check health status
docker compose ps
curl -f http://localhost:3000/up
```

### Option B: Bare Metal / Virtual Machine

```bash
# 1. Install system packages
sudo apt-get update
sudo apt-get install -y ruby3.4 postgresql-client libpq-dev libvips libjemalloc2 curl

# 2. Clone and install gems
bundle config set --local deployment 'true'
bundle config set --local without 'development test'
bundle install

# 3. Precompile assets
SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile

# 4. Run database migrations
bin/rails db:migrate

# 5. Start web server and background queue
bin/thrust bin/rails server &
bin/rails solid_queue:start &
```

---

## 4. Database Migrations & Rollback Procedures

### Running Migrations

```bash
bin/rails db:migrate
```

### Rollback Procedure

```bash
# Roll back the last migration step
bin/rails db:rollback

# Restore from a verified backup if necessary
bin/restore_db.sh backups/vaisastram_production_TIMESTAMP.dump
```

---

## 5. Health Check & Monitoring

- **Endpoint**: `GET /up`
- **Response**: `200 OK` (renders green body when healthy, `500 Internal Server Error` if database or core services are down).
- **Log Silence**: Configured in `config/environments/production.rb` to prevent health check clutter in logs.
