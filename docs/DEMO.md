# VAISASTRAM — Final Demonstration Guide

This guide provides a script for demonstrating VAISASTRAM's capabilities.

**Tagline**: *Autonomy with Accountability.*  
**Core Principle**: *AI proposes. Ruby decides. Humans approve.*

---

## Preparation & Prerequisites

1. Seed the development/demo database:
   ```bash
   bin/rails db:seed
   ```
2. Start the server:
   ```bash
   bin/dev
   ```
3. Open `http://localhost:3000` in a clean browser window.

---

## Demonstration Scenarios

### Demo A — Autonomous Allowed Action (Read-Only)

**Goal**: Demonstrate that low-risk actions execute autonomously without human intervention, while still generating complete audit logs.

1. Sign in as `one@example.com` (Password: `password123`).
2. Navigate to **Agent Workspace** (`/workspace`).
3. Enter instruction:
   ```text
   Retrieve and verify invoice INV-100.
   ```
4. Click **Submit Task**.
5. **Expected Result**:
   - The AI planner generates a plan with `lookup_invoice` and `verify_invoice`.
   - The Ruby Policy Engine evaluates both actions and returns `ALLOW`.
   - Both steps execute automatically through `Tools::Executor`.
   - Execution finishes with status `completed`.
   - In **Audit Center** (`/audit`), two `tool_execution_succeeded` events appear with SHA-256 chain continuity.

---

### Demo B — Sensitive Action Requiring Human-in-the-Loop Approval

**Goal**: Demonstrate that sensitive financial actions are strictly held by Ruby, requiring explicit human authorization.

1. As operator `one@example.com`, submit the canonical demonstration prompt in `/workspace`:
   ```text
   Verify invoice INV-100 and prepare a payment of ₹5,000.
   ```
2. **Expected Result**:
   - The AI generates a 3-step plan:
     1. `lookup_invoice`
     2. `verify_invoice`
     3. `prepare_payment` (`amount: 5000`)
   - Steps 1 and 2 execute automatically (`ALLOW`).
   - Step 3 is evaluated by `Policies::Rules::PaymentLimitRule`: `prepare_payment` for ₹5,000 returns `REQUIRE_APPROVAL`.
   - Execution **pauses immediately**. Step status changes to `waiting_approval`.
   - An approval request appears in the **Approval Center** (`/approvals`).

---

### Demo C — Security & Segregation of Duties

**Goal**: Demonstrate that the operator who initiated the task cannot approve their own payment.

1. Still logged in as `one@example.com`, navigate to **Approval Center** (`/approvals`).
2. Locate the pending approval for `prepare_payment` (₹5,000).
3. Attempt to click **Approve Action**.
4. **Expected Result**:
   - The system displays a red flash alert:
     > *"Segregation of Duties Violation: You cannot approve an action for a task you created."*
   - The action remains safely paused.

---

### Demo D — Authorized Human Review & Resumption

**Goal**: Demonstrate clean resumption upon authorized approval.

1. Sign out of `one@example.com` and sign in as `admin@example.com` (Password: `password123`).
2. Navigate to **Approval Center** (`/approvals`).
3. Inspect the pending ₹5,000 payment voucher approval:
   - Notice the exact SHA-256 fingerprint displayed.
   - Click **Approve Action**.
4. **Expected Result**:
   - The fingerprint is cryptographically verified against the step arguments.
   - The Ruby Policy Engine re-evaluates the action.
   - The simulated voucher is prepared (`VCH-...`).
   - The approval status transitions to `executed`.
   - The task execution status transitions to `completed`.

---

### Demo E — Hard Denied Action (Over-Limit Spending)

**Goal**: Demonstrate deterministic hard denial for actions violating hard security ceilings.

1. In `/workspace`, enter instruction:
   ```text
   Prepare a payment of ₹15,000 for invoice INV-100.
   ```
2. Click **Submit Task**.
3. **Expected Result**:
   - The AI proposes `prepare_payment` with `amount: 15000`.
   - `Policies::Rules::PaymentLimitRule` evaluates ₹15,000 against the ₹10,000 ceiling.
   - Policy returns **`DENY`**.
   - Execution is aborted immediately. Status: `blocked`.
   - No approval is generated. The AI cannot negotiate or override the policy ceiling.

---

### Demo F — Execution Inspection & Simulation Replay

**Goal**: Demonstrate forensic post-incident reconstruction with zero external side effects.

1. Navigate to **Audit Center** (`/audit`) or view the completed execution timeline.
2. Click **Inspection Replay**:
   - Displays the step-by-step state reconstruction as recorded in the immutable audit trail.
3. Click **Simulation Replay**:
   - Re-evaluates each step against the current active policy engine inside an isolated sandbox.
   - Confirms zero external side effects and verifies SHA-256 hash chain validity.

---

### Demo G — Cryptographic Audit Integrity Verification

**Goal**: Demonstrate detection of out-of-band database tampering.

1. Navigate to **Governance Dashboard** (`/governance`), select the **Audit Health** tab.
2. Click **Run Cryptographic Verification**.
3. **Expected Result**:
   - The system re-hashes all historical events sequentially using stored previous hashes.
   - Shows badge: `Verified (Intact)` with 0 broken chains and 0 tampered events.
