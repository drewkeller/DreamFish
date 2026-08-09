local function readFile(path)
    local file = assert(io.open(path, "r"))
    local contents = file:read("*a")
    file:close()
    return contents
end

local toc = readFile("DreamFish.toc")
local bindingsLua = readFile("Bindings.lua")
local bindingsXml = readFile("Bindings.xml")
local copyScript = readFile("scripts/copy_files.sh")
local bindingName = "CLICK DreamFishSecureFishingFrame:RightButton"

assert(toc:find("\nBindings%.lua\n"), "DreamFish.toc must load Bindings.lua")
assert(copyScript:find("Bindings%.lua"), "copy_files.sh must deploy Bindings.lua")
assert(bindingsXml:find(bindingName, 1, true), "Bindings.xml is missing the fishing binding")
assert(
    bindingsLua:find("BINDING_NAME_" .. bindingName, 1, true),
    "Bindings.lua is missing the fishing binding display name"
)

print("bindings_manifest_test: passed")