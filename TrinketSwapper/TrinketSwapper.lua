-- TrinketSwapper.lua
-- Your two trinkets as a pair of icons, with a menu for swapping them.
--
--   * Each icon shows the trinket in that slot and its cooldown. Click it
--     (or press its key: Key Bindings > TrinketSwapper) to use the trinket.
--   * Put the mouse on either icon and the trinkets in your bags open in a
--     menu. Left-click one to wear it as your top trinket, right-click to
--     wear it as your bottom trinket.
--   * The game doesn't allow trinket swaps in combat. A click then queues
--     the trinket for that slot (it shows small in the icon's corner) and
--     it goes on the moment combat ends. Click it again to take it back.
--   * Bag trinkets that are on cooldown stay showing by the icons, counting
--     down, so you can see when one is ready to swap back in.
--   * Wearing a trinket starts a 30 second cooldown on it. Once the trinket
--     you're wearing has longer than that left, swapping costs nothing:
--     "Swap" shows on its icon when a bag trinket is ready to take its place.
--
-- /ts opens the settings; /ts move moves the icons.

local _, ns = ...
local K = ns.K

K.title = "TrinketSwapper"
K.color = "ffe6b450"

local TOP, BOTTOM = 13, 14
local SLOTS = { TOP, BOTTOM }
local GAP = 4
local MENU_TALL = 4          -- trinkets to a column before the next one starts
local SWAP_COOLDOWN = 30     -- the cooldown wearing a trinket starts
local EMPTY = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket"
local DEFAULTS = { size = 36, tray = true, swap = true, keys = true, below = false, durations = {} }
local SPOT = { "CENTER", "CENTER", 0, -220 }

_G.BINDING_HEADER_TRINKETSWAPPER = "TrinketSwapper"
_G["BINDING_NAME_CLICK TrinketSwapperSlot13:LeftButton"] = "Use top trinket"
_G["BINDING_NAME_CLICK TrinketSwapperSlot14:LeftButton"] = "Use bottom trinket"

local db
local bar, flyout, dragBox
local slots = {}             -- slot -> its icon (a secure button)
local seenCooldowns = {}     -- item -> { start, duration }, as last read
local queued = {}            -- slot -> { itemID, icon, link }
local pendingLayout = false

local function InCombat()
    return K.Bool(InCombatLockdown(), false)
end

------------------------------------------------------------------------------
-- Cooldowns
------------------------------------------------------------------------------
-- A trinket's cooldown belongs to the item, so it keeps running in your
-- bags. What was last read is kept by item: where the game stops saying
-- (in combat it can), the icon goes on counting from that.

local function Remember(itemID, start, duration)
    if start > 0 and duration > 1.5 then
        local seen = seenCooldowns[itemID]
        if not seen then
            seen = {}
            seenCooldowns[itemID] = seen
        end
        seen[1], seen[2] = start, duration
        -- The longest seen is the trinket's own (30 seconds is the one
        -- wearing it starts).
        if duration > (db.durations[itemID] or 0) then
            db.durations[itemID] = duration
        end
    else
        seenCooldowns[itemID] = nil
    end
end

local function Seen(itemID)
    local seen = itemID and seenCooldowns[itemID]
    if seen and seen[1] + seen[2] > GetTime() then
        return seen[1], seen[2]
    end
    if seen then
        seenCooldowns[itemID] = nil
    end
    return nil
end

local function SlotItem(slot)
    return K.Num(GetInventoryItemID("player", slot))
end

-- The worn trinket's cooldown: its start and duration, or nil when ready.
local function SlotCooldown(slot)
    local itemID = SlotItem(slot)
    if not itemID then
        return nil
    end
    local start, duration = GetInventoryItemCooldown("player", slot)
    start, duration = K.Num(start), K.Num(duration)
    if start and duration then
        Remember(itemID, start, duration)
    end
    return Seen(itemID)
end

-- A bag trinket's.
local function BagCooldown(itemID)
    local start, duration = C_Container.GetItemCooldown(itemID)
    start, duration = K.Num(start), K.Num(duration)
    if start and duration then
        Remember(itemID, start, duration)
    end
    return Seen(itemID)
end

local function Left(itemID)
    local start, duration = Seen(itemID)
    return start and (start + duration - GetTime()) or 0
end

------------------------------------------------------------------------------
-- The trinkets in your bags
------------------------------------------------------------------------------

local bagList, bagStale = {}, true

