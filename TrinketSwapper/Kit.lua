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
    K.SnapTarget(frame)   -- something for the others to line up with
end

-- While you drag one of these addons' frames it snaps into line: its left
-- edge, middle or right edge onto the middle of the screen or onto another
-- frame's left edge, middle or right edge, and the same up and down. A
-- green line shows what it lined up with; hold Shift to place it freely.
-- The addons share one list of what there is to line up with (each has its
-- own copy of this file), so one addon's frame snaps to another's.
local SNAP = 10   -- how close (in interface units) an edge has to come
local snap = rawget(_G, "ElipsSuiteSnap")
if type(snap) ~= "table" then
    -- frames: every frame that can be lined up with; edges: functions
    -- returning left, right, top, bottom in screen pixels.
    snap = { frames = setmetatable({}, { __mode = "k" }), edges = {} }
    rawset(_G, "ElipsSuiteSnap", snap)
end
K.snap = snap

function K.SnapTarget(frame)
    snap.frames[frame] = true
end

-- A frame's edges in screen pixels: left, right, top, bottom (nil if it
-- has no place yet).
local function Edges(frame)
    local scale = K.Num(frame:GetEffectiveScale())
    local left, bottom = K.Num(frame:GetLeft()), K.Num(frame:GetBottom())
    local width, height = K.Num(frame:GetWidth()), K.Num(frame:GetHeight())
    if not (scale and left and bottom and width and height) then
        return nil
    end
    return left * scale, (left + width) * scale, (bottom + height) * scale, bottom * scale
end

