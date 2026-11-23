-- Options.lua
-- The settings window (/ts).

local _, ns = ...
local K = ns.K

local window

local function Apply()
    if not ns.Refresh() then
        K.Print("that takes effect when combat ends.")
    end
end

local function Build()
    local db = ns.db
    window = K.Window("TrinketSwapperOptions", "TrinketSwapper", 430, 428)
    local x, y = 16, -42
    y = K.Para(window, "Put the mouse on a trinket icon to see the trinkets in your bags. Left-click one to wear it as your top trinket, right-click as your bottom trinket. In combat it's queued and goes on when the fight ends. Click an icon to use that trinket.", x, y, 396)
    K.Stepper(window, "Icon size", x, y,
        function() return tonumber(db.size) or 36 end,
        function(value) db.size = value Apply() end, 2, 20, 72)
    y = y - 30
    K.Check(window, "Open the menu below the icons", x, y,
        function() return db.below == true end,
        function(checked) db.below = checked Apply() end,
        "Off: above them. For when the icons sit near the top of the screen.")
    y = y - 24
    K.Check(window, "Keep bag trinkets on cooldown showing", x, y,
        function() return db.tray ~= false end,
        function(checked) db.tray = checked Apply() end,
        "A trinket you used and swapped out stays by the icons, counting down, until it's ready again.")
    y = y - 24
    K.Check(window, "Say \"Swap\" when swapping costs nothing", x, y,
        function() return db.swap ~= false end,
        function(checked) db.swap = checked Apply() end,
        "Wearing a trinket starts a 30 second cooldown on it. \"Swap\" shows on a worn trinket that has longer than that left, when a bag trinket is ready to take its place.")
    y = y - 24
    K.Check(window, "And show \"Swap\" in the middle of the screen", x + 18, y,
        function() return db.alert ~= false end,
        function(checked) db.alert = checked end,
        "With \"Swap\" on the icon, the trinket's icon with \"Swap\" under it also shows in the middle of the screen for 10 seconds, once per cooldown, out of combat. Move it with the Move button; /ts swap shows it.")
    y = y - 24
    K.Check(window, "Light the icon while the trinket's buff is on you", x, y,
        function() return db.buffs ~= false end,
        function(checked)
            db.buffs = checked
            if not ns.ApplyBuffs() then
                K.Print("that changes when the fight ends.")
            end
        end,
        "The buff from using a trinket, or from its proc, shows on its icon in a green edge with its time sweeping away. A proc trinket whose buff is known waits grey for it. /ts buffs says what it knows of each.")
    y = y - 24
    K.Check(window, "Show each trinket's key on its icon", x, y,
        function() return db.keys ~= false end,
        function(checked) db.keys = checked Apply() end)
    y = y - 24
    K.Check(window, "Show the minimap button", x, y,
        function() return db.minimap.hide ~= true end,
        function(checked) db.minimap.hide = not checked ns.ApplyMinimapButton() end,
        "Off: /ts still opens these settings, and /ts minimap brings the button back.")
    y = y - 30
    y = K.Para(window, "Keys for using each trinket are set in the game's Key Bindings, under TrinketSwapper.", x, y, 396)
    y = y - 4
    K.Button(window, "Move", 80, x, y, function()
        if not ns.Move() and K.inCombat then
            K.Print("not in combat.")
        end
    end, "Blue boxes over the icons and where the swap alert shows: drag them, then click Move again.")
    K.Button(window, "Reset", 80, x + 90, y, function()
        if K.inCombat then
            K.Print("not in combat.")
            return
        end
        ns.Reset()
        window:Refresh()
    end, "Settings and position back to how they came.")
end

function ns.ToggleOptions()
    if not window then
        Build()
    end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
    return window
end
