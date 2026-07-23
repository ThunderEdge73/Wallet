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
	echo_sfx_key = "coin6",
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
				> (
					G.GAME[card.config.center.currency_cost]
					- G.GAME[card.config.center.currency_cost .. "_bankrupt_at"]
				)
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

local card_save_hook = Card.save
function Card:save(...)
	local ret = card_save_hook(self, ...)
	if Wallet.has_custom_currency_cost(self) then
		ret["custom_currency_cost"] = Wallet.get_custom_currency_cost(self)
		ret["custom_currency_sell_cost"] = Wallet.get_custom_currency_sell_cost(self)
		ret["custom_currency_extra_value"] = self.ability[self.config.center.currency_cost .. "_extra_value"] or 0
	end
	return ret
end

local card_load_hook = Card.load
function Card:load(cardTable, other_card, ...)
	local ret = card_load_hook(self, cardTable, other_card, ...)
	if Wallet.has_custom_currency_cost(self) then
		self[self.config.center.currency_cost .. "_cost"] = cardTable.custom_currency_cost
		self[self.config.center.currency_cost .. "_sell_cost"] = cardTable.custom_currency_sell_cost
		self[self.config.center.currency_cost .. "_extra_value"] = cardTable.custom_currency_extra_value
	end
	return ret
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
function SMODS.calculate_individual_effect(effect, scored_card, key, amount, from_edition, ...)
	local ret = calc_individual_effect_hook(effect, scored_card, key, amount, from_edition, ...)
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

Wallet.cashout_currency_amts = {}

local get_mods_scoring_targets_hook = SMODS.get_mods_scoring_targets
function SMODS.get_mods_scoring_targets(_context, ...)
	local ret = get_mods_scoring_targets_hook(_context, ...)
	if _context == "calc_dollar_bonus" then
		ret = SMODS.merge_lists({ ret, SMODS.get_mods_scoring_targets("calc_currency_bonus", ...) })
	end
	return ret
end

local get_stake_scoring_targets_hook = SMODS.get_stake_scoring_targets
function SMODS.get_stake_scoring_targets(_context, ...)
	local ret = get_stake_scoring_targets_hook(_context, ...)
	if _context == "calc_dollar_bonus" then
		ret = SMODS.merge_lists({ ret, SMODS.get_stake_scoring_targets_hook("calc_currency_bonus", ...) })
	end
	return ret
end

