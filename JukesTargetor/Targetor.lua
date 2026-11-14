local ADDON = ...
local ICON = "Interface\\Icons\\Ability_Hunter_SniperShot"
local CROSS = 7 -- raid target index for the X

local defaults = {
    shown = true, minimapAngle = 220, text = "",
    fullMatch = true, announce = true, opacity = 1.0,
}
local db

-------------------------------------------------------------------------------
-- Main window
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame", "TargetorFrame", UIParent, "BackdropTemplate")
frame:SetSize(230, 94)
frame:SetPoint("CENTER", 0, 200)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetClampedToScreen(true)
frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
frame:SetBackdropColor(0, 0, 0, 0.85)
frame:Hide()

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOPLEFT", 10, -8)
title:SetText("Targetor")

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetSize(20, 20)
close:SetPoint("TOPRIGHT", -2, -2)
close:SetScript("OnClick", function() frame:Hide() end)

local edit = CreateFrame("EditBox", "TargetorEditBox", frame, "InputBoxTemplate")
edit:SetSize(160, 20)
edit:SetPoint("TOPLEFT", 16, -24)
edit:SetAutoFocus(false)
edit:SetScript("OnEnterPressed", edit.ClearFocus)
edit:SetScript("OnEscapePressed", edit.ClearFocus)

edit:SetTextInsets(0, 16, 0, 0)

local clear = CreateFrame("Button", nil, edit)
clear:SetSize(14, 14)
clear:SetPoint("RIGHT", edit, "RIGHT", -2, 0)
clear:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
clear:GetNormalTexture():SetAlpha(0.6)
clear:SetHighlightTexture("Interface\\FriendsFrame\\ClearBroadcastIcon", "ADD")
clear:SetScript("OnClick", function()
    edit:SetText("")
    edit:ClearFocus()
end)
clear:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Clear text", 1, 1, 1)
    GameTooltip:Show()
end)
clear:SetScript("OnLeave", GameTooltip_Hide)

local announceCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
announceCheck:SetSize(22, 22)
announceCheck:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -8, -2)
local announceLabel = announceCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
announceLabel:SetPoint("LEFT", announceCheck, "RIGHT", 0, 1)
announceLabel:SetText("Announce in /s")
announceCheck:SetHitRectInsets(0, -announceLabel:GetStringWidth() - 4, 0, 0)

local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("BOTTOMLEFT", 10, 8)
status:SetPoint("BOTTOMRIGHT", -10, 8)
status:SetJustifyH("LEFT")

local function SetStatus(msg, r, g, b)
    status:SetText(msg)
    status:SetTextColor(r or 1, g or 1, b or 1)
end

-------------------------------------------------------------------------------
-- Target button (secure: /target can only run from a secure click)
-------------------------------------------------------------------------------
local btn = CreateFrame("Button", "TargetorTargetButton", frame, "SecureActionButtonTemplate")
btn:SetSize(26, 26)
btn:SetPoint("LEFT", edit, "RIGHT", 8, 0)
btn:RegisterForClicks("AnyUp", "AnyDown")
btn:SetAttribute("type", "macro")
btn:SetNormalTexture(ICON)
btn:SetPushedTexture(ICON)
btn:GetPushedTexture():SetVertexColor(0.6, 0.6, 0.6)
btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Targetor")
    GameTooltip:AddLine("Click to /target the text", 1, 1, 1)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", GameTooltip_Hide)

local pendingUpdate = false
local function UpdateMacro()
    local text = strtrim(edit:GetText() or "")
    if db then db.text = text end
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    pendingUpdate = false
    if text == "" then
        btn:SetAttribute("macrotext", nil)
    else
        btn:SetAttribute("macrotext", "/cleartarget\n/target " .. text)
    end
end
edit:SetScript("OnTextChanged", UpdateMacro)

