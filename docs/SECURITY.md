# VAISASTRAM — Security Model & OWASP ASVS Controls

This document specifies the security controls, invariants, threat mitigations, and compliance postures implemented in VAISASTRAM.

---

## 1. Core Security Invariants (Phase 3 & 4)

1. **Zero Autonomous Tool Invocation**: No tool can execute without passing the Ruby Policy Engine.
2. **Deterministic Evaluation**: AI model outputs or self-assessed "risk levels" are ignored by the authorization engine.
3. **No Dynamic Execution**: Tools are dispatched via an explicit Ruby pattern match (`case action_key`). There are no calls to `eval`, `send`, `system`, `exec`, or shell processes.
4. **Fail-Closed Mandate**: Any unexpected error, database disconnection, or unhandled exception in the policy engine defaults to `DENY`.
5. **Exact Action Binding**: Sensitive actions requiring approval generate a SHA-256 fingerprint from:
   $$\text{Fingerprint} = \text{SHA256}(\text{user\_id} \parallel \text{task\_id} \parallel \text{action\_key} \parallel \text{canonical\_json(arguments)})$$
   If arguments are modified post-approval, [`Approvals::FingerprintValidator`](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/app/services/approvals/fingerprint_validator.rb) raises `FingerprintMismatchError`.
6. **Replay & Concurrency Protection**: Approvals transition to `executed` within an isolated PostgreSQL transaction using `SELECT FOR UPDATE`. An approval can never be executed twice.
7. **Segregation of Duties**: Operators who submit a task cannot approve actions for that task. Only designated administrators or unassociated reviewers may approve.
8. **Monetary Decimal Safety**: All financial comparisons use integer paise ($1\text{ INR} = 100\text{ paise}$) via `BigDecimal`. String amounts (e.g. `"10000"`, `"₹10,000"`), NaN, Infinity, negative values, and zero are rejected.
9. **Zero Raw Credential Exposure**: Logs, audit records, and UI telemetry scrub API keys, tokens, and authorization headers.
10. **Replay Sandbox Isolation**: Inspection and simulation replays never invoke live side-effecting code.

---

## 2. OWASP Top 10 & ASVS Mitigations

### A01: Broken Access Control
- Role-based scoping via [`Governance::QueryScope`](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/app/services/governance/query_scope.rb) ensures operators cannot inspect or modify other tenants' tasks, executions, or audit logs.
- Privilege escalation is blocked: `role` is excluded from Devise strong parameters (`devise_parameter_sanitizer`).
- Resource authorization is verified at controller level via `authorize_record_access!`.

### A02: Cryptographic Failures
- Passwords are salted and hashed using BCrypt via Devise with minimum length constraints.
- Session cookies use `HttpOnly`, `SameSite=Lax`, and `Secure` (over HTTPS).
- Audit trails are linked using SHA-256 hash chaining.

### A03: Injection (SQL, Code, Command)
- **SQL Injection**: All Active Record queries use parameterized statements. Raw SQL string interpolations have been eliminated and audited via Brakeman.
- **Code/Command Injection**: The application contains zero shell execution wrappers. Unrecognized actions raise `ExecutionError`.
- **Cross-Site Scripting (XSS)**: Rails ERB templates escape HTML by default. Dynamic code and formulas are rendered inside pre-formatted blocks (`<code>`, `<pre>`).

### A04: Insecure Design
- AI proposals are treated as untrusted data.
- Defense-in-depth:
  1. PlanSchema structural validation
  2. Independent Ruby Policy Engine
  3. Action fingerprinting
  4. Human reviewer gate
  5. Policy revalidation at execution time
  6. Sandboxed tool dispatcher
  7. Append-only cryptographic audit logging

### A05: Security Misconfiguration
- `config.consider_all_requests_local = false` in production (no stack trace disclosure).
- Production `force_ssl` and `assume_ssl` enabled with SSL exclusions strictly for `/up` health check.
- Static assets digest-stamped with far-future caching headers.

### A06: Vulnerable and Outdated Components
- `devise` upgraded to `>= 5.0.4` to patch CVE-2026-32700 and CVE-2026-40295.
- Zero vulnerabilities reported by `bundle audit`.
- Zero warnings reported by `brakeman`.

### A07: Identification and Authentication Failures
- Devise session management with brute-force lockable capabilities and session invalidation upon sign-out.
- ApprovalsController pulls reviewer identity exclusively from the authenticated session (`current_user`).

### A08: Software and Data Integrity Failures
- Immutable `AuditEvent` records fail on update or delete (`before_update { raise ActiveRecord::ReadOnlyRecord }`).
- Cryptographic verification re-computes hashes on-demand to detect direct database tampering.

---

## 3. Static Security Analysis Status

- **Brakeman**: 0 errors, 0 warnings.
- **Bundle Audit**: 0 vulnerabilities.
- **Automated Security Regression Suite**: 13 runs, 37 assertions, 0 failures, 0 errors.
