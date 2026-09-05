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
                local found = false
                local target_count = count or item.maxStackSize or 64
                local display_name = item.displayName or item.name
                
                for _, req in ipairs(requests) do
                    if req.player == username and req.item_name == item.name then
                        local req_type = req.type or "stock"
                        if req_type == "pile" then
                            log("WARN", username .. " tried to stock " .. display_name .. " but it is already marked for piling.")
                            local cb = find_chat_box()
                            if cb then
                                pcall(cb.sendMessage, username .. " is trying to stock and pile " .. display_name .. " at the same time, but you can't do that, they need to unpile " .. display_name .. " first. DINGUS DETECTED!", "Stockpile")
                            end
                            return
                        end
                        req.target_count = target_count
                        req.display_name = display_name
                        req.type = "stock"
                        found = true
                        break
                    end
                end
                if not found then
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
                    pcall(cb.sendMessageToPlayer, "Stocked " .. display_name .. " up to " .. target_count, username, "Stockpile")
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
                        pcall(cb.sendMessageToPlayer, "Unstocked " .. display_name, username, "Stockpile")
                    end
                else
                    log("WARN", "No stockpile entry found for " .. username .. "'s held item: " .. display_name)
                    local cb = find_chat_box()
                    if cb then
                        pcall(cb.sendMessageToPlayer, "No stockpile entry found for your held item (" .. display_name .. ")", username, "Stockpile")
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
                local found = false
                local target_count = count or 64
                local display_name = item.displayName or item.name
                
                for _, req in ipairs(requests) do
                    if req.player == username and req.item_name == item.name then
                        local req_type = req.type or "stock"
                        if req_type == "stock" then
                            log("WARN", username .. " tried to pile " .. display_name .. " but it is already marked for stocking.")
                            local cb = find_chat_box()
                            if cb then
                                pcall(cb.sendMessage, username .. " is trying to stock and pile " .. display_name .. " at the same time, but you can't do that, they need to unstock " .. display_name .. " first. DINGUS DETECTED!", "Stockpile")
                            end
                            return
                        end
                        req.target_count = target_count
                        req.display_name = display_name
                        req.type = "pile"
                        found = true
                        break
                    end
                end
                if not found then
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
                    pcall(cb.sendMessageToPlayer, "Piled " .. display_name .. " down to " .. target_count, username, "Stockpile")
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
                        pcall(cb.sendMessageToPlayer, "Unpiled " .. display_name, username, "Stockpile")
                    end
                else
                    log("WARN", "No pile entry found for " .. username .. "'s held item: " .. display_name)
                    local cb = find_chat_box()
                    if cb then
                        pcall(cb.sendMessageToPlayer, "No pile entry found for your held item (" .. display_name .. ")", username, "Stockpile")
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
                            pcall(cb.sendMessageToPlayer, "Wiped all (" .. removed_count .. ") of your stockpile and pile requests.", username, "Stockpile")
                        end
                    else
                        log("WARN", "Player " .. username .. " requested reset but had no active entries.")
                        local cb = find_chat_box()
                        if cb then
                            pcall(cb.sendMessageToPlayer, "You don't have any active stockpile or pile requests to reset.", username, "Stockpile")
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
    for _, req in ipairs(requests) do
        if not grouped[req.player] then
            grouped[req.player] = {}
        end
        table.insert(grouped[req.player], req)
    end
    
    local current_line = 3
    for player, reqs in pairs(grouped) do
        if current_line >= h then break end
        
        -- Draw Player Name
        mon.setTextColor(player_color)
        mon.setCursorPos(1, current_line)
        mon.write(player)
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
            
            for player, _ in pairs(unique_players) do
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
                                
                                -- Prepare the transfer payload
                                local transfer_payload = { name = req.item_name, count = needed }
                                if target_slot then
                                    transfer_payload.toSlot = target_slot
                                end
                                
                                -- Add item to player from the supply chest on top of the Inventory Manager
                                local success_add, added = pcall(manager.addItemToPlayer, "up", transfer_payload)
                                if not success_add then
                                    log("ERROR", "Failed to add item to " .. player .. ": " .. tostring(added))
                                elseif added and added > 0 then
                                    log("INFO", "Restocked " .. added .. "x " .. req.display_name .. " to player " .. player .. (target_slot and (" (into slot " .. target_slot .. ")") or ""))
                                else
                                    log("WARN", "Tried to restock " .. needed .. "x " .. req.display_name .. " to player " .. player .. ", but added 0 (supply empty or inventory full)")
                                end
                            end
                        end
                        
                        -- Process Pile / Depletion requests
                        for _, req in ipairs(depletion_reqs) do
                            local current_qty = current_counts[req.item_name]
                            local excess = current_qty - req.target_count
                            if excess > 0 then
                                -- Remove excess items from player and place in the supply/disposal chest on top of the Inventory Manager
                                local success_rem, removed = pcall(manager.removeItemFromPlayer, "up", { name = req.item_name, count = excess })
                                if not success_rem then
                                    log("ERROR", "Failed to remove item from " .. player .. ": " .. tostring(removed))
                                elseif removed and removed > 0 then
                                    log("INFO", "Depleted " .. removed .. "x " .. req.display_name .. " from player " .. player)
                                else
                                    log("WARN", "Tried to deplete " .. excess .. "x " .. req.display_name .. " from player " .. player .. ", but removed 0 (chest full?)")
                                end
                            end
                        end
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

if not cb or #managers == 0 then
    local err_msg = "Stockpile initialization failed: "
    if not cb and #managers == 0 then
        err_msg = err_msg .. "Missing Chat Box AND Inventory Manager!"
    elseif not cb then
        err_msg = err_msg .. "Missing Chat Box peripheral!"
    else
        err_msg = err_msg .. "Missing Inventory Manager peripheral!"
    end
    
    log("CRITICAL", err_msg)
    
    -- If chat box is available, notify game chat before crashing
    if cb then
        pcall(cb.sendMessage, "CRITICAL ERROR: " .. err_msg, "Stockpile")
    end
    
    error(err_msg)
end

log("INFO", "Initializing Stockpile...")
parallel.waitForAny(chat_loop, restock_loop)
