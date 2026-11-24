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
local Look = ns.Look

K.title = "TrinketSwapper"
K.color = "ffe6b450"

local TOP, BOTTOM = 13, 14
local SLOTS = { TOP, BOTTOM }
local GAP = 4                 -- the space between icons as it comes (a setting: db.gap)
local GAP_MIN, GAP_MAX = -12, 24
local MENU_TALL = 4          -- trinkets to a column before the next one starts
local SWAP_COOLDOWN = 30     -- the cooldown wearing a trinket starts
local EMPTY = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket"
local DEFAULTS = { size = 36, gap = GAP, tray = true, swap = true, alert = true, keys = true, below = false, buffs = true, durations = {},
    learned = {}, minimap = { angle = 205, hide = false } }
local ICON = "Interface\\AddOns\\TrinketSwapper\\Media\\TrinketSwapper"
local SPOT = { "CENTER", "CENTER", 0, -220 }

_G.BINDING_HEADER_TRINKETSWAPPER = "TrinketSwapper"
_G["BINDING_NAME_CLICK TrinketSwapperSlot13:LeftButton"] = "Use top trinket"
_G["BINDING_NAME_CLICK TrinketSwapperSlot14:LeftButton"] = "Use bottom trinket"

local db
local bar, flyout, dragBox, alertBox, minimapButton
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

