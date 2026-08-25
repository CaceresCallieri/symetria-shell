---
name: Wait for subagents before compiling reports
description: When dispatching subagents for analysis (tech-debt, code-review, etc.), never generate the report until ALL agents have returned. Don't duplicate agent work with parallel direct searches.
type: feedback
---

When using subagents for analysis tasks (like /tech-debt modules), wait for ALL agents to complete before generating the final report. Do not compile the report early based on your own parallel searches.

**Why:** During a /tech-debt run, 4 background agents were dispatched for Security, Performance, Code Quality, and Architecture. While they ran, the main agent duplicated their work with direct Grep/Read searches and output the full report before agents returned. The agents' findings (which included unique items not found by the main agent) were effectively wasted. The user correctly identified that the report didn't incorporate agent results.

**How to apply:**
1. Dispatch subagents for heavy modules (Security, Performance, Code Quality, Architecture)
2. Run only lightweight/non-overlapping modules directly (Docs, Infra, Deps, Tests)
3. Do NOT grep for the same patterns the agents are searching — that's duplicated work
4. When all agents return, MERGE their findings with your direct results into a single report
5. Only then calculate scores and output the final report
