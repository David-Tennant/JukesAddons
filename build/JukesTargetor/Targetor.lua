local ADDON = ...
local ICON = "Interface\\Icons\\Ability_Hunter_SniperShot"
-- Raid target markers: index -> name and chat token ({square} etc.)
local MARKERS = {
    { "Star", "star" }, { "Circle", "circle" }, { "Diamond", "diamond" }, { "Triangle", "triangle" },
    { "Moon", "moon" }, { "Square", "square" }, { "Cross", "cross" }, { "Skull", "skull" },
}
-- Announce channels: chat type, slash label, name
local CHANNELS = {
    { "SAY", "/s", "Say" }, { "PARTY", "/p", "Party" }, { "EMOTE", "/e", "Emote" }, { "YELL", "/y", "Yell" },
}
local function ChannelInfo(chatType)
    for _, c in ipairs(CHANNELS) do
        if c[1] == chatType then return c end
    end
    return CHANNELS[1]
end
local function MarkerIcon(i, size)
    return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i .. ":" .. (size or 14) .. "|t"
end

local defaults = {
    shown = true, minimapAngle = 220, text = "",
    fullMatch = true, announce = true, opacity = 1.0,
    announceChannel = "SAY", -- SAY, PARTY, EMOTE or YELL (chosen in the settings panel)
    marker = 6, -- raid target index (1-8), 0 = no marker; 6 = square
    useKeybind = false, -- db.keybind holds the chosen key, e.g. "SHIFT-F"
}
local db

-------------------------------------------------------------------------------
-- Main window
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame", "TargetorFrame", UIParent, "BackdropTemplate")
frame:SetSize(230, 118)
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

-- Marker dropdown (right of the announce checkbox)
local markerSetting -- settings-panel mirror, set in CreateSettings
local ApplySettings -- defined further down
local markerDrop = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
markerDrop:SetWidth(90)
markerDrop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -48)
local function SetMarker(i)
    if markerSetting then
        markerSetting:SetValue(i) -- keeps the settings panel in sync; calls ApplySettings
    else
        db.marker = i
        ApplySettings()
    end
end
markerDrop:SetupMenu(function(_, root)
    root:CreateTitle("Mark with")
    for i, m in ipairs(MARKERS) do
        root:CreateRadio(MarkerIcon(i) .. " " .. m[1],
            function() return db and db.marker == i end, function() SetMarker(i) end)
    end
    root:CreateRadio("No marker", function() return db and db.marker == 0 end, function() SetMarker(0) end)
end)
markerDrop:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Marker")
    GameTooltip:AddLine("The raid marker put on a found target.", 1, 1, 1)
    GameTooltip:Show()
end)
markerDrop:SetScript("OnLeave", GameTooltip_Hide)

local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("BOTTOMLEFT", 10, 8)
status:SetPoint("BOTTOMRIGHT", -10, 8)
status:SetJustifyH("LEFT")

-- Tick shown next to "Partial match: <name>"; puts that name into the box
local acceptBtn = CreateFrame("Button", nil, frame)
acceptBtn:SetSize(18, 18)
acceptBtn:SetPoint("BOTTOMRIGHT", -8, 5)
acceptBtn:SetNormalTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
acceptBtn:SetHighlightTexture("Interface\\RaidFrame\\ReadyCheck-Ready", "ADD")
acceptBtn:Hide()
status:SetPoint("BOTTOMRIGHT", -30, 8)

local function SetStatus(msg, r, g, b)
    status:SetText(msg)
    status:SetTextColor(r or 1, g or 1, b or 1)
    acceptBtn:Hide()
end

acceptBtn:SetScript("OnClick", function(self)
    local name = self.name
    if not name then return end
    edit:SetText(name) -- OnTextChanged updates the macro (or queues it until combat ends)
    edit:ClearFocus()
    SetStatus("Name set to: " .. name, 0.3, 1, 0.3)
end)
acceptBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Use this name")
    GameTooltip:AddLine("Put \"" .. (self.name or "") .. "\" in the name box.", 1, 1, 1)
    GameTooltip:Show()
