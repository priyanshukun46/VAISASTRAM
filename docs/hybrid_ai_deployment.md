# VAISASTRAM — Hybrid Local AI Architecture & Deployment Guide

## Overview

VAISASTRAM implements a governed hybrid AI inference architecture:
- **Local Primary**: Ollama running Google's `gemma3:4b` on `http://localhost:11434`.
- **Cloud Fallback 1**: Google Gemini (`gemini-2.5-pro`).
- **Cloud Fallback 2**: Groq (`llama-3.3-70b-versatile`).

Core Principle: **AI proposes. Ruby decides.**

---

## 1. Local Development Architecture

In local development:
1. The Rails application connects to Ollama running locally at `http://localhost:11434`.
2. When local inference succeeds, the plan is returned directly and **zero cloud requests are made**. User prompts never leave the local machine.
3. If Ollama is offline or times out, the `Ai::ProviderRouter` initiates bounded retry and cleanly falls back to cloud providers (Gemini -> Groq) if `AI_CLOUD_FALLBACK_ENABLED=true`.

### Environment Configuration (`.env`)
```bash
# Inference mode: hybrid (local primary + cloud fallback), local (strictly local), or cloud (cloud-only)
AI_PROVIDER_MODE=hybrid
AI_CLOUD_FALLBACK_ENABLED=true

# Local Ollama settings
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=gemma3:4b
OLLAMA_TIMEOUT=90
OLLAMA_KEEP_ALIVE=5m

# Cloud Provider Keys & Models
GEMINI_API_KEY=your_gemini_api_key
GEMINI_MODEL=gemini-2.5-pro

GROQ_API_KEY=your_groq_api_key
GROQ_MODEL=llama-3.3-70b-versatile

AI_REQUEST_TIMEOUT=90
```

---

## 2. Production Deployment (e.g. Railway, Render, Fly.io, AWS)

### Critical Security Rule
**Never assume `localhost` refers to the developer's machine in production.**
In a hosted cloud environment (such as Railway or Render), `http://localhost:11434` refers to the container itself, NOT the developer's local machine.

### Production Strategies

#### Strategy A: Cloud-Only Mode (Recommended for lightweight web instances)
Set environment variables in your production container:
```bash
AI_PROVIDER_MODE=cloud
AI_CLOUD_FALLBACK_ENABLED=true
GEMINI_API_KEY=<production_gemini_key>
GROQ_API_KEY=<production_groq_key>
```
In this mode, `Ai::ProviderRouter` skips the local Ollama tier entirely and uses Gemini with Groq fallback.

#### Strategy B: Private Internal Ollama Service (VPC / Private Network)
If hosting private local/self-hosted inference in production:
1. Deploy Ollama in a private container/VM with GPU acceleration within the same private VPC or internal network.
2. Configure `OLLAMA_BASE_URL` to use the private internal DNS/IP (e.g., `http://ollama-service.railway.internal:11434` or `http://10.0.0.15:11434`).
3. **Security Caution**: Never expose Ollama's port `11434` to the public internet without mutual TLS or an authenticating reverse proxy.

---

## 3. Error Classification & Fallback Rules

| Error Type | Category | Action |
| :--- | :--- | :--- |
| `Errno::ECONNREFUSED` | `Ai::ConnectionRefusedError` | Retries once, then triggers fallback |
| `Net::ReadTimeout` / `Net::OpenTimeout` | `Ai::TimeoutError` | Retries once, then triggers fallback |
| HTTP 429 | `Ai::RateLimitError` | Retries once, then triggers fallback |
| HTTP 500, 502, 503, 504 | `Ai::ServerError` | Retries once, then triggers fallback |
| HTTP 401, 403 | `Ai::AuthenticationError` | **Fails fast** (no retry, no fallback) |
| HTTP 400 | `Ai::InvalidRequestError` | **Fails fast** (no retry, no fallback) |
| Invalid JSON / Schema mismatch | `Ai::ValidationError` | **Fails fast** (no retry, no fallback) |
| Cloud fallback disabled | `Ai::CloudFallbackDisabledError` | **Fails fast** without contacting cloud |

---

## 4. Auditing & Metadata

Every execution records:
- `provider_name` (`ollama`, `gemini`, `groq`)
- `model_name` (`gemma3:4b`, etc.)
- `inference_duration` (latency in milliseconds)
- `fallback_used` (boolean)
- `fallback_reason` (sanitized failure reason if fallback occurred)
- `retry_count` (number of retry attempts)

Audit events are appended to the immutable `audit_events` table for compliance.
