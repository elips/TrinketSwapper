-- Look.lua
-- The action-bar look for TrinketSwapper's icons: your action buttons' own
-- frame around each icon, the icon cut to its shape, and the frame's
-- tintable border for the mouse-over light and for "the buff is up".
--
-- The art is copied from the game's first action button when the icons are
-- built, so it matches the buttons you see; Blizzard's action button art is
-- the fallback. On a client with neither, the icons get a plain look: a
-- thin black edge.

local _, ns = ...
local K = ns.K
local L = {}
ns.Look = L

-- Each part is drawn at w x h around a `size` icon, its center dx, dy off
-- the icon's.
local ART = {
    size = 45,
    normal = { atlas = "UI-HUD-ActionBar-IconFrame", w = 46, h = 45, dx = 0.5, dy = 0 },
    mask = { atlas = "UI-HUD-ActionBar-IconFrame-Mask", w = 64, h = 64, dx = 0, dy = 0 },
    border = { atlas = "UI-HUD-ActionBar-IconFrame-Border", w = 46, h = 45, dx = 0.5, dy = 0 },
}
L.source = "not looked at yet"

local function AtlasInfo(atlas)
    local textures = rawget(_G, "C_Texture")
    if not (textures and textures.GetAtlasInfo) then
        return nil
    end
    local ok, info = pcall(textures.GetAtlasInfo, atlas)
    return ok and type(info) == "table" and info or nil
end

local function Has(part)
    return part.file ~= nil or (part.atlas ~= nil and AtlasInfo(part.atlas) ~= nil)
end

-- One region of a live action button: its art and where it sits.
local function ReadRegion(button, region, into)
    if not region then
        return false
    end
    local ok = pcall(function()
        local atlas = region.GetAtlas and region:GetAtlas()
        local file = region:GetTexture()
        if not atlas and not file then
            return
        end
        into.atlas, into.file = atlas, (not atlas) and file or nil
        if into.file then
            into.coords = { region:GetTexCoord() }
        end
        into.blend = region.GetBlendMode and region:GetBlendMode() or nil
        local w, h = region:GetSize()
        w, h = K.Num(w), K.Num(h)
        if w and w > 0 and h and h > 0 then
            into.w, into.h = w, h
        end
        local bx, by = button:GetCenter()
        local rx, ry = region:GetCenter()
        bx, by, rx, ry = K.Num(bx), K.Num(by), K.Num(rx), K.Num(ry)
        if bx and by and rx and ry then
            into.dx, into.dy = rx - bx, ry - by
        end
    end)
    return ok and (into.atlas ~= nil or into.file ~= nil)
end

-- Copies the art of the game's first action button.
local function Read()
    local button = rawget(_G, "ActionButton1")
    local size = button and K.Num(button:GetWidth())
    if not size or size <= 0 then
        return
    end
    local parts = {
        normal = button.NormalTexture or (button.GetNormalTexture and button:GetNormalTexture()),
        mask = button.IconMask,
        border = button.Border,
    }
    local found = {}
    for name, region in pairs(parts) do
        local part = {}
        if ReadRegion(button, region, part) then
            for key, value in pairs(part) do
                ART[name][key] = value
            end
            -- A part is either an atlas or a file, never both.
            ART[name].atlas, ART[name].file = part.atlas, part.file
            found[#found + 1] = name
        end
    end
    if #found > 0 then
        ART.size = size
        table.sort(found)
        L.source = "copied from your action buttons (" .. table.concat(found, ", ") .. ")"
    end
    -- The border lies over the frame, so it is drawn where the frame is and
    -- as big as it: on the game's own buttons the border region can sit a
    -- pixel or two off (it does on Forever), which would leave the frame's
    -- top edge showing above the light. Only where both are the same size
    -- of art, so one laid on the other matches.
    local frameInfo = ART.normal.atlas and AtlasInfo(ART.normal.atlas)
    local borderInfo = ART.border.atlas and AtlasInfo(ART.border.atlas)
    if frameInfo and borderInfo and frameInfo.width == borderInfo.width and frameInfo.height == borderInfo.height then
        ART.border.w, ART.border.h, ART.border.dx, ART.border.dy = ART.normal.w, ART.normal.h, ART.normal.dx, ART.normal.dy
    end
end

-- Whether the action-bar look can be drawn here. Decided once.
local decided, usable, hasBorder = false, false, false
function L.On()
    if not decided then
        decided = true
        L.source = "Blizzard's action button art"
        pcall(Read)
        usable = Has(ART.normal) and Has(ART.mask)
        hasBorder = usable and Has(ART.border)
        if not usable then
            L.source = "plain (this client has no action button art)"
        end
    end
    return usable
end

local function SetArt(texture, part)
    if part.atlas then
        texture:SetAtlas(part.atlas)
    else
        texture:SetTexture(part.file)
        if part.coords and #part.coords >= 4 then
            texture:SetTexCoord(unpack(part.coords))
        end
    end
    if part.blend then
        texture:SetBlendMode(part.blend)
    end
end

-- Puts one part where it belongs around an icon `size` big.
local function Place(texture, part, size, anchor)
    local k = size / ART.size
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", anchor, "CENTER", (part.dx or 0) * k, (part.dy or 0) * k)
    texture:SetSize((part.w or ART.size) * k, (part.h or ART.size) * k)
end

-- A cooldown as on ArchDruid's icons: no bright edge or flash, seconds
-- rather than minutes:seconds (up to 10 minutes), and no number for
-- anything of 2 seconds or less. Its number is sized in L.Size.
local NUMBER = 0.42   -- the countdown number's height, as a share of the icon's

function L.Cooldown(frame)
    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, frame, "CooldownFrameTemplate")
    if not (ok and cooldown) then
        cooldown = CreateFrame("Cooldown", nil, frame)
    end
    if cooldown.SetSwipeColor then
        cooldown:SetSwipeColor(0, 0, 0, 0.7)
    end
    if cooldown.SetDrawEdge then
        cooldown:SetDrawEdge(false)
    end
    if cooldown.SetDrawBling then
        cooldown:SetDrawBling(false)
    end
    if cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(false)
    end
    if cooldown.SetCountdownAbbrevThreshold then
        pcall(cooldown.SetCountdownAbbrevThreshold, cooldown, 600)
    end
    if cooldown.SetMinimumCountdownDuration then
        pcall(cooldown.SetMinimumCountdownDuration, cooldown, 2000)
    end
    return cooldown
