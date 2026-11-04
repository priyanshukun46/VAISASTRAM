# RedBus Fare & Ticket Inspector — MCP Integration Guide

> **VAISASTRAM Model Context Protocol (MCP) Integration**  
> *Specification Version: 2024-11-05*  
> *Principle: AI proposes. Ruby decides. Humans approve.*

---

## 1. Overview

The **RedBus Fare & Ticket Inspector** is a dedicated Model Context Protocol (MCP) server designed for VAISASTRAM to provide real-time bus ticket search, route pricing breakdown, seat layout inspection, and fare estimation across major intercity Indian routes.

Like all tools in VAISASTRAM, this MCP integration operates under strict **Ruby Policy Engine Governance**:
- An autonomous AI agent can propose querying ticket prices or searching bus routes.
- The Ruby Policy Engine validates whether the tool is enabled and whether approval is required.
- Tool executions are sandboxed with zero shell interpolation, and every query is cryptographically chained in the SHA-256 audit ledger.

---

## 2. Server Specifications

| Attribute | Specification |
| :--- | :--- |
| **Server Identifier** | `redbus` |
| **Transport Type** | Local STDIO Subprocess |
| **Command** | `ruby` |
| **Arguments** | `["bin/mcp-redbus-server"]` |
| **Protocol Specification** | MCP `2024-11-05` (JSON-RPC 2.0) |
| **Execution Sandboxing** | Open3 process isolation without shell interpolation |
| **Tool Namespace** | `mcp.redbus.<tool_name>` |

---

## 3. Discovered Tool Catalog

Upon registration and tool discovery, the following tools are exposed:

### 1. `mcp.redbus.search_bus_routes`
Searches available bus schedules, operator ratings, departure/arrival times, durations, and starting ticket prices.

- **Parameters**:
  - `source` *(string, required)*: Departure city (e.g. `"Bangalore"`, `"Delhi"`, `"Mumbai"`, `"Hyderabad"`, `"Pune"`, `"Chennai"`).
  - `destination` *(string, required)*: Arrival city (e.g. `"Hyderabad"`, `"Jaipur"`, `"Goa"`, `"Manali"`).
  - `travel_date` *(string, optional)*: Date of journey in `YYYY-MM-DD` format (defaults to tomorrow).
  - `ac_only` *(boolean, optional)*: Filter for Air-Conditioned buses only (default: `false`).

### 2. `mcp.redbus.get_ticket_price`
Returns an exact ticket fare breakdown with itemized base fare, operator discount, passenger GST (5%), platform fees, and live surge pricing.

- **Parameters**:
  - `source` *(string, required)*: Origin city.
  - `destination` *(string, required)*: Destination city.
  - `bus_operator` *(string, optional)*: Preferred operator (e.g. `"IntrCity SmartBus"`, `"Zingbus"`, `"KSRTC"`, `"VRL Travels"`).
  - `seat_category` *(string, optional)*: `"seater"`, `"semi_sleeper"`, `"single_sleeper"`, or `"double_sleeper"`.

### 3. `mcp.redbus.check_seat_layout`
Inspects lower and upper berth layouts, available single window berths, aisle seats, and female-reserved seat status.

- **Parameters**:
  - `source` *(string, required)*: Departure city.
  - `destination` *(string, required)*: Arrival city.
  - `operator` *(string, optional)*: Bus operator name.

### 4. `mcp.redbus.estimate_route_fare`
Calculates expected price bands across budget non-AC, executive AC, and luxury Volvo 9600 sleeper categories for any distance.

- **Parameters**:
  - `source` *(string, required)*: Departure city.
  - `destination` *(string, required)*: Arrival city.

---

## 4. Web UI Registration (1-Click Template)

1. Open the VAISASTRAM dashboard and click **MCP Servers** in the top navigation bar (`/mcp_servers`).
2. Scroll to the **MCP Marketplace Directory** section.
3. Locate the **RedBus Fare & Ticket Inspector** card and click **Use Template**.
4. The registration wizard pre-populates the required fields:
   - **Name:** `RedBus Fare & Ticket Inspector`
   - **Slug Identifier:** `redbus`
   - **Transport Type:** `Local STDIO Subprocess`
   - **Command:** `ruby`
   - **Arguments:** `bin/mcp-redbus-server`
5. Click **Create & Connect MCP Server**.
6. On the server details page, click **Discover Tools**.

---

## 5. Security & Governance Policy Setup

Under VAISASTRAM's security invariants, discovered tools initially default to **`disabled`** and **`deny`**.

### Recommended Policy Configuration:
- **`mcp.redbus.search_bus_routes`**:
  - State: **Enabled**
  - Policy Decision: **`allow`**
  - Risk Level: **`low`** (Read-only data query)
- **`mcp.redbus.get_ticket_price`**:
  - State: **Enabled**
  - Policy Decision: **`allow`**
  - Risk Level: **`low`** (Read-only pricing query)
- **`mcp.redbus.check_seat_layout`**:
  - State: **Enabled**
  - Policy Decision: **`allow`**
  - Risk Level: **`low`** (Read-only layout query)
- **Modifying / Booking Actions** (Future Phase):
  - Must be assigned Policy Decision **`require_approval`** and Risk Level **`high`**, requiring cryptographic human approval prior to payment disbursement.

---

## 6. Example Workspace Queries

Once enabled, operators can ask natural language questions in the **Agent Workspace**:

```
"What is the ticket price for a Volvo AC sleeper bus from Bangalore to Hyderabad tomorrow on RedBus?"
```

**Proposed Agent Plan**:
```json
{
  "mode": "action_plan",
  "goal": "Retrieve ticket price breakdown for Bangalore to Hyderabad Volvo AC sleeper bus",
  "response": "I have prepared an action plan to query the RedBus Fare & Ticket Inspector for pricing between Bangalore and Hyderabad.",
  "steps": [
    {
      "step_number": 1,
      "action": "mcp.redbus.get_ticket_price",
      "arguments": {
        "source": "Bangalore",
        "destination": "Hyderabad",
        "seat_category": "single_sleeper"
      },
      "description": "Fetch live fare breakdown, taxes, and operator discounts on RedBus"
    }
  ]
}
```

**Execution Result**:
```
=== REDBUS FARE BREAKDOWN: Bangalore -> Hyderabad ===
Operator: IntrCity SmartBus
Seat Category: Single Sleeper
Distance: 570 km

• Base Ticket Fare:        ₹1,405
• Operator Online Discount: -₹112
• GST (5% Passenger Tax):   +₹70.25
• Platform Service Charge:  +₹25.0
----------------------------------------
TOTAL TICKET PRICE:        ₹1,388 (INR)

Live Fare Assurance: Locked for 15 minutes during booking reservation.
```

---

## 7. Testing

The RedBus MCP server includes end-to-end integration test coverage:

```bash
# Run RedBus MCP integration suite
bin/rails test test/services/mcp/redbus_integration_test.rb

# Verify all MCP servers
bin/rails test test/models/mcp* test/services/mcp* test/controllers/mcp*
```
