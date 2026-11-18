local _, ns = ...

---------------------------------------------------------------------------
-- Sources: how an item was obtained. ids are saved, so never rename an id.
---------------------------------------------------------------------------
ns.SOURCES = {
	{ id = "mob",        label = "Mob loot" },
	{ id = "skinning",   label = "Skinning" },
	{ id = "mining",     label = "Mining" },
	{ id = "herbalism",  label = "Herbalism" },
	{ id = "fishing",    label = "Fishing" },
	{ id = "pickpocket", label = "Pick pocket" },
	{ id = "chest",      label = "Chest / object" },
	{ id = "container",  label = "Opened item" },
	{ id = "disenchant", label = "Disenchanting" },
	{ id = "prospect",   label = "Prospecting" },
	{ id = "mill",       label = "Milling" },
	{ id = "quest",      label = "Quest reward" },
	{ id = "crafted",    label = "Crafted" },
	{ id = "purchase",   label = "Vendor purchase" },
	{ id = "other",      label = "Other" },
}
ns.SOURCE_LABEL = {}
for _, s in ipairs(ns.SOURCES) do ns.SOURCE_LABEL[s.id] = s.label end
function ns.SourceLabel(id) return ns.SOURCE_LABEL[id] or tostring(id) end

-- Tags a source always gives its items
ns.SOURCE_TAGS = {
	mining = { "mining" },
	herbalism = { "herbalism" },
	skinning = { "skinning" },
	fishing = { "fishing" },
	disenchant = { "enchanting" },
	prospect = { "jewelcrafting" },
	mill = { "inscription" },
}

---------------------------------------------------------------------------
-- Tags. Not saved (worked out when shown), so they can change freely.
---------------------------------------------------------------------------
ns.TAGS = {
	-- professions
	{ id = "mining",         label = "Mining",         prof = true },
	{ id = "herbalism",      label = "Herbalism",      prof = true },
	{ id = "skinning",       label = "Skinning",       prof = true },
	{ id = "fishing",        label = "Fishing",        prof = true },
	{ id = "blacksmithing",  label = "Blacksmithing",  prof = true },
	{ id = "engineering",    label = "Engineering",    prof = true },
	{ id = "leatherworking", label = "Leatherworking", prof = true },
	{ id = "tailoring",      label = "Tailoring",      prof = true },
	{ id = "alchemy",        label = "Alchemy",        prof = true },
	{ id = "enchanting",     label = "Enchanting",     prof = true },
	{ id = "jewelcrafting",  label = "Jewelcrafting",  prof = true },
	{ id = "inscription",    label = "Inscription",    prof = true },
	{ id = "cooking",        label = "Cooking",        prof = true },
	{ id = "firstaid",       label = "First Aid",      prof = true },
	-- other
	{ id = "valuable",    label = "Valuable" },
	{ id = "epic",        label = "Epic or better" },
	{ id = "rare",        label = "Rare or better" },
	{ id = "boe",         label = "Bind on equip" },
	{ id = "recipe",      label = "Recipe / pattern" },
	{ id = "gem",         label = "Gem / pearl" },
	{ id = "elemental",   label = "Elemental" },
	{ id = "equipment",   label = "Weapons & armour" },
	{ id = "consumable",  label = "Consumable" },
	{ id = "reagent",     label = "Reagent" },
	{ id = "quest",       label = "Quest item" },
	{ id = "bag",         label = "Bag" },
	{ id = "junk",        label = "Junk (grey)" },
}
ns.TAG_LABEL = {}
for _, t in ipairs(ns.TAGS) do ns.TAG_LABEL[t.id] = t.label end
function ns.TagLabel(id) return ns.TAG_LABEL[id] or tostring(id) end

---------------------------------------------------------------------------
-- Known materials by item id (covers Classic, where most materials are
-- just "Trade Goods" with no sub-type).
---------------------------------------------------------------------------
ns.ITEM_IDS = {}
local function Add(tags, ...)
	for i = 1, select("#", ...) do ns.ITEM_IDS[select(i, ...)] = tags end
end

