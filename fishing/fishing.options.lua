local addonName, ns = ...
local DreamFish = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Fishing = DreamFish:GetModule("Fishing")

ns.Fishing.Defaults = {
    global = {
        buffAuraByItem = {
            ["238374"] = { spellID = 1237942, duration = 30, category="other_consumable", }, -- Tender Lumifin
        },
    },
    profile = {
		fishing = {
			moduleEnabled = true,
			debug = false,
            traceMode = {},
            castByDoubleRightClick = true,
            castBySingleRightClickWhenFishing = false,
            castByHotkey = true,
            strikeByRightClick = false,
            strikeByHotkey = true,
            selectedRaftToy = 0,
            selectedBobberToy = 0,
            useOversizedBobber = false,
            -- other
            closeWindowOnEscape = true,
            lingerDuration = 10,
		},
	},
	char = {
		fishing = {
            -- Tackle
            primaryPole = { isChecked = false, itemID = nil },
            underlightAngler = { isChecked = false, itemID = nil },
            -- Buffs
            buffItems = {
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
                { enabled = false, itemID = nil },
            },
        },
	},
}

Fishing:Configure({
	displayName = "Fishing",
	dbKey = "fishing",
	defaults = ns.Fishing.Defaults,
	childGroups = "tree",
    showEnableOption = false,
})

