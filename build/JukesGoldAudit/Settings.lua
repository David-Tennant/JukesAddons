local _, ns = ...

local mainCategory
local pages = {} -- refresh functions of pages currently built

local function Money(copper)
	return GetMoneyString(math.abs(copper or 0), true)
end

local function SignedMoney(copper)
	if not copper or copper == 0 then return "|cffaaaaaa0|r" end
	local color = copper > 0 and "|cff33ff33+" or "|cffff5555-"
	return color .. Money(copper) .. "|r"
end

local function ClassColored(name, class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c and c.colorStr then return "|c" .. c.colorStr .. name .. "|r" end
	return name
end

local function Ago(ts)
	if not ts then return "-" end
	local d = time() - ts
	if d < 120 then return "now" end
	if d < 3600 then return math.floor(d / 60) .. "m ago" end
	if d < 86400 then return math.floor(d / 3600) .. "h ago" end
	return math.floor(d / 86400) .. "d ago"
end

ns.OnDataChanged = function()
	for frame, refresh in pairs(pages) do
		if frame:IsVisible() then refresh() end
	end
end

-- "Total: Net +X   In X   Out X   (N transactions)"
local function TotalsText(count, sumIn, sumOut, label)
	return ("|cffffd100%s|r  Net %s     |cffffd100In|r %s     |cffffd100Out|r %s     |cffaaaaaa%d transaction%s|r"):format(
		label or "Total:", SignedMoney(sumIn - sumOut), Money(sumIn), Money(sumOut), count, count == 1 and "" or "s")
end

---------------------------------------------------------------------------
-- Time period: presets + a basic From / To date selector
---------------------------------------------------------------------------
local PERIODS = {
	{ "today", "Today" }, { "7", "Last 7 days" }, { "30", "Last 30 days" },
	{ "all", "All time" }, { "custom", "Custom range" },
}

-- "YYYY-MM-DD" -> table, "HH:MM" -> hour, min
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

-- Range selector: two rows (From / To), each a date box and a time box with step arrows.
-- getBounds() returns the earliest and latest entry timestamps, used as the starting values.
local function CreateRangeSelector(parent, onChange, getBounds)
	local block = CreateFrame("Frame", nil, parent)
	block:SetSize(420, 52)
	local sides = {}

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
			onChange()
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

	local function Side(label, y, isEnd)
		local fs = block:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		fs:SetPoint("TOPLEFT", block, "TOPLEFT", 0, y - 4)
		fs:SetWidth(52)
		fs:SetJustifyH("LEFT")
		fs:SetText(label)
		fs.isLabel = true

		local side = { isEnd = isEnd }
		side.day = Box(84, fs, function(t) return ParseDay(t) ~= nil end,
			label .. " date", "YYYY-MM-DD   (arrows: one day)")
		local after = Arrows(side.day, function(n)
			local t = ParseDay(side.day:GetText())
			if not t then return end
			t.day = t.day + n
			side.day:SetText(ns.Date("%Y-%m-%d", ns.Time(t)))
		end)
		side.clock = Box(46, after, function(t) return ParseClock(t) ~= nil end,
			label .. " time", "HH:MM, 24-hour   (arrows: one hour)")
		Arrows(side.clock, function(n)
			local H, M = ParseClock(side.clock:GetText())
			if not H then return end
			side.clock:SetText(("%02d:%02d"):format((H + n) % 24, M))
		end)

		-- timestamp, or nil when the date is invalid (= no limit on this side)
		function side.Get()
			local t = ParseDay(side.day:GetText())
			if not t then return end
			local H, M = ParseClock(side.clock:GetText())
			if not H then H, M = isEnd and 23 or 0, isEnd and 59 or 0 end
			t.hour, t.min, t.sec = H, M, isEnd and 59 or 0
			return ns.Time(t)
		end
		function side.Set(ts)
			side.day:SetText(ns.Date("%Y-%m-%d", ts))
			side.clock:SetText(ns.Date("%H:%M", ts))
		end
		sides[#sides + 1] = side
	end

	Side("From", 0, false)
	Side("To", -28, true)

	-- Fill with the earliest and latest recorded entries
	function block.Reset()
		local first, last = getBounds()
		sides[1].Set(first or ns.StartOfToday())
		sides[2].Set(last or time())
	end

	function block.GetRange()
		return sides[1].Get() or 0, sides[2].Get() or math.huge
	end
	block:Hide()
	return block
end

-- from, to for a period id
local function PeriodRange(period, rangeRow)
	if period == "today" then return ns.StartOfToday(), math.huge end
	if period == "7" then return time() - 7 * 86400, math.huge end
	if period == "30" then return time() - 30 * 86400, math.huge end
	if period == "custom" and rangeRow then return rangeRow.GetRange() end
	return 0, math.huge
end

local function PeriodDropdown(parent, width, get, set)
	local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dd:SetWidth(width)
	dd:SetupMenu(function(_, root)
		for _, ch in ipairs(PERIODS) do
			root:CreateRadio(ch[2], function() return get() == ch[1] end, function() set(ch[1]) end)
		end
	end)
	return dd
end

---------------------------------------------------------------------------
-- "All data" window: every saved entry of every character, movable + resizable
---------------------------------------------------------------------------
local dataWindow

local function CreateDataWindow()
	local saved = ns.db.dataWindow or {}
	ns.db.dataWindow = saved

	local f = CreateFrame("Frame", "GoldAuditDataWindow", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(saved.w or 900, saved.h or 500)
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
	if f.SetResizeBounds then f:SetResizeBounds(640, 260) else f:SetMinResize(640, 260) end
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:Hide()
	tinsert(UISpecialFrames, "GoldAuditDataWindow") -- Esc closes it

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

	local COL = { char = 4, date = 134, amount = 254, cat = 374, detail = 514 }
	local totals = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	totals:SetPoint("TOPLEFT", 16, -34)
	totals:SetPoint("TOPRIGHT", -16, -34)
	totals:SetJustifyH("LEFT")

	local period = "all"
	local Refresh
	local range = CreateRangeSelector(f, function() if Refresh then Refresh() end end, function()
		local first, last
		for _, c in pairs(ns.db.chars) do
			local es = c.entries or {}
			if es[1] and (not first or es[1][1] < first) then first = es[1][1] end
			if es[#es] and (not last or es[#es][1] > last) then last = es[#es][1] end
		end
		return first, last
	end)
	local lastPeriod
	local periodDD = PeriodDropdown(f, 130, function() return period end, function(v)
		period = v
		Refresh()
	end)
	periodDD:SetPoint("TOPLEFT", 14, -56)
	range:SetPoint("TOPLEFT", periodDD, "BOTTOMLEFT", 4, -8)

	local header = CreateFrame("Frame", nil, f)
	local function PlaceHeader()
		local y = range:IsShown() and -146 or -90
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", 14, y)
		header:SetPoint("TOPRIGHT", -34, y)
	end
	PlaceHeader()
	header:SetHeight(18)
	local function Head(text, x, right)
		local fs = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		if right then fs:SetPoint("RIGHT", header, "RIGHT", -4, 0) else fs:SetPoint("LEFT", header, "LEFT", x, 0) end
		fs:SetText(text)
	end
	Head("Character", COL.char)
	Head("Date", COL.date)
	Head("Amount", COL.amount)
	Head("Type", COL.cat)
	Head("Detail", COL.detail)
	Head("Zone", nil, true)

	local scrollBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
	scrollBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 22)
	local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 8, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 8, 0)

	local empty = f:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	empty:SetPoint("TOP", scrollBox, "TOP", 0, -20)
	empty:SetText("Nothing recorded yet.")

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(20)
	view:SetElementInitializer("Frame", function(row, data)
		if not row.date then
			row.bg = row:CreateTexture(nil, "BACKGROUND")
			row.bg:SetAllPoints()
			local function FS(x, w, font)
				local fs = row:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
				fs:SetPoint("LEFT", row, "LEFT", x, 0)
				if w then fs:SetWidth(w) end
				fs:SetJustifyH("LEFT")
				fs:SetWordWrap(false)
				return fs
			end
			row.char = FS(COL.char, 126)
			row.date = FS(COL.date, 116)
			row.amount = FS(COL.amount, 116)
			row.cat = FS(COL.cat, 136)
			row.detail = FS(COL.detail)
			row.zone = FS(0, 170, "GameFontDisable")
			row.zone:ClearAllPoints()
			row.zone:SetPoint("RIGHT", row, "RIGHT", -4, 0)
			row.zone:SetJustifyH("RIGHT")
			row.detail:SetPoint("RIGHT", row.zone, "LEFT", -8, 0)
		end
		local e, c = data.entry, data.char
		row.bg:SetColorTexture(1, 1, 1, (data.index % 2 == 0) and 0.05 or 0)
		row.char:SetText(ClassColored(c.name or "?", c.class))
		row.date:SetText(ns.Date("%Y-%m-%d %H:%M", e[1]))
		row.amount:SetText(SignedMoney(e[2]))
		row.cat:SetText(ns.CatLabel(e[3]))
		row.detail:SetText(e[4] or "")
		row.zone:SetText(e[5] or "")
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	Refresh = function(keepScroll)
		if not f:IsShown() then return end
		if period == "custom" and lastPeriod ~= "custom" then
			lastPeriod = period
			range.Reset() -- fires OnTextChanged -> Refresh; keep going with the new values
		end
		lastPeriod = period
		range:SetShown(period == "custom")
		PlaceHeader()
		local from, to = PeriodRange(period, range)
		local list = {}
		for _, c in pairs(ns.db.chars) do
			for _, e in ipairs(c.entries or {}) do
				if e[1] >= from and e[1] <= to then list[#list + 1] = { entry = e, char = c } end
			end
		end
		table.sort(list, function(a, b) return a.entry[1] > b.entry[1] end)
		local sumIn, sumOut = 0, 0
		for i, item in ipairs(list) do
			item.index = i
			local d = item.entry[2]
			if d > 0 then sumIn = sumIn + d else sumOut = sumOut - d end
		end
		totals:SetText(TotalsText(#list, sumIn, sumOut,
			period == "all" and "Total (all characters):" or "Total (all characters, filtered):"))
		titleText:SetText(("Gold Audit - All data (%d entries)"):format(#list))
		empty:SetShown(#list == 0)
		local retain = keepScroll and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
		scrollBox:SetDataProvider(CreateDataProvider(list), retain)
	end

	f:SetScript("OnShow", function() Refresh() end)
	pages[f] = function() Refresh(true) end
	return f
end

function ns.ToggleDataWindow()
	if not ns.db then return end
	dataWindow = dataWindow or CreateDataWindow()
	dataWindow:SetShown(not dataWindow:IsShown())
end

---------------------------------------------------------------------------
-- Summary page
---------------------------------------------------------------------------
local function CreateSummaryPage()
	local frame = CreateFrame("Frame")
	frame:Hide()

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Gold Audit")

	local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 16)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)

	local COLS = { 0, 230, 380, 530 }
	local rows = {}
	local function GetRow(i)
		local row = rows[i]
		if row then return row end
		row = {}
		for c, x in ipairs(COLS) do
			local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			fs:SetJustifyH("LEFT")
			row[c] = fs
			row[c].x = x
		end
		rows[i] = row
		return row
	end

	local function Refresh()
		local char, db = ns.char, ns.db
		if not char then return end
		for _, row in ipairs(rows) do for _, fs in ipairs(row) do fs:Hide() end end

		local lines = {}
		local function Line(font, ...) lines[#lines + 1] = { font = font, ... } end
		local function Blank() lines[#lines + 1] = { blank = true } end

		title:SetText("Gold Audit - " .. ClassColored(char.name or "?", char.class))
		Line("GameFontNormalLarge", "Current gold", Money(char.balance or GetMoney()))
		Blank()

		-- Characters on this ruleset
		Line("GameFontNormal", "Characters on " .. (char.ruleset or "?"), "Gold", "Last seen")
		local list, total = {}, 0
		for key, c in pairs(db.chars) do
			if c.ruleset == char.ruleset then
				list[#list + 1] = c
				total = total + (c.balance or 0)
			end
		end
		table.sort(list, function(a, b) return (a.balance or 0) > (b.balance or 0) end)
		for _, c in ipairs(list) do
			Line("GameFontHighlight", "  " .. ClassColored(c.name or "?", c.class), Money(c.balance),
				c == char and "playing" or Ago(c.lastSeen))
		end
		Line("GameFontNormal", ("Total (%d character%s)"):format(#list, #list == 1 and "" or "s"), Money(total))
		Blank()

		-- Periods
		local now = time()
		local periods = {
			{ "Today", ns.StartOfToday() },
			{ "Last 7 days", now - 7 * 86400 },
			{ "Last 30 days", now - 30 * 86400 },
			{ "All time", 0 },
		}
		local inc, exp = {}, {}
		for i = 1, #periods do inc[i], exp[i] = 0, 0 end
		local catIn, catOut = {}, {}
		for _, e in ipairs(char.entries) do
			local t, d, cat = e[1], e[2], e[3]
			for i, p in ipairs(periods) do
				if t >= p[2] then
					if d > 0 then inc[i] = inc[i] + d else exp[i] = exp[i] - d end
				end
			end
			if d > 0 then catIn[cat] = (catIn[cat] or 0) + d else catOut[cat] = (catOut[cat] or 0) - d end
		end
		Line("GameFontNormal", "Period", "Income", "Expense", "Net")
		for i, p in ipairs(periods) do
			Line("GameFontHighlight", "  " .. p[1], Money(inc[i]), Money(exp[i]), SignedMoney(inc[i] - exp[i]))
		end
		Blank()

		-- Categories
		Line("GameFontNormal", "By type (all time)", "Income", "Expense", "Net")
		local cats = {}
		for _, c in ipairs(ns.CATEGORIES) do
			if catIn[c.id] or catOut[c.id] then cats[#cats + 1] = c.id end
		end
		for id in pairs(catIn) do if not ns.CAT_LABEL[id] then cats[#cats + 1] = id end end
		table.sort(cats, function(a, b)
			return math.abs((catIn[a] or 0) - (catOut[a] or 0)) > math.abs((catIn[b] or 0) - (catOut[b] or 0))
		end)
		if #cats == 0 then Line("GameFontDisable", "  Nothing recorded yet") end
		for _, id in ipairs(cats) do
			local i, o = catIn[id] or 0, catOut[id] or 0
			Line("GameFontHighlight", "  " .. ns.CatLabel(id), i > 0 and Money(i) or "-", o > 0 and Money(o) or "-",
				SignedMoney(i - o))
		end
		Line("GameFontDisable", ("  %d transactions recorded for this character"):format(#char.entries))

		-- Draw
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
						fs:SetPoint("TOPLEFT", content, "TOPLEFT", fs.x, y)
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
	pages[frame] = Refresh
	return frame
end

---------------------------------------------------------------------------
-- Ledger page
---------------------------------------------------------------------------
local function CreateLedgerPage()
	local frame = CreateFrame("Frame")
	frame:Hide()

	local filters = { cat = "all", dir = "all", period = "all", search = "" }
	local expanded = {}
	local Refresh

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Ledger")

	local dataBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	dataBtn:SetSize(150, 22)
	dataBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -12)
	dataBtn:SetText("All data table")
	dataBtn:SetScript("OnClick", function() ns.ToggleDataWindow() end)

	local summary = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	summary:SetPoint("RIGHT", frame, "RIGHT", -32, 0)
	summary:SetJustifyH("LEFT")

	-- Filters ---------------------------------------------------------------
	local function Dropdown(width, choices, key)
		local dd = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
		dd:SetWidth(width)
		dd:SetupMenu(function(_, root)
			if root.SetScrollMode then root:SetScrollMode(400) end
			for _, ch in ipairs(choices()) do
				root:CreateRadio(ch[2], function() return filters[key] == ch[1] end, function()
					filters[key] = ch[1]
					Refresh()
				end)
			end
		end)
		return dd
	end

	local catDD = Dropdown(180, function()
		local list = { { "all", "All types" } }
		for _, c in ipairs(ns.CATEGORIES) do list[#list + 1] = { c.id, c.label } end
		return list
	end, "cat")
	catDD:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -10)

	local dirDD = Dropdown(120, function()
		return { { "all", "In & out" }, { "in", "Income only" }, { "out", "Expense only" } }
	end, "dir")
	dirDD:SetPoint("LEFT", catDD, "RIGHT", 8, 0)

	local periodDD = PeriodDropdown(frame, 130, function() return filters.period end, function(v)
		filters.period = v
		Refresh()
	end)
	periodDD:SetPoint("LEFT", dirDD, "RIGHT", 8, 0)

	local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	search:SetSize(200, 20)
	search:SetPoint("TOPLEFT", catDD, "BOTTOMLEFT", 6, -10)
	search:HookScript("OnTextChanged", function(self)
		filters.search = (self:GetText() or ""):lower()
		Refresh()
	end)

	local group = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	group:SetSize(24, 24)
	group:SetPoint("LEFT", search, "RIGHT", 16, 0)
	local groupLabel = group:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	groupLabel:SetPoint("LEFT", group, "RIGHT", 2, 0)
	groupLabel:SetText("Group mob loot")
	group:SetScript("OnClick", function(self)
		ns.db.options.groupLoot = self:GetChecked() and true or false
		Refresh()
	end)

	local lastPeriod
	local range = CreateRangeSelector(frame, function() if Refresh then Refresh() end end, function()
		local es = ns.char and ns.char.entries or {}
		return es[1] and es[1][1], es[#es] and es[#es][1]
	end)
	range:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -8)

	-- Column headers --------------------------------------------------------
	local COL = { date = 4, amount = 112, cat = 222, detail = 350 }
	local header = CreateFrame("Frame", nil, frame)
	local function PlaceHeader()
		header:ClearAllPoints()
		if range:IsShown() then
			header:SetPoint("TOPLEFT", range, "BOTTOMLEFT", 0, -8)
		else
			header:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -10)
		end
		header:SetPoint("RIGHT", frame, "RIGHT", -32, 0)
	end
	PlaceHeader()
	header:SetHeight(18)
	local function Head(text, x, justify, rightAnchor)
		local fs = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		if rightAnchor then
			fs:SetPoint("RIGHT", header, "RIGHT", -4, 0)
		else
			fs:SetPoint("LEFT", header, "LEFT", x, 0)
		end
		fs:SetJustifyH(justify or "LEFT")
		fs:SetText(text)
	end
	Head("Date", COL.date)
	Head("Amount", COL.amount)
	Head("Type", COL.cat)
	Head("Detail", COL.detail)
	Head("Zone", nil, "RIGHT", true)

	-- List --------------------------------------------------------------------
	local scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
	scrollBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 16)
	local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 8, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 8, 0)

	local empty = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	empty:SetPoint("TOP", scrollBox, "TOP", 0, -20)
	empty:SetText("No transactions match.")

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(20)
	view:SetElementInitializer("Button", function(row, data)
		if not row.date then
			row.bg = row:CreateTexture(nil, "BACKGROUND")
			row.bg:SetAllPoints()
			local hl = row:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.08)
			local function FS(x, w)
				local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
				fs:SetPoint("LEFT", row, "LEFT", x, 0)
				if w then fs:SetWidth(w) end
				fs:SetJustifyH("LEFT")
				fs:SetWordWrap(false)
				return fs
			end
			row.date = FS(COL.date, 104)
			row.amount = FS(COL.amount, 106)
			row.cat = FS(COL.cat, 124)
			row.detail = FS(COL.detail)
			row.zone = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
			row.zone:SetPoint("RIGHT", row, "RIGHT", -4, 0)
			row.zone:SetJustifyH("RIGHT")
			row.zone:SetWidth(130)
			row.zone:SetWordWrap(false)
			row.detail:SetPoint("RIGHT", row.zone, "LEFT", -6, 0)
			row:SetScript("OnClick", function(self)
				local d = self.data
				if d and d.group then
					expanded[d.key] = not expanded[d.key]
					Refresh(true)
				end
			end)
		end
		row.data = data
		row.bg:SetColorTexture(1, 1, 1, (data.index % 2 == 0) and 0.03 or 0)
		if data.group then
			local run = data.run
			row.date:SetText(ns.Date("%Y-%m-%d %H:%M", run[1][1]))
			row.amount:SetText(SignedMoney(data.total))
			row.cat:SetText((expanded[data.key] and "[-] " or "[+] ") .. ns.CatLabel("mob"))
			row.detail:SetText(("|cffffd100%d mobs|r  %s - %s"):format(#run,
				ns.Date("%H:%M", run[#run][1]), ns.Date("%H:%M", run[1][1])))
			row.zone:SetText(run[1][5])
		else
			local e = data.entry
			row.date:SetText((data.child and "    " or "") .. ns.Date("%Y-%m-%d %H:%M", e[1]))
			row.amount:SetText(SignedMoney(e[2]))
			row.cat:SetText(ns.CatLabel(e[3]))
			row.detail:SetText(e[4] or "")
			row.zone:SetText(e[5] or "")
		end
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	-- Filtering + visual grouping ------------------------------------------
	local upper = math.huge
	local function Pass(e)
		if e[1] > upper then return false end
		if filters.cat ~= "all" and e[3] ~= filters.cat then return false end
		if filters.dir == "in" and e[2] < 0 then return false end
		if filters.dir == "out" and e[2] > 0 then return false end
		local s = filters.search
		if s ~= "" then
			local hay = ((e[4] or "") .. " " .. (e[5] or "") .. " " .. ns.CatLabel(e[3])):lower()
			if not hay:find(s, 1, true) then return false end
		end
		return true
	end

	local GROUP_GAP = 30 * 60 -- mob loot more than 30 min apart starts a new group

	Refresh = function(keepScroll)
		local char = ns.char
		if not char or not frame:IsVisible() then return end
		group:SetChecked(ns.db.options.groupLoot)

		if filters.period == "custom" and lastPeriod ~= "custom" then
			lastPeriod = filters.period
			range.Reset()
		end
		lastPeriod = filters.period
		range:SetShown(filters.period == "custom")
		PlaceHeader()
		local cutoff
		cutoff, upper = PeriodRange(filters.period, range)
		local entries = char.entries
		local grouping = ns.db.options.groupLoot
		local out, sumIn, sumOut, count = {}, 0, 0, 0
		local function Add(item)
			item.index = #out + 1
			out[#out + 1] = item
		end

		local i = #entries
		while i >= 1 do
			local e = entries[i]
			if e[1] < cutoff then break end
			if Pass(e) then
				count = count + 1
				if e[2] > 0 then sumIn = sumIn + e[2] else sumOut = sumOut - e[2] end
				local consumed = false
				if grouping and e[3] == "mob" then
					local run, total = { e }, e[2]
					local j = i - 1
					while j >= 1 do
						local f = entries[j]
						if f[1] < cutoff then break end
						if Pass(f) then
							if f[3] == "mob" and f[5] == e[5] and run[#run][1] - f[1] <= GROUP_GAP then
								run[#run + 1] = f
								total = total + f[2]
								count = count + 1
								if f[2] > 0 then sumIn = sumIn + f[2] else sumOut = sumOut - f[2] end
							else
								break
							end
						end
						j = j - 1
					end
					if #run >= 2 then
						local key = run[#run][1] .. ":" .. (e[5] or "")
						Add({ group = true, key = key, run = run, total = total })
						if expanded[key] then
							for _, f in ipairs(run) do Add({ entry = f, child = true }) end
						end
						i = j
						consumed = true
					end
				end
				if not consumed then
					Add({ entry = e })
					i = i - 1
				end
			else
				i = i - 1
			end
		end

		local filtered = filters.cat ~= "all" or filters.dir ~= "all" or filters.period ~= "all" or filters.search ~= ""
		summary:SetText(TotalsText(count, sumIn, sumOut, filtered and "Total (filtered):" or "Total:"))
		empty:SetShown(#out == 0)
		local retain = keepScroll and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
		scrollBox:SetDataProvider(CreateDataProvider(out), retain)
	end

	frame:SetScript("OnShow", function() Refresh() end)
	pages[frame] = function() Refresh(true) end
	return frame
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
StaticPopupDialogs["GOLDAUDIT_DELETE_HISTORY"] = {
	text = "Delete ALL Gold Audit history for this character?\n\nThis cannot be undone.",
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

	mainCategory = Settings.RegisterCanvasLayoutCategory(CreateSummaryPage(), "Gold Audit")
	Settings.RegisterCanvasLayoutSubcategory(mainCategory, CreateLedgerPage(), "Ledger")

	local opt = Settings.RegisterVerticalLayoutSubcategory(mainCategory, "Options")
	local function Checkbox(key, label, tooltip)
		local s = Settings.RegisterAddOnSetting(opt, "GoldAudit_" .. key, key, db.options,
			Settings.VarType.Boolean, label, ns.OPTION_DEFAULTS[key])
		Settings.RegisterInitializer(opt, Settings.CreateCheckboxInitializer(s, nil, tooltip))
		return s
	end
	Checkbox("chat", "Print each gold change to chat",
		"Shows a chat line with the amount, type and detail every time your gold changes.")
	Checkbox("groupLoot", "Group mob loot in the ledger",
		"Shows runs of mob loot in the same zone as one expandable line. Only changes the display; every entry is still saved.")
	ns.AddClockSetting(opt, "GoldAudit_clock", function() ns.OnDataChanged() end)
	if CreateSettingsButtonInitializer then
		Settings.RegisterInitializer(opt, CreateSettingsButtonInitializer("All data",
			"Open the all data table", function() ns.ToggleDataWindow() end,
			"Opens a movable, resizable window with every recorded transaction for every character. Also: /ga data", true))
	end
	if CreateSettingsButtonInitializer then
		Settings.RegisterInitializer(opt, CreateSettingsButtonInitializer("Delete history",
			"Delete this character's history", function() StaticPopup_Show("GOLDAUDIT_DELETE_HISTORY") end,
			"Permanently removes every recorded transaction for the character you're playing.", true))
	end

	Settings.RegisterAddOnCategory(mainCategory)
end

function ns.OpenSettings()
	if mainCategory then Settings.OpenToCategory(mainCategory:GetID()) end
end