-- Runs right after the secure /target, still inside the click (so /s is allowed)
btn:SetScript("PostClick", function(self, button, down)
    -- registered for both up+down; only react once per press
    local useDown = GetCVarBool("ActionButtonUseKeyDown")
    if (down and not useDown) or (not down and useDown) then return end

    local text = strtrim(edit:GetText() or "")
    if text == "" then
        SetStatus("Type a name first.", 1, 0.8, 0)
        return
    end
    if pendingUpdate then
        SetStatus("Can't change the name in combat.", 1, 0.3, 0.3)
        return
    end

    if UnitExists("target") then
        local name = UnitName("target")
        if db.fullMatch and strlower(name) ~= strlower(text) then
            SetStatus("Partial match: " .. name, 1, 0.8, 0)
            return
        end
        if GetRaidTargetIndex("target") ~= CROSS then
            SetRaidTarget("target", CROSS)
        end
        if db.announce then
            SendChatMessage("Found " .. name .. "! {x}", "SAY")
        end
        SetStatus("Found: " .. name, 0.3, 1, 0.3)
    else
        SetStatus("No \"" .. text .. "\" nearby.", 1, 0.3, 0.3)
    end
end)

-------------------------------------------------------------------------------
-- Minimap button
-------------------------------------------------------------------------------
local mm = CreateFrame("Button", "TargetorMinimapButton", Minimap)
mm:SetSize(31, 31)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(8)
mm:RegisterForClicks("AnyUp")
mm:RegisterForDrag("LeftButton")
mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local mmIcon = mm:CreateTexture(nil, "BACKGROUND")
mmIcon:SetSize(20, 20)
mmIcon:SetPoint("TOPLEFT", 7, -5)
mmIcon:SetTexture(ICON)
mmIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local mmBorder = mm:CreateTexture(nil, "OVERLAY")
mmBorder:SetSize(53, 53)
mmBorder:SetPoint("TOPLEFT")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function PlaceMinimapButton()
    local a = math.rad(db.minimapAngle)
    local r = (Minimap:GetWidth() / 2) + 10
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    PlaceMinimapButton()
end
mm:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

local function Toggle()
    frame:SetShown(not frame:IsShown())
end
frame:SetScript("OnShow", function() if db then db.shown = true end end)
frame:SetScript("OnHide", function() if db then db.shown = false end end)

mm:SetScript("OnClick", Toggle)
mm:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Targetor")
    GameTooltip:AddLine("Click to show/hide", 1, 1, 1)
    GameTooltip:AddLine("Drag to move", 1, 1, 1)
    GameTooltip:Show()
end)
mm:SetScript("OnLeave", GameTooltip_Hide)

-------------------------------------------------------------------------------
-- Settings (Options -> AddOns -> Targetor)
-------------------------------------------------------------------------------
local announceSetting

local function ApplySettings()
    frame:SetAlpha(db.opacity)
    announceCheck:SetChecked(db.announce)
end

local function CreateSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local category = Settings.RegisterVerticalLayoutCategory("Targetor")
    local CreateCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox

    local function Proxy(key, varType, name, tooltip)
        local setting = Settings.RegisterProxySetting(category, "Targetor_" .. key, varType, name,
            defaults[key],
            function() return db[key] end,
            function(value) db[key] = value; ApplySettings() end)
        return setting
    end

    local s = Proxy("fullMatch", Settings.VarType.Boolean, "Full name match only")
    CreateCheckbox(category, s,
        "Only mark and announce when the target's name exactly matches the text. Off: any /target result counts.")

    announceSetting = Proxy("announce", Settings.VarType.Boolean, "Announce in /s")
    CreateCheckbox(category, announceSetting, "Say the found target's name in /s.")

    s = Proxy("opacity", Settings.VarType.Number, "Window opacity")
    local opts = Settings.CreateSliderOptions(0.05, 1.0, 0.05)
    opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
        return string.format("%d%%", v * 100 + 0.5)
    end)
    Settings.CreateSlider(category, s, opts, "Opacity of the Targetor window.")

    Settings.RegisterAddOnCategory(category)
end

announceCheck:SetScript("OnClick", function(self)
    local checked = self:GetChecked() and true or false
    if announceSetting then
        announceSetting:SetValue(checked) -- keeps the settings panel in sync
    else
        db.announce = checked
    end
end)

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        TargetorDB = TargetorDB or {}
        db = TargetorDB
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = v end
        end
        local shown = db.shown
        edit:SetText(db.text or "")
        UpdateMacro()
        PlaceMinimapButton()
        CreateSettings()
        ApplySettings()
        frame:SetShown(shown)
    elseif event == "PLAYER_REGEN_ENABLED" and pendingUpdate then
        UpdateMacro()
    end
end)

SLASH_TARGETOR1 = "/targetor"
SlashCmdList.TARGETOR = Toggle
