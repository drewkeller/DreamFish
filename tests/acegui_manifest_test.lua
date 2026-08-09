local function readFile(path)
    local file = assert(io.open(path, "r"))
    local contents = file:read("*a")
    file:close()
    return contents
end

local toc = readFile("DreamFish.toc")
local aceGuiXml = readFile("Libs/AceGUI-3.0/AceGUI-3.0.xml")

assert(
    toc:find("\nLibs/AceGUI%-3%.0/AceGUI%-3%.0%.xml\n"),
    "DreamFish.toc must load the embedded AceGUI XML"
)

local requiredWidgets = {
    "AceGUIContainer%-ScrollFrame%.lua",
    "AceGUIContainer%-Window%.lua",
    "AceGUIWidget%-Button%.lua",
    "AceGUIWidget%-Heading%.lua",
    "AceGUIWidget%-InteractiveLabel%.lua",
    "AceGUIWidget%-Label%.lua",
}

for _, widget in ipairs(requiredWidgets) do
    assert(aceGuiXml:find(widget), "AceGUI XML is missing a LootTracker widget: " .. widget)
end

print("acegui_manifest_test: passed")