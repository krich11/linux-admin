---
name: disk-pressure
description: Investigate disk pressure using local df and related signals.
---

# Disk pressure

1. `disk_df`
2. Note full or near-full mount points
3. Suggest safe local cleanups (journal vacuum, apt cache) — stage commands; elevate only with approval
4. Optional: correlate with `journal_since` if log spam suspected
