-- Fase 2 — documents the PMS rewrite in 20260827122100 as what it actually
-- is: an INTENTIONAL SECURITY DEVIATION from legacy behavior, not a
-- behavior-preserving translation like every other wrapper in that
-- migration. The legacy `current_staff_role() not in ('admin','master')
-- then raise` check was silently bypassable by any caller for whom
-- current_staff_role() evaluated to NULL (NULL NOT IN (...) is NULL, falsy
-- in a PL/pgSQL IF) — combined with PUBLIC execute never having been
-- revoked on either function, PMS status (the has_credentials boolean and
-- sync metadata, not the stored secrets themselves) was structurally
-- readable by anon. The has_permission()-based rewrite does not have an
-- equivalent NULL-swallowing path — recorded here as a durable, queryable
-- fact (`\df+`, or pg_description) rather than only in a commit message.

comment on function get_pms_integration_status(uuid) is
  'Fase 2 Step 6: intentional security deviation from legacy behavior, not preservation. '
  'The legacy current_staff_role()-based check silently no-opped for a NULL role (anon), '
  'and PUBLIC execute was never revoked -- PMS status was structurally readable by anon. '
  'Rewritten to require has_permission(property, ''guest_requests.pms.manage''), which has '
  'no such NULL-bypass, and PUBLIC is now explicitly revoked.';

comment on function save_pms_integration(uuid, stay_source, text, text, text, text, text, text) is
  'Fase 2 Step 6: intentional security deviation from legacy behavior, not preservation. '
  'Same latent bug and fix as get_pms_integration_status(uuid) -- see its comment.';
