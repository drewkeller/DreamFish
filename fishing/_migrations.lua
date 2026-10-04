local _, ns = ...
local Database = ns.Database

-- Namespace must match the module name passed to RegisterNamespace.
local NAMESPACE = "Fishing"

-- Example: move char.primaryPole into char.poles.primary (set Database.CURRENT_VERSION >= 2 to enable)
-- Database.RegisterMigration(2, NAMESPACE, function(sv)
--     Database.ForEachChar(sv, NAMESPACE, function(char)
--         if char.primaryPole ~= nil then
--             char.poles = char.poles or {}
--             char.poles.primary = char.primaryPole
--             char.primaryPole = nil
--         end
--     end)
-- end)