-- Ore
Add("mining,blacksmithing,engineering", 2770, 2771, 2772, 2775, 2776, 3858, 7911, 10620, 11370,
	23424, 23425, 23426, 23427, 36909, 36910, 36912)
-- Stone
Add("mining,blacksmithing,engineering", 2835, 2836, 2838, 7912, 12365)
-- Bars
Add("blacksmithing,engineering", 2840, 2841, 2842, 3575, 3576, 3577, 3859, 3860, 6037, 11371, 12359, 12360)
-- Gems and pearls
Add("gem,jewelcrafting,mining", 774, 818, 1206, 1210, 1529, 1705, 3864, 7909, 7910, 12361, 12364, 12799, 12800)
Add("gem,jewelcrafting", 5498, 5500, 7971, 13926)
Add("enchanting,mining", 12363) -- Arcane Crystal
-- Herbs
Add("herbalism,alchemy", 765, 785, 2447, 2449, 2450, 2452, 2453, 3355, 3356, 3357, 3358, 3369, 3818, 3819, 3820,
	3821, 4625, 8831, 8836, 8838, 8839, 8845, 8846, 13463, 13464, 13465, 13466, 13467, 13468,
	22785, 22786, 22787, 22789, 22790, 22791, 22792, 22793, 22794)
-- Cloth
Add("tailoring,firstaid", 2589, 2592, 4306, 4338, 14047, 21877, 33470)
Add("tailoring", 2996, 2997, 4305, 4339, 14048, 14256)
-- Leather, hides, scales
Add("skinning,leatherworking", 783, 2318, 2319, 2934, 4232, 4234, 4235, 4304, 8169, 8170, 8171, 21887, 25649,
	8154, 8165, 8167, 15412, 15414, 15415, 15416, 15417, 17012)
Add("leatherworking", 6470, 6471)
-- Enchanting
Add("enchanting", 10938, 10939, 10940, 10978, 10998, 11082, 11083, 11084, 11134, 11135, 11137, 11138, 11139,
	11174, 11175, 11176, 11177, 11178, 14343, 14344, 16202, 16203, 16204, 20725)
-- Elemental
Add("elemental", 7067, 7068, 7069, 7070, 7075, 7076, 7077, 7078, 7079, 7080, 7081, 7082, 7972, 12803, 12808)

-- English name patterns for trade goods not in the list above
ns.NAME_PATTERNS = {
	{ " Ore$",       "mining,blacksmithing,engineering" },
	{ " Stone$",     "mining,blacksmithing,engineering" },
	{ " Bar$",       "blacksmithing,engineering" },
	{ " Cloth$",     "tailoring" },
	{ "^Bolt of ",   "tailoring" },
	{ " Leather",    "skinning,leatherworking" },
	{ " Hide$",      "skinning,leatherworking" },
	{ " Scales?$",   "skinning,leatherworking" },
	{ " Dust$",      "enchanting" },
	{ " Shard$",     "enchanting" },
	{ "^Essence of ", "elemental" },
	{ "^Elemental ", "elemental" },
	{ " Essence$",   "enchanting" },
	{ " Pearl$",     "gem,jewelcrafting" },
	{ " Meat$",      "cooking" },
	{ "^Raw ",       "cooking" },
}

-- Trade goods sub-types (newer item data)
ns.TRADEGOODS_TAGS = {
	[1] = "engineering", [2] = "engineering", [3] = "engineering",
	[4] = "gem,jewelcrafting", [5] = "tailoring", [6] = "skinning,leatherworking",
	[7] = "mining,blacksmithing", [8] = "cooking", [9] = "herbalism,alchemy",
	[10] = "elemental", [12] = "enchanting", [16] = "inscription",
}

-- Recipe sub-types
ns.RECIPE_TAGS = {
	[1] = "leatherworking", [2] = "tailoring", [3] = "engineering", [4] = "blacksmithing",
	[5] = "cooking", [6] = "alchemy", [7] = "firstaid", [8] = "enchanting", [9] = "fishing",
	[10] = "jewelcrafting", [11] = "inscription",
}

-- Quality colour in a link -> quality, for items the client hasn't cached yet
ns.LINK_QUALITY = {
	["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3,
	["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7,
}
