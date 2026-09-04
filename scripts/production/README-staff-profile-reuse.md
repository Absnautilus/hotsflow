# Staff-profile reuse cutover note

The production cutover can encounter a target Auth identity that is already an established Hotsflow user and already owns a module-local `staff_profiles` row (for example from the demo property).

The migration therefore:

- reuses the existing Auth identity;
- reuses its existing target `staff_profiles.id` instead of violating the unique `auth_user_id` constraint;
- re-homes that module-local staff row to the migrating hotel and synchronizes the legacy module-local fields inside the same transaction;
- remaps staff foreign keys in migrated stays and open guest requests to the reused target staff id;
- preserves legacy staff ids for identities that do not already have a target staff row;
- allows recovery of bare Auth users created by an earlier failed production attempt only when `auth_remap` already proves the exact legacy-to-Auth mapping.

This is intentionally structural and contains no PII.