local function Targets(skip, skipToo)
    local scale = K.Num(UIParent:GetEffectiveScale()) or 1
    local xs, ys = { UIParent:GetWidth() * scale / 2 }, { UIParent:GetHeight() * scale / 2 }
    local function Add(left, right, top, bottom)
        if K.Num(left) and K.Num(right) and K.Num(top) and K.Num(bottom) then
            xs[#xs + 1], xs[#xs + 2], xs[#xs + 3] = left, (left + right) / 2, right
            ys[#ys + 1], ys[#ys + 2], ys[#ys + 3] = top, (top + bottom) / 2, bottom
        end
    end
    for frame in pairs(snap.frames) do
        if frame ~= skip and frame ~= skipToo then
            local ok, visible = pcall(frame.IsVisible, frame)
            if ok and K.Bool(visible, false) then
                Add(Edges(frame))
            end
        end
    end
    for _, edges in ipairs(snap.edges) do
        local ok, left, right, top, bottom = pcall(edges, skip)
        if ok then
            Add(left, right, top, bottom)
        end
    end
    return xs, ys
end

local function Nearest(mine, lines, reach)
    local move, line
    for _, at in ipairs(mine) do
        for _, target in ipairs(lines) do
            local gap = target - at
            if math.abs(gap) <= reach and (not move or math.abs(gap) < math.abs(move)) then
                move, line = gap, target
            end
        end
    end
    return move or 0, line
end

-- How far to move a frame with these edges (screen pixels) so it lines up:
-- across, up, and the lines it lined up with (nil where it didn't).
function K.SnapEdges(left, right, top, bottom, skip, skipToo, xs, ys)
    if not xs then
        xs, ys = Targets(skip, skipToo)
    end
    local reach = SNAP * (K.Num(UIParent:GetEffectiveScale()) or 1)
    local dx, lineX = Nearest({ left, (left + right) / 2, right }, xs, reach)
    local dy, lineY = Nearest({ top, (top + bottom) / 2, bottom }, ys, reach)
    return dx, dy, lineX, lineY
end

local guides
local function Guides(lineX, lineY)
    if not guides then
        if not (lineX or lineY) then
            return
        end
        guides = {}
        for _, key in ipairs({ "x", "y" }) do
            local guide = CreateFrame("Frame", nil, UIParent)
            guide:SetFrameStrata("TOOLTIP")
            local line = guide:CreateTexture(nil, "OVERLAY")
            line:SetAllPoints()
            line:SetColorTexture(0.2, 1, 0.2, 0.9)
            guide:SetSize(2, 2)
            guide:Hide()
            guides[key] = guide
        end
    end
    local scale = K.Num(UIParent:GetEffectiveScale()) or 1
    if lineX then
        guides.x:ClearAllPoints()
        guides.x:SetPoint("TOP", UIParent, "TOPLEFT", lineX / scale, 0)
        guides.x:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", lineX / scale, 0)
    end
    guides.x:SetShown(lineX ~= nil)
    if lineY then
        guides.y:ClearAllPoints()
        guides.y:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, lineY / scale)
        guides.y:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, lineY / scale)
    end
    guides.y:SetShown(lineY ~= nil)
end

-- The frame being dragged follows the cursor, snapping as it goes.
local dragging
local driver = CreateFrame("Frame")
local function Follow()
    local drag = dragging
    if not drag then
        driver:SetScript("OnUpdate", nil)
        return
    end
    local frame = drag.frame
    if K.Bool(InCombatLockdown(), false) then
        return   -- (the game doesn't let some frames move in a fight)
    end
    local scale = K.Num(frame:GetEffectiveScale())
    local cursorX, cursorY = GetCursorPosition()
    cursorX, cursorY = K.Num(cursorX), K.Num(cursorY)
    local screen = K.Num(UIParent:GetEffectiveScale())
    if not (scale and cursorX and cursorY and screen) then
        return
    end
    local width, height = frame:GetWidth() * scale, frame:GetHeight() * scale
    local left = math.max(0, math.min(UIParent:GetWidth() * screen - width, cursorX - drag.x))
    local top = math.max(height, math.min(UIParent:GetHeight() * screen, cursorY - drag.y))
    local lineX, lineY
    if not IsShiftKeyDown() then
        local dx, dy
        dx, dy, lineX, lineY = K.SnapEdges(left, left + width, top, top - height, frame, drag.handle)
        left, top = left + dx, top + dy
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
    Guides(lineX, lineY)
end

-- Dragging `handle` (the frame itself, or a box over it) moves `frame`,
-- snapping as above. `saved(x, y)` is told where its center ended up.
function K.Drag(handle, frame, saved)
    frame:SetMovable(true)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    K.SnapTarget(frame)
    handle:SetScript("OnDragStart", function(self)
        if K.Bool(InCombatLockdown(), false) then
            return
        end
        local scale = K.Num(frame:GetEffectiveScale())
        local cursorX, cursorY = GetCursorPosition()
        local left, top = K.Num(frame:GetLeft()), K.Num(frame:GetTop())
        if scale and K.Num(cursorX) and K.Num(cursorY) and left and top then
            dragging = { frame = frame, handle = self, x = cursorX - left * scale, y = cursorY - top * scale }
            driver:SetScript("OnUpdate", Follow)
        else
            -- (Nowhere to measure from: the game's own dragging, no snapping.)
            self.kitGameDrag = true
            frame:StartMoving()
        end
    end)
    handle:SetScript("OnDragStop", function(self)
        if self.kitGameDrag then
            self.kitGameDrag = nil
            frame:StopMovingOrSizing()
        elseif dragging and dragging.handle == self then
            dragging = nil
            driver:SetScript("OnUpdate", nil)
            Guides(nil, nil)
        else
            return
        end
        local x, y = frame:GetCenter()
        x, y = K.Num(x), K.Num(y)
        if x and y then
            saved(x, y)
        end
    end)
end

-- A blue box over `frame` that can be dragged to move it. `saved(x, y)` is
-- told where its center ended up. Returns the box; Show and Hide it.
function K.DragBox(frame, label, saved)
    local box = CreateFrame("Frame", nil, UIParent)
    box:SetFrameStrata("DIALOG")
    box:SetAllPoints(frame)
    local fill = box:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.20, 0.50, 1.00, 0.45)
    local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    text:SetText(label)
    K.Drag(box, frame, saved)
    K.SnapTarget(box)
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
-- The look: dark panels inside a weathered bronze edge, corners rounded
------------------------------------------------------------------------------

K.EDGE = { 0.60, 0.46, 0.26 }       -- a panel's edge: weathered bronze
K.EDGE_DIM = { 0.34, 0.275, 0.18 }  -- a control's edge at rest
K.EDGE_LIT = { 0.84, 0.68, 0.42 }   -- under the mouse, or selected
K.GOLD = { 0.86, 0.71, 0.46 }       -- headings and values: antique gold
K.TEXT = { 0.89, 0.86, 0.79 }       -- labels: parchment
K.TEXT_DIM = { 0.70, 0.67, 0.60 }   -- longer notes
K.FILL = { 0.075, 0.064, 0.052 }    -- inside a panel
K.WELL = { 0.125, 0.108, 0.088 }    -- inside a control

-- Two pieces of art, each tinted where it's used: a white rounded rectangle
-- and the ring around it. Their corner tiles are the outer quarter each way.
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local FILL_ART, EDGE_ART = MEDIA .. "PanelFill.tga", MEDIA .. "PanelEdge.tga"
local Q = 0.25

-- `art` over `frame` in nine pieces: corners `corner` wide, the sides and
-- middle stretched between them (`hollow`: no middle, for the ring).
local Slice = {}
Slice.__index = Slice
function Slice:SetColor(r, g, b, a)
    self.color = { r, g, b, a or 1 }
    for _, piece in ipairs(self.pieces) do
        piece:SetVertexColor(r, g, b, a or 1)
    end
end
function Slice:SetShown(shown)
    for _, piece in ipairs(self.pieces) do
        piece:SetShown(shown)
    end
end
local function NewSlice(frame, art, corner, layer, level, inset, hollow)
    inset = inset or 0
    local slice = setmetatable({ pieces = {} }, Slice)
    local function Piece(left, right, top, bottom)
        local piece = frame:CreateTexture(nil, layer, nil, level or 0)
        piece:SetTexture(art)
        piece:SetTexCoord(left, right, top, bottom)
        slice.pieces[#slice.pieces + 1] = piece
        return piece
    end
    local topLeft, topRight = Piece(0, Q, 0, Q), Piece(1 - Q, 1, 0, Q)
    local bottomLeft, bottomRight = Piece(0, Q, 1 - Q, 1), Piece(1 - Q, 1, 1 - Q, 1)
    topLeft:SetPoint("TOPLEFT", inset, -inset)
    topRight:SetPoint("TOPRIGHT", -inset, -inset)
    bottomLeft:SetPoint("BOTTOMLEFT", inset, inset)
    bottomRight:SetPoint("BOTTOMRIGHT", -inset, inset)
    for _, piece in ipairs(slice.pieces) do
        piece:SetSize(corner, corner)
    end
    local function Between(piece, from, fromPoint, to, toPoint)
        piece:SetPoint("TOPLEFT", from, fromPoint)
        piece:SetPoint("BOTTOMRIGHT", to, toPoint)
    end
    Between(Piece(Q, 1 - Q, 0, Q), topLeft, "TOPRIGHT", topRight, "BOTTOMLEFT")
    Between(Piece(Q, 1 - Q, 1 - Q, 1), bottomLeft, "TOPRIGHT", bottomRight, "BOTTOMLEFT")
    Between(Piece(0, Q, Q, 1 - Q), topLeft, "BOTTOMLEFT", bottomLeft, "TOPRIGHT")
    Between(Piece(1 - Q, 1, Q, 1 - Q), topRight, "BOTTOMLEFT", bottomRight, "TOPRIGHT")
    if not hollow then
        Between(Piece(Q, 1 - Q, Q, 1 - Q), topLeft, "BOTTOMRIGHT", bottomRight, "TOPLEFT")
    end
    return slice
end

-- A rounded panel on `frame`: a dark inside and a bronze edge. Returns its
-- look: look:Fill(r, g, b, a) and look:Edge(r, g, b, a) recolor it.
-- `corner` sets how round (9 for a window, 6 for a button).
local Look = {}
Look.__index = Look
function Look:Fill(r, g, b, a)
    self.fill:SetColor(r, g, b, a)
end
function Look:Edge(r, g, b, a)
    self.edge:SetColor(r, g, b, a)
end
function K.Rounded(frame, corner, inset)
    corner = corner or 9
    local look = setmetatable({}, Look)
    look.fill = NewSlice(frame, FILL_ART, corner, "BACKGROUND", 0, inset)
    look.edge = NewSlice(frame, EDGE_ART, corner, "BORDER", 0, inset, true)
    look:Fill(K.FILL[1], K.FILL[2], K.FILL[3], 0.95)
    look:Edge(K.EDGE[1], K.EDGE[2], K.EDGE[3], 1)
    frame.kitLook = look
    return look
end

-- The same rounded shape in one color, for a light under the mouse and
-- the like. Returns a slice: SetColor, SetShown.
function K.RoundedFill(frame, corner, layer, inset, level)
    return NewSlice(frame, FILL_ART, corner or 6, layer or "ARTWORK", level, inset)
end

local function Tint(region, color, alpha)
    region:SetTextColor(color[1], color[2], color[3], alpha or 1)
end

------------------------------------------------------------------------------
-- The settings window
------------------------------------------------------------------------------

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

-- A button in the look: lit under the mouse, its label a pixel lower
-- while it's held. button:SetSelected(true) marks it as the one that's on
-- (a tab, say).
local function SmallButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 20)
    local look = K.Rounded(button, 6)
    look:Fill(K.WELL[1], K.WELL[2], K.WELL[3], 1)
    look:Edge(K.EDGE_DIM[1], K.EDGE_DIM[2], K.EDGE_DIM[3], 1)
    local hover = K.RoundedFill(button, 6, "HIGHLIGHT")
    hover:SetColor(K.EDGE_LIT[1], K.EDGE_LIT[2], K.EDGE_LIT[3], 0.16)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(text)
    Tint(label, K.TEXT)
    button.label, button.look, button.hover = label, look, hover
    function button:SetSelected(selected)
        self.selected = selected and true or false
        local edge, fill = selected and K.EDGE_LIT or K.EDGE_DIM, selected and 1.5 or 1
        self.look:Edge(edge[1], edge[2], edge[3], 1)
        self.look:Fill(K.WELL[1] * fill, K.WELL[2] * fill, K.WELL[3] * fill, 1)
        Tint(self.label, selected and K.GOLD or K.TEXT)
    end
    button:SetScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 0, -1) end)
    button:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    return button