end)
acceptBtn:SetScript("OnLeave", GameTooltip_Hide)

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
        return
    end
    -- Marking is protected, so the marker is set by /tm inside this secure macro.
    -- /targetexact first: an exact name always wins over a nearer partial one.
    local marker = db and db.marker or defaults.marker
    local mark = marker > 0 and ("/tm [exists] " .. marker) or nil
    local lines = { "/cleartarget", "/targetexact " .. text }
    if db and not db.fullMatch then
        -- partial allowed: fall back to a partial target, and mark either
        lines[#lines + 1] = "/target [noexists] " .. text
        lines[#lines + 1] = mark
    else
        -- exact only: mark the exact match, then (unmarked) look for a partial
        -- one so the window can offer its name
        lines[#lines + 1] = mark
        lines[#lines + 1] = "/target [noexists] " .. text
    end
    btn:SetAttribute("macrotext", table.concat(lines, "\n"))
end
edit:SetScript("OnTextChanged", UpdateMacro)

-- Runs right after the secure /target, still inside the click (so /s and /y are allowed)
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
        local exact = strlower(name) == strlower(text)
        if not exact and db.fullMatch then
            SetStatus("Partial match: " .. name, 1, 0.8, 0)
            acceptBtn.name = name
            acceptBtn:Show()
            return
        end
        if exact then
            local note = ""
            if db.announce then
                local m = MARKERS[db.marker]
                local icon = m and (" {" .. m[2] .. "}") or ""
                local chatType = ChannelInfo(db.announceChannel)[1]
                if chatType == "PARTY" and not (IsInGroup and IsInGroup()) then
                    note = " (not in a party)" -- never fall back to a public channel
                elseif chatType == "EMOTE" then
                    SendChatMessage("found " .. name .. "!" .. icon, "EMOTE") -- "<you> found <name>!"
                else
                    SendChatMessage("Found " .. name .. "!" .. icon, chatType)
                end
            end
            SetStatus("Found: " .. name .. note, 0.3, 1, 0.3)
        else
            -- partial matches allowed: mark it, but never announce
            SetStatus("Found (partial): " .. name, 0.3, 1, 0.3)
            acceptBtn.name = name
            acceptBtn:Show()
        end
    else
        SetStatus("No \"" .. text .. "\" nearby.", 1, 0.3, 0.3)
    end
end)

-------------------------------------------------------------------------------
-- Keybind: an override binding that clicks the target button.
-- Override bindings sit on top of the normal ones without changing them, so
-- clearing the override gives the key back its previous binding.
-------------------------------------------------------------------------------
local bindOwner = CreateFrame("Frame")

local bindPending = false
local keybindSetting -- settings-panel mirror of useKeybind

local keybindCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
keybindCheck:SetSize(22, 22)
keybindCheck:SetPoint("TOPLEFT", announceCheck, "BOTTOMLEFT", 0, 2)
local keybindLabel = keybindCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
keybindLabel:SetPoint("LEFT", keybindCheck, "RIGHT", 0, 1)
keybindLabel:SetText("Keybind")
keybindCheck:SetHitRectInsets(0, -keybindLabel:GetStringWidth() - 4, 0, 0)

local keyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
keyBtn:SetSize(110, 20)
keyBtn:SetPoint("LEFT", keybindLabel, "RIGHT", 10, 0)

local capturing = false

local function ActionName(key)
    local action = key and GetBindingAction(key)
    if not action or action == "" or action:find("TargetorTargetButton", 1, true) then return nil end
    return _G["BINDING_NAME_" .. action] or action
end

local function UpdateKeyButton()
    if capturing then
        keyBtn:SetText("Press a key...")
    else
        keyBtn:SetText(db and db.keybind and GetBindingText(db.keybind) or "Set key")
    end
    keyBtn:SetEnabled(db and db.useKeybind or false)
end

local function ApplyKeybind()
    if not db then return end
    if InCombatLockdown() then
        bindPending = true
        return
    end
    bindPending = false
    ClearOverrideBindings(bindOwner) -- restores whatever the key did before
    if db.useKeybind and db.keybind then
        SetOverrideBindingClick(bindOwner, true, db.keybind, "TargetorTargetButton", "LeftButton")
    end
    UpdateKeyButton()
end

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true,
}

local function StopCapture()
    capturing = false
    keyBtn:EnableKeyboard(false)
    keyBtn:SetScript("OnKeyDown", nil)
    UpdateKeyButton()
end

local function StartCapture()
    if InCombatLockdown() then
        SetStatus("Can't set a key in combat.", 1, 0.3, 0.3)
        return
    end
    capturing = true
    keyBtn:EnableKeyboard(true)
    keyBtn:SetPropagateKeyboardInput(false)
    keyBtn:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            StopCapture()
            SetStatus("Keybind unchanged.", 1, 0.8, 0)
            return
        end
        if MODIFIER_KEYS[key] then return end -- wait for the real key
        local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "") .. ((IsMetaKeyDown and IsMetaKeyDown()) and "META-" or "") .. key
        local overrides = ActionName(combo)
        db.keybind = combo
        StopCapture()
        ApplyKeybind()
        SetStatus("Key: " .. GetBindingText(combo) .. (overrides and (" (over " .. overrides .. ")") or ""), 0.3, 1, 0.3)
    end)
    UpdateKeyButton()
    SetStatus("Press a key (Esc to cancel).", 1, 0.8, 0)
end

