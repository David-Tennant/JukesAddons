local _, ns = ...

---------------------------------------------------------------------------
-- Display clock
--
-- Entries are always stored as UTC epoch seconds (time()). This only changes
-- how they're shown and how typed dates are read back. ns.db.options.clock:
--   "auto"  = follow the game clock's "Use Local Time" setting
--   "local" = your computer's clock
--   "realm" = the realm (server) clock
---------------------------------------------------------------------------
ns.CLOCK_CHOICES = {
	{ "auto", "Same as the game clock" },
	{ "local", "Local time (your computer)" },
	{ "realm", "Realm time (server)" },
}

-- Days since 1970-01-01 for a civil date (any day/month overflow is fine)
local function DaysFromCivil(y, m, d)
	y = y + math.floor((m - 1) / 12)
	m = (m - 1) % 12 + 1
	if m <= 2 then y = y - 1 end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

-- Like time(t), but reads the table as UTC
local function TimeGM(t)
	return DaysFromCivil(t.year, t.month, t.day) * 86400
		+ (t.hour or 12) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
end

-- Seconds the realm clock is ahead of UTC, rounded to 15 minutes
local cachedOffset, cachedAt
local function RealmOffset()
	local now = GetServerTime and GetServerTime() or time()
	if cachedOffset and cachedAt and now - cachedAt < 60 then return cachedOffset end
	local diff
	local cal = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
	if cal and cal.year and cal.year > 2000 then
		diff = TimeGM({ year = cal.year, month = cal.month, day = cal.monthDay,
			hour = cal.hour, min = cal.minute, sec = 0 }) - now
	elseif GetGameTime then
		-- Only hours and minutes: wrap to the nearest day boundary
		local h, m = GetGameTime()
		local u = date("!*t", now)
		diff = ((h * 60 + m) - (u.hour * 60 + u.min)) * 60
		if diff > 14 * 3600 then diff = diff - 86400 end
		if diff < -12 * 3600 then diff = diff + 86400 end
	else
		return 0
	end
	cachedOffset = math.floor(diff / 900 + 0.5) * 900
	cachedAt = now
	return cachedOffset
end

local function UseRealm()
	local choice = ns.db and ns.db.options and ns.db.options.clock or "auto"
	if choice == "realm" then return true end
	if choice == "local" then return false end
	local useLocal
	if C_CVar and C_CVar.GetCVarBool then
		useLocal = C_CVar.GetCVarBool("timeMgrUseLocalTime")
	elseif GetCVarBool then
		useLocal = GetCVarBool("timeMgrUseLocalTime")
	end
	return not useLocal
end

-- date(fmt, ts) on the chosen clock
function ns.Date(fmt, ts)
	ts = ts or time()
	if UseRealm() then return date("!" .. fmt, ts + RealmOffset()) end
	return date(fmt, ts)
end

-- time(t) with t read on the chosen clock
function ns.Time(t)
	if UseRealm() then return TimeGM(t) - RealmOffset() end
	return time(t)
end

function ns.StartOfToday()
	local now = time()
	local t = UseRealm() and date("!*t", now + RealmOffset()) or date("*t", now)
	return now - (t.hour * 3600 + t.min * 60 + t.sec)
end

-- Adds the "Show times in" dropdown to a vertical-layout settings category
function ns.AddClockSetting(category, variable, onChange)
	local setting = Settings.RegisterAddOnSetting(category, variable, "clock", ns.db.options,
		Settings.VarType.String, "Show times in", ns.OPTION_DEFAULTS.clock)
	local function Options()
		local c = Settings.CreateControlTextContainer()
		for _, ch in ipairs(ns.CLOCK_CHOICES) do c:Add(ch[1], ch[2]) end
		return c:GetData()
	end
	local create = Settings.CreateDropdown or Settings.CreateDropDown
	create(category, setting, Options,
		"Which clock dates and times are shown in. Times are always saved in UTC, so changing this never changes your data.\n\n"
		.. "Same as the game clock: follows the \"Use Local Time\" option on the clock by the minimap.")
	if setting.SetValueChangedCallback and onChange then
		setting:SetValueChangedCallback(function() onChange() end)
	end
	return setting
end