-- (Read once after each change to your bags, not every time it's asked.)
local function BagTrinkets()
    if not bagStale then
        return bagList
    end
    bagStale = false
    local list = {}
    bagList = list
    for bag = 0, 5 do
        local count = K.Num(C_Container.GetContainerNumSlots(bag)) or 0
        for slot = 1, count do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = info and K.Num(info.itemID)
            if itemID then
                local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
                if equipLoc == "INVTYPE_TRINKET" then
                    list[#list + 1] = { bag = bag, slot = slot, itemID = itemID, icon = info.iconFileID,
                        link = info.hyperlink }
                end
            end
        end
    end
    return list
end

local function CoolingTrinkets()
    local list = {}
    for _, item in ipairs(BagTrinkets()) do
        item.start, item.duration = BagCooldown(item.itemID)
        if item.start then
            list[#list + 1] = item
        end
    end
    return list
end

-- Wears a bag trinket the way dragging it onto the slot does: pick it up,
-- drop it on the slot. The one it replaces goes into the bag slot it left.
local function EquipFromBag(item, slot)
    local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
    local still = info and K.Num(info.itemID) == item.itemID
    if still then
        ClearCursor()
        C_Container.PickupContainerItem(item.bag, item.slot)
        if CursorHasItem() then
            PickupInventoryItem(slot)
        end
        if CursorHasItem() then
            -- Didn't take (a restriction): don't leave it on the cursor.
            ClearCursor()
        end
        return
    end
    bagStale = true
    -- The bags changed since the menu opened: by name instead.
    local equip = C_Item.EquipItemByName or rawget(_G, "EquipItemByName")
    if equip then
        equip(item.link or item.itemID, slot)
    end
end

------------------------------------------------------------------------------
-- The two icons
------------------------------------------------------------------------------

local Update, ShowTray   -- below

local function Skin(frame)
    local edge = frame:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0, 1)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local hover = frame:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.18)
    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    frame.icon, frame.cooldown = icon, cooldown
end

local function ShowKey(button)
    local text = ""
    if db.keys ~= false then
        local key = GetBindingKey("CLICK TrinketSwapperSlot" .. button.slot .. ":LeftButton")
        if key then
            local short = rawget(_G, "GetBindingText")
            text = short and short(key, true) or key
        end
    end
    button.key:SetText(text)
end

-- A bag trinket worth putting on: ready by the time the swap cooldown is over.
local function SwapCandidate()
    for _, item in ipairs(BagTrinkets()) do
        BagCooldown(item.itemID)
        if Left(item.itemID) <= SWAP_COOLDOWN then
            return item
        end
    end
    return nil
end

local function UpdateSlot(button)
    local slot = button.slot
    local itemID = SlotItem(slot)
    button.icon:SetTexture(itemID and GetInventoryItemTexture("player", slot) or EMPTY)
    local start, duration = SlotCooldown(slot)
    if start then
        button.cooldown:SetCooldown(start, duration)
    else
        button.cooldown:Clear()
    end
    local item = queued[slot]
    button.queuedIcon:SetTexture(item and item.icon or nil)
    button.queuedFrame:SetShown(item ~= nil)
    -- "Swap": this one has longer left than wearing another would cost.
    local swap = db.swap ~= false and item == nil and itemID ~= nil and Left(itemID) > SWAP_COOLDOWN
        and SwapCandidate() ~= nil
    button.swap:SetShown(swap)
    ShowKey(button)
end

Update = function()
    if not bar then
        return
    end
    for _, slot in ipairs(SLOTS) do
        UpdateSlot(slots[slot])
    end
end

-- Sizes and places everything. The icons are secure buttons (they use the
-- trinket), which the game won't let an addon move or size in combat: then
-- it waits for the fight to end.
local function Layout()
    if not bar then
        return
    end
    if InCombat() then
        pendingLayout = true
        return
    end
    pendingLayout = false
    local size = tonumber(db.size) or DEFAULTS.size
    bar:SetSize(size * 2 + GAP, size)
    K.Place(bar, db.pos, SPOT)
    for index, slot in ipairs(SLOTS) do
        local button = slots[slot]
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint("LEFT", bar, "LEFT", (index - 1) * (size + GAP), 0)
        button.queuedFrame:SetSize(size * 0.45, size * 0.45)
    end
    Update()
    ShowTray()
end

local OpenMenu   -- below

