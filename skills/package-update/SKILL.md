---
name: package-update
description: Review upgradable packages from local apt state; plan safe upgrades.
---

# Package update plan

1. `apt_list_upgradable` (local simulation; may be stale offline)
2. For critical packages, `apt_cache_policy` / `dpkg_list`
3. Present risk notes; do not apply upgrades unless the operator explicitly asks and elevation works
4. If mirrors unreachable, report that clearly — diagnosis from local cache still counts as success
