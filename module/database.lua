local _, ns = ...

local Database = {
    -- Bump this and register a step for the new version whenever saved data changes shape.
    CURRENT_VERSION = 1,
    migrations = {},
}
ns.Database = Database

local function Notify(msg)
    local addon = ns.Addon
    if addon and addon.Print then
        addon:Print(msg)
    end
end

-- fn(sv, owner) receives the raw AceDB saved table so it can upgrade every profile/char, not just the active one.
function Database.RegisterMigration(version, owner, fn)
    assert(type(version) == "number" and version > 1, "Migration version must be a number greater than 1")
    assert(type(owner) == "string", "Migration owner must be a string")
    assert(type(fn) == "function", "Migration must be a function")
    table.insert(Database.migrations, {
        version = version,
        owner = owner,
        fn = fn,
        order = #Database.migrations + 1,
    })
end

-- Must be called on the raw SavedVariables table before AceDB:New touches it.
function Database.IsLegacy(sv)
    if type(sv) ~= "table" or next(sv) == nil then
        return false
    end
    return not (type(sv.global) == "table" and sv.global.dbVersion)
end

local function GetScopeRoot(sv, namespaceName)
    if namespaceName == nil then
        return sv
    end
    return type(sv.namespaces) == "table" and sv.namespaces[namespaceName] or nil
end

local function ForEachInScope(sv, namespaceName, scope, fn)
    local root = GetScopeRoot(sv, namespaceName)
    local entries = root and root[scope]
    if type(entries) ~= "table" then
        return
    end
    for key, data in pairs(entries) do
        if type(data) == "table" then
            fn(data, key)
        end
    end
end

function Database.ForEachProfile(sv, namespaceName, fn)
    ForEachInScope(sv, namespaceName, "profiles", fn)
end

function Database.ForEachChar(sv, namespaceName, fn)
    ForEachInScope(sv, namespaceName, "char", fn)
end

local function GetPendingSteps(fromVersion)
    local steps = {}
    for _, step in ipairs(Database.migrations) do
        if step.version > fromVersion and step.version <= Database.CURRENT_VERSION then
            table.insert(steps, step)
        end
    end
    table.sort(steps, function(a, b)
        if a.version ~= b.version then
            return a.version < b.version
        end
        return a.order < b.order
    end)
    return steps
end

function Database.Upgrade(db, wasLegacy)
    local current = Database.CURRENT_VERSION

    if wasLegacy then
        db:ResetDB(true)
        db.global.dbVersion = current
        Notify("Settings were reset to defaults for this version of DreamFish.")
        return true
    end

    local stored = db.global.dbVersion
    if stored == nil then
        db.global.dbVersion = current
        return true
    end

    if stored > current then
        Notify(("Saved settings are from a newer DreamFish (database v%d, this build supports v%d). Settings were not changed."):format(stored, current))
        return false
    end

    local steps = GetPendingSteps(stored)
    for index, step in ipairs(steps) do
        local ok, err = pcall(step.fn, db.sv, step.owner)
        if not ok then
            Notify(("Database upgrade to v%d (%s) failed: %s"):format(step.version, step.owner, tostring(err)))
            return false
        end
        local nextStep = steps[index + 1]
        if not nextStep or nextStep.version ~= step.version then
            db.global.dbVersion = step.version
        end
    end

    db.global.dbVersion = current
    return true
end
