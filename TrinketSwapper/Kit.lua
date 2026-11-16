-- Kit.lua
-- The small set of helpers this addon is built on: events, saved settings,
-- chat lines, hidden ("secret") values, and a plain settings window with
-- check boxes, steppers and buttons. Nothing here is specific to the addon;
-- the same file ships with each of the guild's addons.

local ADDON, ns = ...

local K = {}
ns.K = K

------------------------------------------------------------------------------
-- Hidden values
------------------------------------------------------------------------------
-- On Forever the game hands addons some values it won't let them read (a
-- "secret"). Doing anything with one is an error, so every value that comes
-- from the game goes through one of these first.

function K.IsSecret(value)
    local check = rawget(_G, "issecretvalue")
    if check then
        return check(value) == true
    end
    return false
end

-- A number we may do arithmetic on, or nil.
function K.Num(value)
    if K.IsSecret(value) or type(value) ~= "number" then
        return nil
    end
    return value
end

-- A string we may read, or nil.
function K.Str(value)
    if K.IsSecret(value) or type(value) ~= "string" then
        return nil
    end
    return value
end

-- true or false, or `default` when the game won't say.
function K.Bool(value, default)
    if K.IsSecret(value) or value == nil then
        return default
    end
    return value and true or false
end

------------------------------------------------------------------------------
-- Events and chat
------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

-- Calls `fn` with the event's arguments each time the game sends `event`.
function K.On(event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        -- (An event this client doesn't have is passed over.)
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    list[#list + 1] = fn
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if list then
        for index = 1, #list do
            list[index](...)
        end
    end
end)

K.inCombat = false
K.On("PLAYER_REGEN_DISABLED", function() K.inCombat = true end)
K.On("PLAYER_REGEN_ENABLED", function() K.inCombat = false end)
K.On("PLAYER_ENTERING_WORLD", function()
    K.inCombat = K.Bool(InCombatLockdown(), false)
end)

K.title = ADDON
K.color = "ff8fd16a"

function K.Print(text)
    local chat = rawget(_G, "DEFAULT_CHAT_FRAME")
    local line = string.format("|c%s%s|r: %s", K.color, K.title, tostring(text))
    if chat and chat.AddMessage then
        chat:AddMessage(line)
    else
        print(line)
    end
end

-- Saved settings: `name` is the SavedVariables table; anything missing from
-- it is filled in from `defaults` (one level of nested tables too).
function K.Settings(name, defaults)
    local db = rawget(_G, name)
    if type(db) ~= "table" then
        db = {}
        rawset(_G, name, db)
    end
    for key, value in pairs(defaults) do
        if db[key] == nil then
            if type(value) == "table" then
                db[key] = {}
                for inner, innerValue in pairs(value) do
                    db[key][inner] = innerValue
                end
            else
                db[key] = value
            end
        end
    end
    return db
end

------------------------------------------------------------------------------
-- Placing and moving
------------------------------------------------------------------------------

-- Puts `frame`'s center where it was last left: `pos` is { x, y } from the
-- screen's bottom left corner; with none saved, `default` is
-- { point, relativePoint, x, y }.
function K.Place(frame, pos, default)
    frame:ClearAllPoints()
    if type(pos) == "table" and type(pos[1]) == "number" and type(pos[2]) == "number" then
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos[1], pos[2])
    else
        frame:SetPoint(default[1], UIParent, default[2], default[3], default[4])
    end
end

-- A blue box over `frame` that can be dragged to move it. `saved(x, y)` is
-- told where its center ended up. Returns the box; Show and Hide it.
function K.DragBox(frame, label, saved)
    local box = CreateFrame("Frame", nil, UIParent)
    box:SetFrameStrata("DIALOG")
    box:SetAllPoints(frame)
    box:EnableMouse(true)
    box:RegisterForDrag("LeftButton")
    local fill = box:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.20, 0.50, 1.00, 0.45)
    local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    text:SetText(label)
    frame:SetMovable(true)
    box:SetScript("OnDragStart", function()
        if not K.Bool(InCombatLockdown(), false) then
            frame:StartMoving()
        end
    end)
    box:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local x, y = frame:GetCenter()
        x, y = K.Num(x), K.Num(y)
        if x and y then
            saved(x, y)
        end
    end)
    box:Hide()
    return box
