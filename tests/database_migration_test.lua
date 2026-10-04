local printedMessages = {}

local function LoadDatabase()
    local namespace = {
        Addon = {
            Print = function(_, msg)
                table.insert(printedMessages, msg)
            end,
        },
    }
    local chunk = assert(loadfile("module/database.lua"))
    chunk("DreamFish", namespace)
    return namespace.Database
end

-- Minimal AceDB stand-in: global/sv share storage like the real thing.
local function NewDB(sv)
    sv.global = sv.global or {}
    local db = { sv = sv, resetCount = 0 }
    db.global = sv.global
    function db:ResetDB()
        for k in pairs(self.sv) do
            self.sv[k] = nil
        end
        self.sv.global = {}
        self.global = self.sv.global
        self.resetCount = self.resetCount + 1
    end
    return db
end

-- IsLegacy
do
    local Database = LoadDatabase()
    assert(Database.IsLegacy(nil) == false, "missing SV is a fresh install")
    assert(Database.IsLegacy({}) == false, "empty SV is a fresh install")
    assert(Database.IsLegacy({ profiles = { Default = {} } }) == true, "unversioned SV is legacy")
    assert(Database.IsLegacy({ global = { dbVersion = 1 } }) == false, "versioned SV is not legacy")
end

-- Fresh install stamps current version
do
    local Database = LoadDatabase()
    local db = NewDB({})
    assert(Database.Upgrade(db, false) == true)
    assert(db.global.dbVersion == Database.CURRENT_VERSION, "fresh install must be stamped")
    assert(db.resetCount == 0, "fresh install must not reset")
end

-- Legacy DB is reset and stamped
do
    local Database = LoadDatabase()
    printedMessages = {}
    local db = NewDB({ profiles = { Default = { old = true } } })
    assert(Database.Upgrade(db, true) == true)
    assert(db.resetCount == 1, "legacy DB must be reset")
    assert(db.sv.profiles == nil, "legacy data must be wiped")
    assert(db.global.dbVersion == Database.CURRENT_VERSION, "legacy DB must be stamped after reset")
    assert(#printedMessages == 1, "user must be notified of reset")
end

-- Steps run in version then registration order across all profiles and namespaces
do
    local Database = LoadDatabase()
    Database.CURRENT_VERSION = 3
    local calls = {}
    Database.RegisterMigration(3, "Fishing", function()
        table.insert(calls, "v3-fishing")
    end)
    Database.RegisterMigration(2, "Fishing", function(sv)
        table.insert(calls, "v2-fishing")
        Database.ForEachProfile(sv, "Fishing", function(profile)
            profile.migrated = true
        end)
    end)
    Database.RegisterMigration(2, "Core", function(sv)
        table.insert(calls, "v2-core")
        Database.ForEachProfile(sv, nil, function(profile)
            profile.migrated = true
        end)
        Database.ForEachChar(sv, nil, function(char)
            char.migrated = true
        end)
    end)

    local db = NewDB({
        global = { dbVersion = 1 },
        profiles = { Default = {}, Alt = {} },
        char = { ["Toon - Realm"] = {} },
        namespaces = { Fishing = { profiles = { Default = {}, Alt = {} } } },
    })
    assert(Database.Upgrade(db, false) == true)
    assert(table.concat(calls, ",") == "v2-fishing,v2-core,v3-fishing", "unexpected order: " .. table.concat(calls, ","))
    assert(db.global.dbVersion == 3, "version must reach current")
    assert(db.sv.profiles.Default.migrated and db.sv.profiles.Alt.migrated, "all root profiles must migrate")
    assert(db.sv.char["Toon - Realm"].migrated, "all chars must migrate")
    local fishingProfiles = db.sv.namespaces.Fishing.profiles
    assert(fishingProfiles.Default.migrated and fishingProfiles.Alt.migrated, "all namespace profiles must migrate")

    calls = {}
    assert(Database.Upgrade(db, false) == true)
    assert(#calls == 0, "already-current DB must not rerun steps")
end

-- Failing step halts at last completed version
do
    local Database = LoadDatabase()
    Database.CURRENT_VERSION = 4
    local ranV4 = false
    Database.RegisterMigration(2, "Core", function() end)
    Database.RegisterMigration(3, "Core", function()
        error("boom")
    end)
    Database.RegisterMigration(4, "Core", function()
        ranV4 = true
    end)
    printedMessages = {}
    local db = NewDB({ global = { dbVersion = 1 } })
    assert(Database.Upgrade(db, false) == false)
    assert(db.global.dbVersion == 2, "version must stop at last successful step")
    assert(not ranV4, "steps after a failure must not run")
    assert(#printedMessages == 1, "failure must be reported")
end

-- Newer stored version is left untouched
do
    local Database = LoadDatabase()
    local ran = false
    Database.CURRENT_VERSION = 2
    Database.RegisterMigration(2, "Core", function()
        ran = true
    end)
    printedMessages = {}
    local db = NewDB({ global = { dbVersion = 5 } })
    assert(Database.Upgrade(db, false) == false)
    assert(db.global.dbVersion == 5, "newer version must not be downgraded")
    assert(not ran, "no steps may run against a newer DB")
    assert(#printedMessages == 1, "user must be warned about newer DB")
end

print("database_migration_test.lua passed")
