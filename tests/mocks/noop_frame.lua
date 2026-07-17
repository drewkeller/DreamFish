local function makeNoopFrame(name)
    local frame = {
        _name = name,
        _shown = false,
        _scripts = {},
        _events = {},
        _attrs = {},
    }

    function frame:SetAllPoints() end
    function frame:SetFrameStrata() end
    function frame:SetClampedToScreen() end
    function frame:SetAttribute(key, value) self._attrs[key] = value end
    function frame:GetAttribute(key) return self._attrs[key] end
    function frame:RegisterForClicks() end
    function frame:Hide() self._shown = false end
    function frame:Show() self._shown = true end
    function frame:IsShown() return self._shown end
    function frame:HookScript() end
    function frame:RegisterEvent(event) self._events[event] = true end
    function frame:UnregisterEvent(event) self._events[event] = nil end
    function frame:SetScript(kind, fn) self._scripts[kind] = fn end
    function frame:GetScript(kind) return self._scripts[kind] end
    function frame:SetSize() end
    function frame:SetPoint() end
    function frame:SetMovable() end
    function frame:EnableMouse() end
    function frame:RegisterForDrag() end
    function frame:SetAutoFocus() end
    function frame:SetText() end
    function frame:SetBackdrop() end
    function frame:SetBackdropColor() end
    function frame:SetBackdropBorderColor() end
    function frame:CreateTexture()
        return {
            SetAllPoints = function() end,
            SetColorTexture = function() end,
            SetSize = function() end,
            SetPoint = function() end,
            SetTexture = function() end,
        }
    end
    function frame:CreateFontString()
        return {
            SetPoint = function() end,
            SetText = function() end,
            SetTextColor = function() end,
        }
    end
    function frame:StartMoving() end
    function frame:StopMovingOrSizing() end
    function frame:GetName() return self._name or "DreamFishSecureFishingButton" end
    function frame:SetOwner() return nil end

    frame.Text = { SetText = function() end, SetTextColor = function() end }
    frame.GetChecked = function() return true end
    frame.SetChecked = function() end
    frame.GetText = function() return "2" end

    return frame
end

return {
    makeNoopFrame = makeNoopFrame,
}