end

------------------------------------------------------------------------------
-- A minimap button
------------------------------------------------------------------------------

local function Angle(dy, dx)
    if math.atan2 then
        return math.atan2(dy, dx)
    end
    return math.atan(dy, dx)
end

-- A round button on the minimap's edge showing `texture` (a picture that is
-- already round). Drag it around the minimap. `settings` is a saved table:
-- .angle is where it sits (degrees), .hide puts it away. `onClick(mouse)`
-- is told "LeftButton" or "RightButton"; `lines` are the tooltip's.
-- Returns the button (nil where there's no minimap); button:Apply() after
-- changing a setting.
function K.MinimapButton(name, texture, settings, onClick, lines)
    local minimap = rawget(_G, "Minimap")
    if not minimap then
        return nil
    end
    local button = CreateFrame("Button", name, minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(texture)
    icon:SetAllPoints()
    button.icon = icon
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetPoint("TOPLEFT", -2, 2)
    highlight:SetPoint("BOTTOMRIGHT", 2, -2)
    local function Place()
        local angle = math.rad(tonumber(settings.angle) or 205)
        local radius = (K.Num(minimap:GetWidth()) or 140) / 2 + 6
        button:ClearAllPoints()
        button:SetPoint("CENTER", minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    end
    function button:Apply()
        self:SetShown(settings.hide ~= true)
        Place()
    end
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, mouse)
        onClick(mouse)
    end)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        local tooltip = rawget(_G, "GameTooltip")
        if tooltip then
            tooltip:Hide()
        end
        self:SetScript("OnUpdate", function()
            local mx, my = minimap:GetCenter()
            local scale = minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            mx, my, scale, cx, cy = K.Num(mx), K.Num(my), K.Num(scale), K.Num(cx), K.Num(cy)
            if mx and my and scale and scale > 0 and cx and cy then
                settings.angle = math.deg(Angle(cy / scale - my, cx / scale - mx))
                Place()
            end
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(self)
        local tooltip = rawget(_G, "GameTooltip")
        if tooltip then
            tooltip:SetOwner(self, "ANCHOR_LEFT")
            tooltip:SetText(K.title)
            for _, line in ipairs(lines or {}) do
                tooltip:AddLine(line, 1, 1, 1)
            end
            tooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        local tooltip = rawget(_G, "GameTooltip")
        if tooltip then
            tooltip:Hide()
        end
    end)
    button:Apply()
    return button
end

------------------------------------------------------------------------------
-- The settings window
------------------------------------------------------------------------------

local EDGE = { 0.85, 0.68, 0.30 }

local function Panel(frame)
    local back = frame:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0.06, 0.05, 0.04, 0.94)
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
        line:SetPoint(side[1])
        line:SetPoint(side[2])
        if side[3] then
            line:SetHeight(1)
        else
            line:SetWidth(1)
        end
    end
end

local function Tip(control, tip)
    if not tip then
        return
    end
    if control.EnableMouse then
        control:EnableMouse(true)
    end
    control:SetScript("OnEnter", function(self)
        local tooltip = rawget(_G, "GameTooltip")
        if tooltip then
            tooltip:SetOwner(self, "ANCHOR_RIGHT")
            tooltip:SetText(tip, 1, 1, 1, 1, true)
            tooltip:Show()
        end
    end)
    control:SetScript("OnLeave", function()
        local tooltip = rawget(_G, "GameTooltip")
        if tooltip then
            tooltip:Hide()
        end
    end)
end