------------------------------------------------------------------------------
-- A trinket's buff
------------------------------------------------------------------------------
-- While a trinket's buff is on you (the one using it gives, or the one its
-- proc gives), its icon lights: the buff's own icon in a green edge, with
-- the buff's time sweeping away. A proc trinket whose buff is known waits
-- grey for it, and darker while a cooldown is running on it.
--
-- The game draws the buff itself (a buff display it drives, filtered to the
-- trinket's buff IDs), so it shows in combat too, where an addon can't read
-- your buffs.
--
-- Which buffs are a trinket's: the spells the game names for the item (its
-- "Use:" and what its "Equip:" effect triggers); and, since a proc's buff is
-- often another spell, any buff called like those spells or like the trinket
-- itself: seen on you out of combat, or cast on you in a fight (the game
-- reports a proc's cast even then). What is learned is kept by item
-- (db.learned), so it follows the trinket between slots and characters.

-- Trinkets whose buff is a different spell from the ones the game names, so
-- it is known before the first proc.
local KNOWN_BUFFS = {
    [17774] = { 21970 },   -- Mark of the Chosen: "Equip" spell 21969, buff 21970
}
local UP = { 0.35, 1.00, 0.35 }   -- the edge of a buff that is up
local RETRIES = 20                -- looks at an item whose name the game hasn't loaded yet

local worn = {}            -- slot -> what its trinket does (see Resolve)
local syncPending = false  -- the buff displays need another look (out of combat)
local hiddenRefused = false
local buffStatus = { built = 0, learned = 0, last = "none yet" }

local function SpellName(spellID)
    local get = C_Spell and C_Spell.GetSpellName
    if not (get and spellID) then
        return nil
    end
    local ok, name = pcall(get, spellID)
    return ok and K.Str(name) or nil
end

local function SameSet(a, b)
    for key in pairs(a) do
        if not b[key] then
            return false
        end
    end
    for key in pairs(b) do
        if not a[key] then
            return false
        end
    end
    return true
end

-- Whether a proc trinket's buff is known, so its icon can wait grey for it.
local function Waits(entry)
    if not (entry.procSpell and not entry.useSpell and entry.itemID) then
        return false
    end
    local learned = db.learned[entry.itemID]
    return KNOWN_BUFFS[entry.itemID] ~= nil or (learned ~= nil and next(learned) ~= nil)
end

-- Works out what the trinket in `slot` does.
local function Resolve(slot, itemID)
    local was = worn[slot]
    local entry = { itemID = itemID, names = {}, ids = {}, tries = 0 }
    worn[slot] = entry
    if itemID then
        if was and was.itemID == itemID then
            entry.tries = was.tries + 1
        end
        local useSpell, procSpell, itemName
        if C_Item.GetItemSpell then
            local ok, _, spellID = pcall(C_Item.GetItemSpell, itemID)
            useSpell = ok and K.Num(spellID) or nil
        end
        if C_Item.GetFirstTriggeredSpellForItem then
            local quality = K.Num(GetInventoryItemQuality("player", slot)) or 0
            local ok, spellID = pcall(C_Item.GetFirstTriggeredSpellForItem, itemID, quality)
            procSpell = ok and K.Num(spellID) or nil
            if procSpell == useSpell then
                procSpell = nil
            end
        end
        if C_Item.GetItemNameByID then
            local ok, name = pcall(C_Item.GetItemNameByID, itemID)
            itemName = ok and K.Str(name) or nil
            -- Not loaded yet: asked for, and looked at again shortly.
            if not itemName and entry.tries < RETRIES then
                entry.partial = true
                if C_Item.RequestLoadItemDataByID then
                    pcall(C_Item.RequestLoadItemDataByID, itemID)
                end
            end
        end
        entry.useSpell, entry.procSpell, entry.itemName = useSpell, procSpell, itemName
        -- (A trinket with neither a use nor a proc has no buff to show.)
        if useSpell or procSpell then
            if useSpell then
                entry.ids[useSpell] = true
                entry.names[SpellName(useSpell) or false] = true
            end
            if procSpell then
                entry.ids[procSpell] = true
                entry.names[SpellName(procSpell) or false] = true
            end
            -- Many trinket buffs are named after the trinket.
            entry.names[itemName or false] = true
            entry.names[false] = nil
            for _, spellID in ipairs(KNOWN_BUFFS[itemID] or {}) do
                entry.ids[spellID] = true
            end
            for spellID in pairs(db.learned[itemID] or {}) do
                entry.ids[spellID] = true
            end
        end
        entry.waits = Waits(entry)
    end
    if not was or not SameSet(was.ids, entry.ids) then
        syncPending = true
    end
    return entry
end

-- What the trinket in `slot` does, worked out afresh when it has changed.
local function Worn(slot, itemID)
    local entry = worn[slot]
    if not entry or entry.itemID ~= itemID or entry.partial then
        entry = Resolve(slot, itemID)
    end
    return entry
end

-- Remembers that `spellID` is a buff of the trinket in `slot`.
local function LearnBuff(slot, spellID)
    local entry = worn[slot]
    if not (entry and entry.itemID) or entry.ids[spellID] then
        return
    end
    db.learned[entry.itemID] = db.learned[entry.itemID] or {}
    db.learned[entry.itemID][spellID] = true
    entry.ids[spellID] = true
    entry.waits = Waits(entry)
    syncPending = true
    buffStatus.learned = buffStatus.learned + 1
    buffStatus.last = string.format("%s: %d (%s)", tostring(entry.itemName or entry.itemID), spellID, tostring(SpellName(spellID)))
end

local function LearnByName(name, spellID)
    for _, slot in ipairs(SLOTS) do
        local entry = worn[slot]
        if entry and entry.names[name] then
            LearnBuff(slot, spellID)
        end
    end
end

local function BuffsHidden()
    local secrets = rawget(_G, "C_Secrets")
    if secrets and secrets.ShouldAurasBeSecret then
        return K.Bool(secrets.ShouldAurasBeSecret(), true)
    end
    return false
end

-- Out of combat the game still lets an addon read your buffs: any of them
-- called like a worn trinket's spells is that trinket's.
local function LearnFromBuffs()
    if not (db and bar) or db.buffs == false or InCombat() or BuffsHidden() then
        return
    end
    local auras = rawget(_G, "C_UnitAuras")
    local get = auras and auras.GetAuraDataByIndex
    if not get then
        return
    end
    for index = 1, 40 do
        local ok, aura = pcall(get, "player", index, "HELPFUL")
        if not ok or aura == nil or K.IsSecret(aura) then
            break
        end
        local name, spellID = K.Str(aura.name), K.Num(aura.spellId)
        if name and spellID then
            LearnByName(name, spellID)
        end
    end
end

local function CopySet(set)
    local copy = {}
    for key in pairs(set) do
        copy[key] = true
    end
    return copy
end

-- Runs once, when the game makes the buff's button. Everything it should
-- draw is handed over here; after this the game drives it. (No scripts on
-- it, not even hooked ones: the game shows and hides it with hidden values,
-- and refuses to once an addon has put a script on it.)
local function StyleBuff(made, button)
    button.buffButton = made
    local size = tonumber(db.size) or DEFAULTS.size
    made:ClearAllPoints()
    made:SetPoint("CENTER", button.buffs, "CENTER", 0, 0)
    made:SetSize(size, size)
    -- Display only: clicks go through to the trinket's icon underneath.
    pcall(made.EnableMouse, made, false)
    -- Each part is optional: if the game refuses one, the rest still show.
    pcall(function()
        made:SetIcon(Look.Icon(made, true))
        Look.Edge(made, UP[1], UP[2], UP[3])
    end)
    pcall(function()
        local cooldown = Look.Cooldown(made)
        made.cooldown = cooldown
        if cooldown.SetReverse then
            cooldown:SetReverse(true)
        end
        if cooldown.SetSwipeColor then
            cooldown:SetSwipeColor(0, 0, 0, 0.6)
        end
        made:SetDurationCooldown(cooldown)
    end)
    pcall(Look.Size, made, size)
    pcall(function()
        local textFrame = CreateFrame("Frame", nil, made)
        textFrame:SetAllPoints()
        if made.cooldown then
            textFrame:SetFrameLevel(made.cooldown:GetFrameLevel() + 2)
        end
        local stacks = textFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        stacks:SetPoint("BOTTOMRIGHT", -2, 2)
        made:SetApplicationCount(stacks)
    end)
end

local function BuildBuff(button, ids)
    -- (A child of the bar, not of the icon: the icon is a secure button,
    -- and what the game drives is kept out from under it.)
    local container = CreateFrame("AuraContainer", nil, bar, "CustomAuraContainerTemplate")
    button.buffs = container
    container:SetAllPoints(button)
    -- Over the icon and its cooldown, under the key and "Swap".
    container:SetFrameLevel(button:GetFrameLevel() + 3)
    pcall(container.EnableMouse, container, false)
    container:SetUnit("player")
    container:AddAuraSlot("buff", "HELPFUL", {
        candidateFilters = { includeSpellIDs = CopySet(ids) },
        initializeFrame = function(made)
            StyleBuff(made, button)
        end,
    })
    container:SetEnabled(true)
    container:Show()
end

local function DisplaysAvailable()
    return type(rawget(_G, "C_AuraContainerUtil")) == "table" and type(rawget(_G, "AuraContainerSortMethod")) == "table"
end

-- Makes or updates each icon's buff display. Only out of combat: the game
-- refuses an addon these frames in a fight.
local function SyncBuffs()
    if not bar or InCombat() then
        return   -- (still pending)
    end
    syncPending = false
    if not DisplaysAvailable() then
        buffStatus.why = "this client has no buff displays for addons"
        return
    end
    -- Where buffs are hidden the whole time (a battleground) it is tried
    -- all the same; refused there, it waits until they can be read.
    local hidden = BuffsHidden()
    if not hidden then
        hiddenRefused = false
    elseif hiddenRefused then
        syncPending = true
        return
    end
    for _, slot in ipairs(SLOTS) do
        local button, entry = slots[slot], worn[slot]
        local ids = (db.buffs ~= false and entry and next(entry.ids) ~= nil) and entry.ids or nil
        if button.buffs then
            if ids then
                local ok, err = pcall(button.buffs.SetAuraSlotCandidateFilters, button.buffs, "buff",
                    { includeSpellIDs = CopySet(ids) })
                button.buffsError = not ok and tostring(err) or nil
            end
            pcall(button.buffs.SetEnabled, button.buffs, ids ~= nil)
            pcall(button.buffs.SetShown, button.buffs, ids ~= nil)
        elseif ids and not button.buffsFailed then
            local ok, err = pcall(BuildBuff, button, ids)
            if ok then
                buffStatus.built = buffStatus.built + 1
            else
                local made = button.buffs
                if made then
                    pcall(made.SetEnabled, made, false)
                    pcall(made.Hide, made)
                end
                button.buffs, button.buffButton = nil, nil
                button.buffsError = tostring(err)
                if hidden then
                    hiddenRefused = true
                    syncPending = true
                    return
                end
                button.buffsFailed = true
            end
        end
    end
end

-- A spell's own cooldown, where the game tracks one and lets it be read: its
-- start and duration, or nil.
local function SpellCooldown(spellID)
    local get = C_Spell and C_Spell.GetSpellCooldown
    if not get then
        return nil
    end
    local ok, info = pcall(get, spellID)
    if not ok or type(info) ~= "table" or K.IsSecret(info) then
        return nil
    end
    local start, duration = K.Num(info.startTime), K.Num(info.duration)
    if start and duration and start > 0 and duration > 1.5 and start + duration > GetTime() then
        return start, duration
    end
    return nil
end

-- What it knows of each worn trinket's buff, said in chat (/ts buffs).
function ns.SayBuffs()
    local function List(set)
        local list = {}
        for key in pairs(set) do
            list[#list + 1] = tostring(key)
        end
        table.sort(list)
        return #list > 0 and table.concat(list, ", ") or "none"
    end
    for _, slot in ipairs(SLOTS) do
        local entry, button = worn[slot], slots[slot]
        local where = slot == TOP and "Top" or "Bottom"
        if not (entry and entry.itemID) then
            K.Print(where .. " trinket: none.")
        else
            K.Print(string.format("%s trinket: %s (item %d) | use spell %s, proc spell %s | buffs called: %s | buff IDs: %s | learned: %s | %s | display: %s",
                where, tostring(entry.itemName), entry.itemID, tostring(entry.useSpell), tostring(entry.procSpell), List(entry.names),
                List(entry.ids), List(db.learned[entry.itemID] or {}), entry.waits and "waits grey for its proc" or "in full color",
                button and (button.buffs and "made" or (button.buffsError and ("not made: " .. button.buffsError) or "not made")) or "no icon"))
        end
    end
    K.Print(string.format("buff displays: %s | made %d, learned %d (last: %s) | look: %s", db.buffs == false and "switched off"
        or (buffStatus.why or (syncPending and "waiting for combat to end" or "up to date")), buffStatus.built, buffStatus.learned,
        buffStatus.last, tostring(Look.source)))
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

------------------------------------------------------------------------------
-- The swap alert
------------------------------------------------------------------------------
-- When "Swap" comes up on a worn trinket (see UpdateSlot), the trinket's
-- icon with "Swap" under it also shows in the middle of the screen for 10
-- seconds, pulsing: once per cooldown, and out of combat (a trinket used in
-- a fight gets its alert when the fight ends). It goes early when you swap,
-- queue a trinket for that slot, the cooldown drops under 30 seconds, or a
-- fight starts. It never takes the mouse. /ts move moves it; /ts swap shows
-- it.
local ALERT_SPOT = { "CENTER", "CENTER", 0, 150 }
local ALERT_SHOWN = 10
local ALERT_ICON = 42
local alert
local alerted = {}     -- slot -> { item, the cooldown's start }: already shown for
local alertStatus = { shown = 0 }

local function Alert()
    if alert then
        return alert
    end
    alert = CreateFrame("Frame", "TrinketSwapperAlert", UIParent)
    alert:SetSize(120, 84)
    alert:SetFrameStrata("HIGH")
    alert:EnableMouse(false)
    local holder = CreateFrame("Frame", nil, alert)
    holder:SetSize(ALERT_ICON, ALERT_ICON)
    holder:SetPoint("TOP", 0, -2)
    alert.art = Look.Icon(holder, true)
    Look.Size(holder, ALERT_ICON)
    alert.text = alert:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    alert.text:SetPoint("TOP", holder, "BOTTOM", 0, -4)
    alert.text:SetText("Swap")
    alert.text:SetTextColor(1, 0.82, 0.3)
    local pulse = alert:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.45)
    fade:SetDuration(0.5)
    fade:SetSmoothing("IN_OUT")
    alert.pulse = pulse
    K.Place(alert, db.alertPos, ALERT_SPOT)
    alert:Hide()
    return alert
end

local function HideAlert()
    if alert and alert:IsShown() then
        alert.pulse:Stop()
        alert:Hide()
    end
end

local function ShowAlert(slot)
    local frame = Alert()
    frame.art:SetTexture(GetInventoryItemTexture("player", slot) or EMPTY)
    frame.slot = slot
    frame.shownAt = GetTime()
    frame:Show()
    frame.pulse:Play()
    alertStatus.shown = alertStatus.shown + 1
    local stamp = frame.shownAt
    C_Timer.After(ALERT_SHOWN, function()
        if frame.shownAt == stamp then
            HideAlert()
        end
    end)
end

-- "Swap" is up (or not) on the trinket in `slot`: the alert follows.
local function AlertFor(slot, itemID, swap)
    if not swap then
        if alert and alert:IsShown() and alert.slot == slot then
            HideAlert()
        end
        return
    end
    if db.alert == false or InCombat() then
        return
    end
    -- Once per cooldown, known by when it started (read again after a fight
    -- it can differ by a moment from what was counted meanwhile).
    local seen = seenCooldowns[itemID]
    local start = seen and seen[1] or 0
    local said = alerted[slot]
    if said and said[1] == itemID and math.abs(said[2] - start) < 3 then
        return
    end
    alerted[slot] = { itemID, start }
    ShowAlert(slot)
end

-- /ts swap: the alert, to see it and where it sits.
function ns.TestAlert()
    ShowAlert(TOP)
    alert.slot = nil   -- not tied to a cooldown: it stays its 10 seconds
end

local function UpdateSlot(button)
    local slot = button.slot
    local itemID = SlotItem(slot)
    button.icon:SetTexture(itemID and GetInventoryItemTexture("player", slot) or EMPTY)
    local entry = Worn(slot, itemID)
    -- A proc trinket whose buff is known waits grey for it (only with its
    -- buff display made: without one it would never light).
    local waits = db.buffs ~= false and entry.waits == true and button.buffs ~= nil
    local start, duration = SlotCooldown(slot)
    if not start and waits then
        -- Its internal cooldown, where the game tracks one.
        start, duration = SpellCooldown(entry.procSpell)
    end
    if start then
        button.cooldown:SetCooldown(start, duration)
    else
        button.cooldown:Clear()
    end
    local shade = waits and (start and 0.4 or 0.8) or 1
    button.icon:SetDesaturated(waits)
    button.icon:SetVertexColor(shade, shade, shade)
    local item = queued[slot]
    button.queuedIcon:SetTexture(item and item.icon or nil)
    button.queuedFrame:SetShown(item ~= nil)
    -- "Swap": this one has longer left than wearing another would cost.
    local swap = db.swap ~= false and item == nil and itemID ~= nil and Left(itemID) > SWAP_COOLDOWN
        and SwapCandidate() ~= nil
    if swap ~= button.swap:IsShown() then
        button.swap:SetShown(swap)
        if swap then
            button.swapPulse:Play()
        else
            button.swapPulse:Stop()
        end
    end
    AlertFor(slot, itemID, swap)
    ShowKey(button)
end

Update = function()
    if not bar then
        return
    end
    for _, slot in ipairs(SLOTS) do
        UpdateSlot(slots[slot])
    end
    if syncPending then
        SyncBuffs()
    end
end

-- The space between icons. (The action-button frame around each icon has a
-- soft margin that grows with the icon, so big icons look further apart:
-- the setting goes below zero to pull them together.)
local function Gap()
    local gap = tonumber(db and db.gap) or GAP
    return math.max(GAP_MIN, math.min(GAP_MAX, gap))
end
ns.GAP_MIN, ns.GAP_MAX = GAP_MIN, GAP_MAX

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
    local gap = Gap()
    bar:SetSize(size * 2 + gap, size)
    K.Place(bar, db.pos, SPOT)
    for index, slot in ipairs(SLOTS) do
        local button = slots[slot]
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint("LEFT", bar, "LEFT", (index - 1) * (size + gap), 0)
        Look.Size(button, size)
        button.queuedFrame:SetSize(size * 0.45, size * 0.45)
        Look.Size(button.queuedFrame, size * 0.45)
        -- The buff's button, made at the size of the day.
        if button.buffButton then
            pcall(button.buffButton.SetSize, button.buffButton, size, size)
            pcall(Look.Size, button.buffButton, size)
        end
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
    Look.Icon(button)
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
    local swapPulse = button.swap:CreateAnimationGroup()
    swapPulse:SetLooping("BOUNCE")
    local swapFade = swapPulse:CreateAnimation("Alpha")
    swapFade:SetFromAlpha(1)
    swapFade:SetToAlpha(0.4)
    swapFade:SetDuration(0.5)
    swapFade:SetSmoothing("IN_OUT")
    button.swapPulse = swapPulse
    -- The trinket queued for this slot, small in the corner.
    -- (In the same frame as the other icons.)
    local queuedFrame = CreateFrame("Frame", nil, over)
    queuedFrame:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
    button.queuedIcon = Look.Icon(queuedFrame, true)
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
        Look.Icon(button)
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
    local gap = Gap()
    local step = size + gap
    local away = math.max(0, gap)      -- the menu never laps over the icons
    local columns = math.max(1, math.ceil(#list / MENU_TALL))
    local rows = math.ceil(#list / columns)
    local below = db.below == true
    flyout:SetSize(columns * step - gap, rows * step - gap)
    flyout:ClearAllPoints()
    if below then
        flyout:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -away)
    else
        flyout:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, away)
    end
    for index, item in ipairs(list) do
        local button = MenuButton(index)
        button.item = item
        button:SetSize(size, size)
        Look.Size(button, size)
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

-- The buff setting changed.
function ns.ApplyBuffs()
    syncPending = true
    Update()
    return not syncPending
end

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
    if not alertBox then
        alertBox = K.DragBox(Alert(), "Swap alert", function(x, y)
            db.alertPos = { x, y }
            K.Place(alert, db.alertPos, ALERT_SPOT)
        end)
    end
    if on == nil then
        on = not dragBox:IsShown()
    end
    dragBox:SetShown(on)
    alertBox:SetShown(on)
    return on
end

function ns.Reset()
    -- (What it has learned of cooldowns stays; the minimap table is the one
    -- the minimap button holds on to, so it's put back in place.)
    local durations, minimap, learned = db.durations, db.minimap, db.learned
    local keysAdopted, learnedAdopted = db.keysAdopted, db.learnedAdopted
    for key in pairs(db) do
        db[key] = nil
    end
    -- (And the buffs learned for each trinket, and that ArchDruid's keys and
    -- buffs were already taken over.)
    db.learned = learned or {}
    db.keysAdopted, db.learnedAdopted = keysAdopted, learnedAdopted
    for key, value in pairs(DEFAULTS) do
        if type(value) ~= "table" then
            db[key] = value
        end
    end
    db.durations = durations or {}
    db.minimap = minimap or {}
    for key, value in pairs(DEFAULTS.minimap) do
        db.minimap[key] = value
    end
    Layout()
    if alert then
        K.Place(alert, db.alertPos, ALERT_SPOT)
    end
    ns.ApplyMinimapButton()
end

function ns.ApplyMinimapButton()
    if minimapButton then
        minimapButton:Apply()
    end
end

local function BuildMinimapButton()
    if minimapButton or not db then
        return
    end
    minimapButton = K.MinimapButton("TrinketSwapperMinimapButton", ICON, db.minimap, function(mouse)
        if mouse == "RightButton" then
            if InCombat() or not bar then
                K.Print("not in combat.")
            elseif ns.Move() then
                K.Print("drag the blue boxes (your trinkets, and where the swap alert shows); right-click the minimap button again when they're where you want them.")
            else
                K.Print("locked in place.")
            end
        else
            ns.ToggleOptions()
        end
    end, { "Click: settings", "Right-click: move the trinket icons", "Drag: move this button" })
end

-- Coming from ArchDruid, where the trinkets were part of the HUD: the keys
-- set there for using each trinket are given to these icons instead. Looked
-- for once, out of combat (the game doesn't let keys be set in a fight), and
-- only for a slot that has no key of its own yet.
local function AdoptKeys()
    if not db or db.keysAdopted or InCombat() then
        return
    end
    db.keysAdopted = true
    local get, set = rawget(_G, "GetBindingKey"), rawget(_G, "SetBinding")
    if not (get and set) then
        return
    end
    local moved = 0
    for _, slot in ipairs(SLOTS) do
        local mine = "CLICK TrinketSwapperSlot" .. slot .. ":LeftButton"
        if not get(mine) then
            for _, key in ipairs({ get("CLICK ArchDruidUseTrinket" .. slot .. ":LeftButton") }) do
                key = K.Str(key)
                if key then
                    local ok, done = pcall(set, key, mine)
                    if ok and done then
                        moved = moved + 1
                    end
                end
            end
        end
    end
    if moved > 0 then
        local save, which = rawget(_G, "SaveBindings"), rawget(_G, "GetCurrentBindingSet")
        if save and which then
            pcall(function() save(which()) end)
        end
        K.Print("the keys you had on ArchDruid's trinkets use these icons now (Key Bindings > TrinketSwapper).")
    end
end

K.On("ADDON_LOADED", function(name)
    if name ~= "TrinketSwapper" or db then
        return
    end
    local first = rawget(_G, "TrinketSwapperDB") == nil
    db = K.Settings("TrinketSwapperDB", DEFAULTS)
    ns.db = db
    if not db.learnedAdopted then
        -- Coming from ArchDruid: the buffs it had learned for your trinkets
        -- come along (looked for once).
        db.learnedAdopted = true
        local old = rawget(_G, "ArchDruidDB")
        local learned = type(old) == "table" and old.learnedItems
        if type(learned) == "table" then
            for itemID, spells in pairs(learned) do
                if type(itemID) == "number" and type(spells) == "table" then
                    db.learned[itemID] = db.learned[itemID] or {}
                    for spellID in pairs(spells) do
                        if type(spellID) == "number" then
                            db.learned[itemID][spellID] = true
                        end
                    end
                end
            end
        end
    end
    if first then
        -- Coming from ArchDruid: its two trinket switches come along.
        local old = rawget(_G, "ArchDruidDB")
        if type(old) == "table" then
            if old.trinketTray == false then
                db.tray = false
            end
            if old.trinketSwap == false then
                db.swap = false
            end
        end
        K.Print("your trinkets are under the middle of the screen. /ts for settings, /ts move to move them.")
    end
end)

K.On("PLAYER_LOGIN", function()
    Build()
    BuildMinimapButton()
end)
K.On("PLAYER_ENTERING_WORLD", function()
    Build()
    Soon()
    AdoptKeys()
end)
for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED" }) do
    K.On(event, Soon)
end
K.On("UPDATE_BINDINGS", function() Update() end)
K.On("PLAYER_REGEN_DISABLED", function()
    HideAlert()
    if dragBox then
        dragBox:Hide()
    end
    if alertBox then
        alertBox:Hide()
    end
    if bar then
        bar:StopMovingOrSizing()
    end
end)
K.On("PLAYER_REGEN_ENABLED", function()
    AdoptKeys()
    Build()
    if pendingLayout then
        Layout()
    end
    EquipQueued()
    -- A buff that started in the fight and is still up: nothing else would
    -- prompt a look at it. Now, and once more in case buffs are still hidden.
    LearnFromBuffs()
    C_Timer.After(1, function()
        LearnFromBuffs()
        Soon()
    end)
    Soon()
end)

-- Your buffs changing, out of combat: is one of them a trinket's?
do
    local watch = CreateFrame("Frame")
    if not pcall(watch.RegisterUnitEvent, watch, "UNIT_AURA", "player") then
        pcall(watch.RegisterEvent, watch, "UNIT_AURA")
    end
    watch:SetScript("OnEvent", function(_, _, unit)
        if K.Str(unit) == "player" and not InCombat() then
            LearnFromBuffs()
            if syncPending then
                Soon()
            end
        end
    end)
end
-- A trinket's data arriving after it was put on: look at it again.
local function ItemLoaded(itemID)
    itemID = K.Num(itemID)
    for _, slot in ipairs(SLOTS) do
        local entry = worn[slot]
        if entry and itemID and entry.itemID == itemID then
            entry.partial = true
            Soon()
        end
    end
end
K.On("ITEM_DATA_LOAD_RESULT", ItemLoaded)
K.On("GET_ITEM_INFO_RECEIVED", ItemLoaded)

-- A trinket used where the game hides its cooldown: the icon counts from
-- now, by the longest cooldown this trinket has been seen with.
K.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if K.Str(unit) ~= "player" or not bar then
        return
    end
    spellID = K.Num(spellID)
    if not spellID then
        return
    end
    -- A proc casts its buff on you, and the game reports that cast even in
    -- combat: a spell called like a worn trinket's is its buff. The icon
    -- takes it on once the fight is over (the game only allows that then).
    if db.buffs ~= false then
        local name = SpellName(spellID)
        if name then
            LearnByName(name, spellID)
        end
    end
    local itemSpell = C_Item.GetItemSpell
    if not itemSpell then
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
            K.Print("drag the blue boxes (your trinkets, and where the swap alert shows); /ts move again when they're where you want them.")
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
    elseif command == "minimap" then
        db.minimap.hide = not db.minimap.hide
        ns.ApplyMinimapButton()
        K.Print(db.minimap.hide and "minimap button hidden; /ts minimap brings it back." or "minimap button shown.")
    elseif command == "buffs" or command == "buff" then
        ns.SayBuffs()
    elseif command == "swap" then
        if bar then
            ns.TestAlert()
        end
    elseif command == "help" or command == "?" then
        K.Print("/ts: settings. /ts move: move the icons. /ts minimap: show or hide the minimap button. /ts buffs: what it knows of your trinkets' buffs. /ts swap: shows the swap alert. /ts reset: start over. Keys: Key Bindings > TrinketSwapper.")
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
    Worn = function() return worn end,
    Alert = function() return alert, alertStatus, alertBox end,
    BuffStatus = function() return buffStatus, syncPending end,
    MinimapButton = function() return minimapButton end,
}
