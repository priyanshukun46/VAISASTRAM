# VAISASTRAM

> **Autonomy with Accountability**  
> *Core Principle: AI proposes. Ruby decides. Humans approve.*

[![Ruby on Rails](https://img.shields.io/badge/Ruby_on_Rails-8.1.4-CC0000.svg?style=flat&logo=ruby-on-rails)](https://rubyonrails.org)
[![Ruby](https://img.shields.io/badge/Ruby-3.4.6-CC342D.svg?style=flat&logo=ruby)](https://www.ruby-lang.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1.svg?style=flat&logo=postgresql)](https://www.postgresql.org)
[![Tailwind CSS](https://img.shields.io/badge/Tailwind_CSS-v4-38B2AC.svg?style=flat&logo=tailwind-css)](https://tailwindcss.com)
[![MCP Protocol](https://img.shields.io/badge/MCP_Protocol-2024--11--05-7C5CFC.svg?style=flat)](https://modelcontextprotocol.io)
[![Brakeman](https://img.shields.io/badge/Security-0_Warnings-success.svg?style=flat)](https://brakemanscanner.org)
[![Test Suite](https://img.shields.io/badge/Tests-426_Passing-brightgreen.svg?style=flat)]()

---

## Executive Summary

**VAISASTRAM** is an enterprise-grade platform for **Governed Autonomous AI Agents** engineered with **Ruby on Rails 8**, **PostgreSQL**, and **Hotwire**.

Unlike typical agent frameworks that delegate authorization decisions or risk self-classification to an untrusted language model, VAISASTRAM enforces an **independent, deterministic Ruby Policy Engine**, a cryptographic **Human-in-the-Loop Approval System**, and a dynamic **Model Context Protocol (MCP) Server Manager**.

Large language models (OpenAI GPT, Google Gemini, xAI Groq, or local Ollama) propose multi-step structured action plans. However, execution is strictly gated, authorized, sandboxed, and recorded by independent Ruby code.

---

## Table of Contents

- [Core Principles](#core-principles)
- [Architecture & Governance Flow](#architecture--governance-flow)
- [Key Features](#key-features)
  - [1. Multi-Provider AI Planning](#1-multi-provider-ai-planning)
  - [2. Independent Ruby Policy Engine](#2-independent-ruby-policy-engine)
  - [3. Human Approval System & Cryptographic Binding](#3-human-approval-system--cryptographic-binding)
  - [4. Dynamic MCP Marketplace & Server Manager](#4-dynamic-mcp-marketplace--server-manager)
  - [5. Cryptographic SHA-256 Audit Trail & Replay](#5-cryptographic-sha-256-audit-trail--replay)
  - [6. Governance Dashboard & Evaluation Suite](#6-governance-dashboard--evaluation-suite)
- [Technology Stack](#technology-stack)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation & Setup](#installation--setup)
  - [Environment Variables](#environment-variables)
  - [Default Seed Accounts](#default-seed-accounts)
- [Model Context Protocol (MCP) Integration](#model-context-protocol-mcp-integration)
- [Automated Testing & Security Verification](#automated-testing--security-verification)
- [Project Directory Layout](#project-directory-layout)
- [Documentation Index](#documentation-index)
- [License](#license)

---

## Core Principles

1. **AI Proposes**: LLMs generate structured JSON plans adhering strictly to [`Planning::PlanSchema`](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/app/services/planning/plan_schema.rb). The AI model has zero direct execution permissions and can never authorize its own proposed actions.
2. **Ruby Decides**: Every proposed tool action is independently evaluated by the [`Policies::Evaluator`](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/app/services/policies/evaluator.rb) before any tool can execute. Policy rules are deterministic Ruby code. Unregistered tools, path traversal, arbitrary shell, and SQL queries are hard-denied. Policy failures fail-closed.
3. **Humans Approve**: Modifying actions or spending exceeding policy thresholds trigger human-in-the-loop review. Approvals are cryptographically bound to the exact tool, arguments, user, server configuration version, and schema hash using SHA-256 fingerprints via [`Approvals::FingerprintValidator`](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/app/services/approvals/fingerprint_validator.rb).
4. **Accountability via Hash-Chaining**: All proposals, policy decisions, approvals, and tool outputs are serialized into append-only [`AuditEvent`](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/app/models/audit_event.rb) records linked by a SHA-256 cryptographic hash-chain.

---

## Architecture & Governance Flow

```
User Prompt (Workspace)
          │
          ▼
 Agent Planner (OpenAI / Gemini / Groq / Ollama)
          │
          ▼
 Strict PlanValidator (JSON Schema & Allowed Tools Verification)
          │
          ▼
 [ Ruby Policy Engine ] (Independent Authorization Gate)
  ├── Sensitive Operations Rule (Hard-block rm, shell, SQL)
  ├── User Role & Tenant Isolation Rule
  ├── Domain Tool Allowlist Rule
  ├── MCP Tool Policy Rule (Server/Tool active & policy check)
  └── Spending Threshold Rule (> ₹10k Auto-Blocked, ₹1k–₹10k Approval)
          │
          ├── [ DENY ] ───────────────► Execution Aborted & Audited
          │
          ├── [ REQUIRE_APPROVAL ] ───► Approval Center (Human Review)
          │                                 │
          │                                 ├── [ REJECTED ] ─► Execution Stopped
          │                                 └── [ APPROVED ] ─► Fingerprint Revalidation
          │                                                          │
          ▼                                                          ▼
 [ ALLOW / APPROVED ] ───────────────────────────────────────────────┘
          │
          ▼
 Tools::Executor (Sandboxed Tool Dispatch)
  ├── Built-in Domain Tools (lookup_invoice, verify_invoice, prepare_payment)
  └── MCP Client Protocol Dispatch (mcp.<server_slug>.<tool_name>)
          │
          ▼
 Append-Only Cryptographic Audit Log (SHA-256 Hash Chain)
          │
          ▼
 Governance Dashboard (Real-time Analytics, Health & Scorecard)
```

---

## Key Features

### 1. Multi-Provider AI Planning
- **Supported Providers**:
  - **OpenAI**: `gpt-4o`, `gpt-4o-mini`, `gpt-3.5-turbo`
  - **Google Gemini**: `gemini-3.8-flash`, `gemini-2.5-pro`
  - **Groq**: `llama-3.3-70b-versatile`, `mixtral-8x7b-32768`
  - **xAI**: `grok-beta`
  - **Local Ollama**: `gemma3:4b`, `llama3:latest`
  - **In-Browser Local**: Client-directed inference
- **Dual Mode Output**:
  - `conversation`: Informational dialogues, creative responses, concept explanations with prospective language assurance. Zero tools executed.
  - `action_plan`: Structured tool execution proposals for allowlisted tools only.
- **Failover Routing**: Automatic fallback from local to cloud providers or secondary cloud fallback with full audit logging.

### 2. Independent Ruby Policy Engine
- **Fail-Closed Design**: If an error occurs during policy evaluation, the action is automatically blocked under fail-closed security invariants.
- **Priority Rules Hierarchy**:
  1. `SensitiveOperationRule` (Priority 1): Hard blocks system deletion, arbitrary shell commands, SQL injection, and database destruction.
  2. `UserPermissionRule` (Priority 5): Enforces role boundaries (`admin`, `operator`, `auditor`).
  3. `ToolPermissionRule` (Priority 10): Validates tools against agent allowlists.
  4. `McpToolPolicyRule` (Priority 15): Evaluates dynamic MCP servers and tool permissions (`allow`, `require_approval`, `deny`).
  5. `PaymentLimitRule` (Priority 25): Monetary safeguards (amounts $\le$ ₹1,000 auto-allow; ₹1,001–₹10,000 require human approval; $>$ ₹10,000 hard deny).

### 3. Human Approval System & Cryptographic Binding
- **Action Fingerprinting**: Approvals are bound using SHA-256 fingerprints calculated over the user ID, task ID, action key, and normalized arguments.
- **Segregation of Duties**: Operators cannot approve their own requested tasks.
- **Configuration & Schema Invalidation**: If an MCP server's configuration version changes or a tool's schema drifts before execution, prior approvals are invalidated.

### 4. Dynamic MCP Marketplace & Server Manager
- **Official Specification**: Fully compliant with **Model Context Protocol (MCP) 2024-11-05**.
- **Supported Transports**:
  - **Local STDIO Subprocesses**: Process isolation using `Open3.popen3` with array arguments (no shell interpolation), executable allowlists (`npx`, `node`, `python3`, `ruby`, `uvx`, `deno`, `bun`, `wordcraft`), and separate stderr capture.
  - **Streamable HTTP**: Remote endpoints over HTTPS with Server-Sent Events (SSE) streaming and 5MB payload limits.
- **SSRF Guard**: Strict inspection blocking loopback (`127.0.0.0/8`, `::1`), RFC 1918 private IPv4 (`10/8`, `172.16/12`, `192.168/16`), link-local (`169.254/16`, `fe80::/10`), and cloud metadata IP addresses (`169.254.169.254`).
- **Dynamic Tool Discovery**: Discovered tools default to `disabled` and `deny`.
- **Zero Plaintext Secrets**: Uses **Active Record Encryption** for environment variables and authentication tokens.

### 5. Cryptographic SHA-256 Audit Trail & Replay
- Every lifecycle event is recorded with an incremental index, actor metadata, payload digest, and parent hash.
- **Live Verification**: Cryptographic verification ensures zero undetected insertions, deletions, or tamperings.
- **Simulation Replay**: Historical executions can be inspected or re-simulated with sandboxed mock dispatches.

### 6. Governance Dashboard & Evaluation Suite
- **Scorecard & Analytics**: Comprehensive visibility into execution success rates, policy distributions, approval latencies, and provider reliability.
- **Automated 20-Scenario Evaluation Suite**: Measures compliance across conversational inquiries, domain financial operations, missing-information scenarios, and unplannable prohibited actions.

---

## Technology Stack

| Layer | Technologies |
| :--- | :--- |
| **Backend Framework** | Ruby on Rails 8.1.4, Ruby 3.4.6 |
| **Database** | PostgreSQL 16 (Active Record, Solid Queue, Solid Cache, Solid Cable) |
| **Frontend & UI** | Hotwire (Turbo 8, Stimulus 3), Tailwind CSS v4, Heroicons |
| **Authentication & Auth** | Devise 5.0.4, Role-Based Access Control (`admin`, `operator`, `auditor`) |
| **Security & Cryptography** | Active Record Encryption, OpenSSL SHA-256 Chaining, Brakeman |
| **Protocol Integration** | Model Context Protocol (MCP) 2024-11-05 (STDIO & Streamable HTTP) |
| **AI Providers** | OpenAI, Google Gemini, Groq, xAI Groq, Ollama |

---

## Getting Started

### Prerequisites

- **Ruby**: Version `3.4.6`
- **PostgreSQL**: Version `14+` running locally
- **Node.js & npm** (optional, for local MCP servers like WordCraft)
- **Ollama** (optional, for local offline AI inference)

### Installation & Setup

```bash
# 1. Clone repository
git clone https://github.com/vaisastram/vaisastram.git
cd vaisastram

# 2. Install Ruby gems
bundle install

# 3. Configure environment variables
cp .env.example .env

# 4. Prepare database and seed data
bin/rails db:prepare
bin/rails db:seed

# 5. Build assets and launch development server
bin/dev
```

Visit [`http://localhost:3000`](http://localhost:3000) in your browser.

---

### Environment Variables

Configure `.env` with your desired AI provider credentials:

```bash
# Inference Mode: "cloud", "hybrid" (local-first with cloud fallback), or "local"
AI_INFERENCE_MODE=cloud

# Primary Cloud Provider: "openai", "gemini", or "groq"
AI_PRIMARY_PROVIDER=gemini
AI_FALLBACK_PROVIDER=groq
AI_FALLBACK_ENABLED=true

# Google Gemini
GEMINI_API_KEY=your_gemini_api_key
GEMINI_MODEL=gemini-3.8-flash

# Groq
GROQ_API_KEY=your_groq_api_key
GROQ_MODEL=llama-3.3-70b-versatile

# OpenAI (Optional)
OPENAI_API_KEY=your_openai_api_key
OPENAI_MODEL=gpt-4o

# xAI / Grok (Optional)
XAI_API_KEY=your_xai_api_key
XAI_MODEL=grok-beta

# Ollama (Local)
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=gemma3:4b
```

---

### Default Seed Accounts

The database seed provides pre-configured role-based credentials:

| Email | Password | Role | Capabilities |
| :--- | :--- | :--- | :--- |
| `admin@vaisastram.internal` | `vaisastram2026` | `admin` | Full system administration, policy overrides, all approvals |
| `admin@example.com` | `password123` | `admin` | Secondary administrator |
| `one@example.com` | `password123` | `operator` | Agent task planning, execution, and tenant-scoped servers |
| `auditor@example.com` | `password123` | `auditor` | Read-only compliance review, audit verification & replay |

---

## Model Context Protocol (MCP) Integration

VAISASTRAM includes a first-class **MCP Marketplace & Dynamic Server Manager**:

1. Navigate to **MCP Servers** (`/mcp_servers`).
2. Click **Add MCP Server** or pick a template:
   - **RedBus Fare & Ticket Inspector** (`stdio`, `ruby bin/mcp-redbus-server`)
   - **WordCraft Document Engine** (`stdio`, `npx -y wordcraft mcp`)
   - **Global Weather Service** (`streamable_http`, remote HTTPS)
   - **Governed File Inspector** (`stdio`, filesystem inspection)
   - **Database Schema Inspector** (`stdio`, read-only metadata)
3. Click **Discover Tools** to introspect server capabilities.
4. Manage per-tool permissions: toggle enabled/disabled, set policy (`allow`, `require_approval`, `deny`), and adjust risk classification.

For integration guides, see:
- [RedBus MCP Integration Guide](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/REDBUS_MCP_INTEGRATION.md)
- [WordCraft MCP Integration Guide](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/WORDCRAFT_INTEGRATION.md)

---

## Automated Testing & Security Verification

VAISASTRAM maintains strict test coverage with mock transports and isolated transactions:

```bash
# Run complete test suite (426 tests, 2,000+ assertions, 0 failures)
bin/rails test

# Run MCP integration and governance tests
bin/rails test test/models/mcp* test/services/mcp* test/controllers/mcp*

# Run security regression suite
bin/rails test test/security/

# Run static application security analysis (0 warnings)
bundle exec brakeman --no-pager

# Run dependency vulnerability audit
bundle exec bundle audit
```

---

## Project Directory Layout

```
├── app/
│   ├── controllers/            # Devise auth, workspace, governance, MCP controllers
│   ├── helpers/                # SVG branding, markdown formatters, status badges
│   ├── models/                 # McpServer, McpTool, Task, Execution, AgentStep, Approval, AuditEvent
│   ├── services/
│   │   ├── ai/                 # Multi-provider routers (OpenAI, Gemini, Groq, Ollama, xAI)
│   │   ├── approvals/          # FingerprintValidator, ExpirationService, Approvals::Service
│   │   ├── audit/              # EventSchema, Recorder, IntegrityVerifier
│   │   ├── evaluations/        # 20-case EvaluationSuite, Evaluator, Report generators
│   │   ├── governance/         # Metrics, analytics, scorecard calculations
│   │   ├── mcp/                # ProtocolClient, StdioTransport, StreamableHttpTransport, SsrfGuard
│   │   ├── planning/           # AgentPlanner, PlanValidator, PlanNormalizer, PlanSchema
│   │   ├── policies/           # Evaluator, Context, Fingerprint, Rules hierarchy
│   │   └── tools/              # Sandboxed Executor, registry dispatch
│   └── views/                  # Hotwire Turbo/Tailwind responsive interface
├── config/                     # Routes, deploy configuration, encryption initializers
├── db/                         # Migrations and seed configurations
├── docs/                       # Architecture, security, demo, deployment, WordCraft docs
└── test/                       # Comprehensive unit, controller, integration, and security test suite
```

---

## Documentation Index

- [Architecture Guide](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/ARCHITECTURE.md)
- [Security Model & Invariants](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/SECURITY.md)
- [RedBus MCP Integration](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/REDBUS_MCP_INTEGRATION.md)
- [WordCraft MCP Integration](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/WORDCRAFT_INTEGRATION.md)
- [Deployment & Docker Guide](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/DEPLOYMENT.md)
- [Environment Configuration Guide](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/ENVIRONMENT.md)
- [End-to-End Demonstration Script](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/DEMO.md)
- [Testing & Benchmark Methodology](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/TESTING.md)
- [Known Limitations](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/KNOWN_LIMITATIONS.md)

---

## License

VAISASTRAM is distributed under the **Apache 2.0 License**. See `LICENSE` for details.
