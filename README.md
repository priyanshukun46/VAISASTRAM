# VAISASTRAM

> **Autonomy with Accountability**  
> *Core principle: AI proposes. Ruby decides. Humans approve.*

VAISASTRAM is an enterprise-grade platform for **Governed Autonomous AI Agents** built with **Ruby on Rails 8**, **PostgreSQL**, and **Hotwire**.

Unlike typical agent frameworks that delegate authorization decisions or risk self-classification to the language model, VAISASTRAM enforces an independent, deterministic **Ruby Policy Engine** and a cryptographic **Human-in-the-Loop Approval & Audit System**. AI models propose multi-step structured action plans, but execution is gated, authorized, sandboxed, and recorded by independent Ruby code.

---

## Core Tenets

1. **AI Proposes**: Large Language Models (Local Gemma 3 4B via Ollama, Google Gemini 3.8 Flash, Groq Llama 3.3 70B, or OpenRouter fallback) generate structured JSON plans conforming strictly to [`Planning::PlanSchema`](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/app/services/planning/plan_schema.rb). The AI cannot execute code or make policy decisions.
2. **Ruby Decides**: Every proposed tool action is independently evaluated by the [`Policies::Engine`](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/app/services/policies/engine.rb) before any tool can run. Rules are deterministic Ruby code. Unregistered tools, arbitrary shell, SQL, or code execution are hard-denied. Any policy failure fails closed.
3. **Humans Approve**: High-risk actions (e.g. financial payments up to ₹10,000, sensitive data access) trigger human-in-the-loop state. Approvals are cryptographically bound to the exact tool and arguments using SHA-256 fingerprints via [`Approvals::FingerprintValidator`](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/app/services/approvals/fingerprint_validator.rb). Segregation of duties prevents operators from approving their own tasks.
4. **Immutable Audit & Replay**: All state changes, decisions, approvals, and tool executions are serialized into append-only [`AuditEvent`](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/app/models/audit_event.rb) records secured by cryptographic SHA-256 hash chains. Historical executions can be verified via [`Audit::IntegrityVerifier`](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/app/services/audit/integrity_verifier.rb) and inspected or simulated with zero external side effects via [`Replay::ExecutionReplayer`](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/app/services/replay/execution_replayer.rb).

---

## Architecture at a Glance

```
User Prompt -> Agent Planner (Local/Cloud LLM)
                     |
                     v
             Strict PlanSchema Validator
                     |
                     v
          [ Ruby Policy Engine ] (Independent Gate)
         /           |           \
     ALLOW    REQUIRE_APPROVAL   DENY
       |             |             |
       |             v             x [Execution Aborted]
       |      Approval Center
       |      (Human Decision)
       |             |
       +-------> [ APPROVED ] (Fingerprint Revalidation)
                     |
                     v
             Tools::Executor (Sandboxed Dispatch)
                     |
                     v
          Append-Only Audit Chain (SHA-256)
                     |
          Governance Dashboard & Scorecard
```

---

## Technology Stack

- **Framework**: Ruby on Rails 8.1.4 (Modern Propshaft asset pipeline, Turbo 8, Stimulus 3)
- **Database**: PostgreSQL 16 (Solid Cache, Solid Queue, Solid Cable)
- **Styling**: Tailwind CSS v4
- **Authentication**: Devise 5.0.4 with role-based access control (`admin`, `operator`, `auditor`)
- **AI Inference Pipeline**:
  - **Local-first**: Ollama (Gemma 3 4B)
  - **Cloud Primary**: Google Gemini (gemini-3.8-flash)
  - **Cloud Secondary**: Groq (llama-3.3-70b-versatile) / OpenRouter fallback
- **Security & Integrity**:
  - Deterministic Ruby Policy Engine
  - SHA-256 Action Fingerprinting & Hash-Chain Verification
  - Automated 20-case Evaluation Suite with transactional isolation
  - Brakeman (0 warnings) & Bundler Audit (0 CVEs)

---

## Quickstart (Local Development)

### Prerequisites

- Ruby 3.4.6 (`rbenv` or `asdf`)
- PostgreSQL 14+ running locally
- Ollama (optional for local inference; cloud fallback available)

### Setup Steps

```bash
# 1. Clone repository
git clone https://github.com/vaisastram/vaisastram.git
cd vaisastram

# 2. Install dependencies
bundle install

# 3. Setup environment configuration
cp .env.example .env
# Edit .env with your GEMINI_API_KEY or GROQ_API_KEY (or use local Ollama)

# 4. Initialize Database
bin/rails db:prepare
bin/rails db:seed

# 5. Start Development Server
bin/dev
```

Open your browser at `http://localhost:3000`.

### Seed Accounts

| Email | Password | Role | Description |
| :--- | :--- | :--- | :--- |
| `admin@example.com` | `password123` | `admin` | Full system governance, approvals, policy management |
| `one@example.com` | `password123` | `operator` | Task creation and execution within isolated tenant |
| `auditor@example.com` | `password123` | `auditor` | Read-only compliance inspection, verification & replay |

---

## Running the Automated Test Suite

```bash
# Run complete test suite (355+ tests, 0 failures)
bin/rails test

# Run security regression suite
bin/rails test test/security/

# Run end-to-end integration acceptance test
bin/rails test test/integration/governed_execution_acceptance_test.rb

# Run performance benchmarks
bin/rails runner test/benchmarks/governance_performance_benchmark.rb

# Run static security analysis
bundle exec brakeman --no-pager
bundle exec bundle audit
```

---

## Documentation Index

- [Architecture Guide](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/ARCHITECTURE.md)
- [Security Model & Invariants](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/SECURITY.md)
- [Deployment Guide](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/DEPLOYMENT.md)
- [Environment Configuration](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/ENVIRONMENT.md)
- [End-to-End Demonstration Guide](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/DEMO.md)
- [Testing & Evaluation Suite](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/TESTING.md)
- [Known Limitations & Future Scope](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/docs/KNOWN_LIMITATIONS.md)
