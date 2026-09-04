local addonName, ns = ...

function ns.Utils.Clamp(value, min, max)
    if value == nil then
        return min
    end
    if value < min then
        return min
    end
    if value > max then
        return max
    end
    return value
end

function ns.Utils.ToNumberOrNil(value)
    local n = tonumber(value)
    if not n then
        return nil
    end
    return n
end

function ns.Utils.NearlyEqual(a, b)
    local na = ns.Utils.ToNumberOrNil(a)
    local nb = ns.Utils.ToNumberOrNil(b)
    if not na or not nb then
        return false
    end
    return math.abs(na - nb) <= 0.0001
end

