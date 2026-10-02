local addonName, ns = ...
local Addon = ns.Addon

local ownedToyOptionsCache = {}
local ownedToyItemCache = {}

function ns.Utils.IsToyOwned(itemID)
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

function ns.Utils.FilterOwnedAndReadyToys(candidateIDs)
    if type(candidateIDs) ~= "table" then
        return {}
    end

    local ownedAndReady = {}

    for _, toy in ipairs(candidateIDs) do
        local numeric = tonumber(type(toy) == "table" and toy.id or toy)
        if numeric and numeric > 0 then
            -- Verify the player owns the toy and it is ready to use
            if ns.Utils.IsToyOwned(numeric) and ns.Utils.IsCooldownReady(numeric) then
                table.insert(ownedAndReady, numeric)
            end
        end
    end

    return ownedAndReady
end

function ns.Utils.IsCooldownReady(itemID)
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

function ns.Utils.BuildOwnedToyOptions(candidateIDs, includeDefaultLabel, randomLabel)
    local defaultKey = tostring(includeDefaultLabel or "")
    local randomKey = tostring(randomLabel or "")
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
    if type(randomLabel) == "string" and randomLabel ~= "" then
        options[-1] = randomLabel
    end

    if type(candidateIDs) ~= "table" then
        return options
    end

    for _, toy in ipairs(candidateIDs) do
        local numeric = tonumber(type(toy) == "table" and toy.id or toy)
        local name = type(toy) == "table" and toy.name or nil
        if numeric and numeric > 0 and not seen[numeric] then
            seen[numeric] = true
            if ns.Utils.IsToyOwned(numeric) then
                options[numeric] = (type(name) == "string" and name ~= "") and name or ("item:" .. tostring(numeric))
            end
        end
    end

    cacheByCandidate[defaultKey] = options
    return options
end

function ns.Utils.BuildOwnedToySortingKeys(candidateIDs, includeDefault, randomLabel)
    local values = ns.Utils.BuildOwnedToyOptions(candidateIDs, includeDefault)
    local keys = {}
    if type(includeDefault) == "string" and includeDefault ~= "" and values[0] ~= nil then
        table.insert(keys, 0)
    end
    if type(randomLabel) == "string" and randomLabel ~= "" and values[-1] ~= nil then
        table.insert(keys, -1)
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

function ns.Utils.GetRandomOwnedToyID(candidateIDs, currentID)
    if #candidateIDs > 1 then
        for i = #candidateIDs, 1, -1 do
            if tonumber(type(candidateIDs[i]) == "table" and candidateIDs[i].id or candidateIDs[i]) == currentID then
                table.remove(candidateIDs, i)
            end
        end
    end

    local ownedAndReady = ns.Utils.FilterOwnedAndReadyToys(candidateIDs)

    -- Return a random itemID from the validated pool if any are available
    if ownedAndReady and #ownedAndReady > 0 then
        return ownedAndReady[math.random(1, #ownedAndReady)]
    end

    return nil
end
