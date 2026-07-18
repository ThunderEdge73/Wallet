Wallet = {}

Wallet.ability_keys = {}
Wallet.ease_currency_funcs = {}

--#region Developer-facing Utils

function Wallet.mod_buffer(currency, amt)
	if not Wallet.Currencies[currency] then
		error("No currency exists with key " .. currency)
	end
	G.GAME[currency .. "_buffer"] = (G.GAME[currency .. "_buffer"] or 0) + amt
end

function Wallet.mod_dollars_buffer(amt)
	G.GAME.dollar_buffer = (G.GAME.dollar_buffer or 0) + amt
end

function Wallet.reset_buffer(currency)
	if not Wallet.Currencies[currency] then
		error("No currency exists with key " .. currency)
	end
	G.E_MANAGER:add_event(Event({
		func = function()
			G.GAME[currency .. "_buffer"] = 0
			return true
		end,
	}))
end

function Wallet.reset_dollars_buffer()
	G.E_MANAGER:add_event(Event({
		func = function()
			G.GAME.dollar_buffer = 0
			return true
		end,
	}))
end

function Wallet.reset_buffers(...)
	local currencies = { ... }
	for _, currency in ipairs(currencies) do
		if not Wallet.Currencies[currency] then
			error("No currency exists with key " .. currency)
		end
	end
	G.E_MANAGER:add_event(Event({
		func = function()
			for _, currency in ipairs(currencies) do
				if currency == "$" or currency == "dollars" then
					G.GAME.dollar_buffer = 0
				else
					G.GAME[currency .. "_buffer"] = 0
				end
				return true
			end
		end,
	}))
end

--#endregion

--#region Internals

function Wallet.populate_ability_keys(card, new_ability)
	for _, key in ipairs(Wallet.ability_keys) do
		new_ability[key.perma] = card.ability and card.ability[key.perma] or 0
	end
end

function Wallet.populate_loc_vars(card, vars)
	for _, key in ipairs(Wallet.ability_keys) do
		vars[key.bonus] = (card.ability[key.perma] or 0) ~= 0 and card.ability[key.perma] or nil
	end
end

---@type table<string, Wallet.Currency>
Wallet.Currencies = {}

---@param currency_obj Wallet.Currency
---@return fun(mod_amt: number, instant?: boolean)
local function create_ease_func(currency_obj)
	local key = currency_obj.key
	return function(mod_amt, instant)
		local function _mod(mod)
			if type(currency_obj.custom_ease_func) == "function" then
				currency_obj:custom_ease_func(mod)
			else
				local dollar_UI = G.HUD:get_UIE_by_ID("dollar_text_UI")
				mod = mod or 0
				local text = currency_obj:generate_ease_text(mod)
				local col = currency_obj.colour
				if mod < 0 then
					col = currency_obj.decrease_colour
				end
				G.GAME[key] = G.GAME[key] + mod
				check_for_unlock({ type = key })
				dollar_UI.config.object:update()
				G.HUD:recalculate()
				attention_text({
					text = text,
					scale = 0.8,
					hold = 0.7,
					cover = dollar_UI.parent,
					cover_colour = col,
					align = "cm",
					font = currency_obj.font and SMODS.Fonts[currency_obj.font],
				})
				play_sound(currency_obj.sfx_key)
			end
		end
		local during_calc = Wallet.ease_currency_calc
		local final_amt = currency_obj.pre_ease_func and currency_obj:pre_ease_func(mod_amt, instant) or mod_amt
		Wallet.ease_currency_calc = final_amt
		if instant then
			_mod(final_amt)
		else
			G.E_MANAGER:add_event(Event({
				trigger = "immediate",
				func = function()
					_mod(final_amt)
					return true
				end,
			}))
		end
		if currency_obj.post_ease_func and not during_calc then
			currency_obj:post_ease_func(final_amt, instant)
		end
	end
end

