local _, ns = ...

local mainCategory

---------------------------------------------------------------------------
-- Summary page: this character's loot by period, zone, profession, source
---------------------------------------------------------------------------
local function CreateSummaryPage()
	local frame = CreateFrame("Frame")
	frame:Hide()

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Loot Audit")

	local open = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	open:SetSize(150, 22)
	open:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -12)
	open:SetText("Open loot browser")
	open:SetScript("OnClick", function() ns.ToggleBrowser() end)

	local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 16)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)

	local COLS = { 0, 260, 360, 520 }
	local rows = {}
	local function GetRow(i)
		local row = rows[i]
		if row then return row end
		row = {}
		for c in ipairs(COLS) do
			local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			fs:SetJustifyH(c == 1 and "LEFT" or "RIGHT")
			fs:SetWidth(c == 1 and 250 or (c == 2 and 80 or 150))
			fs:SetWordWrap(false)
			row[c] = fs
		end
		rows[i] = row
		return row
	end

	local function Refresh()
		local char = ns.char
		if not char then return end
		ns.ResetInfo()
		for _, row in ipairs(rows) do for _, fs in ipairs(row) do fs:Hide() end end

		local lines = {}
		local function Line(font, ...) lines[#lines + 1] = { font = font, ... } end
		local function Blank() lines[#lines + 1] = { blank = true } end
		title:SetText("Loot Audit - " .. ns.ClassColored(char.name or "?", char.class))

		local periods = {}
		for i, p in ipairs(ns.PERIODS) do periods[i] = { p[2], ns.PeriodStart(p[1]), 0, 0, 0 } end
		local byZone, byTag, bySource, byItem = {}, {}, {}, {}
		local function Add(tbl, key, n, a, v, link)
			local t = tbl[key]
			if not t then t = { key = key, count = 0, ah = 0, vendor = 0, link = link }; tbl[key] = t end
			t.count, t.ah, t.vendor = t.count + n, t.ah + a, t.vendor + v
		end

		for _, e in ipairs(char.entries) do
			local i = ns.Info(e[2])
			local n = e[3]
			local a, v = (i.ah or 0) * n, i.vendor * n
			for _, p in ipairs(periods) do
				if e[1] >= p[2] then p[3], p[4], p[5] = p[3] + n, p[4] + a, p[5] + v end
			end
			Add(byZone, e[6] ~= "" and e[6] or "Unknown", n, a, v)
			Add(bySource, e[4], n, a, v)
			for _, t in ipairs((ns.EntryTags(e))) do Add(byTag, t, n, a, v) end
			Add(byItem, ns.ItemID(e[2]) or e[2], n, a, v, e[2])
		end

		local function Sorted(tbl, n)
			local list = {}
			for _, t in pairs(tbl) do list[#list + 1] = t end
			table.sort(list, function(a, b)
				if a.ah ~= b.ah then return a.ah > b.ah end
				if a.vendor ~= b.vendor then return a.vendor > b.vendor end
				return a.count > b.count
			end)
			if n then for k = #list, n + 1, -1 do list[k] = nil end end
			return list
		end

		Line("GameFontNormal", "Period", "Items", "AH value", "Vendor value")
		for _, p in ipairs(periods) do
			Line("GameFontHighlight", "  " .. p[1], ns.Number(p[3]), ns.Money(p[4]), ns.Money(p[5]))
		end
		Blank()

		Line("GameFontNormal", "By zone (top 15)", "Items", "AH value", "Vendor value")
		for _, t in ipairs(Sorted(byZone, 15)) do
			Line("GameFontHighlight", "  " .. t.key, ns.Number(t.count), ns.Money(t.ah), ns.Money(t.vendor))
		end
		if not next(byZone) then Line("GameFontDisable", "  Nothing looted yet") end
		Blank()

		Line("GameFontNormal", "By profession", "Items", "AH value", "Vendor value")
		local any = false
		for _, tag in ipairs(ns.TAGS) do
			local t = byTag[tag.id]
			if tag.prof and t then
				any = true
				Line("GameFontHighlight", "  " .. tag.label, ns.Number(t.count), ns.Money(t.ah), ns.Money(t.vendor))
			end
		end
		if not any then Line("GameFontDisable", "  No profession materials yet") end
		Blank()

		Line("GameFontNormal", "Other tags", "Items", "AH value", "Vendor value")
		for _, tag in ipairs(ns.TAGS) do
			local t = byTag[tag.id]
			if not tag.prof and t then
				Line("GameFontHighlight", "  " .. tag.label, ns.Number(t.count), ns.Money(t.ah), ns.Money(t.vendor))
			end
		end
		Blank()

		Line("GameFontNormal", "By source", "Items", "AH value", "Vendor value")
		for _, t in ipairs(Sorted(bySource)) do
			Line("GameFontHighlight", "  " .. ns.SourceLabel(t.key), ns.Number(t.count), ns.Money(t.ah), ns.Money(t.vendor))
		end
		Blank()

		Line("GameFontNormal", "Most valuable items on the AH (top 15)", "Qty", "AH value", "Vendor value")
		for _, t in ipairs(Sorted(byItem, 15)) do
			Line("GameFontHighlight", "  " .. t.link, ns.Number(t.count), ns.Money(t.ah), ns.Money(t.vendor))
		end
		Line("GameFontDisable", ("  %s loots recorded for this character"):format(ns.Number(#char.entries)))

		local y, n = -4, 0
		for _, l in ipairs(lines) do
			if l.blank then
				y = y - 10
			else
				n = n + 1
				local row = GetRow(n)
				for c = 1, #COLS do
					local fs = row[c]
					if l[c] then
						fs:SetFontObject(l.font)
						fs:ClearAllPoints()
						fs:SetPoint("TOPLEFT", content, "TOPLEFT", COLS[c], y)
						fs:SetText(l[c])
						fs:Show()
					end
				end
				y = y - 20
			end
		end
		content:SetHeight(-y + 10)
	end

	frame:SetScript("OnShow", Refresh)
	ns.pages[frame] = Refresh
	return frame
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
StaticPopupDialogs["JUKESLOOT_DELETE_HISTORY"] = {
	text = "Delete ALL Loot Audit history for this character?\n\nThis cannot be undone.",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		if ns.char then
			wipe(ns.char.entries)
			ns.OnDataChanged()
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function ns.RegisterSettings()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	local db = ns.db

	mainCategory = Settings.RegisterCanvasLayoutCategory(CreateSummaryPage(), "Loot Audit")

	local opt = Settings.RegisterVerticalLayoutSubcategory(mainCategory, "Options")
	local function Checkbox(key, label, tooltip)
		local s = Settings.RegisterAddOnSetting(opt, "JukesLoot_" .. key, key, db.options,
			Settings.VarType.Boolean, label, ns.OPTION_DEFAULTS[key])
		Settings.RegisterInitializer(opt, Settings.CreateCheckboxInitializer(s, nil, tooltip))
		return s
	end
	Checkbox("chat", "Print each loot to chat",
		"Adds a chat line with the item, how you got it and where, every time something is recorded.")
	Checkbox("recordCrafted", "Record crafted items",
		"Also records items you make with a profession, as source \"Crafted\".")
	Checkbox("recordPurchases", "Record vendor purchases",
		"Also records items bought from a vendor, as source \"Vendor purchase\".")
	Checkbox("useAuctionator", "Use Auctionator prices",
		"Shows what your loot sells for on the auction house, from Auctionator's last scan. Scan the AH with Auctionator to fill in prices.")

	local s = Settings.RegisterAddOnSetting(opt, "JukesLoot_valuableSilver", "valuableSilver", db.options,
		Settings.VarType.Number, "\"Valuable\" tag from", ns.OPTION_DEFAULTS.valuableSilver)
	local o = Settings.CreateSliderOptions(5, 2000, 5)
	o:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
		return GetMoneyString(math.floor(v) * 100, true)
	end)
	Settings.CreateSlider(opt, s, o, "Items worth at least this much each are tagged Valuable.")
	if s.SetValueChangedCallback then s:SetValueChangedCallback(function() ns.ScheduleRefresh(0.2) end) end
	ns.AddClockSetting(opt, "JukesLoot_clock", function() ns.ScheduleRefresh(0.2) end)

	if CreateSettingsButtonInitializer then
		Settings.RegisterInitializer(opt, CreateSettingsButtonInitializer("Loot browser",
			"Open the loot browser", function() ns.ToggleBrowser() end,
			"Opens a movable, resizable window with all your loot, grouped by zone, tag or source. Also: /jl", true))
		Settings.RegisterInitializer(opt, CreateSettingsButtonInitializer("Delete history",
			"Delete this character's history", function() StaticPopup_Show("JUKESLOOT_DELETE_HISTORY") end,
			"Permanently removes every recorded loot for the character you're playing.", true))
	end

	Settings.RegisterAddOnCategory(mainCategory)
end

function ns.OpenSettings()
	if mainCategory then Settings.OpenToCategory(mainCategory:GetID()) end
end