function Fishing:GetModuleOptions()
    local function SelectPage(pageKey)
        LibStub("AceConfigDialog-3.0"):SelectGroup(addonName, self.moduleConfig.dbKey, pageKey)
    end

	return {
        modesTab = self:AddTab({
            type = "group",
            name = "Modes",
            args = {
                castingTriggers = self:AddOption({
                    type = "group",
                    name = "Casting triggers",
                    inline = true,
                    args = {
                        castByDoubleRightClick = self:AddOption({
                            type = "toggle",
                            name = "Double right click",
                            desc = "Double right click to begin fishing.",
                            width = "full",
                        }),
                        castBySingleRightClickWhenFishing = self:AddOption({
                            type = "toggle",
                            name = "Single right click (while fishing)",
                            desc = "Single right click to cast when already in fishing session.",
                            width = "full",
                            set = function(_, value)
                                Fishing.db.profile.castBySingleRightClickWhenFishing = value
                                if not value and Fishing.clickFrame and not InCombatLockdown() then
                                    ClearOverrideBindings(Fishing.clickFrame)
                                end
                            end,
                        }),
                        castByHotkey = self:AddOption({
                            type = "toggle",
                            name = "Hotkey",
                            desc = "Use a hotkey to begin fishing.",
                            width = "full",
                        }),
                        castHotkeyKeybind1 = self:AddOption({
                            type = "keybinding",
                            name = "",
                            desc = "Set the keybinding for the hotkey casting mode.",
                            width = 1.0,
                            get = function()
                                return self:GetKeybindings()[1]
                            end,
                            set = function(_, value)
                                self:SetKeybindings(value, nil)
                            end,
                        }),
                        castHotkeyKeybind2 = self:AddOption({
                            type = "keybinding",
                            name = "",
                            desc = "Set the keybinding for the hotkey casting mode.",
                            width = 1.0,
                            get = function()
                                return self:GetKeybindings()[2]
                            end,
                            set = function(_, value)
                                self:SetKeybindings(nil, value)
                            end,
                        }),
                    },
                }),
                reelingTriggers = self:AddOption({
                    type = "group",
                    name = "Reel/bobber triggers",
                    inline = true,
                    args = {
                        modeEasyStrikeNote = self:AddOption({
                            type = "description",
                            name = "|c80999999  Requirements for either EasyStrike:|r\n"
                                .. "|c80999999  1. Turn on \"Enable Interact Key\" (Game Options > Controls).|r\n"
                                .. "|c80999999  2. Set the \"Hotkey\" keybinding above.|r\n"
                                .. "|c80999999  3. Ensure another addon does not interfere while fishing.|r",
                            width = "full",
                        }),
                        strikeByRightClick = self:AddOption({
                            type = "toggle",
                            name = "EasyStrike (right click)",
                            desc = "When the bobber indicates a bite, right click anywhere or use the hotkey to hook, play, and land the fish.",
                            width = "full",
                        }),
                        strikeByRightClickNote = self:AddOption({
                            type = "description",
                            name = "      |c80999999Since this replaces the normal \"turn or action\" action|r\n"
                                .. "      |c80999999on the right mouse button, it may be a bit awkward if you|r\n"
                                .. "      |c80999999are used to using RMB to turn or start movement by|r\n"
                                .. "      |c80999999pressing RMB first.|r\n"
                                .. "      |c80999999However, you can still mouse-look using LMB and initiate|r\n"
                                .. "      |c80999999movement by holding down LMB first and then RMB.|r",
                        }),
                        strikeByHotkey = self:AddOption({
                            type = "toggle",
                            name = "EasyStrike (hotkey)",
                            desc = "Use a hotkey to hook, play, and land the fish when the bobber indicates a bite.",
                            width = "full",
                        }),
                    },
                }),
                spacer = self:AddOption({
                    type = "description",
                    name = " ",
                    fontSize = "small",
                }),
                lingerDuration = self:AddOption({
                    type = "range",
                    name = "Linger duration",
                    desc = "The number of seconds after a cast for the fishing session to expire, unless another cast is initiated.",
                    min = 0,
                    max = 60,
                    step = 1,
                    bigStep = 5,
                }),
            },
        }),
        tackleTab = self:AddTab({
            type = "group",
            name = "Tackle",
            args = {
                raftSection = {
                    type = "group",
                    name = "  ",
                    desc = "Settings for auto-casting a raft when fishing.",
                    inline = true,
                    order = 1,
                    args = {
                        selectedRaftToy = {
                            type = "select",
                            name = "Raft",
                            desc = "Choose the raft to be used when fishing. Applied automatically when casting the fishing line.",
                            order = 1,
                            values = function()
                                return DreamFish:BuildOwnedToyOptions(ns.fishing.const.raftToyItemIDs, "No Raft")
                            end,
                            sorting = function()
                                return DreamFish:BuildOwnedToySortingKeys(ns.fishing.const.raftToyItemIDs, "No Raft")
                            end,
                            width = 1.5,
                        },
                        applyRaft = {
                            type = "execute",
                            name = "Apply Raft",
                            desc = "Manually apply the selected raft now.",
                            order = 2,
                            func = "ApplyRaft",
                            width = 0.85,
                        },
                    },
                },
                bobberSection = {
                    type = "group",
                    name = "  ",
                    desc = "Settings for auto-casting a bobber when fishing.",
                    inline = true,
                    order = 2,
                    args = {
                        -- divider = {
                        --     type = "header",
                        --     name = "-----",
                        --     order = 0,
                        -- },
                        selectedBobberToy = {
                            type = "select",
                            name = "Bobber",
                            desc = "Choose the bobber to be used when fishing. Applied automatically when casting the fishing line.",
                            order = 1,
                            values = function()
                                return DreamFish:BuildOwnedToyOptions(ns.fishing.const.bobberToyItemIDs, "Standard Bobber")
                            end,
                            sorting = function()
                                return DreamFish:BuildOwnedToySortingKeys(ns.fishing.const.bobberToyItemIDs, "Standard Bobber")
                            end,
                            width = 1.5,
                        },
                        applyBobber = {
                            type = "execute",
                            name = "Apply Bobber",
                            desc = "Manually apply the selected bobber now.",
                            order = 2,
                            func = "ApplyBobber",
                            width = 0.85,
                        },
                        useOversizedBobber = {
                            type = "toggle",
                            name = "Use Oversized Bobber",
                            desc = "Also apply the oversized bobber to your selected bobber (adds another click to apply it)",
                            order = 3,
                            width = "full",
                        }
                    } -- Bobber section
                },
                openTackleWindow = {
                    type = "execute",
                    name = "Open Tackle Manager",
                    desc = "Open a window to manage fishing tackle (poles, rafts, bobbers).",
                    order = 3,
                    func = function() Fishing:OpenTackleWindow() end,
                    width = "full",
                } -- Tackle manager button
            },
        }), -- Tackle tab
    }
