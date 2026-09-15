-- stockpilecfg.lua
-- Configuration tool for Stockpile staging chest mappings

local config_file = "stockpile_chests.json"

local args = { ... }
local cmd = args[1]

local function usage()
    print("Usage: stockpilecfg map <player> <chest peripheral>")
end

if not cmd or cmd ~= "map" then
    usage()
    return
end

local player = args[2]
local chest = args[3]

if not player or not chest then
    usage()
    return
end

-- Load existing mapping
local mapping = {}
if fs.exists(config_file) then
    local file = fs.open(config_file, "r")
    if file then
        local content = file.readAll()
        file.close()
        local success, result = pcall(textutils.unserialiseJSON, content)
        if success and type(result) == "table" then
            mapping = result
        end
    end
end

-- Update mapping
mapping[player] = chest

-- Save mapping
local file = fs.open(config_file, "w")
if not file then
    print("Error: Could not open " .. config_file .. " for writing.")
    return
end
file.write(textutils.serialiseJSON(mapping))
file.close()

print("Successfully mapped player " .. player .. " to chest " .. chest)
