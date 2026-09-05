-- print_stockpile_manual.lua
-- Printer utility to print the Mobius Technologies Stockpile System Manual.

local manual_file = "in-game-manual.txt"

local function log(level, message)
    print(string.format("[%s] %s", level, message))
end

-- 1. Locate the printer peripheral
local printer = peripheral.find("printer")
if not printer then
    log("ERROR", "No printer peripheral detected! Please connect a Printer to the computer or wired network.")
    return
end

-- 2. Check for the manual file
if not fs.exists(manual_file) then
    log("ERROR", "Source file '" .. manual_file .. "' not found!")
    return
end

-- 3. Read and split the manual content into pages
local file = fs.open(manual_file, "r")
if not file then
    log("ERROR", "Failed to open '" .. manual_file .. "' for reading.")
    return
end
local content = file.readAll()
file.close()

-- Split content into individual lines, preserving empty lines and handling \r\n, \n, and \r cleanly
local lines = {}
local idx = 1
while idx <= #content do
    local start_idx, end_idx = content:find("[\r\n]", idx)
    if not start_idx then
        table.insert(lines, content:sub(idx))
        break
    end
    table.insert(lines, content:sub(idx, start_idx - 1))
    if content:sub(start_idx, start_idx + 1) == "\r\n" then
        idx = start_idx + 2
    else
        idx = start_idx + 1
    end
end

-- Parse pages (splitting by <page>)
local pages = {}
local current_page = {}
for _, line in ipairs(lines) do
    if line:match("<page>") then
        table.insert(pages, current_page)
        current_page = {}
    else
        table.insert(current_page, line)
    end
end
table.insert(pages, current_page) -- Insert the last page

-- 4. Check paper and ink levels before starting
local required_pages = #pages
local paper = printer.getPaperLevel()
local ink = printer.getInkLevel()

log("INFO", "Manual loaded. Total pages to print: " .. required_pages)
log("INFO", "Current printer levels - Paper: " .. paper .. ", Ink: " .. ink)

if paper < required_pages then
    log("ERROR", "Insufficient paper! Printer has " .. paper .. " sheets, but we need " .. required_pages .. ".")
    log("INFO", "Please insert more paper into the printer and try again.")
    return
end

if ink < required_pages then
    log("ERROR", "Insufficient ink! Printer has " .. ink .. " ink points, but we need at least " .. required_pages .. ".")
    log("INFO", "Please insert dye (like ink sacs or black dye) into the printer and try again.")
    return
end

-- 5. Print each page
log("INFO", "Starting print job...")
for i, page in ipairs(pages) do
    log("INFO", "Printing page " .. i .. " of " .. required_pages .. "...")
    
    -- Start a new page sheet
    if not printer.newPage() then
        log("ERROR", "Failed to start page " .. i .. "! Check if paper or ink ran out mid-job.")
        return
    end
    
    -- Set page title (name of the printed sheet item in-game)
    printer.setPageTitle("Stockpile Manual - Page " .. i)
    
    -- Write each line of text
    for line_num, line in ipairs(page) do
        -- CC cursor coordinates are (column, row), 1-indexed.
        printer.setCursorPos(1, line_num)
        printer.write(line)
    end
    
    -- Finalize and output the page
    if not printer.endPage() then
        log("ERROR", "Printer failed to output page " .. i .. "!")
        return
    end
end

log("INFO", "Print job completed successfully! Pick up your manual pages from the printer's output slot.")
