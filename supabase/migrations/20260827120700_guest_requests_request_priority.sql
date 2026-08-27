-- Lets front desk reorder the "in carico" column manually (e.g. swap which
-- of a housekeeper's two claimed requests should be done first). Defaults
-- to insertion order via a sequence, so untouched requests keep the same
-- order they already had.
create sequence guest_requests_priority_seq;

alter table guest_requests
  add column priority bigint not null default nextval('guest_requests_priority_seq');

create index guest_requests_priority_idx on guest_requests(hotel_id, status, priority);