end

-- Build the "Rods & Poles" tab content inside the shared tackle window
function Fishing:BuildPolesTab(content)
    local charDB = self.db.char
    self.poleBorderRefreshers = self.poleBorderRefreshers or {}

    local instructions = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructions:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    instructions:SetText("Modes:\n"
        .. "• Auto-swap: Check both boxes \n"
        .. "   (swap occurs when starting/stopping fishing)\n"
        .. "• Single-pole: Only check one box.\n"
        .. "• Manual: Leave both boxes unchecked.")
    instructions:SetWidth(500)
    instructions:SetJustifyH("LEFT")
    instructions:SetTextColor(0.8, 0.8, 0.8, 1.0)

    local function IsUnderlightAnglerItemID(itemID)
        return tonumber(itemID) == tonumber(ns.fishing.const.underlightAnglerItemID)
    end

    local function IsFishingPoleItemID(itemID)
        if not itemID or IsUnderlightAnglerItemID(itemID) then
            return false
        end

        local _, itemType, itemSubtype, itemEquipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
        local isLegacyFishingPole = (itemType == "Weapon" and itemSubtype == "Fishing Poles")
            or (classID == 2 and (subclassID == 20 or subclassID == 21))
        local isFishingProfessionTool = itemEquipLoc == "INVTYPE_PROFESSION_TOOL"
            and (itemType == "Fishing" or itemSubtype == "Fishing")

        return isLegacyFishingPole or isFishingProfessionTool
    end

    local function GetAvailableFishingPoles()
        local poles = {}
        local seen = {}

        local function AddPole(itemID)
            itemID = tonumber(itemID)
            if not itemID or seen[itemID] or IsUnderlightAnglerItemID(itemID) or not IsFishingPoleItemID(itemID) then
                return
            end

            seen[itemID] = true
            local name = C_Item.GetItemInfo(itemID) or ("item:" .. itemID)
            table.insert(poles, { itemID = itemID, name = name })
        end

        for bag = 0, NUM_BAG_SLOTS do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                AddPole(C_Container.GetContainerItemID(bag, slot))
            end
        end

        AddPole(GetInventoryItemID("player", 28))
        table.sort(poles, function(left, right) return left.name < right.name end)
        return poles
    end

    local leftColumn = CreateFrame("Frame", nil, content)
    leftColumn:SetSize(100, 60)
    leftColumn:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -80)

    local rightColumn = CreateFrame("Frame", nil, content)
    rightColumn:SetSize(100, 60)
    rightColumn:SetPoint("TOPLEFT", content, "TOPLEFT", 120, -80)

    local poleBox, poleCheckbox, setPoleItemID, updatePoleBorder = ns.ui.CreateItemDropBox(
        charDB, "primaryPole", leftColumn, 0, 0, "Fishing Pole:", nil, nil
    )

    local polePickerButton = CreateFrame("Button", nil, leftColumn, "UIPanelButtonTemplate")
    polePickerButton:SetSize(22, 22)
    polePickerButton:SetPoint("BOTTOMLEFT", poleBox, "BOTTOMRIGHT", 4, 4)
    polePickerButton:SetText("v")
    local polePickerMenu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    polePickerMenu:SetFrameStrata("TOOLTIP")
    polePickerMenu:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    polePickerMenu:Hide()
    content:HookScript("OnHide", function()
        polePickerMenu:Hide()
    end)
    polePickerButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText("Select fishing pole")
        GameTooltip:Show()
    end)
    polePickerButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    polePickerButton:SetScript("OnClick", function(button)
        local items = GetAvailableFishingPoles()
        if polePickerMenu:IsShown() then
            polePickerMenu:Hide()
            return
        end

        polePickerMenu.buttons = polePickerMenu.buttons or {}
        for _, menuButton in ipairs(polePickerMenu.buttons) do
            menuButton:Hide()
        end

        if #items == 0 then
            items = { { name = "No fishing poles available" } }
        end

        polePickerMenu:ClearAllPoints()
        polePickerMenu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
        polePickerMenu:SetSize(240, #items * 24 + 8)

        for index, pole in ipairs(items) do
            local itemID = pole.itemID
            local itemName = pole.name
            local menuButton = polePickerMenu.buttons[index]
            if not menuButton then
                menuButton = CreateFrame("Button", nil, polePickerMenu, "UIPanelButtonTemplate")
                polePickerMenu.buttons[index] = menuButton
            end

            menuButton:ClearAllPoints()
            menuButton:SetPoint("TOPLEFT", polePickerMenu, "TOPLEFT", 4, -4 - (index - 1) * 24)
            menuButton:SetSize(232, 22)
            menuButton:SetText(itemName)
            menuButton:SetEnabled(itemID ~= nil)
            menuButton:SetScript("OnClick", function()
                setPoleItemID(itemID)
                updatePoleBorder()
                polePickerMenu:Hide()
            end)
            menuButton:SetScript("OnEnter", function(menuEntry)
                if itemID then
                    GameTooltip:SetOwner(menuEntry, "ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(itemID)
                    GameTooltip:Show()
                end
            end)
            menuButton:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            menuButton:Show()
        end

        polePickerMenu:Show()
    end)

    local anglerBox, anglerCheckbox, setAnglerItemID, updateAnglerBorder = ns.ui.CreateItemDropBox(
        charDB, "underlightAngler", rightColumn, 0, 0, "Underlight Angler:", nil, IsUnderlightAnglerItemID
    )

    if charDB.primaryPole and charDB.primaryPole.itemID then
        setPoleItemID(charDB.primaryPole.itemID)
    end
    poleCheckbox:SetChecked(charDB.primaryPole and charDB.primaryPole.isChecked or false)
    updatePoleBorder()
    self.poleBorderRefreshers.primaryPole = updatePoleBorder

    if not (charDB.underlightAngler and charDB.underlightAngler.itemID) then
        local underlightID = ns.fishing.const.underlightAnglerItemID
        if underlightID and underlightID > 0 and ns.precast.IsItemAvailableForEquip(underlightID) then
            setAnglerItemID(underlightID)
        end
    else
        setAnglerItemID(charDB.underlightAngler.itemID)
    end
    anglerCheckbox:SetChecked(charDB.underlightAngler and charDB.underlightAngler.isChecked or false)
    updateAnglerBorder()
    self.poleBorderRefreshers.underlightAngler = updateAnglerBorder
end

function Fishing:RefreshPoleBorders()
    if not self.poleBorderRefreshers then
        return
    end
    for _, refreshBorder in pairs(self.poleBorderRefreshers) do
        refreshBorder()
    end
end

function Fishing:OpenTackleWindow()
    ns.ui.TackleWindow:Open("poles")
end

function Fishing:RegisterTackleWindowTab()
    ns.ui.TackleWindow:RegisterTab({
        id = "poles",
        title = "Rods & Poles",
        order = 1,
        build = function(content) self:BuildPolesTab(content) end,
    })
    -- ns.ui.TackleWindow:RegisterTab({
    --     id = "buffs",
    --     title = "Buffs",
    --     order = 2,
    --     --build = function(content) self:BuildBuffsTab(content) end,
    -- })
end
