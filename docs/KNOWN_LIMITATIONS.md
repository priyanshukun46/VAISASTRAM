# VAISASTRAM — Known Limitations & Operational Considerations

In accordance with Phase 13 and Phase 14 guidelines, this document explicitly details the architectural boundaries, known trade-offs, and operational limitations of the current implementation.

---

## 1. Simulated Financial Disbursal

- **Limitation**: The `prepare_payment` tool generates simulated voucher identifiers (`VCH-...`) rather than transferring real funds through banking APIs.
- **Rationale**: By architectural design and security mandate, VAISASTRAM does not connect to real banking or payment gateway rails in this phase to prevent real-world financial loss during development, evaluation, and demonstration.

---

## 2. Application-Level Immutability & Database Administrator Bounds

- **Limitation**: While `AuditEvent` enforces application-level immutability (`before_update { raise ActiveRecord::ReadOnlyRecord }`) and cryptographically detects tampering via SHA-256 hash chains, a PostgreSQL superuser with direct SQL access could theoretically alter both the event metadata and recompute all downstream SHA-256 hashes.
- **Mitigation**: In high-assurance production environments, the audit log should be mirrored to write-once-read-many (WORM) cloud object storage (e.g. AWS S3 with Object Lock or GCP Cloud Storage Bucket Lock) or an external SIEM.

---

## 3. Local Ollama vs Cloud Hosting

- **Limitation**: Local Ollama instances running on a developer's machine (`localhost:11434`) are not reachable from cloud container runtimes (e.g. AWS ECS, Render, Fly.io, or Kamal hosts) without private mesh networking (e.g. Tailscale or WireGuard).
- **Mitigation**: Production defaults to `AI_PROVIDER_MODE=cloud` using Google Gemini (`gemini-3.8-flash`) and Groq (`llama-3.3-70b-versatile`). Local Ollama inference is retained as the default for local development and self-hosted on-premise deployments.

---

## 4. Single-Chain Advisory Lock Concurrency

- **Limitation**: Sequential audit events within the exact same execution chain are serialized using PostgreSQL transaction-level advisory locks (`pg_advisory_xact_lock`) to guarantee continuous sequence numbering without race conditions.
- **Impact**: While benchmarked at < 0.2ms overhead per event write, heavy concurrent tool invocations within the *same execution* will queue briefly behind the advisory lock. Independent executions and tasks write concurrently across distinct lock keys.

---

## 5. Model Output Parsing Drift

- **Limitation**: Even with strict temperature and JSON schema prompting, local LLMs under high quantization (e.g. 2-bit or small parameters) may occasionally omit top-level keys or return conversational text.
- **Mitigation**: `Planning::PlanNormalizer` automatically strips Markdown code fences and extracts JSON objects, and `Planning::PlanValidator` rejects any non-conformant output before execution, returning clear validation feedback to the user.
