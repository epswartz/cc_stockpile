--[[
================================================================================
                                 STOCKPILE
================================================================================
A restocking program for CC:Tweaked and Advanced Peripherals.

IN-GAME SETUP:
1. INVENTORY MANAGER:
   - Place an Inventory Manager block next to your computer.
   - Bind yourself to a Memory Card (shift + right-click with card in hand).
   - Place the bound Memory Card inside the Inventory Manager.
2. CHAT BOX:
   - Place a Chat Box block next to your computer or connect it via a wired network.
3. SUPPLY CHEST:
   - Place a supply chest directly on top of the Inventory Manager block (specifically
     on the Manager's 'up' side). It does NOT need to touch the computer!
4. RUNNING:
   - Put 'stockpile.lua' and 'startup.lua' in the root directory.
   - Reboot the computer. The program will run in a background shell tab.

COMMANDS (Type in public chat):
- "stock [optional count]" - Restocks held item up to the count (defaults to max stack).
- "unstock" - Stops restocking the currently held item.
================================================================================
--]]


local requests_file = "stockpile_requests.json"

local config_file = "stockpile_chests.json"

-- Automatically create the config file if it doesn't exist on run
if not fs.exists(config_file) then
    local file = fs.open(config_file, "w")
    if file then
        file.write(textutils.serialiseJSON({}))
        file.close()
    end
end

-- Helper to load the current staging chest configurations
local function load_chest_map()
    if not fs.exists(config_file) then
        return {}
    end
    local file = fs.open(config_file, "r")
    if not file then
        return {}
    end
    local content = file.readAll()
    file.close()
    local success, result = pcall(textutils.unserialiseJSON, content)
    if success and type(result) == "table" then
        return result
    end
    return {}
end

-- Helper function to log messages with timestamps
local function log(level, message)
    local time_str = textutils.formatTime(os.time(), true)
    local formatted = string.format("[%s] [%s] %s", time_str, level, message)
    print(formatted)
end

-- Safely load the current requests from the JSON file
local function load_requests()
    if not fs.exists(requests_file) then
        return {}
    end
    local file = fs.open(requests_file, "r")
    if not file then
        return {}
    end
    local content = file.readAll()
    file.close()
    
    local success, result = pcall(textutils.unserialiseJSON, content)
    if success and type(result) == "table" then
        return result
    end
    log("WARN", "Failed to parse requests file. Resetting requests.")
    return {}
end

-- Safely save the requests to the JSON file
local function save_requests(requests)
    local success, content = pcall(textutils.serialiseJSON, requests)
    if not success then
        log("ERROR", "Failed to serialise requests table")
        return false
    end
    local file = fs.open(requests_file, "w")
    if not file then
        log("ERROR", "Failed to open requests file for writing")
        return false
    end
    file.write(content)
    file.close()
    return true
end

-- Find the Chat Box peripheral (supporting different naming across versions)
local function find_chat_box()
    return peripheral.find("chatBox") or peripheral.find("chat_box")
end

-- Find the ME Bridge peripheral if present on the network
local function find_me_bridge()
    return peripheral.find("me_bridge") or peripheral.find("meBridge") or peripheral.find("me_interface")
end

-- Find all connected Inventory Managers (supporting different naming across versions)
local function find_all_managers()
    local managers = { peripheral.find("inventoryManager") }
    if #managers == 0 then
        managers = { peripheral.find("inventory_manager") }
    end
    return managers
end

-- Find the Inventory Manager bound to a specific player
local function find_manager_for_player(player_name)
    local managers = find_all_managers()
    for _, manager in ipairs(managers) do
        local success, owner = pcall(manager.getOwner)
        if success and owner == player_name then
            return manager
        end
    end
    return nil
end


-- Thread 1: Listen for chat events and process player commands
local function chat_loop()
    log("INFO", "Starting Chat Command Listener thread...")
    while true do
        local event, username, message, uuid, isHidden = os.pullEvent("chat")
        
        -- Run the command handler in a protected call to prevent loop crashes
        local ok, err = pcall(function()
            local words = {}
            for word in message:gmatch("%S+") do
                table.insert(words, word)
            end
            
            local cmd = words[1]
            if cmd == "stock" then
                -- Ignore if there are more than 2 words (prevents false positives from normal sentences)
                if #words > 2 then
                    return
                end
                
                local count = nil
                if words[2] then
                    count = tonumber(words[2])
                    if not count or count <= 0 then
                        log("WARN", username .. " requested invalid count: " .. tostring(words[2]))
                        return
                    end
                end
                
                -- Find the manager for this player
                local manager = find_manager_for_player(username)
                if not manager then
                    log("ERROR", "No Inventory Manager with a memory card found for player: " .. username)
                    return
                end
                
                -- Get the item in the player's main hand
                local item = nil
                local success, res = pcall(manager.getItemInHand)
                if success then
                    item = res
                else
                    log("ERROR", "Failed to call getItemInHand for player " .. username .. ": " .. tostring(res))
                end
                
                if not item or not item.name then
                    log("WARN", username .. " tried to 'stock' but has no item in hand.")
                    return
                end
                
                local requests = load_requests()
                local existing_stock = nil
                local existing_pile = nil
                for _, req in ipairs(requests) do
                    if req.player == username and req.item_name == item.name then
                        local rtype = req.type or "stock"
                        if rtype == "stock" then
                            existing_stock = req
                        elseif rtype == "pile" then
                            existing_pile = req
                        end
                    end
                end
                
                local target_count = count or item.maxStackSize or 64
                local display_name = item.displayName or item.name
                
                if existing_pile and existing_pile.target_count ~= target_count then
                    log("WARN", username .. " tried to stock " .. display_name .. " at " .. target_count .. " but it is piled at " .. existing_pile.target_count)
                    local cb = find_chat_box()
                    if cb then
                        pcall(cb.sendMessage, username .. " is trying to stock and pile " .. display_name .. " at different quantities (" .. target_count .. " vs " .. existing_pile.target_count .. "), but you can't do that, they must be the same quantity to keep at exactly " .. target_count .. ". DINGUS DETECTED!", "Stockpile")
                    end
                    return
                end
                
                if existing_stock then
                    existing_stock.target_count = target_count
                    existing_stock.display_name = display_name
                else
                    table.insert(requests, {
                        player = username,
                        item_name = item.name,
                        display_name = display_name,
                        target_count = target_count,
                        type = "stock"
                    })
                end
                
                save_requests(requests)
                log("INFO", "Added/updated request: " .. username .. " -> " .. display_name .. " x" .. target_count .. " (stock)")
                
                -- Send player notification if possible
                local cb = find_chat_box()
                if cb then
                    pcall(cb.sendToastToPlayer, "Stocked " .. display_name .. " up to " .. target_count, "Stockpile", username, "Stockpile")
                end
                
            elseif cmd == "unstock" then
                -- Ignore if there are more than 1 words (prevents false positives from normal sentences)
                if #words > 1 then
                    return
                end
                
                -- Find the manager for this player
                local manager = find_manager_for_player(username)
                if not manager then
                    log("ERROR", "No Inventory Manager with a memory card found for player: " .. username)
                    return
                end
                
                -- Get the item in the player's main hand
                local item = nil
                local success, res = pcall(manager.getItemInHand)
                if success then
                    item = res
                else
                    log("ERROR", "Failed to call getItemInHand for player " .. username .. ": " .. tostring(res))
                end
                
                if not item or not item.name then
                    log("WARN", username .. " tried to 'unstock' but has no item in hand.")
                    return
                end
                
                local requests = load_requests()
                local new_requests = {}
                local removed = false
                local display_name = item.displayName or item.name
                
                for _, req in ipairs(requests) do
                    local req_type = req.type or "stock"
                    if req.player == username and req.item_name == item.name and req_type == "stock" then
                        removed = true
                    else
                        table.insert(new_requests, req)
                    end
                end
                
                if removed then
                    save_requests(new_requests)
                    log("INFO", "Removed request: " .. username .. " -> " .. display_name)
                    local cb = find_chat_box()
                    if cb then
                        pcall(cb.sendToastToPlayer, "Unstocked " .. display_name, "Stockpile", username, "Stockpile")
                    end
                else
                    log("WARN", "No stockpile entry found for " .. username .. "'s held item: " .. display_name)
                    local cb = find_chat_box()
                    if cb then
                        pcall(cb.sendToastToPlayer, "No stockpile entry found for your held item (" .. display_name .. ")", "Stockpile", username, "Stockpile")
                    end
                end
                
            elseif cmd == "pile" then
                -- Ignore if there are more than 2 words (prevents false positives from normal sentences)
                if #words > 2 then
                    return
                end
                
                local count = nil
                if words[2] then
                    count = tonumber(words[2])
                    if not count or count < 0 then
                        log("WARN", username .. " requested invalid preserve count: " .. tostring(words[2]))
                        return
                    end
                end
                
                -- Find the manager for this player
                local manager = find_manager_for_player(username)
                if not manager then
                    log("ERROR", "No Inventory Manager with a memory card found for player: " .. username)
                    return
                end
                
                -- Get the item in the player's main hand
                local item = nil
                local success, res = pcall(manager.getItemInHand)
                if success then
                    item = res
                else
                    log("ERROR", "Failed to call getItemInHand for player " .. username .. ": " .. tostring(res))
                end
                
                if not item or not item.name then
                    log("WARN", username .. " tried to 'pile' but has no item in hand.")
                    return
                end
                
                local requests = load_requests()
                local existing_stock = nil
                local existing_pile = nil
                for _, req in ipairs(requests) do
                    if req.player == username and req.item_name == item.name then
                        local rtype = req.type or "stock"
                        if rtype == "stock" then
                            existing_stock = req
                        elseif rtype == "pile" then
                            existing_pile = req
                        end
                    end
                end
                
                local target_count = count or 64
                local display_name = item.displayName or item.name
                
                if existing_stock and existing_stock.target_count ~= target_count then
                    log("WARN", username .. " tried to pile " .. display_name .. " leaving " .. target_count .. " but it is stocked at " .. existing_stock.target_count)
                    local cb = find_chat_box()
                    if cb then
                        pcall(cb.sendMessage, username .. " is trying to stock and pile " .. display_name .. " at different quantities (" .. existing_stock.target_count .. " vs " .. target_count .. "), but you can't do that, they must be the same quantity to keep at exactly " .. target_count .. ". DINGUS DETECTED!", "Stockpile")
                    end
                    return
                end
                
                if existing_pile then
                    existing_pile.target_count = target_count
                    existing_pile.display_name = display_name
                else
                    table.insert(requests, {
                        player = username,
                        item_name = item.name,
                        display_name = display_name,
                        target_count = target_count,
                        type = "pile"
                    })
                end
                
                save_requests(requests)
                log("INFO", "Added/updated request: " .. username .. " -> " .. display_name .. " leaving " .. target_count .. " (pile)")
                
                -- Send player notification if possible
                local cb = find_chat_box()
                if cb then
                    pcall(cb.sendToastToPlayer, "Piled " .. display_name .. " down to " .. target_count, "Stockpile", username, "Stockpile")
                end
                
            elseif cmd == "unpile" then
                -- Ignore if there are more than 1 words (prevents false positives from normal sentences)
                if #words > 1 then
                    return
                end
                
                -- Find the manager for this player
                local manager = find_manager_for_player(username)
                if not manager then
                    log("ERROR", "No Inventory Manager with a memory card found for player: " .. username)
                    return
                end
                
                -- Get the item in the player's main hand
                local item = nil
                local success, res = pcall(manager.getItemInHand)
                if success then
                    item = res
                else
                    log("ERROR", "Failed to call getItemInHand for player " .. username .. ": " .. tostring(res))
                end
                
                if not item or not item.name then
                    log("WARN", username .. " tried to 'unpile' but has no item in hand.")
                    return
                end
                
                local requests = load_requests()
                local new_requests = {}
                local removed = false
                local display_name = item.displayName or item.name
                
                for _, req in ipairs(requests) do
                    if req.player == username and req.item_name == item.name and req.type == "pile" then
                        removed = true
                    else
                        table.insert(new_requests, req)
                    end
                end
                
                if removed then
                    save_requests(new_requests)
                    log("INFO", "Removed pile request: " .. username .. " -> " .. display_name)
                    local cb = find_chat_box()
                    if cb then
                        pcall(cb.sendToastToPlayer, "Unpiled " .. display_name, "Stockpile", username, "Stockpile")
                    end
                else
                    log("WARN", "No pile entry found for " .. username .. "'s held item: " .. display_name)
                    local cb = find_chat_box()
                    if cb then
                        pcall(cb.sendToastToPlayer, "No pile entry found for your held item (" .. display_name .. ")", "Stockpile", username, "Stockpile")
                    end
                end
                
            elseif cmd == "stockpile" then
                -- Ignore if there are not exactly 2 words
                if #words ~= 2 then
                    return
                end
                
                if words[2] == "reset" then
                    local requests = load_requests()
                    local new_requests = {}
                    local removed_count = 0
                    
                    for _, req in ipairs(requests) do
                        if req.player == username then
                            removed_count = removed_count + 1
                        else
                            table.insert(new_requests, req)
                        end
                    end
                    
                    if removed_count > 0 then
                        save_requests(new_requests)
                        log("INFO", "Reset all " .. removed_count .. " stockpile/pile entries for player: " .. username)
                        local cb = find_chat_box()
                        if cb then
                            pcall(cb.sendToastToPlayer, "Wiped all (" .. removed_count .. ") of your stockpile and pile requests.", "Stockpile", username, "Stockpile")
                        end
                    else
                        log("WARN", "Player " .. username .. " requested reset but had no active entries.")
                        local cb = find_chat_box()
                        if cb then
                            pcall(cb.sendToastToPlayer, "You don't have any active stockpile or pile requests to reset.", "Stockpile", username, "Stockpile")
                        end
                    end
                end
            end
        end)
        
        if not ok then
            log("ERROR", "Exception in chat handler: " .. tostring(err))
        end
    end
end

-- Render a visual dashboard on any adjacent Monitor
local function update_monitor()
    local mon = peripheral.find("monitor")
    if not mon then
        return
    end
    
    local is_color = mon.isColor()
    
    -- Clear and setup
    mon.setTextScale(0.5) -- High density text
    local w, h = mon.getSize()
    mon.clear()
    
    -- Colors config
    local bg_color = is_color and colors.black or colors.black
    local text_color = is_color and colors.white or colors.white
    local header_bg = is_color and colors.green or colors.black
    local header_text = is_color and colors.white or colors.white
    local player_color = is_color and colors.yellow or colors.white
    local stock_color = is_color and colors.lightBlue or colors.white
    local pile_color = is_color and colors.orange or colors.white
    local border_color = is_color and colors.gray or colors.white
    local label_color = is_color and colors.lightGray or colors.white
    
    mon.setBackgroundColor(bg_color)
    mon.setTextColor(text_color)
    
    -- Draw header
    mon.setBackgroundColor(header_bg)
    mon.setTextColor(header_text)
    
    local title = " MOBIUS STOCKPILE "
    local padding = math.max(0, math.floor((w - #title) / 2))
    mon.setCursorPos(1, 1)
    mon.write(string.rep(" ", w)) -- Fill header row
    mon.setCursorPos(1 + padding, 1)
    mon.write(title)
    
    mon.setBackgroundColor(bg_color)
    
    -- Draw Border separator
    mon.setTextColor(border_color)
    mon.setCursorPos(1, 2)
    mon.write(string.rep("-", w))
    
    local requests = load_requests()
    if #requests == 0 then
        mon.setTextColor(is_color and colors.red or colors.white)
        mon.setCursorPos(1, 4)
        local msg = "No Active Requests"
        local msg_pad = math.max(1, math.floor((w - #msg) / 2))
        mon.setCursorPos(msg_pad, 4)
        mon.write(msg)
        return
    end
    
    -- Group requests by player
    local grouped = {}
    local sorted_players = {}
    for _, req in ipairs(requests) do
        if not grouped[req.player] then
            grouped[req.player] = {}
            table.insert(sorted_players, req.player)
        end
        table.insert(grouped[req.player], req)
    end
    
    table.sort(sorted_players)
    
    local current_line = 3
    for _, player in ipairs(sorted_players) do
        local reqs = grouped[player]
        if current_line >= h then break end
        
        -- Draw Player Name
        mon.setTextColor(player_color)
        mon.setCursorPos(1, current_line)
        mon.write(player)
        
        -- Check for and display any configuration/hardware errors in red
        local PLAYER_CHEST_MAP = load_chest_map()
        local has_chest = PLAYER_CHEST_MAP[player] ~= nil
        local has_card = find_manager_for_player(player) ~= nil
        
        local errs = {}
        if not has_chest then
            table.insert(errs, "(NO CHEST)")
        end
        if not has_card then
            table.insert(errs, "(NO CARD)")
        end
        
        if #errs > 0 then
            mon.setTextColor(colors.red)
            mon.write(" " .. table.concat(errs, " "))
        end
        
        current_line = current_line + 1
        
        for _, req in ipairs(reqs) do
            if current_line >= h then break end
            
            local req_type = req.type or "stock"
            local prefix = "[STCK]"
            local item_color = stock_color
            if req_type == "pile" then
                prefix = "[PILE]"
                item_color = pile_color
            end
            
            -- Format:  [STCK] 64x Cobblestone
            mon.setCursorPos(2, current_line)
            mon.setTextColor(item_color)
            mon.write(prefix .. " ")
            
            mon.setTextColor(text_color)
            local qty_str = tostring(req.target_count) .. "x "
            mon.write(qty_str)
            
            -- Truncate item display name if too long for screen
            local remaining_space = w - 2 - #prefix - 1 - #qty_str
            local item_display = req.display_name or req.item_name
            if #item_display > remaining_space then
                item_display = item_display:sub(1, remaining_space - 3) .. "..."
            end
            mon.write(item_display)
            
            current_line = current_line + 1
        end
        
        -- Blank line between players if space allows
        current_line = current_line + 1
    end
    
end

-- Thread 2: Periodically check and restock players
local function restock_loop()
    log("INFO", "Starting Restocking Thread...")
    while true do
        os.sleep(2)
        
        local ok, err = pcall(function()
            -- Always update adjacent monitor first
            pcall(update_monitor)
            
            local requests = load_requests()
            if #requests == 0 then
                return
            end
            
            -- Group requests by player and by type (stock vs pile)
            local player_stock_requests = {}
            local player_pile_requests = {}
            local unique_players = {}
            
            for _, req in ipairs(requests) do
                local req_type = req.type or "stock"
                unique_players[req.player] = true
                
                if req_type == "stock" then
                    if not player_stock_requests[req.player] then
                        player_stock_requests[req.player] = {}
                    end
                    table.insert(player_stock_requests[req.player], req)
                elseif req_type == "pile" then
                    if not player_pile_requests[req.player] then
                        player_pile_requests[req.player] = {}
                    end
                    table.insert(player_pile_requests[req.player], req)
                end
            end
            
            local me = find_me_bridge()
            local PLAYER_CHEST_MAP = load_chest_map()
            for player, _ in pairs(unique_players) do
                local target_chest = PLAYER_CHEST_MAP[player]
                if not target_chest then
                    log("WARN", "Skipping player " .. player .. ": No staging chest configured in PLAYER_CHEST_MAP")
                else
                    local manager = find_manager_for_player(player)
                    if not manager then
                        log("ERROR", "No Inventory Manager found with a memory card for player: " .. player)
                    else
                        -- Get the player's current items
                        local success, player_items = pcall(manager.getItems)
                        if not success or not player_items then
                            log("ERROR", "Failed to read inventory for player: " .. player)
                        else
                            -- Count current items for each request
                            local current_counts = {}
                            local stock_reqs = player_stock_requests[player] or {}
                            local depletion_reqs = player_pile_requests[player] or {}
                            
                            for _, req in ipairs(stock_reqs) do
                                current_counts[req.item_name] = 0
                            end
                            for _, req in ipairs(depletion_reqs) do
                                current_counts[req.item_name] = 0
                            end
                            
                            for _, item in pairs(player_items) do
                                if current_counts[item.name] then
                                    current_counts[item.name] = current_counts[item.name] + item.count
                                end
                            end
                            
                            -- Process Stockpile / Restocking requests
                            for _, req in ipairs(stock_reqs) do
                                local needed = req.target_count - current_counts[req.item_name]
                                if needed > 0 then
                                    -- Find if the player already has this item in a slot (so we can restock into the same slot)
                                    -- ONLY target the slot if it is NOT completely full yet.
                                    local target_slot = nil
                                    for _, item in pairs(player_items) do
                                        if item.name == req.item_name then
                                            if item.count < (item.maxStackSize or 64) then
                                                target_slot = item.slot
                                                break
                                            end
                                        end
                                    end
                                    
                                    -- Export the needed count from the ME system into the player's staging chest
                                    local success_exp, exported = pcall(me.exportItem, { name = req.item_name, count = needed }, target_chest)
                                    if not success_exp then
                                        log("ERROR", "Failed to export " .. req.display_name .. " to " .. target_chest .. ": " .. tostring(exported))
                                    elseif not exported or exported == 0 then
                                        log("WARN", "ME network out of stock for " .. req.display_name .. " (needed " .. needed .. ")")
                                    else
                                        log("INFO", "ME Bridge exported " .. exported .. "x " .. req.display_name .. " to " .. target_chest)
                                    end
                                    
                                    -- Prepare the transfer payload
                                    local transfer_payload = { name = req.item_name, count = needed }
                                    if target_slot then
                                        transfer_payload.toSlot = target_slot
                                    end
                                    
                                    -- Add item to player from the staging chest on top of the Inventory Manager
                                    local success_add, added = pcall(manager.addItemToPlayer, "up", transfer_payload)
                                    if not success_add then
                                        log("ERROR", "Failed to add item to " .. player .. ": " .. tostring(added))
                                    elseif added and added > 0 then
                                        log("INFO", "Restocked " .. added .. "x " .. req.display_name .. " to player " .. player .. (target_slot and (" (into slot " .. target_slot .. ")") or ""))
                                    else
                                        log("WARN", "Tried to restock " .. needed .. "x " .. req.display_name .. " to player " .. player .. ", but added 0 (supply empty or inventory full)")
                                    end
                                    
                                    -- Clean up/sweep leftovers back to ME Bridge from player's staging chest
                                    local success_imp, imported = pcall(me.importItem, target_chest)
                                    if success_imp and imported and imported > 0 then
                                        log("INFO", "Returned " .. imported .. "x " .. req.display_name .. " from " .. target_chest .. " back to ME network")
                                    end
                                end
                            end
                            
                            -- Process Pile / Depletion requests
                            for _, req in ipairs(depletion_reqs) do
                                local current_qty = current_counts[req.item_name]
                                local excess = current_qty - req.target_count
                                if excess > 0 then
                                    -- Gather all slots containing this item
                                    local other_slots = {}
                                    local hotbar_slots = {}
                                    
                                    for _, item in pairs(player_items) do
                                        if item.name == req.item_name then
                                            -- Determine if hotbar (1-9) or other (>= 10)
                                            local is_hotbar = (item.slot >= 1 and item.slot <= 9)
                                            if is_hotbar then
                                                table.insert(hotbar_slots, item)
                                            else
                                                table.insert(other_slots, item)
                                            end
                                        end
                                    end
                                    
                                    -- Try other_slots first, then hotbar_slots
                                    local targets = {}
                                    for _, item in ipairs(other_slots) do
                                        table.insert(targets, item)
                                    end
                                    for _, item in ipairs(hotbar_slots) do
                                        table.insert(targets, item)
                                    end
                                    
                                    local total_removed = 0
                                    local remaining_excess = excess
                                    
                                    for _, item in ipairs(targets) do
                                        if remaining_excess <= 0 then
                                            break
                                        end
                                        
                                        local take = math.min(remaining_excess, item.count)
                                        local success_rem, removed = pcall(manager.removeItemFromPlayer, "up", {
                                            name = req.item_name,
                                            fromSlot = item.slot,
                                            count = take
                                        })
                                        
                                        if not success_rem then
                                            log("ERROR", "Failed to remove item from slot " .. item.slot .. " for player " .. player .. ": " .. tostring(removed))
                                            break
                                        elseif removed and removed > 0 then
                                            total_removed = total_removed + removed
                                            remaining_excess = remaining_excess - removed
                                        else
                                            break
                                        end
                                    end
                                    
                                    if total_removed > 0 then
                                        log("INFO", "Depleted " .. total_removed .. "x " .. req.display_name .. " from player " .. player)
                                        
                                        -- Import the depleted items from player's staging chest back into ME system
                                        local success_imp, imported = pcall(me.importItem, target_chest)
                                        if not success_imp then
                                            log("ERROR", "Failed to import depleted items back into ME from " .. target_chest .. ": " .. tostring(imported))
                                        elseif imported and imported > 0 then
                                            log("INFO", "Imported " .. imported .. "x " .. req.display_name .. " back into ME network")
                                        end
                                    else
                                        log("WARN", "Tried to deplete " .. excess .. "x " .. req.display_name .. " from player " .. player .. ", but removed 0 (chest full?)")
                                    end
                                end
                            end
                        end
                    end
                end
            end
            
            -- Global Sweep: Clear all configured staging chests back into AE2 storage at the end of each cycle
            if me then
                for player, chest_peripheral in pairs(PLAYER_CHEST_MAP) do
                    local success_imp, imported = pcall(me.importItem, chest_peripheral)
                    if success_imp and imported and imported > 0 then
                        log("INFO", "Global Sweep: Returned " .. imported .. "x items from " .. player .. "'s chest (" .. chest_peripheral .. ") back to ME network")
                    end
                end
            end
        end)
        
        if not ok then
            log("ERROR", "Exception in restocking loop: " .. tostring(err))
        end
    end
end

-- Check that necessary peripherals exist on startup
local cb = find_chat_box()
local managers = find_all_managers()
local me = find_me_bridge()

if not cb or #managers == 0 or not me then
    local err_msg = "Stockpile initialization failed: "
    local errors = {}
    if not cb then table.insert(errors, "Missing Chat Box") end
    if #managers == 0 then table.insert(errors, "Missing Inventory Manager") end
    if not me then table.insert(errors, "Missing ME Bridge") end
    
    err_msg = err_msg .. table.concat(errors, ", ") .. "!"
    log("CRITICAL", err_msg)
    
    -- If chat box is available, notify game chat before crashing
    if cb then
        pcall(cb.sendMessage, "CRITICAL ERROR: " .. err_msg, "Stockpile")
    end
    
    error(err_msg)
end

log("INFO", "Initializing Stockpile...")
parallel.waitForAny(chat_loop, restock_loop)
