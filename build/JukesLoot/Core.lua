local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- Midnight-engine clients can hand back "secret" values; treat those as unknown.
local function Plain(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function pack(...) return { n = select("#", ...), ... } end

-- Calls a game function safely; returns nothing if it is missing or errors.
local function Call(fn, ...)
	if type(fn) ~= "function" then return end
	local r = pack(pcall(fn, ...))
	if not r[1] then return end
	return unpack(r, 2, r.n)
end
ns.Call = Call

local function Num(v)
	v = Plain(v)
	return type(v) == "number" and v or nil
end
ns.Num = Num

local function Str(v)
	v = Plain(v)
	return type(v) == "string" and v ~= "" and v or nil
end
ns.Str = Str

-- hooksecurefunc that never breaks the game if our code errors or the function is missing.
local function Hook(tbl, name, fn)
	local safe = function(...) pcall(fn, ...) end
	if tbl then
		if type(tbl[name]) == "function" then hooksecurefunc(tbl, name, safe) end
	elseif type(_G[name]) == "function" then
		hooksecurefunc(name, safe)
	end
end

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end

local function ItemID(link)
	return link and tonumber(link:match("item:(%d+)"))
end
ns.ItemID = ItemID

---------------------------------------------------------------------------
-- Character / ruleset (same keys as Gold Audit)
---------------------------------------------------------------------------
local function GetRuleset()
	if C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule then
		local G = Enum.GameRule
		local function on(rule) return rule ~= nil and Call(C_GameRules.IsGameRuleActive, rule) end
		if on(G.PvPRuleset) and on(G.RPRuleset) then return "RPPvP"
		elseif on(G.PvPRuleset) then return "PvP"
		elseif on(G.RPRuleset) then return "RP"
		elseif on(G.HardcoreRuleset) then return "HC"
		end
		return "PvE"
	end
	return GetRealmName() or "Unknown"
end

local function GetCharKey()
	local name, second = UnitName("player")
	local ruleset = GetRuleset()
	if RegionalUniqueNamesEnabled and Call(RegionalUniqueNamesEnabled) then
		local full = name .. ((second and second ~= "") and (" " .. second) or "")
		return full .. "-" .. ruleset, full, ruleset
	end
	local realm = GetRealmName() or "?"
	return name .. "-" .. realm, name, realm
end

---------------------------------------------------------------------------
-- Database
-- entry = { time, itemLink, count, source, sourceDetail, zone, subzone }
---------------------------------------------------------------------------
local db, char
ns.OPTION_DEFAULTS = {
	chat = false,
	recordCrafted = true,
	recordPurchases = false,
	useAuctionator = true,
	valuableSilver = 100,
	clock = "auto",
}

local function InitDB()
	JukesLootDB = JukesLootDB or {}
	db = JukesLootDB
	db.options = db.options or {}
	for k, v in pairs(ns.OPTION_DEFAULTS) do
		if db.options[k] == nil then db.options[k] = v end
	end
	db.chars = db.chars or {}
	ns.db = db
end

local function InitChar()
	local key, display, ruleset = GetCharKey()
	char = db.chars[key]
	if not char then
		char = { entries = {} }
		db.chars[key] = char
	end
	char.name = display
	char.ruleset = ruleset
	char.class = select(2, UnitClass("player"))
	char.lastSeen = time()
	ns.char, ns.charKey = char, key
end

---------------------------------------------------------------------------
-- Item info: tags, quality, value
---------------------------------------------------------------------------
local tagCache = {} -- itemID -> list of item tags (only once the item is fully cached)

local function AddTags(set, list)
	if list then for t in list:gmatch("[^,]+") do set[t] = true end end
end

-- Tags that come from the item itself (not the source, quality or price)
function ns.ItemTags(link)
	local id = ItemID(link)
	if id and tagCache[id] then return tagCache[id] end
	local set = {}
	AddTags(set, id and ns.ITEM_IDS[id])

	local name, _, _, _, _, _, _, _, equipLoc, _, _, classID, subclassID, bindType = Call(GetItemInfo, link)
	local complete = Str(name) ~= nil
	if not classID then
		local _, _, _, eq, _, c, s = Call(GetItemInfoInstant, link)
		equipLoc, classID, subclassID = eq, c, s
	end
	classID, subclassID, bindType = Num(classID), Num(subclassID), Num(bindType)
	name = Str(name) or (link and link:match("%[(.-)%]"))

	if classID == 7 then -- trade goods
		AddTags(set, ns.TRADEGOODS_TAGS[subclassID])
	elseif classID == 9 then
		set.recipe = true
		AddTags(set, ns.RECIPE_TAGS[subclassID])
	elseif classID == 3 then
		set.gem, set.jewelcrafting = true, true
	elseif classID == 5 then
		set.reagent = true
	elseif classID == 12 then
		set.quest = true
	elseif classID == 0 then
		set.consumable = true
	elseif classID == 1 then
		set.bag = true
	elseif classID == 2 or classID == 4 then
		if equipLoc and equipLoc ~= "" then set.equipment = true end
		if bindType == 2 then set.boe = true end
	end
	if bindType == 4 then set.quest = true end

	-- English names for trade goods the tables above didn't place
	if name and (classID == 7 or classID == 15 or classID == 0) and not (id and ns.ITEM_IDS[id]) then
		for _, p in ipairs(ns.NAME_PATTERNS) do
			if name:find(p[1]) then AddTags(set, p[2]) end
		end
	end

	local list = {}
	for t in pairs(set) do list[#list + 1] = t end
	if complete and id then tagCache[id] = list end
	return list
end

function ns.ItemQuality(link)
	local q = Num(select(3, Call(GetItemInfo, link)))
	if q then return q end
	-- newer clients colour links as "|cnIQ4:" (quality index) instead of "|cffa335ee"
	local iq = link and tonumber(link:match("|cnIQ(%d+):"))
	if iq then return iq end
	local color = link and link:match("|c%x%x(%x%x%x%x%x%x)")
	return color and ns.LINK_QUALITY[color:lower()] or 1
end

function ns.HasAuctionator()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	return db.options.useAuctionator and api and api.GetAuctionPriceByItemLink and api or nil
end

-- Prices of one item, in copper:
--   ah     = Auctionator's last scanned auction price (nil if never seen on the AH)
--   ahAge  = days since that price was scanned (0 = today)
--   vendor = what a vendor pays
--   bound  = soulbound / quest item, so it can't go on the AH
function ns.ItemPrices(link)
	local _, _, _, _, _, _, _, _, _, _, sell, classID, _, bindType = Call(GetItemInfo, link)
	local p = { vendor = Num(sell) or 0 }
	bindType, classID = Num(bindType), Num(classID)
	p.bound = bindType == 1 or bindType == 4 or classID == 12
	local api = ns.HasAuctionator()
	if api and not p.bound then
		local v = Num(Call(api.GetAuctionPriceByItemLink, ADDON_NAME, link))
		if v and v > 0 then
			p.ah = v
			if api.GetAuctionAgeByItemLink then p.ahAge = Num(Call(api.GetAuctionAgeByItemLink, ADDON_NAME, link)) end
		end
	end
	return p
end

-- Best value of one item: its AH price if there is one, otherwise vendor
function ns.ItemValue(link)
	local p = ns.ItemPrices(link)
	if p.ah then return p.ah, true end
	return p.vendor, false
end

function ns.ItemIcon(link)
	local icon = select(5, Call(GetItemInfoInstant, link))
	return icon or 134400
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
local refreshPending = false
function ns.ScheduleRefresh(delay)
	if not ns.OnDataChanged or refreshPending then return end
	refreshPending = true
	C_Timer.After(delay or 0.5, function()
		refreshPending = false
		ns.OnDataChanged()
	end)
end

local function Record(link, count, src, detail)
	if not char or not link then return end
	local zone = Str(Call(GetRealZoneText)) or ""
	local sub = Str(Call(GetSubZoneText)) or ""
	char.entries[#char.entries + 1] = { time(), link, count or 1, src or "other", detail or "", zone, sub }
	char.lastSeen = time()
	if db.options.chat then
		print(("|cffffd100Loot Audit:|r %s%s - %s%s"):format(link, (count and count > 1) and (" x" .. count) or "",
			ns.SourceLabel(src), (detail and detail ~= "") and (" (" .. detail .. ")") or ""))
	end
	-- make sure the item gets cached so its tags and price can be worked out
	local id = ItemID(link)
	if id and C_Item and C_Item.RequestLoadItemDataByID then Call(C_Item.RequestLoadItemDataByID, id) end
	ns.ScheduleRefresh()
end

---------------------------------------------------------------------------
-- Context
---------------------------------------------------------------------------
local state = {}
local function CloseLater(key)
	C_Timer.After(1, function() state[key] = nil end)
end

-- Gathering / looting spells, by name so every rank matches
local SPELL_KIND = {}
for id, kind in pairs({
	[2575] = "mining", [195122] = "mining", [423341] = "mining", [471013] = "mining",
	[2366] = "herbalism", [8613] = "skinning", [194174] = "skinning",
	[13262] = "disenchant", [31252] = "prospect", [51005] = "mill",
	[3365] = "chest", [22810] = "chest", [921] = "pickpocket",
}) do
	local name = Str(Call(GetSpellName, id))
	if name then SPELL_KIND[name] = kind end
end

local castTargets = {}  -- castGUID -> target name
local lastCast          -- { kind, target, at }
local lastUsedItem      -- { name, at }: bag item just used (clam, lockbox, item being disenchanted)

-- Names for creatures we've seen
local guidNames, guidCount = {}, 0
local function RememberUnit(unit)
	local guid = Str(Call(UnitGUID, unit))
	if not guid or Plain(Call(UnitIsPlayer, unit)) then return end
	local name = Str(Call(UnitName, unit))
	if not name then return end
	if guidCount > 500 then guidNames, guidCount = {}, 0 end
	if not guidNames[guid] then guidCount = guidCount + 1 end
	guidNames[guid] = name
end

local function SourceInfo(guid)
	guid = Str(guid)
	if not guid then return "mob" end
	local kind = guid:match("^(%a+)%-")
	if kind == "Creature" or kind == "Vehicle" or kind == "Pet" then
		local name = guidNames[guid]
		if not name then
			local npcID = select(6, strsplit("-", guid))
			name = npcID and ("NPC #" .. npcID) or nil
		end
		return "mob", name
	elseif kind == "GameObject" then
		return "chest", nil
	elseif kind == "Item" then
		return "container", lastUsedItem and lastUsedItem.name
	end
	return "mob"
end

---------------------------------------------------------------------------
-- Loot window: work out where each item came from
---------------------------------------------------------------------------
local lootMap, lootDefault = {}, nil
local lootClosedAt = 0

local function OnLootOpened()
	state.loot = true
	lootMap, lootDefault = {}, nil
	RememberUnit("mouseover")
	RememberUnit("target")

	local cast = lastCast and (GetTime() - lastCast.at < 5) and lastCast or nil
	lastCast = nil
	local forced, forcedDetail
	if Call(IsFishingLoot) then
		forced, forcedDetail = "fishing", Str(Call(GetSubZoneText))
	elseif cast then
		forced, forcedDetail = cast.kind, cast.target
	end

	for slot = 1, Num(Call(GetNumLootItems)) or 0 do
		local link = Str(Call(GetLootSlotLink, slot))
		if link then
			local src = pack(Call(GetLootSourceInfo, slot))
			local kind, detail = SourceInfo(src[1])
			if forced then
				-- gathering a node or skinning: keep the node / mob name as the detail
				if forced == "chest" or forced == "mining" or forced == "herbalism" then
					detail = forcedDetail or detail
				elseif forced == "disenchant" or forced == "prospect" or forced == "mill" then
					detail = forcedDetail or (lastUsedItem and lastUsedItem.name) or detail
				elseif forced == "fishing" then
					detail = forcedDetail
				else
					detail = detail or forcedDetail
				end
				kind = forced
			end
			local id = ItemID(link)
			if id then lootMap[id] = { kind, detail } end
			lootDefault = lootDefault or { kind, detail }
		end
	end
	if not lootDefault and forced then lootDefault = { forced, forcedDetail } end
end

---------------------------------------------------------------------------
-- Chat lines (built from the client's own strings, any language)
---------------------------------------------------------------------------
local function ToPattern(fmt)
	local p = fmt:gsub("%%%d%$", "%%")
	p = p:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
	p = p:gsub("%%s", "(.+)")
	p = p:gsub("%%d", "(%%d+)")
	return "^" .. p .. "$"
end

local PATTERNS = {}
for _, p in ipairs({
	-- the "x%d" versions first: the plain ones would match them too
	{ LOOT_ITEM_SELF_MULTIPLE, "loot" },
	{ LOOT_ITEM_SELF, "loot" },
	{ LOOT_ITEM_PUSHED_SELF_MULTIPLE, "pushed" },
	{ LOOT_ITEM_PUSHED_SELF, "pushed" },
	{ LOOT_ITEM_CREATED_SELF_MULTIPLE, "created" },
	{ LOOT_ITEM_CREATED_SELF, "created" },
}) do
	if type(p[1]) == "string" then PATTERNS[#PATTERNS + 1] = { ToPattern(p[1]), p[2] } end
end

local function TradeskillName()
	if GetTradeSkillLine then
		local name = Str(Call(GetTradeSkillLine))
		if name and name ~= "UNKNOWN" then return name end
	end
	if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
		local info = Call(C_TradeSkillUI.GetBaseProfessionInfo)
		if type(info) == "table" then return Str(info.professionName) end
	end
end

local function HandleItem(link, count, how)
	local id = ItemID(link)
	if not id then return end

	if how == "created" then
		if db.options.recordCrafted then Record(link, count, "crafted", state.tradeskill or TradeskillName()) end
		return
	end

	local fromLoot = state.loot or (GetTime() - lootClosedAt < 3)
	if fromLoot and (how == "loot" or lootMap[id]) then
		local s = lootMap[id] or lootDefault
		if s then return Record(link, count, s[1], s[2]) end
		return Record(link, count, "mob")
	end

	if state.quest then return Record(link, count, "quest", state.questTitle) end
	if state.merchant then
		if db.options.recordPurchases then Record(link, count, "purchase", state.merchantName) end
		return
	end
	if lastUsedItem and GetTime() - lastUsedItem.at < 3 then
		return Record(link, count, "container", lastUsedItem.name)
	end
	if how == "loot" then return Record(link, count, "mob") end
	Record(link, count, "other")
end

local function OnChatLoot(text, ...)
	text = Str(text)
	if not text then return end
	for _, p in ipairs(PATTERNS) do
		local link, n = text:match(p[1])
		if link and link:find("|Hitem:", 1, true) then
			HandleItem(link, tonumber(n) or 1, p[2])
			return
		end
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local handlers = {}

local function On(event, fn)
	handlers[event] = fn
	pcall(ev.RegisterEvent, ev, event)
end

ev:SetScript("OnEvent", function(_, event, ...)
	local fn = handlers[event]
	if fn then
		local ok, err = pcall(fn, ...)
		if not ok and ns.debug then print("Loot Audit error:", event, err) end
	end
end)

On("ADDON_LOADED", function(name)
	if name ~= ADDON_NAME then return end
	InitDB()
	if ns.RegisterSettings then ns.RegisterSettings() end
end)

On("PLAYER_LOGIN", InitChar)

On("PLAYER_TARGET_CHANGED", function() RememberUnit("target") end)
On("UPDATE_MOUSEOVER_UNIT", function() RememberUnit("mouseover") end)

On("UNIT_SPELLCAST_SENT", function(unit, target, castGUID)
	if unit ~= "player" then return end
	castGUID = Str(castGUID)
	if castGUID then castTargets[castGUID] = Str(target) or false end
end)

handlers.UNIT_SPELLCAST_SUCCEEDED = function(unit, castGUID, spellID)
	if unit ~= "player" then return end
	castGUID = Str(castGUID)
	local target = castGUID and castTargets[castGUID] or nil
	if castGUID then castTargets[castGUID] = nil end
	local name = Str(Call(GetSpellName, Num(spellID)))
	local kind = name and SPELL_KIND[name]
	if kind then
		if kind == "pickpocket" and not target then target = Str(Call(UnitName, "target")) end
		lastCast = { kind = kind, target = target or nil, at = GetTime() }
	end
end
if ev.RegisterUnitEvent then
	pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
else
	pcall(ev.RegisterEvent, ev, "UNIT_SPELLCAST_SUCCEEDED")
end

On("LOOT_OPENED", OnLootOpened)
On("LOOT_CLOSED", function()
	lootClosedAt = GetTime()
	CloseLater("loot")
end)

On("CHAT_MSG_LOOT", OnChatLoot)

On("GET_ITEM_INFO_RECEIVED", function() ns.ScheduleRefresh(1) end)

On("QUEST_COMPLETE", function()
	state.quest = true
	state.questTitle = Str(Call(GetTitleText))
end)
On("QUEST_FINISHED", function() CloseLater("quest") end)

On("MERCHANT_SHOW", function()
	state.merchant = true
	state.merchantName = Str(Call(UnitName, "npc"))
end)
On("MERCHANT_CLOSED", function() CloseLater("merchant") end)

On("TRADE_SKILL_SHOW", function() state.tradeskill = TradeskillName() end)

-- Using a bag item away from a merchant: opening a clam / lockbox, or the item being disenchanted
local function OnUseContainerItem(bag, slot)
	if state.merchant then return end
	local name
	if C_Container and C_Container.GetContainerItemInfo then
		local info = Call(C_Container.GetContainerItemInfo, bag, slot)
		if type(info) == "table" then name = Str(info.itemName) end
	end
	if not name and GetContainerItemLink then
		local link = Str(Call(GetContainerItemLink, bag, slot))
		name = link and link:match("%[(.-)%]")
	end
	if name then lastUsedItem = { name = name, at = GetTime() } end
end
if C_Container then Hook(C_Container, "UseContainerItem", OnUseContainerItem) end
Hook(nil, "UseContainerItem", OnUseContainerItem)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
SLASH_JUKESLOOT1 = "/jl"
SLASH_JUKESLOOT2 = "/lootaudit"
SLASH_JUKESLOOT3 = "/jukesloot"
SlashCmdList.JUKESLOOT = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "debug" then
		ns.debug = not ns.debug
		print("Loot Audit debug:", ns.debug and "on" or "off")
	elseif msg == "options" or msg == "summary" then
		if ns.OpenSettings then ns.OpenSettings() end
	else
		if ns.ToggleBrowser then ns.ToggleBrowser() end
	end
end
