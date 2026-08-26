-- property_modules represents commercial entitlement — "does this property
-- own this module?" — not staff configuration. 0007 let anyone with
-- core.property.manage flip a module on for their own property, which is
-- exactly the boundary the Architecture Proposal drew between entitlement
-- and authorization. Removes write access for `authenticated` entirely;
-- SELECT is untouched. No replacement policy — service-role/migration only,
-- same as modules/roles/permissions/role_permissions already are. Future
-- billing/admin tooling gets a real, separate write path when it exists;
-- this isn't it.

drop policy property_modules_insert on property_modules;
drop policy property_modules_update on property_modules;

revoke insert, update on property_modules from authenticated;