local function SlotEnter(button)
    OpenMenu()
    local tooltip = rawget(_G, "GameTooltip")
    if tooltip then
        tooltip:SetOwner(button, db.below and "ANCHOR_TOPLEFT" or "ANCHOR_BOTTOMRIGHT")
        if SlotItem(button.slot) then
            tooltip:SetInventoryItem("player", button.slot)
        else
            tooltip:SetText(button.slot == TOP and "Top trinket (empty)" or "Bottom trinket (empty)")
        end
        tooltip:Show()
    end
end

local function HideTooltip()
    local tooltip = rawget(_G, "GameTooltip")
    if tooltip then
        tooltip:Hide()
    end
end

local function BuildSlot(slot)
    local button = CreateFrame("Button", "TrinketSwapperSlot" .. slot, bar, "SecureActionButtonTemplate")
    button.slot = slot
    -- A key press arrives as a down and an up click; the button acts on the
    -- one your "cast on key down" setting picks. Left-click uses the trinket.
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "/use " .. slot)
    button:SetAttribute("type2", "")
    Skin(button)
    local over = CreateFrame("Frame", nil, button)
    over:SetAllPoints()
    over:SetFrameLevel(button:GetFrameLevel() + 5)
    button.key = over:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    button.key:SetPoint("TOPRIGHT", -2, -3)
    button.swap = over:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.swap:SetPoint("BOTTOM", 0, 3)
    button.swap:SetText("Swap")
    button.swap:SetTextColor(1, 0.82, 0.2)
    button.swap:Hide()
    -- The trinket queued for this slot, small in the corner.
    local queuedFrame = CreateFrame("Frame", nil, over)
    queuedFrame:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
    local edge = queuedFrame:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(1, 0.82, 0, 1)
    button.queuedIcon = queuedFrame:CreateTexture(nil, "ARTWORK")
    button.queuedIcon:SetPoint("TOPLEFT", 1, -1)
    button.queuedIcon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.queuedIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    queuedFrame:Hide()
    button.queuedFrame = queuedFrame
    button:HookScript("OnEnter", SlotEnter)
    button:HookScript("OnLeave", HideTooltip)
    slots[slot] = button
end

