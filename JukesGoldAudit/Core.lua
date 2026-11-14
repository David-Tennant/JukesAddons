local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- Midnight-engine clients can hand back "secret" values; treat those as unknown.
local function Plain(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end
ns.Plain = Plain

local function pack(...) return { n = select("#", ...), ... } end

-- Calls a game function safely; returns nothing if it is missing or errors.
local function Call(fn, ...)
	if type(fn) ~= "function" then return end
	local r = pack(pcall(fn, ...))
	if not r[1] then return end
	return unpack(r, 2, r.n)
end

local function Num(v)
	v = Plain(v)
	return type(v) == "number" and v or nil
end

local function Str(v)
	v = Plain(v)
	return type(v) == "string" and v ~= "" and v or nil
end

-- hooksecurefunc that never breaks the game if our code errors or the function is missing.
local function Hook(tbl, name, fn)
	local safe = function(...) pcall(fn, ...) end
	if tbl then
		if type(tbl[name]) == "function" then hooksecurefunc(tbl, name, safe) end
	elseif type(_G[name]) == "function" then
		hooksecurefunc(name, safe)
	end
end

---------------------------------------------------------------------------
-- Character / ruleset
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
	-- Classic-style realms: group by realm
	local realm = GetRealmName() or "?"
	return name .. "-" .. realm, name, realm
end

---------------------------------------------------------------------------
-- Database
---------------------------------------------------------------------------
local db, char
ns.OPTION_DEFAULTS = { chat = false, groupLoot = true }

local function InitDB()
	GoldAuditDB = GoldAuditDB or {}
	db = GoldAuditDB
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
-- Recording
---------------------------------------------------------------------------
local function MoneyText(copper)
	return (copper < 0 and "-" or "+") .. GetMoneyString(math.abs(copper), true)
end
ns.MoneyText = MoneyText

local refreshPending = false
local function Record(delta, cat, detail)
	if not char or delta == 0 then return end
	local zone = Str(Call(GetRealZoneText)) or ""
	char.entries[#char.entries + 1] = { time(), delta, cat or "other", detail or "", zone }
	char.lastSeen = time()
	if db.options.chat then
		local color = delta > 0 and "|cff33ff33" or "|cffff5555"
		print(("|cffffd100Gold Audit:|r %s%s|r %s%s"):format(color, MoneyText(delta), ns.CatLabel(cat),
			(detail and detail ~= "") and (" - " .. detail) or ""))
	end
	if ns.OnDataChanged and not refreshPending then
		refreshPending = true
		C_Timer.After(0.5, function()
			refreshPending = false
			ns.OnDataChanged()
		end)
	end
end

---------------------------------------------------------------------------
-- Context: what the game was doing just before money moved
---------------------------------------------------------------------------
local contexts = {}
local state = {}

-- amount: signed copper if known. sign: +1 / -1 when the amount isn't known.
local function Push(cat, detail, amount, sign, ttl, group)
	amount = Num(amount)
	if amount == 0 then amount = nil end
	contexts[#contexts + 1] = {
		cat = cat, detail = detail, amount = amount,
		sign = amount and (amount > 0 and 1 or -1) or sign,
		expires = GetTime() + (ttl or 4), group = group,
	}
end

local function Prune()
	local now = GetTime()
	for i = #contexts, 1, -1 do
		if contexts[i].expires < now then table.remove(contexts, i) end
	end
end

local function RemoveGroup(group)
	if not group then return end
	for i = #contexts, 1, -1 do
		if contexts[i].group == group then table.remove(contexts, i) end
	end
end

local function Fallback(delta, s)
	local gain = delta > 0
	if s.loot then return s.lootKind or "mob", s.lootDetail end
	if s.quest then return "quest", s.questTitle end
	if s.trade then return "trade", s.tradeName end
	if s.mail then return gain and "mail" or "postage" end
	if s.ah then return gain and "ah_refund" or "ah_buy" end
	if s.merchant then
		if not gain and s.repairMode then return "repair" end
		return gain and "vendor_sell" or "vendor_buy"
	end
	if s.trainer then return s.tradeskillTrainer and "profession" or "learn" end
	if s.taxi then return "flight" end
	if s.bank then return "bank" end
	return "other"
end

-- Returns a list of { amount, cat, detail } that add up to delta.
local function Classify(delta, snap)
	Prune()
	local sign = delta > 0 and 1 or -1

	-- 1. a context with exactly this amount
	for i = #contexts, 1, -1 do
		local c = contexts[i]
		if c.amount == delta then
			table.remove(contexts, i)
			RemoveGroup(c.group)
			return { { delta, c.cat, c.detail } }
		end
	end

	-- 2. several known amounts that add up (AoE loot, mail postage + gold)
	local idx, sum = {}, 0
	for i, c in ipairs(contexts) do
		if c.amount and c.sign == sign then
			idx[#idx + 1] = i
			sum = sum + c.amount
		end
	end
	if #idx > 1 and sum == delta then
		local out = {}
		for k = #idx, 1, -1 do
			local c = table.remove(contexts, idx[k])
			table.insert(out, 1, { c.amount, c.cat, c.detail })
		end
		return out
	end

	-- 3. something we know happened but not for how much
	for i = #contexts, 1, -1 do
		local c = contexts[i]
		if not c.amount and c.sign == sign then
			table.remove(contexts, i)
			RemoveGroup(c.group)
			return { { delta, c.cat, c.detail } }
		end
	end

	-- 4. a same-direction context whose amount didn't match (price estimate, split loot)
	for i = #contexts, 1, -1 do
		local c = contexts[i]
		if c.sign == sign then
			table.remove(contexts, i)
			return { { delta, c.cat, c.detail } }
		end
	end

	-- 5. whatever window was open
	local cat, detail = Fallback(delta, snap)
	return { { delta, cat, detail } }
end

---------------------------------------------------------------------------
-- Money changes
---------------------------------------------------------------------------
local lastMoney

local function OnMoney()
	if not char then return end
	local now = GetMoney()
	local delta = now - (lastMoney or now)
	lastMoney = now
	char.balance = now
	if delta == 0 then return end

	local snap = {}
	for k, v in pairs(state) do snap[k] = v end
	snap.repairMode = Call(InRepairMode) and true or false

	-- Wait a moment: the event that explains the change (quest turn-in, loot chat line,
	-- trade close) can arrive just after the money itself.
	C_Timer.After(0.4, function()
		for _, part in ipairs(Classify(delta, snap)) do
			Record(part[1], part[2], part[3])
		end
	end)
end

---------------------------------------------------------------------------
-- Names for loot sources
---------------------------------------------------------------------------
local guidNames, guidCount = {}, 0

local function RememberUnit(unit)
	local guid = Str(Call(UnitGUID, unit))
	if not guid or Call(UnitIsPlayer, unit) then return end
	local name = Str(Call(UnitName, unit))
	if not name then return end
	if guidCount > 500 then guidNames, guidCount = {}, 0 end
	if not guidNames[guid] then guidCount = guidCount + 1 end
	guidNames[guid] = name
end

local lastOpenedItem -- name of a bag item (lockbox, clam...) the player just opened

local function SourceInfo(guid)
	guid = Str(guid)
	if not guid then return "mob" end
	local kind = guid:match("^(%a+)%-")
	if kind == "Creature" or kind == "Vehicle" or kind == "Pet" then
		for _, u in ipairs({ "target", "mouseover", "focus" }) do
			if Str(Call(UnitGUID, u)) == guid then RememberUnit(u) end
		end
		local name = guidNames[guid]
		if not name then
			local npcID = select(6, strsplit("-", guid))
			name = npcID and ("NPC #" .. npcID) or nil
		end
		return "mob", name
	elseif kind == "GameObject" then
		return "container", "Chest / object"
	elseif kind == "Item" then
		return "container", lastOpenedItem or "Container"
	end
	return "mob"
end

---------------------------------------------------------------------------
-- Chat line patterns (built from the client's own strings, any language)
---------------------------------------------------------------------------
local function ToPattern(fmt)
	local p = fmt:gsub("%%%d%$", "%%")
	p = p:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
	p = p:gsub("%%s", "(.+)")
	p = p:gsub("%%d", "(%%d+)")
	return "^" .. p
end
local SHARE_PATTERN = ToPattern(LOOT_MONEY_SPLIT or "Your share of the loot is %s.")

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local handlers = {}

local function On(event, fn)
	handlers[event] = fn
	pcall(ev.RegisterEvent, ev, event) -- unknown events in this client are simply skipped
end

ev:SetScript("OnEvent", function(_, event, ...)
	local fn = handlers[event]
	if fn then
		local ok, err = pcall(fn, ...)
		if not ok and ns.debug then print("Gold Audit error:", event, err) end
	end
end)

local function CloseLater(key)
	C_Timer.After(1, function() state[key] = nil end)
end

On("ADDON_LOADED", function(name)
	if name ~= ADDON_NAME then return end
	InitDB()
	if ns.RegisterSettings then ns.RegisterSettings() end
end)

On("PLAYER_LOGIN", function()
	InitChar()
	lastMoney = GetMoney()
	if char.balance and char.balance ~= lastMoney then
		Record(lastMoney - char.balance, "offline", "Changed while this addon wasn't running")
	end
	char.balance = lastMoney
end)

On("PLAYER_MONEY", OnMoney)

On("PLAYER_TARGET_CHANGED", function() RememberUnit("target") end)
On("UPDATE_MOUSEOVER_UNIT", function() RememberUnit("mouseover") end)

-- Loot ----------------------------------------------------------------------
local pickpocketAt, pickpocketTarget

if ev.RegisterUnitEvent then
	handlers.UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
		if Num(spellID) == 921 then -- Pick Pocket
			pickpocketAt = GetTime()
			pickpocketTarget = Str(Call(UnitName, "target"))
		end
	end
	pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
end

On("LOOT_OPENED", function()
	state.loot = true
	state.lootKind, state.lootDetail = nil, nil
	RememberUnit("mouseover")
	RememberUnit("target")

	local forced, forcedDetail
	if Call(IsFishingLoot) then
		forced = "fishing"
	elseif pickpocketAt and GetTime() - pickpocketAt < 3 then
		forced, forcedDetail = "pickpocket", pickpocketTarget
	end

	local MONEY = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or LOOT_SLOT_MONEY or 2
	for slot = 1, Num(Call(GetNumLootItems)) or 0 do
		if Num(Call(GetLootSlotType, slot)) == MONEY then
			local src = pack(Call(GetLootSourceInfo, slot))
			if src.n == 0 then
				state.lootKind = forced or "mob"
				state.lootDetail = forcedDetail
			end
			for i = 1, src.n, 2 do
				local kind, name = SourceInfo(src[i])
				kind = forced or kind
				name = forcedDetail or name
				if not state.lootKind then state.lootKind, state.lootDetail = kind, name end
				local qty = Num(src[i + 1])
				Push(kind, name, (qty and qty > 0) and qty or nil, 1, 600, "loot")
			end
		end
	end
	if not state.lootKind then state.lootKind, state.lootDetail = forced, forcedDetail end
end)

On("LOOT_CLOSED", function()
	for _, c in ipairs(contexts) do
		if c.group == "loot" then c.expires = math.min(c.expires, GetTime() + 2) end
	end
	CloseLater("loot")
end)

On("CHAT_MSG_MONEY", function(text)
	text = Str(text)
	if text and text:match(SHARE_PATTERN) then
		Push("share", state.lootDetail, nil, 1, 3)
	end
end)

-- Quests --------------------------------------------------------------------
On("QUEST_COMPLETE", function()
	state.quest = true
	state.questTitle = Str(Call(GetTitleText))
end)
On("QUEST_FINISHED", function() CloseLater("quest") end)
On("QUEST_TURNED_IN", function(questID, _, money)
	money = Num(money)
	if money and money > 0 then
		local title = C_QuestLog and Str(Call(C_QuestLog.GetTitleForQuestID, questID)) or state.questTitle
		Push("quest", title or state.questTitle, money)
	end
end)

-- Merchant ------------------------------------------------------------------
On("MERCHANT_SHOW", function() state.merchant = true end)
On("MERCHANT_CLOSED", function() CloseLater("merchant") end)

local function MerchantItemName(index)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = Call(C_MerchantFrame.GetItemInfo, index)
		if type(info) == "table" then return Str(info.name) end
	end
	return Str(Call(GetMerchantItemInfo, index))
end

Hook(nil, "BuyMerchantItem", function(index, quantity)
	local name = MerchantItemName(index) or "Item"
	quantity = Num(quantity)
	if quantity and quantity > 1 then name = name .. " x" .. quantity end
	Push("vendor_buy", name, nil, -1)
end)

Hook(nil, "BuybackItem", function(index)
	local name, _, price = Call(GetBuybackItemInfo, index)
	price = Num(price)
	Push("buyback", Str(name) or "Item", price and -price or nil, -1)
end)

Hook(nil, "RepairAllItems", function(guildBank)
	if not guildBank then Push("repair", "All items", nil, -1) end
end)

if C_MerchantFrame then
	Hook(C_MerchantFrame, "SellAllJunkItems", function() Push("vendor_sell", "Junk items", nil, 1, 6) end)
end

-- Using a bag item: sale at a merchant, otherwise maybe opening a lockbox/clam
local function OnUseContainerItem(bag, slot)
	local name, count, link
	if C_Container and C_Container.GetContainerItemInfo then
		local info = Call(C_Container.GetContainerItemInfo, bag, slot)
		if type(info) == "table" then
			name, count, link = Str(info.itemName), Num(info.stackCount), Str(info.hyperlink)
		end
	end
	if state.merchant then
		local price
		if link then
			local sell = Num(select(11, Call(C_Item and C_Item.GetItemInfo or GetItemInfo, link)))
			if sell and sell > 0 then price = sell * (count or 1) end
		end
		local detail = (name or "Item") .. ((count and count > 1) and (" x" .. count) or "")
		Push("vendor_sell", detail, price, 1)
	else
		lastOpenedItem = name
	end
end
if C_Container then Hook(C_Container, "UseContainerItem", OnUseContainerItem) end
Hook(nil, "UseContainerItem", OnUseContainerItem)

-- Auction house -------------------------------------------------------------
On("AUCTION_HOUSE_SHOW", function() state.ah = true end)
On("AUCTION_HOUSE_CLOSED", function() CloseLater("ah") end)

if C_AuctionHouse then
	local function ItemLocName(loc)
		return C_Item and Str(Call(C_Item.GetItemName, loc)) or nil
	end
	Hook(C_AuctionHouse, "PostItem", function(loc) Push("ah_deposit", ItemLocName(loc), nil, -1, 6) end)
	Hook(C_AuctionHouse, "PostCommodity", function(loc, _, qty)
		local name = ItemLocName(loc)
		qty = Num(qty)
		if name and qty and qty > 1 then name = name .. " x" .. qty end
		Push("ah_deposit", name, nil, -1, 6)
	end)
	Hook(C_AuctionHouse, "PlaceBid", function(_, bid)
		bid = Num(bid)
		Push("ah_buy", nil, bid and -bid or nil, -1, 6)
	end)
	Hook(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, qty)
		local name = C_Item and Str(Call(C_Item.GetItemNameByID, itemID)) or nil
		qty = Num(qty)
		if name and qty and qty > 1 then name = name .. " x" .. qty end
		Push("ah_buy", name, nil, -1, 6)
	end)
	Hook(C_AuctionHouse, "CancelAuction", function() Push("ah_cancel", nil, nil, -1, 6) end)
end

-- Mail ----------------------------------------------------------------------
On("MAIL_SHOW", function() state.mail = true end)
On("MAIL_CLOSED", function() CloseLater("mail") end)

local function IsAuctionHouseSender(sender)
	return sender and sender:find("Auction House", 1, true) ~= nil
end

local function OnTakeMail(index)
	local _, _, sender, subject, money, cod = Call(GetInboxHeaderInfo, index)
	sender, subject, money, cod = Str(sender), Str(subject), Num(money), Num(cod)
	if money and money > 0 then
		local invoiceType, itemName, playerName = Call(GetInboxInvoiceInfo, index)
		invoiceType, itemName, playerName = Str(invoiceType), Str(itemName), Str(playerName)
		if invoiceType == "seller" then
			Push("ah_sale", (itemName or subject or "Auction") .. (playerName and (" -> " .. playerName) or ""), money)
		elseif invoiceType or IsAuctionHouseSender(sender) then
			Push("ah_refund", subject, money)
		else
			Push("mail", "From " .. (sender or "?") .. (subject and (": " .. subject) or ""), money)
		end
	end
	if cod and cod > 0 then
		Push("cod", "To " .. (sender or "?") .. (subject and (": " .. subject) or ""), -cod)
	end
end
Hook(nil, "TakeInboxMoney", OnTakeMail)
Hook(nil, "AutoLootMailItem", OnTakeMail)
Hook(nil, "TakeInboxItem", function(index)
	local _, _, sender, subject, _, cod = Call(GetInboxHeaderInfo, index)
	cod = Num(cod)
	if cod and cod > 0 then
		sender, subject = Str(sender), Str(subject)
		Push("cod", "To " .. (sender or "?") .. (subject and (": " .. subject) or ""), -cod)
	end
end)

local mailSends = 0
Hook(nil, "SendMail", function(recipient, subject)
	recipient, subject = Str(recipient) or "?", Str(subject)
	mailSends = mailSends + 1
	local group = "send" .. mailSends
	local price, money = Num(Call(GetSendMailPrice)), Num(Call(GetSendMailMoney))
	if price and price > 0 then Push("postage", "To " .. recipient, -price, -1, 6, group) end
	if money and money > 0 then
		Push("mail", "To " .. recipient .. (subject and (": " .. subject) or ""), -money, -1, 6, group)
	end
end)

-- Trade ---------------------------------------------------------------------
local tradeNet = 0
local function UpdateTradeNet()
	tradeNet = (Num(Call(GetTargetTradeMoney)) or 0) - (Num(Call(GetPlayerTradeMoney)) or 0)
end
On("TRADE_SHOW", function()
	state.trade = true
	state.tradeName = Str(Call(UnitName, "NPC"))
	tradeNet = 0
end)
On("TRADE_MONEY_CHANGED", UpdateTradeNet)
On("TRADE_ACCEPT_UPDATE", UpdateTradeNet)
On("TRADE_CLOSED", function()
	if tradeNet ~= 0 then Push("trade", state.tradeName, tradeNet, nil, 5) end
	tradeNet = 0
	CloseLater("trade")
end)

-- Flight paths --------------------------------------------------------------
On("TAXIMAP_OPENED", function() state.taxi = true end)
On("TAXIMAP_CLOSED", function() CloseLater("taxi") end)
Hook(nil, "TakeTaxiNode", function(index)
	local cost = Num(Call(TaxiNodeCost, index))
	Push("flight", Str(Call(TaxiNodeName, index)), cost and -cost or nil, -1, 6)
end)

-- Trainers ------------------------------------------------------------------
On("TRAINER_SHOW", function()
	state.trainer = true
	state.tradeskillTrainer = Call(IsTradeskillTrainer) and true or false
end)
On("TRAINER_CLOSED", function() CloseLater("trainer") end)
Hook(nil, "BuyTrainerService", function(index)
	local name, rank = Call(GetTrainerServiceInfo, index)
	name, rank = Str(name), Str(rank)
	if name and rank then name = name .. " (" .. rank .. ")" end
	local cost = Num(Call(GetTrainerServiceCost, index))
	local cat = (Call(IsTradeskillTrainer) or state.tradeskillTrainer) and "profession" or "learn"
	Push(cat, name, cost and -cost or nil, -1)
end)

On("CONFIRM_TALENT_WIPE", function(cost)
	cost = Num(cost)
	Push("respec", "Talents reset", cost and -cost or nil, -1, 120)
end)

-- Bank, stable, guild, barber ------------------------------------------------
On("BANKFRAME_OPENED", function() state.bank = true end)
On("BANKFRAME_CLOSED", function() CloseLater("bank") end)
Hook(nil, "PurchaseSlot", function() Push("bank", "Bank slot", nil, -1) end)
Hook(nil, "BuyStableSlot", function() Push("bank", "Stable slot", nil, -1) end)
Hook(nil, "BuyGuildCharter", function(name) Push("guild", "Guild charter: " .. (Str(name) or "?"), nil, -1) end)
Hook(nil, "DepositGuildBankMoney", function(amount)
	amount = Num(amount)
	Push("guild", "Guild bank deposit", amount and -amount or nil, -1)
end)
Hook(nil, "WithdrawGuildBankMoney", function(amount)
	amount = Num(amount)
	Push("guild", "Guild bank withdrawal", amount, 1)
end)
if C_BarberShop then
	Hook(C_BarberShop, "ApplyCustomizationChoices", function() Push("barber", "Barber shop", nil, -1) end)
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
SLASH_GOLDAUDIT1 = "/goldaudit"
SLASH_GOLDAUDIT2 = "/ga"
SlashCmdList.GOLDAUDIT = function(msg)
	if msg == "debug" then
		ns.debug = not ns.debug
		print("Gold Audit debug:", ns.debug and "on" or "off")
		return
	end
	if msg == "data" then
		if ns.ToggleDataWindow then ns.ToggleDataWindow() end
		return
	end
	if ns.OpenSettings then ns.OpenSettings() end
end
