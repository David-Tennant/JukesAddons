local ADDON_NAME = ...
local TITLE = "Scale Counts"

-- scale in percent, colour 0-1, alignment strings
local DEFAULTS = { scale = 150, r = 1, g = 1, b = 1, a = 1, h = "RIGHT", v = "BOTTOM" }
local STYLE_KEYS = { "scale", "r", "g", "b", "a", "h", "v" }

-- Blizzard action bars that can have their own settings.
-- "check" is the bar frame; bars whose frame doesn't exist in this client are skipped.
local BARS = {
	{ key = "main",  name = "Action Bar 1 (Main)",  prefixes = { "ActionButton", "BonusActionButton", "OverrideActionBarButton" } },
	{ key = "bl",    name = "Bottom Left Bar",      prefixes = { "MultiBarBottomLeftButton" },  check = "MultiBarBottomLeft" },
	{ key = "br",    name = "Bottom Right Bar",     prefixes = { "MultiBarBottomRightButton" }, check = "MultiBarBottomRight" },
	{ key = "right", name = "Right Bar",            prefixes = { "MultiBarRightButton" },       check = "MultiBarRight" },
	{ key = "left",  name = "Right Bar 2",          prefixes = { "MultiBarLeftButton" },        check = "MultiBarLeft" },
	{ key = "mb5",   name = "Action Bar 6",         prefixes = { "MultiBar5Button" },           check = "MultiBar5" },
	{ key = "mb6",   name = "Action Bar 7",         prefixes = { "MultiBar6Button" },           check = "MultiBar6" },
	{ key = "mb7",   name = "Action Bar 8",         prefixes = { "MultiBar7Button" },           check = "MultiBar7" },
}

