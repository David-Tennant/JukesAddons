local _, ns = ...

---------------------------------------------------------------------------
-- Shared helpers (also used by Settings.lua)
---------------------------------------------------------------------------
ns.pages = {} -- frame -> refresh function, for frames that show data

function ns.Money(copper)
	copper = math.floor(copper or 0)
	if copper <= 0 then return "|cffaaaaaa-|r" end
	return GetMoneyString(copper, true)
end

function ns.ClassColored(name, class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c and c.colorStr then return "|c" .. c.colorStr .. name .. "|r" end
	return name
end

function ns.Number(n)
	local s = tostring(math.floor(n or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

ns.OnDataChanged = function()
	for frame, refresh in pairs(ns.pages) do
		if frame:IsVisible() then refresh() end
	end
end

-- Per-refresh cache of what we know about each link
local info = {}
function ns.ResetInfo() wipe(info) end

function ns.Info(link)
	local i = info[link]
	if i then return i end
	local p = ns.ItemPrices(link)
	local quality = ns.ItemQuality(link)
	i = {
		ah = p.ah, ahAge = p.ahAge, vendor = p.vendor, bound = p.bound,
		unit = p.ah or p.vendor, isAH = p.ah ~= nil, quality = quality,
		name = link:match("%[(.-)%]") or "?",
		itemTags = ns.ItemTags(link),
	}
	info[link] = i
	return i
end

-- All tags of an entry: from the item, its source, its quality and its price
function ns.EntryTags(e)
	local i = ns.Info(e[2])
	local tags, seen = {}, {}
	local function T(t) if not seen[t] then seen[t] = true; tags[#tags + 1] = t end end
	for _, t in ipairs(i.itemTags) do T(t) end
	for _, t in ipairs(ns.SOURCE_TAGS[e[4]] or {}) do T(t) end
	if i.quality == 0 then T("junk") end
	if i.quality >= 3 then T("rare") end
	if i.quality >= 4 then T("epic") end
	if i.unit >= (ns.db.options.valuableSilver or 100) * 100 then T("valuable") end
	return tags, seen
end

---------------------------------------------------------------------------
-- Time periods
---------------------------------------------------------------------------
ns.PERIODS = {
	{ "today", "Today" }, { "7", "Last 7 days" }, { "30", "Last 30 days" }, { "all", "All time" },
}

function ns.PeriodStart(period)
	if period == "today" then return ns.StartOfToday() end
	if period == "7" then return time() - 7 * 86400 end
	if period == "30" then return time() - 30 * 86400 end
	return 0
end

-- The browser also offers a custom From / To range (not used by the summary page)
local BROWSER_PERIODS = {}
for i, p in ipairs(ns.PERIODS) do BROWSER_PERIODS[i] = p end
BROWSER_PERIODS[#BROWSER_PERIODS + 1] = { "custom", "Custom range" }

-- "YYYY-MM-DD" -> date table, "HH:MM" -> hour, min
local function ParseDay(text)
	local y, m, d = (text or ""):match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if not y or m < 1 or m > 12 or d < 1 or d > 31 then return end
	return { year = y, month = m, day = d, hour = 12, min = 0, sec = 0 }
end

local function ParseClock(text)
	local H, M = (text or ""):match("^%s*(%d%d?):(%d%d)%s*$")
	H, M = tonumber(H), tonumber(M)
	if not H or H > 23 or M > 59 then return end
	return H, M
end

-- From / To rows, each a date box and a time box with step arrows.
-- store: table the four texts are saved in (fromDay, fromTime, toDay, toTime).
-- getBounds(): earliest and latest loot timestamps, used to fill the boxes.
local function CreateRangeSelector(parent, store, onChange, getBounds)
	local block = CreateFrame("Frame", nil, parent)
	block:SetSize(560, 52)
	local sides = {}
	local quiet = false -- true while filling the boxes from code

	-- byUser: typed / arrows / buttons (the caller switches to "Custom range")
	local function Changed(byUser)
		if quiet then return end
		for _, side in ipairs(sides) do
			store[side.key .. "Day"] = side.day:GetText()
			store[side.key .. "Time"] = side.clock:GetText()
		end
		onChange(byUser)
	end

	local function Arrows(anchor, onStep)
		local prev = CreateFrame("Button", nil, block)
		prev:SetSize(20, 20)
		prev:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
		prev:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
		prev:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
		prev:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		prev:SetScript("OnClick", function() onStep(-1) end)
		local nextB = CreateFrame("Button", nil, block)
		nextB:SetSize(20, 20)
		nextB:SetPoint("LEFT", prev, "RIGHT", 0, 0)
		nextB:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
		nextB:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
		nextB:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		nextB:SetScript("OnClick", function() onStep(1) end)
		return nextB
	end

	local function Box(width, anchor, valid, tipTitle, tipText)
		local eb = CreateFrame("EditBox", nil, block, "InputBoxTemplate")
		eb:SetSize(width, 20)
		eb:SetPoint("LEFT", anchor, "RIGHT", anchor.isLabel and 10 or 14, 0)
		eb:SetAutoFocus(false)
		eb:SetMaxLetters(10)
		eb:SetScript("OnEnterPressed", eb.ClearFocus)
		eb:SetScript("OnEscapePressed", eb.ClearFocus)
		eb:SetScript("OnTextChanged", function(self)
			local ok = valid(self:GetText())
			self:SetTextColor(1, ok and 1 or 0.3, ok and 1 or 0.3)
			Changed(true)
		end)
		eb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(tipTitle)
			GameTooltip:AddLine(tipText, 1, 1, 1)
			GameTooltip:Show()
		end)
		eb:SetScript("OnLeave", GameTooltip_Hide)
		return eb
	end

	local function Side(key, label, y, isEnd)
		local fs = block:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		fs:SetPoint("TOPLEFT", block, "TOPLEFT", 0, y - 4)
		fs:SetWidth(40)
		fs:SetJustifyH("LEFT")
		fs:SetText(label)
		fs.isLabel = true

		local side = { key = key }
		side.day = Box(84, fs, function(t) return ParseDay(t) ~= nil end,
			label .. " date", "YYYY-MM-DD   (arrows: one day)")
		local after = Arrows(side.day, function(n)
			local t = ParseDay(side.day:GetText())
			if not t then return end
			t.day = t.day + n
			side.day:SetText(ns.Date("%Y-%m-%d", ns.Time(t)))
		end)
		side.clock = Box(46, after, function(t) return ParseClock(t) ~= nil end,
			label .. " time", "HH:MM, 24-hour   (arrows: one hour)\nLeave empty for " .. (isEnd and "the end" or "the start") .. " of the day.")
		side.lastArrow = Arrows(side.clock, function(n)
			local H, M = ParseClock(side.clock:GetText())
			if not H then return end
			side.clock:SetText(("%02d:%02d"):format((H + n) % 24, M))
		end)

		-- timestamp, or nil when the date isn't valid (= no limit on this side)
		function side.Get()
			local t = ParseDay(side.day:GetText())
			if not t then return end
			local H, M = ParseClock(side.clock:GetText())
			if not H then H, M = isEnd and 23 or 0, isEnd and 59 or 0 end
			t.hour, t.min, t.sec = H, M, isEnd and 59 or 0
			return ns.Time(t)
		end
		function side.SetTexts(dayText, clockText)
			side.day:SetText(dayText or "")
			side.clock:SetText(clockText or "")
		end
		sides[#sides + 1] = side
		return side
	end

	local fromSide = Side("from", "From", 0, false)
	local toSide = Side("to", "To", -28, true)

	local function Fill(fn, byUser)
		quiet = true
		fn()
		quiet = false
		Changed(byUser)
	end

	local function SetBoth(first, last)
		fromSide.SetTexts(ns.Date("%Y-%m-%d", first), ns.Date("%H:%M", first))
		toSide.SetTexts(ns.Date("%Y-%m-%d", last), ns.Date("%H:%M", last))
	end

	-- Fill with the first and last loot in scope
	function block.FillBounds(byUser)
		local first, last = getBounds()
		first, last = first or ns.StartOfToday(), last or time()
		Fill(function() SetBoth(first, last) end, byUser)
	end

	-- Show a preset period's span in the boxes without saving it or notifying
	function block.ShowSpan(first, last)
		quiet = true
		SetBoth(first, last)
		quiet = false
	end

	-- Put the saved texts back, or fill from the loot if nothing is saved yet
	function block.Load()
		if not store.fromDay and not store.toDay then return block.FillBounds() end
		Fill(function()
			fromSide.SetTexts(store.fromDay, store.fromTime)
			toSide.SetTexts(store.toDay, store.toTime)
		end)
	end

	local fullBtn = CreateFrame("Button", nil, block, "UIPanelButtonTemplate")
	fullBtn:SetSize(130, 22)
	fullBtn:SetPoint("LEFT", fromSide.lastArrow, "RIGHT", 16, 0)
	fullBtn:SetText("First to last loot")
	fullBtn:SetScript("OnClick", function() block.FillBounds(true) end)
	fullBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Full range")
		GameTooltip:AddLine("Set From and To to the first and last loot of the characters shown.", 1, 1, 1)
		GameTooltip:Show()
	end)
	fullBtn:SetScript("OnLeave", GameTooltip_Hide)

	local nowBtn = CreateFrame("Button", nil, block, "UIPanelButtonTemplate")
	nowBtn:SetSize(130, 22)
	nowBtn:SetPoint("LEFT", toSide.lastArrow, "RIGHT", 16, 0)
	nowBtn:SetText("To now")
	nowBtn:SetScript("OnClick", function()
		local now = time()
		toSide.SetTexts(ns.Date("%Y-%m-%d", now), ns.Date("%H:%M", now))
	end)

	function block.GetRange()
		return fromSide.Get() or 0, toSide.Get() or math.huge
	end
	block:Hide()
	return block
end

---------------------------------------------------------------------------
-- Loot browser window
---------------------------------------------------------------------------
local browser

local GROUPS = {
	{ "none", "No grouping" }, { "item", "Totals per item" }, { "zone", "Group by zone" },
	{ "subzone", "Group by subzone" }, { "tag", "Group by tag" }, { "source", "Group by source" },
}
local SORTS = { { "ah", "Sort by AH total" }, { "value", "Sort by value (AH, else vendor)" }, { "vendor", "Sort by vendor total" }, { "count", "Sort by quantity" }, { "name", "Sort by name" }, { "recent", "Sort by most recent" } }

local function CreateBrowser()
	local saved = ns.db.browser or {}
	ns.db.browser = saved
	saved.filters = saved.filters or {}
	local F = saved.filters
	F.chars = F.chars or "me"
	F.period = F.period or "all"
	F.zone = F.zone or "all"
	F.tag = F.tag or "all"
	-- sources: set of source ids to show; empty = all sources
	F.sources = F.sources or {}
	if F.source and F.source ~= "all" then F.sources[F.source] = true end -- older single choice
	F.source = nil
	F.group = "none" -- the window always opens ungrouped
	F.sort = F.sort or "ah"
	if F.hideJunk == nil then F.hideJunk = false end
	local search = ""
	local expanded = {}

	local f = CreateFrame("Frame", "JukesLootBrowser", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(math.max(saved.w or 1060, 960), saved.h or 560)
	if saved.point then
		f:SetPoint(saved.point, UIParent, saved.point, saved.x or 0, saved.y or 0)
	else
		f:SetPoint("CENTER")
	end
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetResizeBounds then f:SetResizeBounds(960, 300) else f:SetMinResize(960, 300) end
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:Hide()
	tinsert(UISpecialFrames, "JukesLootBrowser")

	local function SavePos()
		local point, _, _, x, y = f:GetPoint()
		saved.point, saved.x, saved.y = point, x, y
		saved.w, saved.h = f:GetSize()
	end
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function() f:StopMovingOrSizing(); SavePos() end)

	local titleText = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	if not f.TitleText then titleText:SetPoint("TOP", 0, -5) end

	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -4, 4)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); SavePos() end)

	local Refresh

	-- Filters ---------------------------------------------------------------
	local function Dropdown(width, choices, key)
		local dd = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
		dd:SetWidth(width)
		dd:SetupMenu(function(_, root)
			if root.SetScrollMode then root:SetScrollMode(420) end
			for _, ch in ipairs(choices()) do
				root:CreateRadio(ch[2], function() return F[key] == ch[1] end, function()
					F[key] = ch[1]
					Refresh()
				end)
			end
		end)
		return dd
	end

	local function CharsInScope()
		local list = {}
		for key, c in pairs(ns.db.chars) do
			if F.chars == "all" or (F.chars == "me" and c == ns.char) or F.chars == key then
				list[#list + 1] = c
			end
		end
		return list
	end

	local charDD = Dropdown(150, function()
		local list = { { "me", "This character" }, { "all", "All characters" } }
		local keys = {}
		for key in pairs(ns.db.chars) do keys[#keys + 1] = key end
		table.sort(keys)
		for _, key in ipairs(keys) do
			local c = ns.db.chars[key]
			list[#list + 1] = { key, ns.ClassColored(c.name or key, c.class) .. " |cff888888(" .. (c.ruleset or "?") .. ")|r" }
		end
		return list
	end, "chars")
	charDD:SetPoint("TOPLEFT", 14, -32)

	local periodDD = Dropdown(120, function() return BROWSER_PERIODS end, "period")
	periodDD:SetPoint("LEFT", charDD, "RIGHT", 6, 0)

	local zoneDD = Dropdown(170, function()
		local list, seen = { { "all", "All zones" } }, {}
		for _, c in ipairs(CharsInScope()) do
			for _, e in ipairs(c.entries) do
				local z = e[6] ~= "" and e[6] or "Unknown"
				if not seen[z] then seen[z] = true; list[#list + 1] = { z, z } end
			end
		end
		table.sort(list, function(a, b)
			if a[1] == "all" then return true elseif b[1] == "all" then return false end
			return a[2] < b[2]
		end)
		return list
	end, "zone")
	zoneDD:SetPoint("LEFT", periodDD, "RIGHT", 6, 0)

	local tagDD = Dropdown(150, function()
		local list = { { "all", "All tags" } }
		for _, t in ipairs(ns.TAGS) do list[#list + 1] = { t.id, t.prof and t.label or ("|cffffd100" .. t.label .. "|r") } end
		return list
	end, "tag")
	tagDD:SetPoint("LEFT", zoneDD, "RIGHT", 6, 0)

	-- Sources: tick any number; none ticked = all sources
	local sourceDD = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
	sourceDD:SetWidth(150)
	local function SourceText()
		local names = {}
		for _, s in ipairs(ns.SOURCES) do
			if F.sources[s.id] then names[#names + 1] = s.label end
		end
		if #names == 0 then return "All sources" end
		if #names == 1 then return names[1] end
		return #names .. " sources"
	end
	local function UpdateSourceText()
		if sourceDD.OverrideText then sourceDD:OverrideText(SourceText()) end
	end
	sourceDD:SetupMenu(function(_, root)
		if root.SetScrollMode then root:SetScrollMode(420) end
		root:CreateRadio("All sources", function() return next(F.sources) == nil end, function()
			wipe(F.sources)
			UpdateSourceText()
			Refresh()
		end)
		root:CreateDivider()
		for _, src in ipairs(ns.SOURCES) do
			root:CreateCheckbox(src.label, function() return F.sources[src.id] == true end, function()
				F.sources[src.id] = (not F.sources[src.id]) or nil
				UpdateSourceText()
				Refresh()
			end)
		end
	end)
	if sourceDD.SetSelectionTranslator then sourceDD:SetSelectionTranslator(SourceText) end
	UpdateSourceText()
	sourceDD:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Sources")
		GameTooltip:AddLine("Tick as many sources as you like. None ticked shows all.", 1, 1, 1)
		if next(F.sources) then
			for _, src in ipairs(ns.SOURCES) do
				if F.sources[src.id] then GameTooltip:AddLine("  " .. src.label, 0.3, 1, 0.3) end
			end
		end
		GameTooltip:Show()
	end)
	sourceDD:HookScript("OnLeave", GameTooltip_Hide)
	sourceDD:SetPoint("LEFT", tagDD, "RIGHT", 6, 0)

	local searchBox = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
	searchBox:SetSize(190, 20)
	searchBox:SetPoint("TOPLEFT", charDD, "BOTTOMLEFT", 6, -8)
	searchBox:HookScript("OnTextChanged", function(self)
		search = (self:GetText() or ""):lower()
		Refresh()
	end)

	local groupDD = Dropdown(150, function() return GROUPS end, "group")
	groupDD:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)

	local sortDD = Dropdown(150, function() return SORTS end, "sort")
	sortDD:SetPoint("LEFT", groupDD, "RIGHT", 6, 0)

	local junk = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	junk:SetSize(24, 24)
	junk:SetPoint("LEFT", sortDD, "RIGHT", 8, 0)
	local junkLabel = junk:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	junkLabel:SetPoint("LEFT", junk, "RIGHT", 2, 0)
	junkLabel:SetText("Hide grey items")
	junk:SetScript("OnClick", function(self)
		F.hideJunk = self:GetChecked() and true or false
		Refresh()
	end)

	local expandBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	expandBtn:SetSize(100, 22)
	expandBtn:SetPoint("LEFT", junkLabel, "RIGHT", 16, 0)
	local allExpanded = false
	expandBtn:SetScript("OnClick", function()
		allExpanded = not allExpanded
		wipe(expanded)
		Refresh(true)
	end)

	-- Big item count for everything the current filters show
	local itemCount = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	itemCount:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -36)
	itemCount:SetJustifyH("RIGHT")
	local kindCount = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	kindCount:SetPoint("TOPRIGHT", itemCount, "BOTTOMRIGHT", 0, -2)
	kindCount:SetJustifyH("RIGHT")

	-- From / To range under the search row
	F.range = F.range or {}
	local rangeLoaded = false -- custom texts put back into the boxes
	local function LootBounds()
		local first, last
		for _, c in ipairs(CharsInScope()) do
			for _, e in ipairs(c.entries) do
				if not first or e[1] < first then first = e[1] end
				if not last or e[1] > last then last = e[1] end
			end
		end
		return first, last
	end
	-- Always visible. Shows the chosen period's dates; changing them switches to "Custom range".
	local range = CreateRangeSelector(f, F.range, function(byUser)
		if byUser and F.period ~= "custom" then
			F.period = "custom"
			rangeLoaded = true -- the boxes already hold what the user wants
			if periodDD.GenerateMenu then periodDD:GenerateMenu() end
		end
		if Refresh then Refresh(true) end
	end, LootBounds)
	range:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -8)
	range:Show()

	local totals = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	totals:SetJustifyH("LEFT")
	totals:SetPoint("TOPLEFT", range, "BOTTOMLEFT", 0, -8)
	totals:SetPoint("RIGHT", f, "RIGHT", -16, 0)

	-- Columns -----------------------------------------------------------------
	local W = { count = 50, each = 100, ah = 110, vendor = 100, info = 220 }
	-- right edge offset of each column (from the row's right side)
	local X = {}
	X.info = 4
	X.vendor = X.info + W.info + 8
	X.ah = X.vendor + W.vendor + 6
	X.each = X.ah + W.ah + 6
	X.count = X.each + W.each + 6
	local header = CreateFrame("Frame", nil, f)
	header:SetPoint("TOPLEFT", totals, "BOTTOMLEFT", 0, -8)
	header:SetPoint("RIGHT", f, "RIGHT", -34, 0)
	header:SetHeight(18)
	local function Head(text, rightOffset, width, justify)
		local fs = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		if rightOffset then
			fs:SetPoint("RIGHT", header, "RIGHT", -rightOffset, 0)
			fs:SetWidth(width)
		else
			fs:SetPoint("LEFT", header, "LEFT", 4, 0)
		end
		fs:SetJustifyH(justify or "LEFT")
		return fs
	end
	local TIME_W = 120 -- timestamp column on the left
	local headTime = Head("Looted", nil)
	local headName = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	headName:SetPoint("LEFT", header, "LEFT", 4 + TIME_W, 0)
	local headCount = Head("Qty", X.count, W.count, "RIGHT")
	local headEach = Head("AH each", X.each, W.each, "RIGHT")
	local headAH = Head("AH total", X.ah, W.ah, "RIGHT")
	local headVendor = Head("Vendor", X.vendor, W.vendor, "RIGHT")
	local headInfo = Head("", X.info, W.info, "LEFT")
	headName:SetText("Item")
	headCount:SetText("Qty")
	headEach:SetText("AH each")
	headAH:SetText("AH total")
	headVendor:SetText("Vendor total")

	local scrollBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
	scrollBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 22)
	local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 8, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 8, 0)

	local empty = f:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	empty:SetPoint("TOP", scrollBox, "TOP", 0, -20)
	empty:SetText("Nothing looted matches.")

	local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", 16, 8)
	hint:SetText("Click a group to open it.  Hover an item for its tooltip; shift-click to link it in chat.")

	local function QualityColor(q)
		local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
		return c and c.hex or "|cffffffff"
	end

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(20)
	view:SetElementInitializer("Button", function(row, data)
		if not row.name then
			row.bg = row:CreateTexture(nil, "BACKGROUND")
			row.bg:SetAllPoints()
			local hl = row:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.08)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(16, 16)
			local function FS(font, width, justify)
				local fs = row:CreateFontString(nil, "ARTWORK", font)
				if width then fs:SetWidth(width) end
				fs:SetJustifyH(justify or "LEFT")
				fs:SetWordWrap(false)
				return fs
			end
			row.info = FS("GameFontDisable", W.info)
			row.info:SetPoint("RIGHT", row, "RIGHT", -X.info, 0)
			row.vendor = FS("GameFontHighlight", W.vendor, "RIGHT")
			row.vendor:SetPoint("RIGHT", row, "RIGHT", -X.vendor, 0)
			row.ah = FS("GameFontHighlight", W.ah, "RIGHT")
			row.ah:SetPoint("RIGHT", row, "RIGHT", -X.ah, 0)
			row.each = FS("GameFontHighlight", W.each, "RIGHT")
			row.each:SetPoint("RIGHT", row, "RIGHT", -X.each, 0)
			row.count = FS("GameFontHighlight", W.count, "RIGHT")
			row.count:SetPoint("RIGHT", row, "RIGHT", -X.count, 0)
			row.name = FS("GameFontHighlight")
			row.name:SetPoint("RIGHT", row.count, "LEFT", -8, 0)
			row.time = FS("GameFontDisable", TIME_W - 4)
			row.time:SetPoint("LEFT", row, "LEFT", 4, 0)
			row:RegisterForClicks("LeftButtonUp")
			row:SetScript("OnClick", function(self)
				local d = self.data
				if not d then return end
				if d.header then
					expanded[d.key] = not (expanded[d.key] == nil and allExpanded or expanded[d.key])
					Refresh(true)
				elseif d.link and IsModifiedClick("CHATLINK") then
					ChatEdit_InsertLink(d.link)
				end
			end)
			row:SetScript("OnEnter", function(self)
				local d = self.data
				if not d or not d.link then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				pcall(GameTooltip.SetHyperlink, GameTooltip, d.link)
				local i = ns.Info(d.link)
				GameTooltip:AddLine(" ")
				GameTooltip:AddDoubleLine("Looted", ns.Number(d.count), 1, 0.82, 0, 1, 1, 1)
				if i.bound then
					GameTooltip:AddLine("Soulbound or quest item: can't be sold on the AH", 0.7, 0.7, 0.7)
				elseif i.ah then
					local age = i.ahAge == 0 and "today" or i.ahAge == 1 and "yesterday"
						or i.ahAge and (i.ahAge .. " days ago") or "?"
					GameTooltip:AddDoubleLine("AH price (each)", GetMoneyString(i.ah, true), 1, 0.82, 0, 1, 1, 1)
					GameTooltip:AddDoubleLine("AH price x" .. ns.Number(d.count), GetMoneyString(i.ah * d.count, true),
						1, 0.82, 0, 1, 1, 1)
					GameTooltip:AddDoubleLine("After the 5% AH cut", GetMoneyString(math.floor(i.ah * d.count * 0.95), true),
						1, 0.82, 0, 1, 1, 1)
					GameTooltip:AddDoubleLine("Auctionator scan", age, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
				elseif ns.HasAuctionator() then
					GameTooltip:AddLine("No AH price yet: scan the AH with Auctionator", 0.7, 0.7, 0.7)
				end
				if i.vendor > 0 then
					GameTooltip:AddDoubleLine("Vendor price (each)", GetMoneyString(i.vendor, true), 1, 0.82, 0, 1, 1, 1)
				end
				local tags = {}
				for _, t in ipairs(d.tags or {}) do tags[#tags + 1] = ns.TagLabel(t) end
				if #tags > 0 then GameTooltip:AddLine("Tags: " .. table.concat(tags, ", "), 0.6, 0.8, 1, true) end
				if d.where then GameTooltip:AddLine(d.where, 0.7, 0.7, 0.7, true) end
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", GameTooltip_Hide)
		end
		row.data = data
		row.bg:SetColorTexture(1, 1, 1, data.header and 0.10 or ((data.index % 2 == 0) and 0.03 or 0))
		local indent = TIME_W + (data.child and 22 or 4)
		row.time:SetText(data.last and data.last > 0 and ns.Date("%Y-%m-%d %H:%M", data.last) or "")
		row.icon:ClearAllPoints()
		if data.link then
			row.icon:SetPoint("LEFT", row, "LEFT", indent, 0)
			row.icon:SetTexture(ns.ItemIcon(data.link))
			row.icon:Show()
			row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
		else
			row.icon:Hide()
			row.name:SetPoint("LEFT", row, "LEFT", indent, 0)
		end
		if data.header then
			local open = expanded[data.key]
			if open == nil then open = allExpanded end
			row.name:SetFontObject("GameFontNormal")
			row.name:SetText((open and "[-] " or "[+] ") .. data.label)
		else
			row.name:SetFontObject("GameFontHighlight")
			local q = ns.Info(data.link).quality
			row.name:SetText((data.prefix or "") .. QualityColor(q) .. ns.Info(data.link).name .. "|r")
		end
		row.count:SetText(ns.Number(data.count))
		if data.header then
			row.each:SetText("")
		else
			local i = ns.Info(data.link)
			row.each:SetText(i.bound and "|cff888888bound|r" or i.ah and ns.Money(i.ah) or "|cff888888no data|r")
		end
		row.ah:SetText(ns.Money(data.ah))
		row.vendor:SetText(ns.Money(data.vendor))
		row.info:SetText(data.info or "")
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	-- Building the list -------------------------------------------------------
	local function GroupKeys(e, tags)
		local g = F.group
		if g == "zone" then return { e[6] ~= "" and e[6] or "Unknown" } end
		if g == "subzone" then
			local z = e[6] ~= "" and e[6] or "Unknown"
			return { (e[7] and e[7] ~= "" and e[7] ~= z) and (z .. " - " .. e[7]) or z }
		end
		if g == "source" then return { ns.SourceLabel(e[4]) } end
		if g == "tag" then
			local keys = {}
			for _, t in ipairs(tags) do keys[#keys + 1] = ns.TagLabel(t) end
			if #keys == 0 then keys[1] = "Untagged" end
			return keys
		end
	end

	local function Top(set, n)
		local list = {}
		for k, v in pairs(set) do list[#list + 1] = { k, v } end
		table.sort(list, function(a, b) return a[2] > b[2] end)
		local out = {}
		for i = 1, math.min(n, #list) do out[i] = list[i][1] end
		local extra = #list - n
		return table.concat(out, ", ") .. (extra > 0 and (" +" .. extra) or "")
	end

	local function Sorter(a, b)
		if F.sort == "ah" then
			if a.ah ~= b.ah then return a.ah > b.ah end
		elseif F.sort == "vendor" then
			if a.vendor ~= b.vendor then return a.vendor > b.vendor end
		elseif F.sort == "count" then
			if a.count ~= b.count then return a.count > b.count end
		elseif F.sort == "name" then
			local an, bn = a.label or ns.Info(a.link).name, b.label or ns.Info(b.link).name
			if an ~= bn then return an < bn end
		elseif F.sort == "recent" then
			if a.last ~= b.last then return a.last > b.last end
		end
		if a.value ~= b.value then return a.value > b.value end
		return a.count > b.count
	end

	Refresh = function(keepScroll)
		if not f:IsShown() or not ns.char then return end
		ns.ResetInfo()
		junk:SetChecked(F.hideJunk)
		expandBtn:SetText(allExpanded and "Collapse all" or "Expand all")
		expandBtn:SetShown(F.group ~= "item" and F.group ~= "none")

		local custom = F.period == "custom"
		if custom and not rangeLoaded then
			rangeLoaded = true
			range.Load() -- fills the boxes; their change callback calls Refresh again
			return
		end
		local from, to = ns.PeriodStart(F.period), math.huge
		if custom then
			from, to = range.GetRange()
		else
			rangeLoaded = false -- next time "Custom range" is picked, bring back the saved one
			local first = from
			if first == 0 then first = LootBounds() or ns.StartOfToday() end
			range.ShowSpan(first, time())
		end
		local rows = {}
		local nLoots, nItems, total = 0, 0, 0
		local totalAH, totalVendor, noPrice = 0, 0, 0
		local kinds, nKinds = {}, 0
		local groups, items = {}, {}

		local function ItemAgg(bucket, e, tags, value, ahV, vendV)
			local key = ns.ItemID(e[2]) or e[2]
			local it = bucket[key]
			if not it then
				it = { link = e[2], count = 0, value = 0, ah = 0, vendor = 0, last = 0, zones = {}, sources = {}, tags = {}, tagSet = {} }
				bucket[key] = it
			end
			for _, t in ipairs(tags) do
				if not it.tagSet[t] then it.tagSet[t] = true; it.tags[#it.tags + 1] = t end
			end
			it.count = it.count + e[3]
			it.value = it.value + value
			it.ah = it.ah + ahV
			it.vendor = it.vendor + vendV
			if e[1] > it.last then it.last = e[1] end
			local z = e[6] ~= "" and e[6] or "Unknown"
			it.zones[z] = (it.zones[z] or 0) + e[3]
			local s = ns.SourceLabel(e[4])
			it.sources[s] = (it.sources[s] or 0) + e[3]
		end

		local multiChar = F.chars ~= "me"
		for _, c in ipairs(CharsInScope()) do
			for _, e in ipairs(c.entries) do
				if e[1] >= from and e[1] <= to
					and (F.zone == "all" or (e[6] ~= "" and e[6] or "Unknown") == F.zone)
					and (next(F.sources) == nil or F.sources[e[4]]) then
					local tags, has = ns.EntryTags(e)
					local i = ns.Info(e[2])
					local pass = (F.tag == "all" or has[F.tag]) and not (F.hideJunk and i.quality == 0)
					if pass and search ~= "" then
						local hay = (i.name .. " " .. (e[5] or "") .. " " .. (e[6] or "") .. " " .. (e[7] or "") .. " "
							.. ns.SourceLabel(e[4])):lower()
						pass = hay:find(search, 1, true) ~= nil
					end
					if pass then
						local value = i.unit * e[3]
						local ahV, vendV = (i.ah or 0) * e[3], i.vendor * e[3]
						nLoots, nItems, total = nLoots + 1, nItems + e[3], total + value
						local kid = ns.ItemID(e[2]) or e[2]
						if not kinds[kid] then kinds[kid] = true; nKinds = nKinds + 1 end
						totalAH, totalVendor = totalAH + ahV, totalVendor + vendV
						if not i.ah and not i.bound then noPrice = noPrice + 1 end
						if F.group == "none" then
							local where = ns.SourceLabel(e[4]) .. ((e[5] and e[5] ~= "") and (": " .. e[5]) or "")
							local zone = (e[7] and e[7] ~= "" and e[7] ~= e[6]) and (e[6] .. " - " .. e[7]) or e[6]
							rows[#rows + 1] = {
								link = e[2], count = e[3], value = value, ah = ahV, vendor = vendV, last = e[1], tags = tags,
								prefix = multiChar and (ns.ClassColored(c.name or "?", c.class) .. "  ") or nil,
								info = where .. "  |cff666666" .. (zone or "") .. "|r",
								where = (zone or "") .. "  " .. ns.Date("%Y-%m-%d %H:%M", e[1]),
							}
						elseif F.group == "item" then
							ItemAgg(items, e, tags, value, ahV, vendV)
						else
							for _, k in ipairs(GroupKeys(e, tags)) do
								local g = groups[k]
								if not g then
									g = { header = true, key = F.group .. ":" .. k, label = k, count = 0, value = 0, ah = 0, vendor = 0,
										last = 0, items = {}, kinds = 0 }
									groups[k] = g
								end
								g.count = g.count + e[3]
								g.value = g.value + value
								g.ah = g.ah + ahV
								g.vendor = g.vendor + vendV
								if e[1] > g.last then g.last = e[1] end
								ItemAgg(g.items, e, tags, value, ahV, vendV)
							end
						end
					end
				end
			end
		end

		local function ItemRows(bucket, child)
			local list = {}
			for _, it in pairs(bucket) do
				it.child = child
				local showSources = F.group == "zone" or F.group == "subzone"
				it.info = showSources and Top(it.sources, 2) or Top(it.zones, 2)
				it.where = "Zones: " .. Top(it.zones, 6) .. "\nSources: " .. Top(it.sources, 6)
				list[#list + 1] = it
			end
			table.sort(list, Sorter)
			return list
		end

		if F.group == "item" then
			rows = ItemRows(items, false)
			headInfo:SetText("Where")
			headTime:SetText("Last looted")
		elseif F.group == "none" then
			table.sort(rows, function(a, b) return a.last > b.last end)
			headInfo:SetText("Source / zone")
			headTime:SetText("Looted")
		else
			headInfo:SetText((F.group == "zone" or F.group == "subzone") and "Sources" or "Zones")
			headTime:SetText("Last looted")
			local glist = {}
			for _, g in pairs(groups) do
				local n = 0
				for _ in pairs(g.items) do n = n + 1 end
				g.info = n .. (n == 1 and " kind of item" or " kinds of items")
				glist[#glist + 1] = g
			end
			table.sort(glist, Sorter)
			for _, g in ipairs(glist) do
				rows[#rows + 1] = g
				local open = expanded[g.key]
				if open == nil then open = allExpanded end
				if open then
					for _, it in ipairs(ItemRows(g.items, true)) do rows[#rows + 1] = it end
				end
			end
		end
		for i, r in ipairs(rows) do r.index = i end

		local note
		if not ns.HasAuctionator() then
			note = ns.db.options.useAuctionator and "Install Auctionator for AH prices" or "AH prices are turned off in Options"
		elseif noPrice > 0 then
			note = ns.Number(noPrice) .. " loots have no AH price yet: scan the AH with Auctionator"
		else
			note = "AH prices: Auctionator's last scan"
		end
		totals:SetText(("|cffffd100Items|r %s   |cffffd100Loots|r %s   |cffffd100AH total|r %s   |cffffd100Vendor total|r %s   |cff888888%s|r"):format(
			ns.Number(nItems), ns.Number(nLoots), ns.Money(totalAH), ns.Money(totalVendor), note))
		titleText:SetText("Loot Audit")
		itemCount:SetText(ns.Number(nItems) .. (nItems == 1 and " item" or " items"))
		kindCount:SetText(("%s kind%s, %s loot%s"):format(ns.Number(nKinds), nKinds == 1 and "" or "s",
			ns.Number(nLoots), nLoots == 1 and "" or "s"))
		empty:SetShown(#rows == 0)
		local retain = keepScroll and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
		scrollBox:SetDataProvider(CreateDataProvider(rows), retain)
	end

	f:SetScript("OnShow", function()
		F.group = "none"
		Refresh()
	end)
	ns.pages[f] = function() Refresh(true) end
	return f
end

function ns.ToggleBrowser()
	if not ns.db or not ns.char then return end
	browser = browser or CreateBrowser()
	browser:SetShown(not browser:IsShown())
end
