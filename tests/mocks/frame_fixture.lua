local function makeFontString()
    local fs = {
        text = "",
    }

    function fs:SetPoint() end
    function fs:SetTextColor() end
    function fs:SetJustifyH() end
    function fs:SetText(text)
        self.text = text
    end

    return fs
end

local function makeTexture()
    local tx = {
        texture = nil,
    }

    function tx:SetAllPoints() end
    function tx:SetColorTexture() end
    function tx:SetSize() end
    function tx:SetPoint() end
    function tx:SetTexture(texture)
        self.texture = texture
    end

    return tx
end

local function makeFrame(name, opts)
    opts = opts or {}

    local frame = {
        _name = name,
        _shown = opts.shown == true,
        _alpha = opts.alpha or 1,
        _scripts = {},
        _events = {},
        _attrs = {},
        _lines = {},
    }

    local defaultName = opts.defaultName or "Frame"
    local fontStringFactory = opts.fontStringFactory or makeFontString
    local textureFactory = opts.textureFactory or makeTexture

    function frame:SetAllPoints() end
    function frame:SetFrameStrata() end
    function frame:SetClampedToScreen() end
    function frame:SetAttribute(key, value) self._attrs[key] = value end
    function frame:GetAttribute(key) return self._attrs[key] end
    function frame:RegisterForClicks() end
    function frame:Hide() self._shown = false end
    function frame:Show() self._shown = true end
    function frame:IsShown() return self._shown end
    function frame:HookScript(kind, fn) self._scripts[kind] = fn end
    function frame:RegisterEvent(event) self._events[event] = true end
    function frame:UnregisterEvent(event) self._events[event] = nil end
    function frame:SetScript(kind, fn) self._scripts[kind] = fn end
    function frame:GetScript(kind) return self._scripts[kind] end
    function frame:SetSize() end
    function frame:SetPoint() end
    function frame:SetMovable() end
    function frame:EnableMouse() end
    function frame:EnableKeyboard() end
    function frame:RegisterForDrag() end
    function frame:SetAutoFocus() end
    function frame:SetText(text) self._text = text end
    function frame:SetBackdrop() end
    function frame:SetBackdropColor() end
    function frame:SetBackdropBorderColor() end
    function frame:SetScale() end
    function frame:SetStaticPOIArrowTexture() end
    function frame:SetPlayerTexture() end
    function frame:GetAlpha() return self._alpha end
    function frame:SetAlpha(value) self._alpha = value end
    function frame:CreateTexture() return textureFactory() end
    function frame:CreateFontString() return fontStringFactory() end
    function frame:StartMoving() end
    function frame:StopMovingOrSizing() end
    function frame:GetName() return self._name or defaultName end
    function frame:SetOwner() return nil end
    function frame:SetInventoryItem() end
    function frame:SetBagItem() end
    function frame:ClearLines() self._lines = {} end
    function frame:AddLine(text)
        table.insert(self._lines, text)
    end

    frame.Text = { SetText = function() end, SetTextColor = function() end }
    frame.GetChecked = function() return true end
    frame.SetChecked = function() end
    frame.GetText = function() return tostring(opts.defaultText or "2") end

    return frame
end

return {
    makeFrame = makeFrame,
    makeFontString = makeFontString,
    makeTexture = makeTexture,
}
