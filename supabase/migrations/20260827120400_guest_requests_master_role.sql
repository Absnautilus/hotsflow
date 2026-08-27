-- Must run alone: Postgres won't let a new enum value be referenced by
-- other statements in the same transaction that added it.
alter type staff_role add value if not exists 'master';
