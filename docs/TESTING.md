# VAISASTRAM — Testing & Evaluation Guide

This document describes the testing strategy, test suites, static analysis tools, and automated evaluation framework in VAISASTRAM.

---

## 1. Test Suite Structure

| Suite | File Path | Focus |
| :--- | :--- | :--- |
| **Deterministic Evaluation** | `test/services/evaluations/evaluator_test.rb` | 20 canonical cases covering Policy (TC-01..08), Human-in-the-Loop (TC-09..14), Execution & Replay (TC-15..20). Runs in transactional rollback. |
| **Autonomous Agent Security** | `test/security/autonomous_agent_security_test.rb` | 13 regression tests verifying that AI cannot bypass policy, approve own actions, tamper arguments, execute shell/Ruby/SQL, or reuse expired approvals. |
| **End-to-End Acceptance** | `test/integration/governed_execution_acceptance_test.rb` | Complete lifecycle of "Verify invoice INV-100 and prepare payment of ₹5,000", ₹15k rejection, and audit tampering detection. |
| **Governance Metrics & Scorecard** | `test/services/governance/metrics_test.rb` | Mathematical scorecard accuracy, zero-divide handling (`Unavailable`), failure categorization. |
| **Query Scoping & Isolation** | `test/services/governance/query_scope_test.rb` | Tenant isolation: admin/auditor vs operator restrictions and date filtering. |
| **Controllers & UI** | `test/controllers/governance_controller_test.rb`, `evaluations_controller_test.rb` | Auth requirements, Turbo Streams, JSON endpoints. |

---

## 2. Running Test Commands

### Run All Unit, Service, Controller & Integration Tests

```bash
bin/rails test
```

### Run Dedicated Security Regression Suite

```bash
bin/rails test test/security/autonomous_agent_security_test.rb
```

### Run Static Security & Vulnerability Analysis

```bash
# Brakeman AST security scanner
bundle exec brakeman --no-pager

# Bundler audit against ruby-advisory-db
bundle exec bundle audit
```

### Run Performance Benchmarks

```bash
bin/rails runner test/benchmarks/governance_performance_benchmark.rb
```

---

## 3. Evaluation Suite (20 Canonical Cases)

The evaluation suite runs programmatically via [`Evaluations::Evaluator.run`](file:///Users/priyanshukumar/RailsApps/VAISASTRAM/app/services/evaluations/evaluator.rb) or via the UI at `/governance?tab=evaluations` and `/evaluations`.

- **Isolation**: Runs inside an `ActiveRecord::Base.transaction` that raises `ActiveRecord::Rollback` on completion. Zero records are left behind in the database.
- **Pass Rate**: 20 of 20 test cases pass (100.0% pass rate in < 250ms).