end

-- A window in the middle of the screen: drag it to move it, Escape or the
-- x closes it. Controls made with the functions below are put on
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
    K.Rounded(window, 9)
    local heading = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 16, -12)
    heading:SetText(title)
    Tint(heading, K.GOLD)
    window.heading = heading
    -- A faint rule under the title.
    local rule = window:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 12, -33)
    rule:SetPoint("TOPRIGHT", -12, -33)
    rule:SetHeight(1)
    rule:SetColorTexture(K.EDGE[1], K.EDGE[2], K.EDGE[3], 0.35)
    local close = CreateFrame("Button", nil, window)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -8, -8)
    local closeHover = K.RoundedFill(close, 6, "HIGHLIGHT")
    closeHover:SetColor(K.EDGE_LIT[1], K.EDGE_LIT[2], K.EDGE_LIT[3], 0.22)
    local cross = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cross:SetPoint("CENTER", 0, 1)
    cross:SetText("x")
    Tint(cross, K.GOLD)
    close:SetScript("OnClick", function() window:Hide() end)
    window.close = close
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
    Tint(label, K.GOLD)
    return label
end

-- Wrapped text; returns the y just under it.
function K.Para(window, text, x, y, width)
    local label = window.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    Tint(label, K.TEXT_DIM)
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
    local look = K.Rounded(check, 5, 1)
    look:Fill(0.045, 0.039, 0.032, 1)
    look:Edge(K.EDGE_DIM[1], K.EDGE_DIM[2], K.EDGE_DIM[3], 1)
    local hover = K.RoundedFill(check, 5, "HIGHLIGHT", 1)
    hover:SetColor(K.EDGE_LIT[1], K.EDGE_LIT[2], K.EDGE_LIT[3], 0.18)
    -- The tick: a small rounded block of antique gold.
    local tick = CreateFrame("Frame", nil, check)
    tick:SetPoint("TOPLEFT", 5, -5)
    tick:SetPoint("BOTTOMRIGHT", -5, 5)
    K.RoundedFill(tick, 3, "ARTWORK"):SetColor(K.EDGE_LIT[1], K.EDGE_LIT[2], K.EDGE_LIT[3], 1)
    local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 6, 0)
    label:SetText(text)
    Tint(label, K.TEXT)
    check.tick, check.label, check.look = tick, label, look
    function check:Refresh()
        self.checked = get() and true or false
        self.tick:SetShown(self.checked)
        local edge = self.checked and K.EDGE or K.EDGE_DIM
        self.look:Edge(edge[1], edge[2], edge[3], 1)
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

-- A number with - and + beside it, kept between `least` and `most`.
function K.Stepper(window, text, x, y, get, set, step, least, most, format, tip)
    local row = CreateFrame("Frame", nil, window.body)
    row:SetSize(360, 20)
    row:SetPoint("TOPLEFT", x, y)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(text)
    Tint(label, K.TEXT)
    local minus = SmallButton(row, "-", 20)
    minus:SetPoint("LEFT", 190, 0)
    local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    value:SetWidth(96)
    value:SetJustifyH("CENTER")
    Tint(value, K.GOLD)
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