end

-- Gives `frame` an icon in the look: frame.icon, and (unless `bare`)
-- frame.cooldown and a light while the mouse is over it. L.Size it after.
function L.Icon(frame, bare)
    local look = { on = L.On() }
    frame.look = look
    local icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon = icon
    if look.on then
        icon:SetAllPoints()
        local mask = frame:CreateMaskTexture()
        if ART.mask.atlas then
            mask:SetAtlas(ART.mask.atlas, false, nil, nil, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        else
            mask:SetTexture(ART.mask.file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        icon:AddMaskTexture(mask)
        look.mask = mask
        look.frame = frame:CreateTexture(nil, "OVERLAY")
        SetArt(look.frame, ART.normal)
    else
        local edge = frame:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints()
        edge:SetColorTexture(0, 0, 0, 1)
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    if bare then
        return icon
    end
    local hover = frame:CreateTexture(nil, "HIGHLIGHT")
    if look.on and hasBorder then
        SetArt(hover, ART.border)
        hover:SetVertexColor(1, 1, 1, 1)
        look.hover = hover
    else
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.18)
    end
    frame.cooldown = L.Cooldown(frame)
    return icon
end

-- The border in a color, over an icon made with L.Icon: "this is up".
function L.Edge(frame, r, g, b)
    local look = frame.look
    local edge = frame:CreateTexture(nil, "OVERLAY", nil, 3)
    if look and look.on and hasBorder then
        SetArt(edge, ART.border)
        edge:SetVertexColor(r, g, b, 1)
        look.edge = edge
    else
        -- Plain: a soft glow around the icon.
        edge:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        edge:SetBlendMode("ADD")
        edge:SetVertexColor(r, g, b, 1)
        if look then
            look.glow = edge
        end
    end
    return edge
end

-- Fits the parts to an icon `size` big (after L.Icon, and when the size
-- setting changes).
function L.Size(frame, size)
    local look = frame.look
    if not look then
        return
    end
    if look.on then
        Place(look.mask, ART.mask, size, frame)
        Place(look.frame, ART.normal, size, frame)
        if look.hover then
            Place(look.hover, ART.border, size, frame)
        end
        if look.edge then
            Place(look.edge, ART.border, size, frame)
        end
    end
    if look.glow then
        look.glow:ClearAllPoints()
        look.glow:SetPoint("CENTER", frame, "CENTER", 0, 0)
        look.glow:SetSize(size * 1.75, size * 1.75)
    end
    local cooldown = frame.cooldown
    if cooldown then
        cooldown:ClearAllPoints()
        if look.on then
            -- Action buttons keep the sweep inside the frame's bevel.
            local inset = 3 * size / ART.size
            cooldown:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
            cooldown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
        else
            cooldown:SetAllPoints(frame.icon)
        end
        -- The countdown number, small against the icon (the game's own is
        -- about twice this).
        if cooldown.GetCountdownFontString then
            local found, text = pcall(cooldown.GetCountdownFontString, cooldown)
            if found and text and text.GetFont then
                local font = text:GetFont()
                if font then
                    pcall(text.SetFont, text, font, math.floor(size * NUMBER + 0.5), "OUTLINE")
                end
            end
        end
    end
end
