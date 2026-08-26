-- PostgreSQL grants EXECUTE to PUBLIC on every function by default at
-- CREATE FUNCTION time — a later `GRANT EXECUTE ... TO authenticated` does
-- not remove that. Every SECURITY DEFINER function in this project (0006,
-- 0010) has therefore been callable by `anon` this whole time, silently.
-- This migration is the fix: explicit REVOKE ALL FROM PUBLIC on each one,
-- then only the grants actually intended.
--
-- validate_membership_role_scope (0008) is deliberately not included here:
-- it's a trigger function (returns trigger), not SECURITY DEFINER, and
-- Postgres refuses to invoke a trigger function directly outside a trigger
-- context regardless of grants — there's nothing a PUBLIC grant on it could
-- do.

revoke all on function has_property_access(uuid) from public;
revoke all on function has_organization_access(uuid) from public;
revoke all on function has_permission(uuid, text) from public;
revoke all on function has_organization_permission(uuid, text) from public;
revoke all on function has_module(uuid, text) from public;
revoke all on function guest_session_is_valid(uuid, uuid, smallint) from public;

revoke all on function current_actor_role_rank(uuid) from public;
revoke all on function current_actor_role_rank_for_organization(uuid) from public;
revoke all on function role_assignment_allowed(uuid, uuid, uuid, uuid) from public;
revoke all on function assign_membership_role(uuid, uuid) from public;

-- Re-grant only what's actually needed. The five staff-facing helpers go to
-- `authenticated` (0006/0010 already did this, restated here so this
-- migration is a complete, self-contained statement of intent — re-running
-- these GRANTs is harmless).
grant execute on function has_property_access(uuid) to authenticated;
grant execute on function has_organization_access(uuid) to authenticated;
grant execute on function has_permission(uuid, text) to authenticated;
grant execute on function has_organization_permission(uuid, text) to authenticated;
grant execute on function has_module(uuid, text) to authenticated;
grant execute on function current_actor_role_rank(uuid) to authenticated;
grant execute on function current_actor_role_rank_for_organization(uuid) to authenticated;
grant execute on function role_assignment_allowed(uuid, uuid, uuid, uuid) to authenticated;
grant execute on function assign_membership_role(uuid, uuid) to authenticated;

-- guest_session_is_valid gets NO grant at all — not even to `authenticated`
-- — until Fase 2 introduces an actual guest-facing flow that needs it.
-- 0006 had granted it to `authenticated`; REVOKE ALL FROM PUBLIC above does
-- NOT undo that (PUBLIC and authenticated are different grantees — this is
-- exactly the kind of gap this migration exists to close, and testing this
-- migration by hand is what caught it: `authenticated` could still call it
-- and get a real answer, `f`, without ever hitting a permission error).
-- Explicit revoke from authenticated too, so it's unreachable from any
-- client role, exactly as intended. When a future guest-verification
-- function is written, it can call guest_session_is_valid() from inside its
-- own SECURITY DEFINER body without needing any grant of its own on it — a
-- SECURITY DEFINER function runs as its owner, and an owner's own
-- privileges on its own objects are never affected by a revoke targeting a
-- different role.
revoke all on function guest_session_is_valid(uuid, uuid, smallint) from authenticated;