-- Bar addons: always use the global ("All bars") settings.
local OTHER_PREFIXES = { "BT4Button", "DominosActionButton" }
for i = 1, 10 do OTHER_PREFIXES[#OTHER_PREFIXES + 1] = "ElvUI_Bar" .. i .. "Button" end

local MAX_BUTTONS = 180

local db
local originalFonts = {} -- [fontString] = { font, size, flags }
local buttonBar = {}     -- [button] = bar key

local function GetCountText(button)
	if not button then return end
	local count = button.Count
	if not count and button.GetName and button:GetName() then
		count = _G[button:GetName() .. "Count"]
	end
	if count and count.SetFont then return count end
end

-- Settings for a button: its bar's custom settings if enabled, otherwise global.
local function StyleFor(button)
	local key = buttonBar[button]
	local bar = key and db and db.bars[key]
	if bar and bar.custom then return bar end
	return db or DEFAULTS
end

---------------------------------------------------------------------------
-- Resource store: every reagent spell / consumable seen on a bar.
-- Unticked entries go on the blacklist and their button shows no count.
-- Anything not in the store is treated normally.
---------------------------------------------------------------------------
local RefreshStoreUI -- defined with the settings panel

local function GetSlot(button)
	local slot = button.action or button._state_action
	if not slot and button.GetAttribute then slot = button:GetAttribute("action") end
	if type(slot) == "number" and slot > 0 then return slot end
end

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	return GetSpellInfo and (GetSpellInfo(id))
end

local function ItemName(id)
	if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
	return GetItemInfo and (GetItemInfo(id))
end

-- Returns "spell:123" / "item:456" for the action in a slot.
local function KeyForSlot(slot)
	local kind, id = GetActionInfo(slot)
	if kind == "macro" and id then
		local spellID = GetMacroSpell and GetMacroSpell(id)
		if spellID then
			kind, id = "spell", spellID
		else
			local _, link = GetMacroItem and GetMacroItem(id)
			local itemID = link and tonumber(link:match("item:(%d+)"))
			if itemID then kind, id = "item", itemID else return end
		end
	end
	if (kind == "spell" or kind == "item") and id then
		return kind .. ":" .. id, kind, id
	end
end

local function RecordInStore(slot, key, kind, id)
	if not (IsConsumableAction(slot) or (IsStackableAction and IsStackableAction(slot))) then return end
	local entry = db.store[key]
	local name = (kind == "spell") and SpellName(id) or ItemName(id)
	if not entry then
		db.store[key] = { kind = kind, name = name or key, icon = GetActionTexture(slot) }
		if not db.autoShowNew then db.blacklist[key] = true end
		if RefreshStoreUI then RefreshStoreUI() end
	elseif name and entry.name == key then
		entry.name = name -- item info wasn't cached the first time
		if RefreshStoreUI then RefreshStoreUI() end
	end
end

local function ApplyToButton(button)
	local count = GetCountText(button)
	if not count then return end
	local orig = originalFonts[count]
	if not orig then
		local font, size, flags = count:GetFont()
		if not font or not size then return end
		orig = { font, size, flags }
		originalFonts[count] = orig
	end
	local d = StyleFor(button)

	count:SetFont(orig[1], orig[2] * (d.scale or DEFAULTS.scale) / 100, orig[3])
	count:SetTextColor(d.r, d.g, d.b, d.a)

	-- Position: build an anchor such as "BOTTOMRIGHT", "TOP", "CENTER"
	local h, v = d.h or DEFAULTS.h, d.v or DEFAULTS.v
	local point
	if v == "MIDDLE" then
		point = (h == "CENTER") and "CENTER" or h
	else
		point = v .. ((h == "CENTER") and "" or h)
	end
	local x = (h == "LEFT" and 2) or (h == "RIGHT" and -2) or 0
	local y = (v == "BOTTOM" and 2) or (v == "TOP" and -2) or 0
	count:ClearAllPoints()
	count:SetPoint(point, button, point, x, y)
	count:SetJustifyH(h)

	-- Resource store / blacklist
	local hidden = false
	local slot = db and GetSlot(button)
	if slot and HasAction(slot) then
		local key, kind, id = KeyForSlot(slot)
		if key then
			RecordInStore(slot, key, kind, id)
			hidden = db.blacklist[key] and true or false
		end
	end
	count:SetAlpha(hidden and 0 or 1)
end

local function ForEachButton(prefix, fn)
	for i = 1, MAX_BUTTONS do
		local button = _G[prefix .. i]
		if button then
			fn(button)
		elseif i > 12 then
			break
		end
	end
end

local function ApplyAll()
	for _, bar in ipairs(BARS) do
		for _, prefix in ipairs(bar.prefixes) do
			ForEachButton(prefix, function(button)
				buttonBar[button] = bar.key
				ApplyToButton(button)
			end)
		end
	end
	for _, prefix in ipairs(OTHER_PREFIXES) do
		ForEachButton(prefix, ApplyToButton)
	end
end

-- Re-apply when the game refreshes a button (bar swaps, new buttons, etc.)
if type(ActionButton_UpdateCount) == "function" then
	hooksecurefunc("ActionButton_UpdateCount", ApplyToButton)
end
if ActionBarActionButtonMixin and ActionBarActionButtonMixin.UpdateCount then
	hooksecurefunc(ActionBarActionButtonMixin, "UpdateCount", ApplyToButton)
end

---------------------------------------------------------------------------
-- Colour picker
---------------------------------------------------------------------------
local activeSwatches = {} -- [styleTable] = texture currently showing it

local function UpdateSwatch(tbl)
	local sw = activeSwatches[tbl]
	if sw then sw:SetColorTexture(tbl.r, tbl.g, tbl.b, tbl.a) end
end

local function SetColor(tbl, r, g, b, a)
	tbl.r, tbl.g, tbl.b, tbl.a = r, g, b, a
	ApplyAll()
	UpdateSwatch(tbl)
end

local function OpenColorPicker(tbl)
	local prev = { tbl.r, tbl.g, tbl.b, tbl.a }
	local picker = ColorPickerFrame
	picker:SetFrameStrata("FULLSCREEN_DIALOG")
	if picker.SetupColorPickerAndShow then -- modern picker
		local function cb()
			local r, g, b = picker:GetColorRGB()
			SetColor(tbl, r, g, b, picker:GetColorAlpha())
		end
		picker:SetupColorPickerAndShow({
			r = tbl.r, g = tbl.g, b = tbl.b, opacity = tbl.a, hasOpacity = true,
			swatchFunc = cb,
			opacityFunc = cb,
			cancelFunc = function() SetColor(tbl, unpack(prev)) end,
		})
	else -- older picker: "opacity" is transparency (1 - alpha)
		picker:Hide()
		local function cb()
			local r, g, b = picker:GetColorRGB()
			SetColor(tbl, r, g, b, 1 - OpacitySliderFrame:GetValue())
		end
		picker.func, picker.opacityFunc = cb, cb
		picker.cancelFunc = function() SetColor(tbl, unpack(prev)) end
		picker.hasOpacity = true
		picker.opacity = 1 - tbl.a
		picker.previousValues = prev
		picker:SetColorRGB(tbl.r, tbl.g, tbl.b)
		picker:Show()
	end
end

---------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------
local category
local CreateStorePage

-- Adds size / alignment / colour controls to a page, stored in `tbl`.
-- `parentInit` + `isEnabled` grey the controls out until the bar's "custom" box is ticked.
local function AddStyleControls(page, tbl, varPrefix, parentInit, isEnabled)
	local registered = {} -- [key] = setting, so values can be pushed back into the controls
	local function Link(init)
		if parentInit and init.SetParentInitializer then
			init:SetParentInitializer(parentInit, isEnabled)
		end
		Settings.RegisterInitializer(page, init)
	end

	-- Size
	local scale = Settings.RegisterAddOnSetting(page, varPrefix .. "scale", "scale", tbl,
		Settings.VarType.Number, "Reagent count size", DEFAULTS.scale)
	scale:SetValueChangedCallback(function() ApplyAll() end)
	registered.scale = scale
	local options = Settings.CreateSliderOptions(50, 300, 5)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return value .. "%"
	end)
	Link(Settings.CreateSliderInitializer(scale, options,
		"Scales the item/reagent count number shown on action bar buttons."))

	-- Alignment
	local function Dropdown(key, label, choices, tooltip)
		local st = Settings.RegisterAddOnSetting(page, varPrefix .. key, key, tbl,
			Settings.VarType.String, label, DEFAULTS[key])
		st:SetValueChangedCallback(function() ApplyAll() end)
		registered[key] = st
		local function GetOptions()
			local c = Settings.CreateControlTextContainer()
			for _, ch in ipairs(choices) do c:Add(ch[1], ch[2]) end
			return c:GetData()
		end
		Link(Settings.CreateDropdownInitializer(st, GetOptions, tooltip))
	end
	Dropdown("h", "Horizontal alignment",
		{ { "LEFT", "Left" }, { "CENTER", "Centre" }, { "RIGHT", "Right" } },
		"Where the count sits across the button.")
	Dropdown("v", "Vertical alignment",
		{ { "TOP", "Top" }, { "MIDDLE", "Middle" }, { "BOTTOM", "Bottom" } },
		"Where the count sits up/down the button.")

	-- Colour
	if CreateSettingsButtonInitializer then
		local colorInit = CreateSettingsButtonInitializer("Reagent count colour", "Choose colour",
			function() OpenColorPicker(tbl) end, "Pick the colour and opacity of the count text.", true)
		local origInit = colorInit.InitFrame
		colorInit.InitFrame = function(self, frame)
			origInit(self, frame)
			local button = frame.Button
			if not button then return end
			if not frame.SRTSwatch then
				local sw = frame:CreateTexture(nil, "OVERLAY")
				sw:SetSize(20, 20)
				sw:SetPoint("LEFT", button, "RIGHT", 8, 0)
				local border = frame:CreateTexture(nil, "ARTWORK")
				border:SetColorTexture(0, 0, 0, 1)
				border:SetPoint("TOPLEFT", sw, -1, 1)
				border:SetPoint("BOTTOMRIGHT", sw, 1, -1)
				sw.border = border
				frame.SRTSwatch = sw
				frame:HookScript("OnHide", function()
					sw:Hide(); border:Hide()
					for t, s in pairs(activeSwatches) do
						if s == sw then activeSwatches[t] = nil end
					end
				end)
			end
			activeSwatches[tbl] = frame.SRTSwatch
			UpdateSwatch(tbl)
			frame.SRTSwatch:Show(); frame.SRTSwatch.border:Show()
		end
		Link(colorInit)

		Link(CreateSettingsButtonInitializer("", "Reset colour", function()
			SetColor(tbl, DEFAULTS.r, DEFAULTS.g, DEFAULTS.b, DEFAULTS.a)
		end, "Back to the default white.", true))
	end
	return registered
