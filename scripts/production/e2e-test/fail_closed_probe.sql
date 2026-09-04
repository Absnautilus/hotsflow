-- E2E TEST ONLY -- proves the DO $$ ... RAISE EXCEPTION $$; fail-closed
-- mechanism used throughout the PRE-FLIGHT #14 gate scripts
-- (verify_readonly_credential.sql / verify_auth_lookup_view_created.sql)
-- actually makes psql exit non-zero. Replaces the earlier `\quit 1`
-- mechanism, which the real run against the real legacy project
-- (workflow run 33878792799) proved does NOT set psql's process exit
-- code in this runner's psql client -- the job reported success despite
-- an internal FAIL. Deliberately fails on a hardcoded false condition,
-- not a real check against any table or role -- used only by
-- test-gate-mechanism.yml, never referenced by any production script.
\set ON_ERROR_STOP on

select false as ok_dummy \gset
\if :ok_dummy
  \echo 'PASS: unreachable -- this probe is designed to always fail'
\else
  \echo 'FAIL: deliberately-false probe check'
  DO $$
  BEGIN
    RAISE EXCEPTION 'Gate failed: fail_closed_probe (deliberately triggered, not a real check)';
  END
  $$;
\endif

\echo 'UNREACHABLE: the probe should have aborted with a non-zero exit code before this line'
