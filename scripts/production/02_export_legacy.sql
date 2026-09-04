-- Production migration -- EXPORT, legacy side. Generates literal `insert
-- into legacy_source.*` statements as psql OUTPUT ROWS (not narration) --
-- the orchestrator MUST redirect this file's run to a local file (`psql
-- ... -o "$WORKDIR/import.sql"`), never let it print to stdout/the job
-- log. Requires -v legacy_hotel_id=<uuid>.
--
-- legacy_source.staff_profiles.id is the real legacy staff_profiles.id
-- (NOT auth_user_id) -- confirmed by reading orchestrate_rehearsal.sh and
-- its already-validated real seed file before writing this: auth_remap
-- keys off legacy_source.staff_profiles.id paired with email, and
-- stays.created_by / guest_requests.accepted_by / created_by_staff all
-- already reference staff_profiles.id in both schemas identically, so no
-- id translation is needed anywhere in this export -- values carry
-- straight through unchanged.
--
-- auth.users is touched only via the (id, email) column-level grant
-- (see setup_readonly_role.sql) -- id only to join, email is the only
-- value actually read.
\set ON_ERROR_STOP on

select 'insert into legacy_source.staff_profiles (id, hotel_id, email, name, role, department, active, login_username) values (' ||
  quote_literal(sp.id) || ',' || quote_literal(sp.hotel_id) || ',' || quote_nullable(au.email) || ',' ||
  quote_literal(sp.name) || ',' || quote_literal(sp.role::text) || ',' || quote_nullable(sp.department::text) || ',' ||
  sp.active::text || ',' || quote_nullable(sp.login_username) || ') on conflict (id) do nothing;'
from staff_profiles sp
join auth.users au on au.id = sp.auth_user_id
where sp.hotel_id = :'legacy_hotel_id';

select 'insert into legacy_source.rooms (id, hotel_id, room_number, active) values (' ||
  quote_literal(r.id) || ',' || quote_literal(r.hotel_id) || ',' || quote_literal(r.room_number) || ',' || r.active::text ||
  ') on conflict (id) do nothing;'
from rooms r
where r.hotel_id = :'legacy_hotel_id';

select 'insert into legacy_source.request_categories (id, hotel_id, name, department, icon, active, sort_order) values (' ||
  quote_literal(rc.id) || ',' || quote_literal(rc.hotel_id) || ',' || quote_literal(rc.name) || ',' ||
  quote_literal(rc.department::text) || ',' || quote_nullable(rc.icon) || ',' || rc.active::text || ',' || rc.sort_order::text ||
  ') on conflict (id) do nothing;'
from request_categories rc
where rc.hotel_id = :'legacy_hotel_id';

select 'insert into legacy_source.request_types (id, category_id, name, description, allows_quantity, active, sort_order, available_quantity) values (' ||
  quote_literal(rt.id) || ',' || quote_literal(rt.category_id) || ',' || quote_literal(rt.name) || ',' ||
  quote_nullable(rt.description) || ',' || rt.allows_quantity::text || ',' || rt.active::text || ',' || rt.sort_order::text || ',' ||
  quote_nullable(rt.available_quantity) ||
  ') on conflict (id) do nothing;'
from request_types rt
join request_categories rc on rc.id = rt.category_id
where rc.hotel_id = :'legacy_hotel_id';

select 'insert into legacy_source.stays (id, hotel_id, room_id, guest_last_name, check_in_at, check_out_at, status, source, external_stay_id, created_by) values (' ||
  quote_literal(s.id) || ',' || quote_literal(s.hotel_id) || ',' || quote_literal(s.room_id) || ',' || quote_literal(s.guest_last_name) || ',' ||
  quote_literal(s.check_in_at::text) || ',' || quote_literal(s.check_out_at::text) || ',' || quote_literal(s.status::text) || ',' ||
  quote_literal(s.source::text) || ',' || quote_nullable(s.external_stay_id) || ',' || quote_nullable(s.created_by) ||
  ') on conflict (id) do nothing;'
from stays s
where s.hotel_id = :'legacy_hotel_id';

select 'insert into legacy_source.guest_requests (id, hotel_id, stay_id, room_number, request_type_id, quantity, status, assigned_department, accepted_by, created_at, accepted_at, completed_at, priority, created_by_staff, archived_at, returned_at) values (' ||
  quote_literal(gr.id) || ',' || quote_literal(gr.hotel_id) || ',' || quote_nullable(gr.stay_id) || ',' || quote_literal(gr.room_number) || ',' ||
  quote_literal(gr.request_type_id) || ',' || quote_nullable(gr.quantity) || ',' || quote_literal(gr.status::text) || ',' ||
  quote_literal(gr.assigned_department::text) || ',' || quote_nullable(gr.accepted_by) || ',' || quote_nullable(gr.created_at) || ',' ||
  quote_nullable(gr.accepted_at) || ',' || quote_nullable(gr.completed_at) || ',' || quote_nullable(gr.priority) || ',' ||
  quote_nullable(gr.created_by_staff) || ',' || quote_nullable(gr.archived_at) || ',' || quote_nullable(gr.returned_at) ||
  ') on conflict (id) do nothing;'
from guest_requests gr
where gr.hotel_id = :'legacy_hotel_id';
