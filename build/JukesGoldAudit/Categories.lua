local _, ns = ...

-- Display order. ids are stored in the saved data, so never rename an id.
ns.CATEGORIES = {
	{ id = "quest",       label = "Quest reward" },
	{ id = "mob",         label = "Mob loot" },
	{ id = "container",   label = "Chest / container" },
	{ id = "pickpocket",  label = "Pick pocket" },
	{ id = "fishing",     label = "Fishing loot" },
	{ id = "share",       label = "Party loot share" },
	{ id = "ah_sale",     label = "AH sale" },
	{ id = "ah_buy",      label = "AH purchase / bid" },
	{ id = "ah_deposit",  label = "AH deposit" },
	{ id = "ah_cancel",   label = "AH cancel fee" },
	{ id = "ah_refund",   label = "AH refund / outbid" },
	{ id = "repair",      label = "Repair" },
	{ id = "vendor_sell", label = "Vendor sale" },
	{ id = "vendor_buy",  label = "Vendor purchase" },
	{ id = "buyback",     label = "Vendor buyback" },
	{ id = "flight",      label = "Flight path" },
	{ id = "learn",       label = "Learning spells" },
	{ id = "profession",  label = "Profession training" },
	{ id = "respec",      label = "Talent reset" },
	{ id = "bank",        label = "Bank / stable slot" },
	{ id = "trade",       label = "Player trade" },
	{ id = "mail",        label = "Mail (player)" },
	{ id = "postage",     label = "Postage" },
	{ id = "cod",         label = "COD payment" },
	{ id = "guild",       label = "Guild" },
	{ id = "barber",      label = "Barber" },
	{ id = "offline",     label = "Offline / unknown" },
	{ id = "other",       label = "Other" },
}

ns.CAT_LABEL = {}
for _, c in ipairs(ns.CATEGORIES) do ns.CAT_LABEL[c.id] = c.label end

function ns.CatLabel(id)
	return ns.CAT_LABEL[id] or tostring(id)
end