function Wallet.add_to_cashout(key, amt)
	local entry = {
		key = key,
		amt = amt,
	}
	local found = false
	for _, currency in ipairs(Wallet.cashout_currency_amts) do
		if currency.key == key then
			currency.amt = currency.amt + amt
			found = true
			break
		end
	end
	if not found then
		Wallet.cashout_currency_amts[#Wallet.cashout_currency_amts + 1] = entry
	end
end

function Wallet.process_cashout()
	for _, entry in ipairs(Wallet.cashout_currency_amts) do
		Wallet.ease_currency_funcs[entry.key](entry.amt)
	end
end

function Card:calc_currency_bonus()
	if not self:can_calculate() then
		return
	end
	local obj = self.config.center
	if obj.calc_currency_bonus and type(obj.calc_currency_bonus) == "function" then
		return obj:calc_currency_bonus(self)
	end
end

function Blind:calc_currency_bonus()
	local obj = self.config.center
	if obj.calc_currency_bonus and type(obj.calc_currency_bonus) == "function" then
		return obj:calc_currency_bonus(self)
	end
end

function Back:calc_currency_bonus()
	local obj = self.config.center
	if obj.calc_currency_bonus and type(obj.calc_currency_bonus) == "function" then
		return obj:calc_currency_bonus(self)
	end
end

function Wallet.calc_currency_bonus(obj, i, pitch)
	local n = i
	local current_pitch = pitch
	if type(obj.calc_currency_bonus) ~= "function" then
		return n, current_pitch
	end
	local res = obj:calc_currency_bonus()
	if res then
		if obj.is and obj:is(Card) then
			for _, key in ipairs(Wallet.Currency.obj_buffer) do
				if res[key] then
					local amt = type(res[key]) == "number" and res[key] or res[key][1]
					local res_args = type(res[key]) == "number" and {} or res[key][2]
					if not res_args.no_eval_row then
						n = n + 1
						Wallet.add_custom_round_eval_row({
							currency_key = key,
							dollars = amt,
							bonus = true,
							name = "joker" .. n,
							pitch = current_pitch,
							card = obj,
							loc_opts = res_args or {},
						})
						current_pitch = current_pitch + 0.06
					end
					Wallet.add_to_cashout(amt)
				end
			end
		else
			for _, key in ipairs(Wallet.Currency.obj_buffer) do
				if res[key] then
					local amt = type(res[key]) == "number" and res[key] or res[key][1]
					local res_args = type(res[key]) == "number" and {} or res[key][2]
					if not res_args.no_eval_row then
						if res_args.text then
							name = res_args.text
						elseif (res_args.set or obj.set) and (res_args.key or obj.key) then
							if res_args.set == "Challenge" or (not res_args.set and obj.set == "Challenge") then
								name = localize(res_args.key or obj.key, "challenge_names")
							elseif
								(res_args.set == "Mod" or (not res_args.set and obj.set == "Mod"))
								and not (G.localization.descriptions.Mod or {})[res_args.key or obj.key]
							then
								name = (SMODS.Mods[res_args.key or obj.key] or {}).name
							else
								name = localize({
									type = "name_text",
									set = res_args.set or obj.set,
									key = res_args.key or obj.key,
								})
							end
						end
						n = n + 1
						Wallet.add_custom_round_eval_row({
							dollars = amt,
							bonus = true,
							name = "custom_individual" .. n,
							pitch = pitch,
							text_colour = res_args.text_colour or G.C.FILTER,
							text = name or "ERROR",
							text_scale = res_args.scale or 0.6,
							currency_key = key,
						})
						current_pitch = current_pitch + 0.06
					end
					Wallet.add_to_cashout(key, amt)
				end
			end
		end
	end
	return n, current_pitch
end

local round_eval_row_hook = add_round_eval_row
function add_round_eval_row(config, ...)
	if config.currency_key and Wallet.Currencies[config.currency_key] then
		Wallet.add_custom_round_eval_row(config)
	else
		round_eval_row_hook(config, ...)
	end
end

function Wallet.add_custom_round_eval_row(config)
	local config = config or {}
	if not config.currency_key then
		error("No custom currency")
	end
	local currency_obj = Wallet.Currencies[config.currency_key]
	local width = G.round_eval.T.w - 0.51
	local num_dollars = config.dollars or 1
	local scale = 0.9

	if config.name ~= "bottom" then
		total_cashout_rows = (total_cashout_rows or 0) + 1
		if total_cashout_rows > 7 then
			return
		end
		if config.name ~= "blind1" then
			if not G.round_eval.divider_added then
				G.E_MANAGER:add_event(Event({
					trigger = "after",
					delay = 0.25,
					func = function()
						local spacer = {
							n = G.UIT.R,
							config = { align = "cm", minw = width },
							nodes = {
								{
									n = G.UIT.O,
									config = {
										object = DynaText({
											string = { "......................................" },
											colours = { G.C.WHITE },
											shadow = true,
											float = true,
											y_offset = -30,
											scale = 0.45,
											spacing = 13.5,
											font = G.LANGUAGES["en-us"].font,
											pop_in = 0,
										}),
									},
								},
							},
						}
						G.round_eval:add_child(
							spacer,
							G.round_eval:get_UIE_by_ID(config.bonus and "bonus_round_eval" or "base_round_eval")
						)
						return true
					end,
				}))
				delay(0.6)
				G.round_eval.divider_added = true
			end
		else
			delay(0.2)
		end

		delay(0.2)

		G.E_MANAGER:add_event(Event({
			trigger = "before",
			delay = 0.5,
			func = function()
				--Add the far left text and context first:
				local left_text = {}
				if config.name == "blind1" then
					local stake_sprite = get_stake_sprite(G.GAME.stake or 1, 0.5)
					local obj = G.GAME.blind.config.blind
					local blind_sprite =
						SMODS.create_sprite(0, 0, 1.2, 1.2, obj.atlas or "blind_chips", copy_table(G.GAME.blind.pos))
					blind_sprite:define_draw_steps({
						{ shader = "dissolve", shadow_height = 0.05 },
						{ shader = "dissolve" },
					})
					table.insert(left_text, {
						n = G.UIT.O,
						config = {
							w = 1.2,
							h = 1.2,
							object = blind_sprite,
							hover = true,
							can_collide = false,
						},
					})

					table.insert(left_text, config.saved and {
						n = G.UIT.C,
						config = { padding = 0.05, align = "cm" },
						nodes = {
							{
								n = G.UIT.R,
								config = { align = "cm" },
								nodes = {
									{
										n = G.UIT.O,
										config = {
											object = DynaText({
												string = {
													" "
														.. (type(G.GAME.saved_text) == "string" and (G.localization.misc.dictionary[G.GAME.saved_text] and localize(
															G.GAME.saved_text
														) or G.GAME.saved_text) or localize("ph_mr_bones"))
														.. " ",
												},
												colours = { G.C.FILTER },
												shadow = true,
												pop_in = 0,
												scale = 0.5 * scale,
												silent = true,
											}),
										},
									},
								},
							},
						},
					} or {
						n = G.UIT.C,
						config = { padding = 0.05, align = "cm" },
						nodes = {
							{
								n = G.UIT.R,
								config = { align = "cm" },
								nodes = {
									{
										n = G.UIT.O,
										config = {
											object = DynaText({
												string = { " " .. localize("ph_score_at_least") .. " " },
												colours = { G.C.UI.TEXT_LIGHT },
												shadow = true,
												pop_in = 0,
												scale = 0.4 * scale,
												silent = true,
											}),
										},
									},
								},
							},
							{
								n = G.UIT.R,
								config = { align = "cm", minh = 0.8 },
								nodes = {
									{
										n = G.UIT.O,
										config = {
											w = 0.5,
											h = 0.5,
											object = stake_sprite,
											hover = true,
											can_collide = false,
										},
									},
									{
										n = G.UIT.T,
										config = {
											text = G.GAME.blind.chip_text,
											scale = scale_number(G.GAME.blind.chips, scale, 100000),
											colour = G.C.RED,
											shadow = true,
										},
									},
								},
							},
						},
					})
				elseif string.find(config.name, "tag") then
					local blind_sprite = SMODS.create_sprite(0, 0, 0.7, 0.7, "tags", copy_table(config.pos))
					blind_sprite:define_draw_steps({
						{ shader = "dissolve", shadow_height = 0.05 },
						{ shader = "dissolve" },
					})
					blind_sprite:juice_up()
					table.insert(left_text, {
						n = G.UIT.O,
						config = {
							w = 0.7,
							h = 0.7,
							object = blind_sprite,
							hover = true,
							can_collide = false,
						},
					})
					table.insert(left_text, {
						n = G.UIT.O,
						config = {
							object = DynaText({
								string = { config.condition },
								colours = { G.C.UI.TEXT_LIGHT },
								shadow = true,
								pop_in = 0,
								scale = 0.4 * scale,
								silent = true,
							}),
						},
					})
				elseif config.name == "hands" then
					table.insert(left_text, {
						n = G.UIT.T,
						config = {
							text = config.disp or config.dollars,
							scale = 0.8 * scale,
							colour = G.C.BLUE,
							shadow = true,
							juice = true,
						},
					})
					table.insert(left_text, {
						n = G.UIT.O,
						config = {
							object = DynaText({
								string = {
									" " .. localize({
										type = "variable",
										key = "remaining_hand_money",
										vars = { G.GAME.modifiers.money_per_hand or 1 },
									}),
								},
								colours = { G.C.UI.TEXT_LIGHT },
								shadow = true,
								pop_in = 0,
								scale = 0.4 * scale,
								silent = true,
							}),
						},
					})
				elseif config.name == "discards" then
					table.insert(left_text, {
						n = G.UIT.T,
						config = {
							text = config.disp or config.dollars,
							scale = 0.8 * scale,
							colour = G.C.RED,
							shadow = true,
							juice = true,
						},
					})
					table.insert(left_text, {
						n = G.UIT.O,
						config = {
							object = DynaText({
								string = {
									" " .. localize({
										type = "variable",
										key = "remaining_discard_money",
										vars = { G.GAME.modifiers.money_per_discard or 0 },
									}),
								},
								colours = { G.C.UI.TEXT_LIGHT },
								shadow = true,
								pop_in = 0,
								scale = 0.4 * scale,
								silent = true,
							}),
						},
					})
				elseif string.find(config.name, "custom") then
					if config.number then
						table.insert(left_text, {
							n = G.UIT.T,
							config = {
								text = config.number,
								scale = config.number_scale or (0.8 * scale),
								colour = config.number_colour or G.C.FILTER,
								shadow = true,
								juice = true,
							},
						})
					end
					table.insert(left_text, {
						n = G.UIT.O,
						config = {
							object = DynaText({
								string = { "" .. config.text },
								colours = { config.text_colour or G.C.UI.TEXT_LIGHT },
								shadow = true,
								pop_in = 0,
								scale = config.text_scale or (0.4 * scale),
								silent = true,
							}),
						},
					})
				elseif string.find(config.name, "joker") then
					local loc_opts = config.loc_opts or {}
					local vars = loc_opts.vars
					if not vars and type(config.card.config.center.loc_vars) == "function" then
						local res = config.card.config.center:loc_vars({}, config.card)
						vars = res.name_vars or res.vars or {}
					end
					table.insert(left_text, {
						n = G.UIT.O,
						config = {
							object = DynaText({
								string = loc_opts.text or localize({
									type = "name_text",
									set = loc_opts.set or config.card.config.center.set,
									key = loc_opts.key or config.card.config.center.key,
									vars = vars,
								}),
								colours = { loc_opts.text_colour or G.C.FILTER },
								shadow = true,
								pop_in = 0,
								scale = (loc_opts.scale or 0.6) * scale,
								silent = true,
							}),
						},
					})
				elseif config.name == "interest" then
					table.insert(left_text, {
						n = G.UIT.T,
						config = {
							text = num_dollars,
							scale = 0.8 * scale,
							colour = G.C.MONEY,
							shadow = true,
							juice = true,
						},
					})
					table.insert(left_text, {
						n = G.UIT.O,
						config = {
							object = DynaText({
								string = {
									" " .. localize({
										type = "variable",
										key = "interest",
										vars = {
											G.GAME.interest_amount,
											5,
											G.GAME.interest_amount * G.GAME.interest_cap / 5,
										},
									}),
								},
								colours = { G.C.UI.TEXT_LIGHT },
								shadow = true,
								pop_in = 0,
								scale = 0.4 * scale,
								silent = true,
							}),
						},
					})
				end
				local full_row = {
					n = G.UIT.R,
					config = { align = "cm", minw = 5 },
					nodes = {
						{
							n = G.UIT.C,
							config = { padding = 0.05, minw = width * 0.55, minh = 0.61, align = "cl" },
							nodes = left_text,
						},
						{
							n = G.UIT.C,
							config = { padding = 0.05, minw = width * 0.45, align = "cr" },
							nodes = {
								{ n = G.UIT.C, config = { align = "cm", id = "dollar_" .. config.name }, nodes = {} },
							},
						},
					},
				}

				if config.name == "blind1" then
					G.GAME.blind:juice_up()
				end
				G.round_eval:add_child(
					full_row,
					G.round_eval:get_UIE_by_ID(config.bonus and "bonus_round_eval" or "base_round_eval")
				)
				play_sound("cancel", config.pitch or 1)
				play_sound("highlight1", (1.5 * config.pitch) or 1, 0.2)
				if config.card then
					config.card:juice_up(0.7, 0.46)
				end
				return true
			end,
		}))
		local dollar_row = 0
		if num_dollars > 60 or num_dollars < -60 or currency_obj.currency_label then
			if num_dollars < 0 then --if negative
				G.E_MANAGER:add_event(Event({
					trigger = "before",
					delay = 0.38,
					func = function()
						G.round_eval:add_child({
							n = G.UIT.R,
							config = { align = "cm", id = "dollar_row_" .. (dollar_row + 1) .. "_" .. config.name },
							nodes = {
								{
									n = G.UIT.O,
									config = {
										object = DynaText({
											string = { currency_obj.generate_ease_text(num_dollars) },
											colours = { currency_obj.decrease_colour },
											shadow = true,
											pop_in = 0,
											scale = 0.65,
											float = true,
											font = currency_obj.font and SMODS.Fonts[currency_obj.font],
										}),
									},
								},
							},
						}, G.round_eval:get_UIE_by_ID("dollar_" .. config.name))
						play_sound(currency_obj.scoring_sfx_key, 0.9 + 0.2 * math.random(), 0.7)
						play_sound(currency_obj.echo_sfx_key, 1.3, 0.8)
						return true
					end,
				}))
			else --if positive
				G.E_MANAGER:add_event(Event({
					trigger = "before",
					delay = 0.38,
					func = function()
						G.round_eval:add_child({
							n = G.UIT.R,
							config = { align = "cm", id = "dollar_row_" .. (dollar_row + 1) .. "_" .. config.name },
							nodes = {
								{
									n = G.UIT.O,
									config = {
										object = DynaText({
											string = { currency_obj.generate_ease_text(num_dollars) },
											colours = { currency_obj.colour },
											shadow = true,
											pop_in = 0,
											scale = 0.65,
											float = true,
											font = currency_obj.font and SMODS.Fonts[currency_obj.font],
										}),
									},
								},
							},
						}, G.round_eval:get_UIE_by_ID("dollar_" .. config.name))

						play_sound(currency_obj.scoring_sfx_key, 0.9 + 0.2 * math.random(), 0.7)
						play_sound(currency_obj.echo_sfx_key, 1.3, 0.8)
						return true
					end,
				}))
				--asdf
			end
		else
			local dollars_to_loop
			if num_dollars < 0 then
				dollars_to_loop = (num_dollars * -1) + 1
			else
				dollars_to_loop = num_dollars
			end
			for i = 1, dollars_to_loop do
				G.E_MANAGER:add_event(Event({
					trigger = "before",
					delay = 0.18 - ((num_dollars > 20 and 0.13) or (num_dollars > 9 and 0.1) or 0),
					func = function()
						if i % 30 == 1 then
							G.round_eval:add_child({
								n = G.UIT.R,
								config = {
									align = "cm",
									id = "dollar_row_" .. (dollar_row + 1) .. "_" .. config.name,
								},
								nodes = {},
							}, G.round_eval:get_UIE_by_ID("dollar_" .. config.name))
							dollar_row = dollar_row + 1
						end

						local r
						if i == 1 and num_dollars < 0 then
							r = {
								n = G.UIT.T,
								config = {
									text = "-",
									colour = currency_obj.decrease_colour,
									scale = ((num_dollars < -20 and 0.28) or (num_dollars < -9 and 0.43) or 0.58),
									shadow = true,
									hover = true,
									can_collide = false,
									juice = true,
								},
							}
							play_sound(
								currency_obj.scoring_sfx_key,
								0.9 + 0.2 * math.random(),
								0.7 - (num_dollars < -20 and 0.2 or 0)
							)
						else
							if num_dollars < 0 then
								r = {
									n = G.UIT.T,
									config = {
										text = (currency_obj.currency_prefix or "") ~= ""
												and currency_obj.currency_prefix
											or currency_obj.currency_suffix,
										colour = currency_obj.decrease_colour,
										scale = ((num_dollars > 20 and 0.28) or (num_dollars > 9 and 0.43) or 0.58),
										shadow = true,
										hover = true,
										can_collide = false,
										juice = true,
										font = currency_obj.font and SMODS.Fonts[currency_obj.font],
									},
								}
							else
								r = {
									n = G.UIT.T,
									config = {
										text = (currency_obj.currency_prefix or "") ~= ""
												and currency_obj.currency_prefix
											or currency_obj.currency_suffix,
										colour = currency_obj.colour,
										scale = ((num_dollars > 20 and 0.28) or (num_dollars > 9 and 0.43) or 0.58),
										shadow = true,
										hover = true,
										can_collide = false,
										juice = true,
										font = currency_obj.font and SMODS.Fonts[currency_obj.font],
									},
								}
							end
						end
						play_sound(
							currency_obj.scoring_sfx_key,
							0.9 + 0.2 * math.random(),
							0.7 - (num_dollars > 20 and 0.2 or 0)
						)

						if config.name == "blind1" then
							G.GAME.current_round.dollars_to_be_earned = G.GAME.current_round.dollars_to_be_earned:sub(2)
						end

						G.round_eval:add_child(
							r,
							G.round_eval:get_UIE_by_ID("dollar_row_" .. dollar_row .. "_" .. config.name)
						)
						G.VIBRATION = G.VIBRATION + 0.4
						return true
					end,
				}))
			end
		end
	else
		delay(0.4)
		G.E_MANAGER:add_event(Event({
			trigger = "before",
			delay = 0.5,
			func = function()
				UIBox({
					definition = {
						n = G.UIT.ROOT,
						config = { align = "cm", colour = G.C.CLEAR },
						nodes = {
							{
								n = G.UIT.R,
								config = {
									id = "cash_out_button",
									align = "cm",
									padding = 0.1,
									minw = 7,
									r = 0.15,
									colour = G.C.ORANGE,
									shadow = true,
									hover = true,
									one_press = true,
									button = "cash_out",
									focus_args = { snap_to = true },
								},
								nodes = {
									{
										n = G.UIT.T,
										config = {
											text = localize("b_cash_out") .. ": ",
											scale = 1,
											colour = G.C.UI.TEXT_LIGHT,
											shadow = true,
										},
									},
									{
										n = G.UIT.T,
										config = {
											text = localize("$") .. format_ui_value(config.dollars),
											scale = 1.2 * scale,
											colour = G.C.WHITE,
											shadow = true,
											juice = true,
										},
									},
								},
							},
						},
					},
					config = {
						align = "tmi",
						offset = { x = 0, y = 0.4 },
						major = G.round_eval,
					},
				})

				--local left_text = {n=G.UIT.R, config={id = 'cash_out_button', align = "cm", padding = 0.1, minw = 2, r = 0.15, colour = G.C.ORANGE, shadow = true, hover = true, one_press = true, button = 'cash_out', focus_args = {snap_to = true}}, nodes={
				--    {n=G.UIT.T, config={text = localize('b_cash_out')..": ", scale = 1, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
				--    {n=G.UIT.T, config={text = localize('$')..format_ui_value(config.dollars), scale = 1.3*scale, colour = G.C.WHITE, shadow = true, juice = true}}
				--}}
				--G.round_eval:add_child(left_text,G.round_eval:get_UIE_by_ID('eval_bottom'))

				G.GAME.current_round.dollars = config.dollars

				play_sound(currency_obj.echo_sfx_key, config.pitch or 1)
				G.VIBRATION = G.VIBRATION + 1
				return true
			end,
		}))
	end
end
