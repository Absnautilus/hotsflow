# Production recovery state

A failed SQL-phase production attempt may leave `auth_remap` populated and may leave Auth users that were created successfully before the SQL transaction failed. The Auth migration recovery path only reuses such a bare identity when the existing `auth_remap` row matches the exact legacy id and target Auth id. It does not adopt unrelated bare Auth collisions.
