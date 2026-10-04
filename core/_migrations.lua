local _, ns = ...
local Database = ns.Database

-- Core settings live at the root of the saved table, so pass nil as the namespace.

-- Example: rename profile.debugMode -> profile.debugEnabled (set Database.CURRENT_VERSION >= 2 to enable)
-- Database.RegisterMigration(2, "Core", function(sv)
--     Database.ForEachProfile(sv, nil, function(profile)
--         if profile.debugMode ~= nil then
--             profile.debugEnabled = profile.debugMode
--             profile.debugMode = nil
--         end
--     end)
-- end)
