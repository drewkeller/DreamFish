local _, ns = ...
local Database = ns.Database

-- Namespace must match the module name passed to RegisterNamespace.
local NAMESPACE = "LootTracker"

-- Example: drop an obsolete profile key (set Database.CURRENT_VERSION >= 2 to enable)
-- Database.RegisterMigration(2, NAMESPACE, function(sv)
--     Database.ForEachProfile(sv, NAMESPACE, function(profile)
--         profile.obsoleteSetting = nil
--     end)
-- end)