Wallet.Currency = SMODS.GameObject:extend({
	set = "wal_Currency",
	inject = function(self, i)
		Wallet.ability_keys[#Wallet.ability_keys + 1] = {
			perma = "perma_p_" .. self.key,
			bonus = "bonus_p_" .. self.key,
			ability = "p_" .. self.key,
			key = self.key,
		}
		Wallet.ability_keys[#Wallet.ability_keys + 1] = {
			perma = "perma_h_" .. self.key,
			bonus = "bonus_h_" .. self.key,
			ability = "h_" .. self.key,
			key = self.key,
		}

		SMODS.other_calculation_keys[#SMODS.other_calculation_keys + 1] = "p_" .. self.key
		SMODS.other_calculation_keys[#SMODS.other_calculation_keys + 1] = self.key
		SMODS.other_calculation_keys[#SMODS.other_calculation_keys + 1] = "h_" .. self.key

		SMODS.calculation_keys[#SMODS.calculation_keys + 1] = "p_" .. self.key
		SMODS.calculation_keys[#SMODS.calculation_keys + 1] = self.key
		SMODS.calculation_keys[#SMODS.calculation_keys + 1] = "h_" .. self.key
	end,
	register = function(self)
		if self.registered then
			sendWarnMessage(("Detected duplicate register call on object %s"):format(self.key), self.set)
			return
		end
		SMODS.GameObject.register(self)
		Wallet.ease_currency_funcs[self.key] = create_ease_func(self)
		_G["ease_" .. self.key] = function(mod, instant, ...)
			Wallet.ease_currency_funcs[self.key](mod, instant, ...)
		end
	end,
	required_params = {
		"key",
	},
	obj_buffer = {},
	obj_table = Wallet.Currencies,
	starting_amount = 0,
	generate_ease_text = function(self, amt)
		local ret = (amt >= 0 and "+" or "-") .. self.currency_prefix .. tostring(math.abs(amt)) .. self.currency_suffix
		if self.currency_label then
			ret = ret .. " " .. localize(self.currency_label)
		end
		return ret
	end,
	colour = G.C.MONEY,
	decrease_colour = G.C.RED,
	currency_prefix = "$",
	currency_suffix = "",
	sfx_key = "coin1",
	scoring_sfx_key = "coin3",
	currency_label = nil,
})

--#endregion

--#region Run Start

function Wallet.init_currencies()
	for key, currency in pairs(Wallet.Currencies) do
		-- in case this function is called more than once at start of run
		G.GAME[key] = G.GAME[key] or currency.starting_amount
		G.GAME[key .. "_buffer"] = 0
		G.GAME[key .. "_bankrupt_at"] = 0
	end
end

SMODS.current_mod.reset_game_globals = function(run_start)
	if run_start then
		Wallet.init_currencies()
	end
end

--#endregion

--#region Custom Currency Costs

function Wallet.has_custom_currency_cost(card)
	if not card then
		return false
	end
	return card.config.center.currency_cost and Wallet.Currencies[card.config.center.currency_cost]
end

function Wallet.get_custom_currency_cost(card)
	if not Wallet.has_custom_currency_cost(card) then
		return 0
	end
	return card[card.config.center.currency_cost .. "_cost"]
end

function Wallet.get_custom_currency_sell_cost(card)
	if not Wallet.has_custom_currency_cost(card) then
		return 0
	end
	return card[card.config.center.currency_cost .. "_sell_cost"]
end

local can_buy_hook = G.FUNCS.can_buy
function G.FUNCS.can_buy(e)
	can_buy_hook(e)
	local card = e.config.ref_table
	if Wallet.has_custom_currency_cost(card) then
		if
			(
				Wallet.get_custom_currency_cost(card)
				> G.GAME[card.config.center.currency_cost]
					- G.GAME[card.config.center.currency_cost .. "_bankrupt_at"]
			) and (Wallet.get_custom_currency_cost(card) > 0)
		then
			e.config.colour = G.C.UI.BACKGROUND_INACTIVE
			e.config.button = nil
		else
			e.config.colour = G.C.ORANGE
			e.config.button = "buy_from_shop"
		end
	end
end

local can_buy_and_use_hook = G.FUNCS.can_buy_and_use
function G.FUNCS.can_buy_and_use(e)
	can_buy_and_use_hook(e)
	local card = e.config.ref_table
	if Wallet.has_custom_currency_cost(card) then
		if
			(
				(
					Wallet.get_custom_currency_cost(card)
					> G.GAME[card.config.center.currency_cost]
						- G.GAME[card.config.center.currency_cost .. "_bankrupt_at"]
				) and (Wallet.get_custom_currency_cost(card) > 0)
			) or (not e.config.ref_table:can_use_consumeable())
		then
			e.UIBox.states.visible = false
			e.config.colour = G.C.UI.BACKGROUND_INACTIVE
			e.config.button = nil
		else
			if e.config.ref_table.highlighted then
				e.UIBox.states.visible = true
			end
			e.config.colour = G.C.SECONDARY_SET.Voucher
			e.config.button = "buy_from_shop"
		end
	end
end

local can_redeem_hook = G.FUNCS.can_redeem
function G.FUNCS.can_redeem(e)
	can_redeem_hook(e)
	local card = e.config.ref_table
	if Wallet.has_custom_currency_cost(card) then
		if
			(
				Wallet.get_custom_currency_cost(card)
				> G.GAME[card.config.center.currency_cost]
					- G.GAME[card.config.center.currency_cost .. "_bankrupt_at"]
			) and (Wallet.get_custom_currency_cost(card) > 0)
		then
			e.config.colour = G.C.UI.BACKGROUND_INACTIVE
			e.config.button = nil
		else
			e.config.colour = G.C.GREEN
			e.config.button = "use_card"
		end
	end
end

local can_open_hook = G.FUNCS.can_open
function G.FUNCS.can_open(e)
	can_open_hook(e)
	local card = e.config.ref_table
	if Wallet.has_custom_currency_cost(card) then
		if
			(
				Wallet.get_custom_currency_cost(card)
				> G.GAME[card.config.center.currency_cost]
					- G.GAME[card.config.center.currency_cost .. "_bankrupt_at"]
			) and (Wallet.get_custom_currency_cost(card) > 0)
		then
			e.config.colour = G.C.UI.BACKGROUND_INACTIVE
			e.config.button = nil
		else
			e.config.colour = G.C.GREEN
			e.config.button = "use_card"
		end
	end
end

local set_sell_value_hook = Card.set_sell_value
function Card:set_sell_value()
	set_sell_value_hook(self)
	if Wallet.has_custom_currency_cost(self) then
		self.sell_cost = 0
		self[self.config.center.currency_cost .. "_sell_cost"] = math.max(
			1,
			math.floor(self[self.config.center.currency_cost .. "_cost"] / 2)
		) + (self.ability[self.config.center.currency_cost .. "_extra_value"] or 0)
	end
end

local set_cost_value_hook = Card.set_cost_value
function Card:set_cost_value()
	set_cost_value_hook(self)
	if Wallet.has_custom_currency_cost(self) then
		local obj = Wallet.Currencies[self.config.center.currency_cost]
		self.cost = 0
		self[self.config.center.currency_cost .. "_cost"] = self.config.center.cost
		if obj.modify_cost then
			self[self.config.center.currency_cost .. "_cost"] = obj:modify_cost(self, self.config.center.cost)
				or self.config.center.cost
		end
	end
end

function Wallet.get_edition_extra_cost(card)
	if card.edition then
		for k, v in pairs(G.P_CENTER_POOLS.Edition) do
			if card.edition[v.key:sub(3)] then
				if v.extra_cost then
					return v.extra_cost
				end
			end
		end
	end
	return 0
end

function Wallet.generate_custom_sell_button(card)
	if not card.config.center.currency_cost or not Wallet.Currencies[card.config.center.currency_cost] then
		return
	end
	local obj = Wallet.Currencies[card.config.center.currency_cost]
	return {
		n = G.UIT.C,
		config = { align = "cr" },
		nodes = {
			{
				n = G.UIT.C,
				config = {
					ref_table = card,
					align = "cr",
					padding = 0.1,
					r = 0.08,
					minw = 1.25,
					hover = true,
					shadow = true,
					colour = G.C.UI.BACKGROUND_INACTIVE,
					one_press = true,
					button = "sell_card",
					func = "can_sell_card",
				},
				nodes = {
					{ n = G.UIT.B, config = { w = 0.1, h = 0.6 } },
					{
						n = G.UIT.C,
						config = { align = "tm" },
						nodes = {
							{
								n = G.UIT.R,
								config = { align = "cm", maxw = 1.25 },
								nodes = {
									{
										n = G.UIT.T,
										config = {
											text = localize("b_sell"),
											colour = G.C.UI.TEXT_LIGHT,
											scale = 0.4,
											shadow = true,
										},
									},
								},
							},
							{
								n = G.UIT.R,
								config = { align = "cm" },
								nodes = {
									obj.currency_prefix and {
										n = G.UIT.T,
										config = {
											text = obj.currency_prefix,
											colour = G.C.WHITE,
											scale = 0.4,
											shadow = true,
											font = obj.font and SMODS.Fonts[obj.font],
										},
									},
									{
										n = G.UIT.T,
										config = {
											ref_table = card,
											ref_value = "sell_cost_label",
											colour = G.C.WHITE,
											scale = 0.55,
											shadow = true,
										},
									},
									(obj.currency_suffix or obj.currency_label) and {
										n = G.UIT.T,
										config = {
											text = obj.currency_suffix
												.. (obj.currency_label and localize(obj.currency_label) or ""),
											colour = G.C.WHITE,
											scale = 0.4,
											shadow = true,
											font = obj.font and SMODS.Fonts[obj.font],
										},
									},
								},
							},
						},
					},
				},
			},
		},
	}
end

function Wallet.generate_custom_cost_display(card)
	if not card.config.center.currency_cost or not Wallet.Currencies[card.config.center.currency_cost] then
		return
	end
	local obj = Wallet.Currencies[card.config.center.currency_cost]
	local prefix = obj.currency_prefix
	local suffix = obj.currency_suffix
	if obj.currency_label then
		suffix = suffix .. " " .. localize(obj.currency_label)
	else
	end
	return {
		n = G.UIT.ROOT,
		config = {
			minw = 0.6,
			align = "tm",
			colour = darken(G.C.BLACK, 0.2),
			shadow = true,
			r = 0.05,
			padding = 0.05,
			minh = 1,
		},
		nodes = {
			{
				n = G.UIT.R,
				config = {
					align = "cm",
					colour = lighten(G.C.BLACK, 0.1),
					r = 0.1,
					minw = 1,
					minh = 0.55,
					emboss = 0.05,
					padding = 0.03,
				},
				nodes = {
					{
						n = G.UIT.O,
						config = {
							object = DynaText({
								string = {
									{
										prefix = prefix,
										ref_table = card,
										ref_value = card.config.center.currency_cost .. "_cost",
										suffix = suffix,
									},
								},
								colours = { obj.colour },
								shadow = true,
								silent = true,
								bump = true,
								pop_in = 0,
								scale = 0.5,
								font = obj.font and SMODS.Fonts[obj.font],
							}),
						},
					},
				},
			},
		},
	}
end

--#endregion

--#region Calculation

function Wallet.handle_ability_calc(ret, card)
	for _, key in ipairs(Wallet.ability_keys) do
		if (card.ability[key.perma] or 0) ~= 0 then
			Wallet.mod_buffer(key.key, card.ability[key.perma])
			ret.playing_card[key.key] = card.ability[key.perma]
			Wallet.reset_buffer(key.key)
		end
	end
end

local calc_individual_effect_hook = SMODS.calculate_individual_effect
function SMODS.calculate_individual_effect(effect, scored_card, key, amount, from_edition)
	local ret = calc_individual_effect_hook(effect, scored_card, key, amount, from_edition)
	for _, k in pairs(Wallet.Currency.obj_buffer) do
		local currency = Wallet.Currencies[k]
		if key == currency.key or key == "p_" .. currency.key or key == "h_" .. currency.key then
			if effect.card and effect.card ~= scored_card then
				juice_card(effect.card)
			end
			Wallet.ease_currency_funcs[currency.key](amount, effect.instant)
			local final_amt = Wallet.ease_currency_calc
			Wallet.ease_currency_calc = nil
			if not effect.remove_default_message then
				if effect.dollar_message then
					card_eval_status_text(
						effect.message_card or effect.juice_card or scored_card or effect.card or effect.focus,
						"extra",
						nil,
						percent,
						nil,
						effect.dollar_message,
						{
							font = currency.font,
						}
					)
				elseif final_amt ~= 0 then
					card_eval_status_text(
						effect.message_card or effect.juice_card or scored_card or effect.card or effect.focus,
						"extra",
						nil,
						percent,
						nil,
						{
							sound_override = currency.scoring_sfx_key,
							volume = 1,
							delay = 0.65,
							message = currency:generate_ease_text(final_amt),
							colour = final_amt >= 0 and currency.colour or currency.decrease_colour,
							font = currency.font,
						}
					)
				end
			end
			if currency.post_ease_func then
				currency:post_ease_func(final_amt)
			end
			return true
		end
	end
	return ret
end

--#endregion

--#region UI

function Wallet.currency_uidef(key)
	local obj = Wallet.Currencies[key]
	local scale = 0.4
	local spacing = 0.13
	local temp_col = G.C.DYN_UI.BOSS_MAIN
	local temp_col2 = G.C.DYN_UI.BOSS_DARK
	local prefix = obj.currency_prefix
	local suffix = obj.currency_suffix
	if obj.currency_label then
		suffix = suffix .. " " .. localize(obj.currency_label)
	end
	return {
		n = G.UIT.R,
		config = { align = "cm" },
		nodes = {
			{
				n = G.UIT.C,
				config = {
					align = "cm",
					padding = 0.05,
					minw = 1.45 * 2 + spacing,
					minh = 1.15,
					colour = temp_col,
					emboss = 0.05,
					r = 0.1,
					id = key .. "_text_UI",
				},
				nodes = {
					{
						n = G.UIT.R,
						config = { align = "cm" },
						nodes = {
							{
								n = G.UIT.C,
								config = {
									align = "cm",
									r = 0.1,
									minw = 1.28 * 2 + spacing,
									minh = 1,
									colour = temp_col2,
								},
								nodes = {
									{
										n = G.UIT.O,
										config = {
											object = DynaText({
												string = {
													{
														ref_table = G.GAME,
														ref_value = key,
														prefix = prefix,
														suffix = suffix,
													},
												},
												scale_function = function()
													return scale_number(G.GAME[key], 2.2 * scale, 99999, 1000000)
												end,
												maxw = 1.35,
												colours = { obj.colour },
												font = obj.font and SMODS.Fonts[obj.font] or G.LANGUAGES["en-us"].font,
												shadow = true,
												spacing = 2,
												bump = true,
												scale = 2.2 * scale,
											}),
										},
									},
								},
							},
						},
					},
				},
			},
		},
	}
end

function Wallet.generate_currency_hover_UIBox()
	local collision_obj = G.HUD:get_UIE_by_ID("dollar_text_UI").parent.parent.parent
	local lines = {}
	for _, key in ipairs(Wallet.Currency.obj_buffer) do
		if not Wallet.Currencies[key].no_ui then
			lines[#lines + 1] = Wallet.currency_uidef(key)
		end
	end
	local temp_box = UIBox({
		definition = {
			n = G.UIT.ROOT,
			config = { align = "cm", padding = 0.05, colour = G.C.CLEAR },
			nodes = lines,
		},
		config = {},
	})
	local h = temp_box.T.h
	local maxh = 6.5
	local scroll_box = SMODS.UIScrollBox({
		content = {
			definition = {
				n = G.UIT.ROOT,
				config = { colour = G.C.CLEAR },
				nodes = {
					{
						n = G.UIT.O,
						config = {
							object = temp_box,
						},
					},
				},
			},
			config = { align = "cm" },
		},
		overflow = {
			node_config = {
				align = "tm",
				maxh = maxh,
			},
		},
		sync_mode = "offset",
		scroll_move = function(self, dt)
			self._counter = (self._counter or 0) + G.real_dt
			local scroll_velocity = SMODS.wheel_velocity.y * 1.5 / G.TILESIZE
			local percent = (self.scroll_offset.y - scroll_velocity) / (h - maxh)
			percent = math.max(0, math.min(1, percent))
			if G.CONTROLLER.HID.controller then
				local clamped =
					math.max(0, math.min(h - maxh, math.fmod(self._counter, 2 * (h - maxh)) - (h - maxh) / 2))
				self.scroll_offset.y = clamped
			elseif collision_obj and collision_obj:collides_with_point(G.CURSOR.T) then
				self.scroll_offset.y = percent * (h - maxh)
			end
		end,
	})
	local scrollbar = h > maxh
			and {
				n = G.UIT.C,
				config = { padding = 0.05 },
				nodes = {
					SMODS.GUI.scrollbar({
						w = 0.2,
						h = maxh - 0.1,
						ref_table = scroll_box.scroll_offset,
						ref_value = "y",
						max = temp_box.T.h - maxh,
						min = 0,
						colour = G.C.FILTER,
						bg_colour = { 0, 0, 0, 0.1 },
						ui_type = G.UIT.R,
					}),
				},
			}
		or nil
	return {
		n = G.UIT.ROOT,
		config = { align = "cm", colour = lighten(G.C.JOKER_GREY, 0.5), r = 0.1, emboss = 0.05, padding = 0.05 },
		nodes = {
			{
				n = G.UIT.R,
				config = {
					align = "cm",
					emboss = 0.05,
					r = 0.1,
					minw = 2.5,
					padding = 0.05,
					colour = lighten(G.C.BLACK, 0.2),
				},
				nodes = {
					{
						n = G.UIT.C,
						nodes = { { n = G.UIT.O, config = { object = h > maxh and scroll_box or temp_box } } },
					},
					scrollbar,
				},
			},
		},
	}
end

local update_hook = Game.update
function Game:update(dt, ...)
	update_hook(self, dt, ...)
	if G.HUD then
		local collides = G.HUD:get_UIE_by_ID("dollar_text_UI").parent.parent.parent:collides_with_point(G.CURSOR.T)
		if collides and not G.wal_money_info and not G.SETTINGS.paused then
			local should_show_ui = false
			for _, key in ipairs(Wallet.Currency.obj_buffer) do
				if not Wallet.Currencies[key].no_ui then
					should_show_ui = true
					break
				end
			end
			if should_show_ui then
				G.wal_money_info = UIBox({
					definition = Wallet.generate_currency_hover_UIBox(),
					config = {
						major = G.HUD:get_UIE_by_ID("dollar_text_UI").parent.parent.parent,
						align = "tm",
						offset = { x = 0, y = -0.15 },
					},
					instance_type = "CARD",
				})
			end
		elseif G.wal_money_info and (not collides or G.SETTINGS.paused) then
			G.wal_money_info:remove()
			G.wal_money_info = nil
		end
	end
end

local localize_bonuses_hook = SMODS.localize_perma_bonuses
function SMODS.localize_perma_bonuses(specific_vars, desc_nodes, ...)
	localize_bonuses_hook(specific_vars, desc_nodes, ...)
	for _, key in ipairs(Wallet.ability_keys) do
		if specific_vars and specific_vars[key.bonus] then
			localize({
				type = "other",
				key = key.ability,
				nodes = desc_nodes,
				vars = { Wallet.Currencies[key.key]:generate_ease_text(specific_vars[key.bonus]) },
			})
		end
	end
end

--#endregion

--#region Cashout

-- Wallet.cashout_currency_amts = {}

-- function Wallet.add_to_cashout(key, amt)
-- 	local entry = {
-- 		key = key,
-- 		amt = amt,
-- 	}
-- 	local found = false
-- 	for _, currency in ipairs(Wallet.cashout_currency_amts) do
-- 		if currency.key == key then
-- 			currency.amt = currency.amt + amt
-- 			found = true
-- 			break
-- 		end
-- 	end
-- 	if not found then
-- 		Wallet.cashout_currency_amts[#Wallet.cashout_currency_amts + 1] = entry
-- 	end
-- end

-- function Wallet.calc_currency_bonus(obj)
-- 	if not type(obj.calc_currency_bonus) == "function" then
-- 		return
-- 	end
-- 	local res = obj:calc_currency_bonus()
-- 	for _, key in ipairs(Wallet.Currency.obj_buffer) do
-- 		if res[key] then
-- 		end
-- 	end
-- end
