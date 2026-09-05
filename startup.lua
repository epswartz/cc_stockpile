-- startup.lua
-- Auto-run stockpile on boot in the background (if multishell is available)
if multishell then
    shell.openTab("stockpile.lua")
else
    shell.run("stockpile.lua")
end

