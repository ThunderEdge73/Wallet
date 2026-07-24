---@meta

---@class Wallet.Currency: SMODS.GameObject
---@field key string
---@field font? string The key of the font used when displaying your currency amount.
---@field original_mod? Mod
---@field starting_amount? number How much of this currency you start a run with. Defaults to 0.
---@field colour? table The primary colour associated with this currency. Defaults to G.C.MONEY.
---@field decrease_colour? table The colour associated with decreases in this currency. Defaults to G.C.RED.
---@field sfx_key? string The string passed into play_sound whenever this currency's amount changes. Defaults to "coin1".
---@field echo_sfx_key? string The echo sound effect played during cashout. Defaults to "coin6".
---@field scoring_sfx_key? string The string passed into play_sound after this currency's amount changes as a result of calculation. Defaults to "coin3".
---@field currency_prefix? string The text that precedes the number whenever this currency is displayed. Defaults to "$".
---@field currency_suffix? string The text that follows the number whenever this currency is displayed. Defaults to "".
---@field currency_label? string A key in misc.dictionary for use with localizing this currency's label.
---@field pre_ease_func? fun(self: Wallet.Currency, mod: number, instant: boolean): number? Called before the amount of this currency changes. 
---@field post_ease_func? fun(self: Wallet.Currency, mod: number, instant: boolean) Called after the amount of this currency changes. Use `SMODS.calculate_context` inside this function to handle contexts that should trigger in response to changes in this currency.
---@field custom_ease_func? fun(self: Wallet.Currency, mod: number) [ADVANCED] Define this to manually control how this currency changes and the associated animations.
---@field generate_ease_text? fun(self: Wallet.Currency, mod: number): string
---@field no_ui? boolean [ADVANCED] If true, this currency's amount will not be displayed when hovering over your dollars. Use when you have a custom display UI for your currency.
---@field calc_cost? fun(self: Wallet.Currency, card: Card, base_cost: number): number? Called when calculating a card's cost. Return a number to set the card's cost to that number.
---@field cashout_always_number? boolean Whether or not this currency should display a numeric amount earned regardless of amount.

---@overload fun(self: Wallet.Currency): Wallet.Currency
Wallet.Currency = setmetatable({}, {
    __call = function(self)
        return self
    end
})

---@class SMODS.Joker
---@field calc_currency_bonus? fun(self: SMODS.Joker, card: Card): table?

---@class SMODS.Consumable
---@field calc_currency_bonus? fun(self: SMODS.Consumable, card: Card): table?

---@class SMODS.Back
---@field calc_currency_bonus? fun(self: SMODS.Back, back: Back): table?

---@class SMODS.Voucher
---@field calc_currency_bonus? fun(self: SMODS.Voucher, card: Card): table?

---@class SMODS.Blind
---@field calc_currency_bonus? fun(self: SMODS.Blind, blind: Blind): table?

---@class SMODS.Stake
---@field calc_currency_bonus? fun(self: SMODS.Stake): table?

---@class SMODS.Challenge
---@field calc_currency_bonus? fun(self: SMODS.Challenge): table?

---@class Mod
---@field calc_currency_bonus? fun(self: Mod, card: Card): table?