keyBtn:SetScript("OnClick", function()
    if capturing then StopCapture() else StartCapture() end
end)
keyBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Targetor keybind")
    GameTooltip:AddLine("Click, then press a key (modifiers allowed).", 1, 1, 1)
    GameTooltip:AddLine("While ticked, it overrides that key's normal binding.", 1, 1, 1)
    GameTooltip:AddLine("Untick to give the key back its previous binding.", 1, 1, 1)
    if db and db.keybind then
        local was = ActionName(db.keybind)
        if db.useKeybind then
            -- our override hides the normal action from GetBindingAction; look it up without it
            was = nil
            for i = 1, GetNumBindings() do
                local command, _, k1, k2 = GetBinding(i)
                if k1 == db.keybind or k2 == db.keybind then
                    was = _G["BINDING_NAME_" .. command] or command
                    break
                end
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Normally: " .. (was or "nothing"), 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end)
keyBtn:SetScript("OnLeave", GameTooltip_Hide)

local function SetUseKeybind(on)
    if keybindSetting then
        keybindSetting:SetValue(on) -- keeps the settings panel in sync; calls ApplySettings
    else
        db.useKeybind = on
        ApplyKeybind()
    end
end

keybindCheck:SetScript("OnClick", function(self)
    if InCombatLockdown() then
        self:SetChecked(db.useKeybind)
        SetStatus("Can't change the keybind in combat.", 1, 0.3, 0.3)
        return
    end
    local on = self:GetChecked() and true or false
    if not on and capturing then StopCapture() end
    SetUseKeybind(on)
    if on and not db.keybind then
        StartCapture() -- first time: go straight to "press a key"
    elseif not on then
        SetStatus("Keybind off, key restored.", 1, 1, 1)
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

function ApplySettings()
    if not MARKERS[db.marker] then db.marker = 0 end
    frame:SetAlpha(db.opacity)
    markerDrop:GenerateMenu()
    db.announceChannel = ChannelInfo(db.announceChannel)[1]
    announceCheck:SetChecked(db.announce)
    announceLabel:SetText("Announce in " .. ChannelInfo(db.announceChannel)[2])
    announceCheck:SetHitRectInsets(0, -announceLabel:GetStringWidth() - 4, 0, 0)
    keybindCheck:SetChecked(db.useKeybind)
    UpdateMacro()
    ApplyKeybind()
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

    local partialSetting = Settings.RegisterProxySetting(category, "Targetor_allowPartial", Settings.VarType.Boolean,
        "Allow partial match", not defaults.fullMatch,
        function() return not db.fullMatch end,
        function(value) db.fullMatch = not value; ApplySettings() end)
    CreateCheckbox(category, partialSetting,
        "Ticked: any target /target finds counts, e.g. \"wolf\" finds \"Timber Wolf\". "
        .. "Unticked: only an exact name is marked and announced, and a partial match shows a tick to use that name.")

    local s

    announceSetting = Proxy("announce", Settings.VarType.Boolean, "Announce")
    CreateCheckbox(category, announceSetting, "Announce the found target's name in the channel below.")

    local CreateDropdown = Settings.CreateDropdown or Settings.CreateDropDown
    if CreateDropdown and Settings.CreateControlTextContainer then
        local channelSetting = Proxy("announceChannel", Settings.VarType.String, "Announce in")
        CreateDropdown(category, channelSetting, function()
            local c = Settings.CreateControlTextContainer()
            for _, ch in ipairs(CHANNELS) do c:Add(ch[1], ch[2] .. "  " .. ch[3]) end
            return c:GetData()
        end, "Where the found message goes: /s say, /p party, /e emote or /y yell. "
            .. "Party is skipped when you're not in a group.")

        markerSetting = Proxy("marker", Settings.VarType.Number, "Marker")
        CreateDropdown(category, markerSetting, function()
            local c = Settings.CreateControlTextContainer()
            for i, m in ipairs(MARKERS) do c:Add(i, MarkerIcon(i) .. " " .. m[1]) end
            c:Add(0, "No marker")
            return c:GetData()
        end, "The raid marker put on a found target.")
    end

    keybindSetting = Proxy("useKeybind", Settings.VarType.Boolean, "Use keybind")
    CreateCheckbox(category, keybindSetting,
        "Lets your chosen key click the target button, overriding that key's normal binding. "
        .. "Unticking restores the key's previous binding. Choose the key with the button on the Targetor window.")

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
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_LOGIN")
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
    elseif event == "PLAYER_LOGIN" then
        ApplyKeybind()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if capturing then StopCapture() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingUpdate then UpdateMacro() end
        if bindPending then ApplyKeybind() end
    end
end)

SLASH_TARGETOR1 = "/targetor"
SlashCmdList.TARGETOR = Toggle
