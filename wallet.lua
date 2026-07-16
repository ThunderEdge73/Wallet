Wallet = {}

Wallet.ability_keys = {}
Wallet.ease_currency_funcs = {}

-- for convenience
function Wallet.hook_currency_ease_func(key, before_func, after_func)
	if not Wallet.ease_currency_funcs[key] then
		error("Cannot find function to hook")
	end
	local ease_func_hook = Wallet.ease_currency_funcs[key]
	Wallet.ease_currency_funcs[key] = function(mod, instant, ...)
		local new_mod = mod
		if before_func then
			new_mod = before_func(mod, instant, ...)
		end
		ease_func_hook(new_mod, instant, ...)
		if after_func then
			after_func(new_mod, instant, ...)
		end
	end
end

function Wallet.mod_buffer(currency, amt)
	if currency == nil or currency == "$" or currency == "dollars" then
		G.GAME.dollar_buffer = (G.GAME.dollar_buffer or 0) + amt
	else
		G.GAME[currency .. "_buffer"] = (G.GAME[currency .. "_buffer"] or 0) + amt
	end
end

function Wallet.reset_buffer(currency)
	G.E_MANAGER:add_event(Event({
		func = function()
			if currency == nil or currency == "$" or currency == "dollars" then
				G.GAME.dollar_buffer = 0
			else
				G.GAME[currency .. "_buffer"] = 0
			end
			return true
		end,
	}))
end

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

function Wallet.handle_ability_calc(ret, card)
	for _, key in ipairs(Wallet.ability_keys) do
		if (card.ability[key.perma] or 0) ~= 0 then
			Wallet.mod_buffer(key.key, card.ability[key.perma])
			ret.playing_card[key.key] = card.ability[key.perma]
			Wallet.reset_buffer(key.key)
		end
	end
end

---@type table<string, Wallet.Currency>
Wallet.Currencies = {}

---@param currency_obj Wallet.Currency
---@return function
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
			currency_obj:post_ease_func(final_amt)
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
		return (amt >= 0 and "+" or "-") .. self.currency_prefix .. tostring(math.abs(amt)) .. self.currency_suffix
	end,
	colour = G.C.MONEY,
	decrease_colour = G.C.RED,
	currency_prefix = "$",
	currency_suffix = "",
	sfx_key = "coin1",
	scoring_sfx_key = "coin3",
})

function Wallet.init_currencies()
	for key, currency in pairs(Wallet.Currencies) do
		-- in case this function is called more than once at start of run
		G.GAME[key] = G.GAME[key] or currency.starting_amount
		G.GAME[key .. "_buffer"] = 0
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

function Wallet.currency_uidef(key)
	local obj = Wallet.Currencies[key]
	local scale = 0.4
	local spacing = 0.13
	local temp_col = G.C.DYN_UI.BOSS_MAIN
	local temp_col2 = G.C.DYN_UI.BOSS_DARK
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
														prefix = obj.currency_prefix,
														suffix = obj.currency_suffix,
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
			G.wal_money_info = UIBox({
				definition = Wallet.generate_currency_hover_UIBox(),
				config = {
					major = G.HUD:get_UIE_by_ID("dollar_text_UI").parent.parent.parent,
					align = "tm",
					offset = { x = 0, y = -0.15 },
				},
				instance_type = "CARD",
			})
		elseif G.wal_money_info and (not collides or G.SETTINGS.paused) then
			G.wal_money_info:remove()
			G.wal_money_info = nil
		end
	end
end

SMODS.current_mod.reset_game_globals = function(run_start)
	if run_start then
		Wallet.init_currencies()
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