local function Build()
    if bar or InCombat() then
        return
    end
    bar = CreateFrame("Frame", "TrinketSwapperBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    for _, slot in ipairs(SLOTS) do
        BuildSlot(slot)
    end
    -- Twice a second: "Swap" comes and goes with the cooldowns.
    local tick = 0
    bar:SetScript("OnUpdate", function(_, elapsed)
        tick = tick + elapsed
        if tick >= 0.5 then
            tick = 0
            Update()
        end
    end)
    Layout()
end

------------------------------------------------------------------------------
-- Queueing in combat
------------------------------------------------------------------------------

local function Queue(item, slot)
    local current = queued[slot]
    if current and current.itemID == item.itemID then
        queued[slot] = nil
        K.Print(string.format("%s no longer queued.", item.link or "Trinket"))
    else
        queued[slot] = { itemID = item.itemID, icon = item.icon, link = item.link }
        K.Print(string.format("%s queued for the %s slot; it goes on when combat ends.", item.link or "Trinket",
            slot == TOP and "top" or "bottom"))
    end
    Update()
end

-- Combat over: put the queued trinkets on, finding each in the bags afresh.
local function EquipQueued()
    for _, slot in ipairs(SLOTS) do
        local wanted = queued[slot]
        if wanted then
            queued[slot] = nil
            if SlotItem(slot) ~= wanted.itemID then
                for _, item in ipairs(BagTrinkets()) do
                    if item.itemID == wanted.itemID then
                        EquipFromBag(item, slot)
                        break
                    end
                end
            end
        end
    end
    Update()
end

------------------------------------------------------------------------------
-- The menu and the cooldown tray
------------------------------------------------------------------------------
-- One frame beside the icons with two looks:
--   the menu   every trinket in your bags, while the mouse is on an icon or
--              on the menu: click one to wear it;
--   the tray   only the bag trinkets that are on cooldown, staying up by
--              itself until they're all ready.
-- The menu falls back to the tray when the mouse leaves.

local function OverSlot()
    for _, slot in ipairs(SLOTS) do
        local button = slots[slot]
        if button and button:IsVisible() and button:IsMouseOver() then
            return true
        end
    end
    return false
end

local function MenuClick(button, mouseButton)
    local slot = mouseButton == "RightButton" and BOTTOM or TOP
    if InCombat() then
        Queue(button.item, slot)
    else
        EquipFromBag(button.item, slot)
    end
    -- The menu shuts; trinkets still cooling down stay showing.
    flyout.mode = nil
    ShowTray()
end

local function MenuEnter(button)
    local tooltip = rawget(_G, "GameTooltip")
    if not tooltip then
        return
    end
    tooltip:SetOwner(button, "ANCHOR_RIGHT")
    tooltip:SetBagItem(button.item.bag, button.item.slot)
    if InCombat() then
        tooltip:AddLine("In combat: goes on when combat ends", 1, 0.82, 0)
        tooltip:AddLine("Left-click: queue as top trinket", 0.6, 0.8, 1)
        tooltip:AddLine("Right-click: queue as bottom trinket", 0.6, 0.8, 1)
    else
        tooltip:AddLine("Left-click: wear as top trinket", 0.6, 0.8, 1)
        tooltip:AddLine("Right-click: wear as bottom trinket", 0.6, 0.8, 1)
    end
    tooltip:Show()
end

local function BuildFlyout()
    flyout = CreateFrame("Frame", "TrinketSwapperMenu", UIParent)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetClampedToScreen(true)
    flyout.buttons = {}
    flyout:Hide()
    local away, tick = 0, 0
    flyout:SetScript("OnUpdate", function(self, elapsed)
        if self.mode ~= "tray" then
            -- Open while the mouse is on the menu or on either icon, and a
            -- moment longer (the way from an icon to the menu crosses a gap).
            if self:IsMouseOver() or OverSlot() then
                away = 0
                return
            end
            away = away + elapsed
            if away > 0.4 then
                away = 0
                self.mode = nil
                ShowTray()
            end
            return
        end
        -- The tray: twice a second, has one of them come ready?
        tick = tick + elapsed
        if tick < 0.5 then
            return
        end
        tick = 0
        local now = GetTime()
        for _, button in ipairs(self.buttons) do
            if button:IsShown() and button.item.start and button.item.start + button.item.duration <= now then
                ShowTray()
                return
            end
        end
    end)
end

local function MenuButton(index)
    local button = flyout.buttons[index]
    if not button then
        button = CreateFrame("Button", nil, flyout)
        Skin(button)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", MenuClick)
        button:SetScript("OnEnter", MenuEnter)
        button:SetScript("OnLeave", HideTooltip)
        flyout.buttons[index] = button
    end
    return button
end

-- Lays the trinkets out beside the left icon, each with its cooldown: in
-- columns of up to MENU_TALL, evened out (5 trinkets: 3 and 2, not 4 and 1),
-- above the icons or (a setting) below them.
local function Fill(list, mode)
    if not flyout then
        BuildFlyout()
    end
    local size = tonumber(db.size) or DEFAULTS.size
    local step = size + GAP
    local columns = math.max(1, math.ceil(#list / MENU_TALL))
    local rows = math.ceil(#list / columns)
    local below = db.below == true
    flyout:SetSize(columns * step - GAP, rows * step - GAP)
    flyout:ClearAllPoints()
    if below then
        flyout:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -GAP)
    else
        flyout:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, GAP)
    end
    for index, item in ipairs(list) do
        local button = MenuButton(index)
        button.item = item
        button:SetSize(size, size)
        button.icon:SetTexture(item.icon)
        item.start, item.duration = BagCooldown(item.itemID)
        if item.start then
            button.cooldown:SetCooldown(item.start, item.duration)
        else
            button.cooldown:Clear()
        end
        button:ClearAllPoints()
        local column, row = math.floor((index - 1) / rows), (index - 1) % rows
        if below then
            button:SetPoint("TOPLEFT", flyout, "TOPLEFT", column * step, -row * step)
        else
            button:SetPoint("BOTTOMLEFT", flyout, "BOTTOMLEFT", column * step, row * step)
        end
        button:Show()
    end
    for index = #list + 1, #flyout.buttons do
        flyout.buttons[index]:Hide()
    end
    flyout.mode = mode
    flyout:Show()
end

OpenMenu = function()
    local list = BagTrinkets()
    if #list > 0 then
        Fill(list, "menu")
    end
end

-- The tray. Nothing cooling down (or switched off): it goes away. Leaves the
-- menu alone while the mouse has it open.
ShowTray = function()
    if not bar or (flyout and flyout:IsShown() and flyout.mode == "menu") then
        return
    end
    local list = db.tray ~= false and CoolingTrinkets() or nil
    if not list or #list == 0 then
        if flyout then
            flyout.mode = nil
            flyout:Hide()
        end
        return
    end
    Fill(list, "tray")
end

local traySoon = false
local function TrayNow()
    traySoon = false
    bagStale = true
    Update()
    ShowTray()
end
local function Soon()
    if not traySoon then
        traySoon = true
        C_Timer.After(0.1, TrayNow)
    end
end

------------------------------------------------------------------------------
-- Settings, moving, start-up
------------------------------------------------------------------------------

function ns.Refresh()
    Layout()
    if flyout and flyout:IsShown() and flyout.mode == "menu" then
        OpenMenu()
    end
    return not pendingLayout
end

-- A blue box over the icons: drag it. Again (or a fight) puts it away.
function ns.Move(on)
    if not bar or InCombat() then
        return false
    end
    if not dragBox then
        dragBox = K.DragBox(bar, "drag", function(x, y)
            db.pos = { x, y }
            if not InCombat() then
                K.Place(bar, db.pos, SPOT)
            end
        end)
    end
    if on == nil then
        on = not dragBox:IsShown()
    end
    dragBox:SetShown(on)
    return on
end

function ns.Reset()
    local durations = db.durations
    for key in pairs(db) do
        db[key] = nil
    end
    for key, value in pairs(DEFAULTS) do
        db[key] = value
    end
    db.durations = durations or {}
    Layout()
end

K.On("ADDON_LOADED", function(name)
    if name ~= "TrinketSwapper" or db then
        return
    end
    local first = rawget(_G, "TrinketSwapperDB") == nil
    db = K.Settings("TrinketSwapperDB", DEFAULTS)
    ns.db = db
    if first then
        K.Print("your trinkets are under the middle of the screen. /ts for settings, /ts move to move them.")
    end
end)

K.On("PLAYER_LOGIN", Build)
K.On("PLAYER_ENTERING_WORLD", function()
    Build()
    Soon()
end)
for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED" }) do
    K.On(event, Soon)
end
K.On("UPDATE_BINDINGS", function() Update() end)
K.On("PLAYER_REGEN_DISABLED", function()
    if dragBox then
        dragBox:Hide()
    end
    if bar then
        bar:StopMovingOrSizing()
    end
end)
K.On("PLAYER_REGEN_ENABLED", function()
    Build()
    if pendingLayout then
        Layout()
    end
    EquipQueued()
    Soon()
end)

-- A trinket used where the game hides its cooldown: the icon counts from
-- now, by the longest cooldown this trinket has been seen with.
K.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if K.Str(unit) ~= "player" or not bar then
        return
    end
    spellID = K.Num(spellID)
    local itemSpell = C_Item.GetItemSpell
    if not (spellID and itemSpell) then
        return
    end
    for _, slot in ipairs(SLOTS) do
        local itemID = SlotItem(slot)
        if itemID then
            local ok, _, useSpell = pcall(itemSpell, itemID)
            if ok and K.Num(useSpell) == spellID then
                local start = K.Num((GetInventoryItemCooldown("player", slot)))
                local known = db.durations[itemID]
                if not start and known and not Seen(itemID) then
                    seenCooldowns[itemID] = { GetTime(), known }
                end
                Soon()
            end
        end
    end
end)

SLASH_TRINKETSWAPPER1 = "/ts"
SLASH_TRINKETSWAPPER2 = "/trinketswapper"
SlashCmdList["TRINKETSWAPPER"] = function(message)
    local command = (message or ""):lower():match("^%s*(%S*)")
    if not db then
        return
    end
    if command == "move" then
        if InCombat() or not bar then
            K.Print("not in combat.")
        elseif ns.Move() then
            K.Print("drag the blue box; /ts move again when it's where you want it.")
        else
            K.Print("locked in place.")
        end
    elseif command == "reset" then
        if InCombat() then
            K.Print("not in combat.")
        else
            ns.Reset()
            K.Print("settings and position are back to how they came.")
        end
    elseif command == "help" or command == "?" then
        K.Print("/ts: settings. /ts move: move the icons. /ts reset: start over. Keys: Key Bindings > TrinketSwapper.")
    else
        ns.ToggleOptions()
    end
end

ns.internals = {
    Bar = function() return bar end,
    Slots = function() return slots end,
    Flyout = function() return flyout end,
    Queued = function() return queued end,
    BagTrinkets = BagTrinkets,
    DragBox = function() return dragBox end,
    Pending = function() return pendingLayout end,
}
