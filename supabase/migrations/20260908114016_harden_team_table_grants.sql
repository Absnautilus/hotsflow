-- Supabase projects created with older default privileges can attach
-- non-CRUD table privileges (including TRUNCATE) to new public tables.
-- RLS does not cover TRUNCATE, so replace inherited/default table grants with
-- the exact Data API surface Team needs.

revoke all privileges on table property_job_titles from anon, authenticated;
revoke all privileges on table property_staff_details from anon, authenticated;

grant select, insert on table property_job_titles to authenticated;
grant update (name, active) on table property_job_titles to authenticated;
grant select, insert on table property_staff_details to authenticated;
grant update (job_title_id, employment_status) on table property_staff_details to authenticated;
