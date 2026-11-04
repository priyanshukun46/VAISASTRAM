# VAISASTRAM — WordCraft MCP Server Integration Guide

This guide describes how to connect **WordCraft** (an open-source AI document engine) to VAISASTRAM using the Model Context Protocol (MCP) STDIO transport, with independent Ruby policy enforcement and human-in-the-loop approvals.

---

## 1. Overview

- **Upstream Repository**: [https://github.com/storytold/wordcraft](https://github.com/storytold/wordcraft)
- **Protocol**: Model Context Protocol (MCP 2024-11-05 standard JSON-RPC 2.0).
- **Transport**: Local STDIO subprocess.
- **VAISASTRAM Policy Mandate**:
  - Read-only queries (`inspect_document`, `list_commands`, `render_page`) are evaluated as **LOW RISK** and can be set to `ALLOW`.
  - Mutating operations (`modify_document`, `save_document`, `delete_page`, `write_section`) are classified as **HIGH RISK** and require **HUMAN APPROVAL**.
  - All unreviewed or unknown discovered commands default to **DENY**.

---

## 2. Prerequisites

Ensure Node.js (v18+) is installed on your local host:

```bash
node -v
npm -v
```

---

## 3. Registering WordCraft in the VAISASTRAM UI

1. Navigate to **MCP Servers** (`/mcp_servers`) in the navigation bar.
2. Under **MCP Marketplace Directory**, click **Install Server** on the **WordCraft Document Engine** card (or click **Add MCP Server**).
3. The wizard will pre-populate the following verified settings:
   - **Server Name**: `WordCraft Document Engine`
   - **Identifier**: `wordcraft`
   - **Transport**: `Local STDIO Subprocess`
   - **Command**: `npx`
   - **Arguments**: `-y wordcraft mcp`
   - **Connection Timeout**: `15` seconds
   - **Request Timeout**: `30` seconds
   - **Enabled in Governance Engine**: Checked
4. Click **Save MCP Server**.

---

## 4. Tool Discovery & Permission Configuration

Once connected:

1. Click **Discover Tools** on the WordCraft server page.
2. The MCP client performs the initialization handshake (`initialize` -> `notifications/initialized`) and queries `tools/list`.
3. Discovered tools are saved with namespaced keys:
   - `mcp.wordcraft.inspect_document`
   - `mcp.wordcraft.list_commands`
   - `mcp.wordcraft.render_page`
   - `mcp.wordcraft.modify_document`
4. Under **Ruby Governance Matrix**:
   - For `inspect_document`, `list_commands`, `render_page`: select **Allow (No gate)** and click **Authorize & Enable**.
   - For `modify_document`: select **Require Human Approval**, set risk to **High Risk**, and click **Authorize & Enable**.
   - Leave any untrusted administrative tools as **DENY** and **DISABLED**.

---

## 5. Governed Execution Walkthrough

When an operator in the Agent Workspace requests:

> *"Inspect the meeting summary document in docs/summary.md and prepare revisions for section 2."*

1. **AI Planner**: Proposes step 1 (`mcp.wordcraft.inspect_document`) and step 2 (`mcp.wordcraft.modify_document`).
2. **Ruby Policy Engine**:
   - Step 1 matches `mcp.wordcraft.inspect_document` (configured `ALLOW`) -> Proceeds immediately.
   - Step 2 matches `mcp.wordcraft.modify_document` (configured `REQUIRE_APPROVAL`) -> Policy engine triggers `require_approval`.
3. **Execution Paused**: Execution status transitions to `paused`. An approval record is created with a cryptographic action fingerprint binding user, document path, server version, and schema hash.
4. **Human Review**: The operator inspects the proposed diff in the **Approval Center** (`/approvals`).
5. **Resumption**: Upon clicking **Approve**, `Tools::Executor` verifies the action fingerprint, confirms the server configuration has not drifted, and dispatches the call to WordCraft's STDIO subprocess.
6. **Audit Trail**: Every handshake, tool discovery, policy evaluation, and tool invocation is recorded with cryptographic SHA-256 chaining.
