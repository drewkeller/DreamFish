local addonName, ns = ...

function ns.Utils.IsSwimmingOrSubmerged()
    return (
        (type(IsSwimming) == "function" and IsSwimming())
        or (type(IsSubmerged) == "function" and IsSubmerged())
    )
end
