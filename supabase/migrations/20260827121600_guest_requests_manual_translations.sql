-- Manual per-language translations for admin-entered category/item text,
-- replacing the Google Translate auto-translate call for these two fields
-- (unreliable on mixed-language admin input — e.g. "Comfort camera"
-- mistranslating to "Fotocamera confortevole"). name_i18n/description_i18n
-- are partial maps ({"en": "...", "fr": "...", ...}) keyed by locale code;
-- a locale missing from the map just falls back to the base name/description
-- (assumed Italian) instead of guessing via machine translation.

begin;

alter table request_categories add column name_i18n jsonb not null default '{}'::jsonb;
alter table request_types add column name_i18n jsonb not null default '{}'::jsonb;
alter table request_types add column description_i18n jsonb not null default '{}'::jsonb;

commit;