-- A window in the middle of the screen: drag its title to move it, Escape
-- or the x closes it. Controls made with the functions below are put on
-- window.body; window:Refresh() re-reads every one of them.
function K.Window(name, title, width, height)
    local window = CreateFrame("Frame", name, UIParent)
    window:SetSize(width, height)
    window:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    window:SetFrameStrata("DIALOG")
    window:EnableMouse(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    Panel(window)
    local heading = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 14, -12)
    heading:SetText(title)
    local close = CreateFrame("Button", nil, window)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -6, -6)
    local cross = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cross:SetPoint("CENTER")
    cross:SetText("x")
    close:SetScript("OnClick", function() window:Hide() end)
    local special = rawget(_G, "UISpecialFrames")
    if special and name then
        special[#special + 1] = name
    end
    window.body = window
    window.controls = {}
    function window:Refresh()
        for _, control in ipairs(self.controls) do
            control:Refresh()
        end
    end
    window:SetScript("OnShow", function(self) self:Refresh() end)
    window:Hide()
    return window
end

function K.Header(window, text, x, y)
    local label = window.body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(text)
    return label
end

-- Wrapped text; returns the y just under it.
function K.Para(window, text, x, y, width)
    local label = window.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    local height = K.Num(label:GetStringHeight()) or 0
    if height < 12 then
        -- (Not laid out yet: by the length of the text.)
        height = 12 * math.ceil(#text * 6 / width)
    end
    return y - height - 8
end

-- A check box: `get()` says whether it's ticked, `set(checked)` is told when
-- it's clicked.
function K.Check(window, text, x, y, get, set, tip)
    local check = CreateFrame("Button", nil, window.body)
    check:SetSize(18, 18)
    check:SetPoint("TOPLEFT", x, y)
    local box = check:CreateTexture(nil, "BACKGROUND")
    box:SetAllPoints()
    box:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
    local inner = check:CreateTexture(nil, "BORDER")
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(0.10, 0.09, 0.08, 1)
    local tick = check:CreateTexture(nil, "ARTWORK")
    tick:SetPoint("TOPLEFT", 4, -4)
    tick:SetPoint("BOTTOMRIGHT", -4, 4)
    tick:SetColorTexture(0.46, 0.84, 0.38, 1)
    local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 6, 0)
    label:SetText(text)
    check.tick, check.label = tick, label
    function check:Refresh()
        self.checked = get() and true or false
        self.tick:SetShown(self.checked)
    end
    check:SetScript("OnClick", function(self)
        set(not self.checked)
        self:Refresh()
    end)
    Tip(check, tip)
    check:Refresh()
    window.controls[#window.controls + 1] = check
    return check
end

local function SmallButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 20)
    local edge = button:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
    local inner = button:CreateTexture(nil, "BORDER")
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(0.14, 0.12, 0.10, 1)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(0.46, 0.84, 0.38, 0.25)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(text)
    button.label = label
    return button
end

-- A number with - and + beside it, kept between `least` and `most`.
function K.Stepper(window, text, x, y, get, set, step, least, most, format, tip)
    local row = CreateFrame("Frame", nil, window.body)
    row:SetSize(360, 20)
    row:SetPoint("TOPLEFT", x, y)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(text)
    local minus = SmallButton(row, "-", 20)
    minus:SetPoint("LEFT", 190, 0)
    local value = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    value:SetWidth(96)
    value:SetJustifyH("CENTER")
    local plus = SmallButton(row, "+", 20)
    plus:SetPoint("LEFT", value, "RIGHT", 6, 0)
    row.value, row.minus, row.plus = value, minus, plus
    function row:Refresh()
        local now = get()
        self.value:SetText(format and format(now) or tostring(now))
    end
    local function Step(by)
        local now = math.max(least, math.min(most, get() + by))
        set(now)
        row:Refresh()
    end
    minus:SetScript("OnClick", function() Step(-step) end)
    plus:SetScript("OnClick", function() Step(step) end)
    Tip(row, tip)
    row:Refresh()
    window.controls[#window.controls + 1] = row
    return row
end

function K.Button(window, text, width, x, y, onClick, tip)
    local button = SmallButton(window.body, text, width)
    button:SetHeight(22)
    button:SetPoint("TOPLEFT", x, y)
    button:SetScript("OnClick", onClick)
    Tip(button, tip)
    return button
end
