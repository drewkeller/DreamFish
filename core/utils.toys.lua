local addonName, ns = ...
local Addon = LibStub("AceAddon-3.0"):GetAddon(addonName)

local ownedToyOptionsCache = {}
local ownedToyItemCache = {}

function Addon:IsToyOwned(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return false
    end

    local cached = ownedToyItemCache[numeric]
    if cached ~= nil then
        return cached
    end

    local owned = (type(C_ToyBox.PlayerHasToy) ~= "function") or C_ToyBox.PlayerHasToy(numeric)
    ownedToyItemCache[numeric] = owned and true or false
    return ownedToyItemCache[numeric]
end

function Addon:IsCooldownReady(itemID)
    local numeric = tonumber(itemID)
    if not numeric or numeric <= 0 then
        return true
    end

    local start, duration, enabled = C_Item.GetItemCooldown(numeric)
    if enabled == 0 then
        return false
    end

    start = tonumber(start) or 0
    duration = tonumber(duration) or 0
    if start <= 0 or duration <= 0 then
        return true
    end

    local now = (type(GetTime) == "function") and GetTime() or 0
    return (start + duration) <= (now + 0.05)
end

function Addon:BuildOwnedToyOptions(candidateIDs, includeDefaultLabel)
    local defaultKey = tostring(includeDefaultLabel or "")
    local candidateKey = (type(candidateIDs) == "table") and candidateIDs or "__non_table__"

    local cacheByCandidate = ownedToyOptionsCache[candidateKey]
    if not cacheByCandidate then
        cacheByCandidate = {}
        ownedToyOptionsCache[candidateKey] = cacheByCandidate
    end

    local cached = cacheByCandidate[defaultKey]
    if cached then
        return cached
    end

    local options = {}
    local seen = {}

    if type(includeDefaultLabel) == "string" and includeDefaultLabel ~= "" then
        options[0] = includeDefaultLabel
    end

    if type(candidateIDs) ~= "table" then
        return options
    end

    for _, toy in ipairs(candidateIDs) do
        local numeric = tonumber(type(toy) == "table" and toy.id or toy)
        local name = type(toy) == "table" and toy.name or nil
        if numeric and numeric > 0 and not seen[numeric] then
            seen[numeric] = true
            if Addon:IsToyOwned(numeric) then
                options[numeric] = (type(name) == "string" and name ~= "") and name or ("item:" .. tostring(numeric))
            end
        end
    end

    cacheByCandidate[defaultKey] = options
    return options
end

function Addon:BuildOwnedToySortingKeys(candidateIDs, includeDefault)
    local values = Addon:BuildOwnedToyOptions(candidateIDs, includeDefault)
    local keys = {}
    if type(includeDefault) == "string" and includeDefault ~= "" and values[0] ~= nil then
        table.insert(keys, 0)
    end
    if type(candidateIDs) ~= "table" then
        return keys
    end
    for _, toy in ipairs(candidateIDs) do
        local itemID = tonumber(type(toy) == "table" and toy.id or toy)
        if itemID and values[itemID] ~= nil then
            table.insert(keys, itemID)
        end
    end
    return keys
end