---
name: Use multiple measurements for benchmarks
description: Shell startup timing is non-deterministic — single measurements are unreliable, must use 3+ runs
type: feedback
---

Never draw conclusions from a single timing measurement. Startup times vary significantly between runs (observed 20s-61s range for identical code on the same system within the same session).

**Why:** The user explicitly corrected this approach. Factors like CPU thermal state, system load, background processes, and Qt/QML internal state cause variance. Basing an entire debugging session on single-point comparisons led to wrong conclusions repeatedly.

**How to apply:** For every benchmark configuration, run 3+ times. Report min/median/max. Only compare medians between configurations. Flag any measurement >2x the median as likely contaminated.