end

-- Writes style values into a bar and refreshes its controls.
local function SetBarStyle(tbl, registered, source)
	for _, k in ipairs(STYLE_KEYS) do tbl[k] = source[k] end
	for k, setting in pairs(registered) do
		setting:SetValue(source[k])
	end
	ApplyAll()
	UpdateSwatch(tbl)
end

-- Canvas page listing every stored resource with a checkbox.
CreateStorePage = function()
	local frame = CreateFrame("Frame")
	frame:Hide()

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Resource Store")

	-- Clear store (with confirmation)
	StaticPopupDialogs["SCALECOUNTS_CLEAR_STORE"] = {
		text = "Clear the Resource Store?\n\nThis removes every entry and the blacklist, so all counts show again. Items still on your bars will be re-added.",
		button1 = YES,
		button2 = NO,
		OnAccept = function()
			wipe(db.store)
			wipe(db.blacklist)
			ApplyAll()
			RefreshStoreUI()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clear:SetSize(110, 22)
	clear:SetPoint("TOPRIGHT", -16, -14)
	clear:SetText("Clear store")
	clear:SetScript("OnClick", function()
		StaticPopup_Show("SCALECOUNTS_CLEAR_STORE")
	end)

	-- Select all / Deselect all
	local function SetAll(show)
		for key in pairs(db.store) do
			db.blacklist[key] = (not show) or nil
		end
		ApplyAll()
		RefreshStoreUI()
	end
	local deselectAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	deselectAll:SetSize(110, 22)
	deselectAll:SetPoint("RIGHT", clear, "LEFT", -6, 0)
	deselectAll:SetText("Deselect all")
	deselectAll:SetScript("OnClick", function() SetAll(false) end)

	local selectAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	selectAll:SetSize(110, 22)
	selectAll:SetPoint("RIGHT", deselectAll, "LEFT", -6, 0)
	selectAll:SetText("Select all")
	selectAll:SetScript("OnClick", function() SetAll(true) end)

	local help = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	help:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
	help:SetJustifyH("LEFT")
	help:SetText("Reagent spells and consumables seen on your action bars are added here automatically.\n"
		.. "Ticked: the button shows its count (with your size/colour settings).\n"
		.. "Unticked: blacklisted - the button shows no count. Anything not listed here works as normal.")

	local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	-- "Always add count to new items" toggle
	local auto = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	auto:SetSize(24, 24)
	auto:SetPoint("TOPLEFT", help, "BOTTOMLEFT", -2, -8)
	local autoLabel = auto:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	autoLabel:SetPoint("LEFT", auto, "RIGHT", 4, 0)
	autoLabel:SetText("Always add count to new items")
	auto:SetScript("OnClick", function(self) db.autoShowNew = self:GetChecked() and true or false end)
	auto:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Ticked: new spells/items added to the store are ticked (count shown).\n"
			.. "Unticked: new entries are added unticked (count hidden).", nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	auto:SetScript("OnLeave", GameTooltip_Hide)

	scroll:SetPoint("TOPLEFT", auto, "BOTTOMLEFT", 2, -8)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 16)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)

	local rows, headers = {}, {}
	local ROW_H = 26

	local function GetHeader(i)
		local hdr = headers[i]
		if not hdr then
			hdr = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			headers[i] = hdr
		end
		return hdr
	end

	local function GetRow(i)
		local row = rows[i]
		if row then return row end
		row = CreateFrame("Frame", nil, content)
		row:SetHeight(ROW_H)
		row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.check:SetSize(24, 24)
		row.check:SetPoint("LEFT", 0, 0)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(20, 20)
		row.icon:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
		row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.forget = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.forget:SetSize(70, 20)
		row.forget:SetPoint("RIGHT", -4, 0)
		row.forget:SetText("Forget")
		row.check:SetScript("OnClick", function(self)
			db.blacklist[row.key] = (not self:GetChecked()) or nil
			ApplyAll()
		end)
		row.forget:SetScript("OnClick", function()
			db.store[row.key] = nil
			db.blacklist[row.key] = nil
			ApplyAll()
			RefreshStoreUI()
		end)
		row.forget:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Remove from the store (it comes back if it's still on a bar).", nil, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		row.forget:SetScript("OnLeave", GameTooltip_Hide)
		rows[i] = row
		return row
	end

	local empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	empty:SetPoint("TOPLEFT", 4, -4)
	empty:SetText("Nothing yet - put a reagent spell or consumable on an action bar.")

	RefreshStoreUI = function()
		if not frame:IsShown() then return end
		local groups = {
			{ kind = "spell", title = "Spells that need reagents", list = {} },
			{ kind = "item",  title = "Consumables", list = {} },
		}
		for key, e in pairs(db.store) do
			for _, g in ipairs(groups) do
				if g.kind == e.kind then g.list[#g.list + 1] = key end
			end
		end
		for _, r in ipairs(rows) do r:Hide() end
		for _, h in ipairs(headers) do h:Hide() end

		local y, rowIndex, hdrIndex, total = -4, 0, 0, 0
		for _, g in ipairs(groups) do
			if #g.list > 0 then
				table.sort(g.list, function(a, b) return (db.store[a].name or a) < (db.store[b].name or b) end)
				hdrIndex = hdrIndex + 1
				local hdr = GetHeader(hdrIndex)
				hdr:SetPoint("TOPLEFT", 4, y)
				hdr:SetText(g.title)
				hdr:Show()
				y = y - 22
				for _, key in ipairs(g.list) do
					local e = db.store[key]
					rowIndex = rowIndex + 1
					total = total + 1
					local row = GetRow(rowIndex)
					row.key = key
					row:ClearAllPoints()
					row:SetPoint("TOPLEFT", 4, y)
					row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
					row.icon:SetTexture(e.icon or 134400)
					row.label:SetText(e.name or key)
					row.check:SetChecked(not db.blacklist[key])
					row:Show()
					y = y - ROW_H
				end
				y = y - 8
			end
		end
		empty:SetShown(total == 0)
		content:SetHeight(math.max(1, -y))
	end

	frame:SetScript("OnShow", function()
		auto:SetChecked(db.autoShowNew)
		ApplyAll() -- pick up anything new on the bars
		RefreshStoreUI()
	end)
	return frame
end

local function RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
	category = Settings.RegisterVerticalLayoutCategory(TITLE)

	-- Main page: applies to all bars
	AddStyleControls(category, db, "ScaleCounts_")

	-- One sub-page per action bar
	for _, bar in ipairs(BARS) do
		if not bar.check or _G[bar.check] then
			local tbl = db.bars[bar.key]
			local page = Settings.RegisterVerticalLayoutSubcategory(category, bar.name)
			local prefix = "ScaleCounts_" .. bar.key .. "_"

			local custom = Settings.RegisterAddOnSetting(page, prefix .. "custom", "custom", tbl,
				Settings.VarType.Boolean, "Use custom settings for this bar", false)
			custom:SetValueChangedCallback(function() ApplyAll() end)
			local customInit = Settings.CreateCheckboxInitializer(custom, nil,
				"Off: this bar uses the main Scale Counts settings.\nOn: this bar uses the settings below.")
			Settings.RegisterInitializer(page, customInit)

			local registered = AddStyleControls(page, tbl, prefix, customInit, function() return tbl.custom end)

			if CreateSettingsButtonInitializer then
				Settings.RegisterInitializer(page, CreateSettingsButtonInitializer("Copy settings", "Copy from All bars",
					function() SetBarStyle(tbl, registered, db) end,
					"Copies the size, alignment and colour from the main Scale Counts page to this bar.", true))
				Settings.RegisterInitializer(page, CreateSettingsButtonInitializer("Reset settings", "Reset this bar",
					function() SetBarStyle(tbl, registered, DEFAULTS) end,
					"Resets this bar's size, alignment and colour to the addon defaults (150%, bottom-right, white).", true))
			end
		end
	end

	-- Resource store page
	local storeFrame = CreateStorePage()
	Settings.RegisterCanvasLayoutSubcategory(category, storeFrame, "Resource Store")

	Settings.RegisterAddOnCategory(category)
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
local function InitDB()
	ScaleCountsDB = ScaleCountsDB or {}
	db = ScaleCountsDB
	for k, v in pairs(DEFAULTS) do
		if db[k] == nil then db[k] = v end
	end
	db.bars = db.bars or {}
	db.store = db.store or {}         -- [key] = { kind, name, icon }
	db.blacklist = db.blacklist or {} -- [key] = true
	if db.autoShowNew == nil then db.autoShowNew = true end
	for _, bar in ipairs(BARS) do
		local t = db.bars[bar.key]
		if not t then
			-- new bar settings start as a copy of the global settings
			t = { custom = false }
			for _, k in ipairs(STYLE_KEYS) do t[k] = db[k] end
			db.bars[bar.key] = t
		end
		for k, v in pairs(DEFAULTS) do
			if t[k] == nil then t[k] = v end
		end
		if t.custom == nil then t.custom = false end
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
f:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
f:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		InitDB()
		RegisterSettings()
	elseif event == "ACTIONBAR_SLOT_CHANGED" then
		C_Timer.After(0, ApplyAll)
	else
		C_Timer.After(0.5, ApplyAll) -- let bar addons create their buttons first
	end
end)

SLASH_SCALECOUNTS1 = "/scalecounts"
SLASH_SCALECOUNTS2 = "/srt"
SlashCmdList.SCALECOUNTS = function(msg)
	local n = tonumber(msg)
	if n then
		db.scale = math.max(50, math.min(300, n))
		ApplyAll()
		print(TITLE .. ": size set to " .. db.scale .. "% (all bars)")
	elseif category then
		Settings.OpenToCategory(category:GetID())
	end
end
