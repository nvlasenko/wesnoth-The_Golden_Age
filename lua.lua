--! #textdomain "wesnoth-loti"
local _ = wesnoth.textdomain "wesnoth-loti"

local helper = wesnoth.require "lua/helper.lua"

local _ = wesnoth.textdomain "wesnoth-loti"
local old_unit_status = wesnoth.theme_items.unit_status
function wesnoth.theme_items.unit_status()
local u = wesnoth.get_displayed_unit()
if not u then return {} end
local s = old_unit_status()
if u.status.incinerated then
 table.insert(s, { "element", {
     image = "misc/incinerated.png",
     tooltip = "in flames: This unit is in flames. It will lose 12 HP per turn, unless cured by a healer, by standing on a village or by standing in water."
 } })
end
return s
end


                 local _ = wesnoth.textdomain "wesnoth-units"
                 local old_unit_status = wesnoth.theme_items.unit_status
                 function wesnoth.theme_items.unit_status()
                     local u = wesnoth.get_displayed_unit()
                     if not u then return {} end
                     local s = old_unit_status()
                     if u.status.paralyzed then
                         table.insert(s, { "element", {
                             image = "misc/paralyzed.png",
                             tooltip = "paralyzed: this unit is paralyzed. It wion't be able to move or attack until a turn has passed."
                         } })
                     end
                     return s
                 end

function wesnoth.wml_actions.get_unit_resistance(cfg)
	local damage_type = cfg.damage_type or helper.wml_error "[get_unit_resistance] has no damage type specified"
	local to_variable = cfg.to_variable or "resistance_obtained"
	local unit = wesnoth.get_units(cfg)[1] or wesnoth.set_variable( to_variable , 100 ) --It's mainly used for weapon specials, and the target might be already killed
	if unit then
		local result = wesnoth.unit_resistance( unit, damage_type )
		wesnoth.set_variable( to_variable , result )
	end
end

function wesnoth.wml_actions.harm_unit_loti(cfg)
	-- Most of this is pasted from core, but I needed to do some edits that could not have been done without this unpleasant violation of the DRY (Don't Repeat Yourself) rule
	-- To be honest, there are parts I don't even understand
	-- It's meant to harm units but give experience only on kill, works only when used by weapon specials

	-- These two functions were copied from wml-tags.lua too
	local function start_var_scope(name)
		local var = helper.get_variable_array(name) --containers and arrays
		if #var == 0 then var = wesnoth.get_variable(name) end --scalars (and nil/empty)
		wesnoth.set_variable(name)
		return var
	end
	local function end_var_scope(name, var)
		wesnoth.set_variable(name)
		if type(var) == "table" then
			helper.set_variable_array(name, var)
		else
			wesnoth.set_variable(name, var)
		end
	end

	local filter = helper.get_child(cfg, "filter") or helper.wml_error("[harm_unit_loti] missing required [filter] tag")
	-- we need to use shallow_literal field, to avoid raising an error if $this_unit (not yet assigned) is used
	if not cfg.__shallow_literal.amount then helper.wml_error("[harm_unit_loti] has missing required amount= attribute") end
	local variable = cfg.variable -- kept out of the way to avoid problems
	local _ = wesnoth.textdomain "wesnoth"
	local harmer

	local function toboolean( value ) -- helper for animate fields
		-- units will be animated upon leveling or killing, even
		-- with special attacker and defender values
		if value then return true
		else return false end
	end

	local this_unit = start_var_scope("this_unit")

	for index, unit_to_harm in ipairs(wesnoth.get_units(filter)) do
		if unit_to_harm.valid then
			-- block to support $this_unit
			wesnoth.set_variable ( "this_unit" ) -- clearing this_unit
			wesnoth.set_variable("this_unit", unit_to_harm.__cfg) -- cfg field needed
			local amount = tonumber(cfg.amount)
			local animate = cfg.animate -- attacker and defender are special values
			local delay = cfg.delay or 500
			local fire_event = cfg.fire_event
			local primary_attack = helper.get_child(cfg, "primary_attack")
			local secondary_attack = helper.get_child(cfg, "secondary_attack")
			local harmer_filter = helper.get_child(cfg, "filter_second")
			local resistance_multiplier = tonumber(cfg.resistance_multiplier) or 1
			if harmer_filter then harmer = wesnoth.get_units(harmer_filter)[1] end
			-- end of block to support $this_unit

			if animate then
				if animate ~= "defender" and harmer and harmer.valid then
					wesnoth.scroll_to_tile(harmer.x, harmer.y, true)
					wesnoth.wml_actions.animate_unit( { flag = "attack", hits = true, { "filter", { id = harmer.id } },
						{ "primary_attack", primary_attack },
						{ "secondary_attack", secondary_attack }, with_bars = true,
						{ "facing", { x = unit_to_harm.x, y = unit_to_harm.y } } } )
				end
				wesnoth.scroll_to_tile(unit_to_harm.x, unit_to_harm.y, true)
			end

			-- the two functions below are taken straight from the C++ engine, util.cpp and actions.cpp, with a few unuseful parts removed
			-- may be moved in helper.lua in 1.11
			local function round_damage( base_damage, bonus, divisor )
				local rounding
				if base_damage == 0 then return 0
				else
					if bonus < divisor or divisor == 1 then
						rounding = divisor / 2 - 0
					else
						rounding = divisor / 2 - 1
					end
					return math.max( 1, math.floor( ( base_damage * bonus + rounding ) / divisor ) )
				end
			end

			local function calculate_damage( base_damage, alignment, tod_bonus, resistance, modifier )
				local damage_multiplier = 100
				if alignment == "lawful" then
					damage_multiplier = damage_multiplier + tod_bonus
				elseif alignment == "chaotic" then
					damage_multiplier = damage_multiplier - tod_bonus
				elseif alignment == "liminal" then
					damage_multiplier = damage_multiplier - math.abs( tod_bonus )
				else -- neutral, do nothing
				end
				local resistance_modified = resistance * modifier
				damage_multiplier = damage_multiplier * resistance_modified
				local damage = round_damage( base_damage, damage_multiplier, 10000 ) -- if harmer.status.slowed, this may be 20000 ?
				return damage
			end

			local damage = calculate_damage( amount,
							 ( cfg.alignment or "neutral" ),
							 wesnoth.get_time_of_day( { unit_to_harm.x, unit_to_harm.y, true } ).lawful_bonus,
							 wesnoth.unit_resistance( unit_to_harm, cfg.damage_type or "dummy" ),
							 resistance_multiplier
						       )

			if unit_to_harm.hitpoints <= damage then
				damage = unit_to_harm.hitpoints
			end

			unit_to_harm.hitpoints = unit_to_harm.hitpoints - damage
			local text = string.format("%d%s", damage, "\n")
			local add_tab = false
			local gender = unit_to_harm.__cfg.gender

			local function set_status(name, male_string, female_string, sound)
				if not cfg[name] or unit_to_harm.status[name] then return end
				if gender == "female" then
					text = string.format("%s%s%s", text, tostring(female_string), "\n")
				else
					text = string.format("%s%s%s", text, tostring(male_string), "\n")
				end

				unit_to_harm.status[name] = true
				add_tab = true

				if animate and sound then -- for unhealable, that has no sound
					wesnoth.play_sound (sound)
				end
			end

			if not unit_to_harm.status.unpoisonable then
				set_status("poisoned", _"poisoned", _"female^poisoned", "poison.ogg")
			end
			set_status("slowed", _"slowed", _"female^slowed", "slowed.wav")
			set_status("petrified", _"petrified", _"female^petrified", "petrified.ogg")
			set_status("unhealable", _"unhealable", _"female^unhealable")

			-- Extract unit and put it back to update animation if status was changed
			wesnoth.extract_unit(unit_to_harm)
			wesnoth.put_unit(unit_to_harm, unit_to_harm.x, unit_to_harm.y)

			if add_tab then
				text = string.format("%s%s", "\t", text)
			end

			if animate and animate ~= "attacker" then
				if harmer and harmer.valid then
					wesnoth.wml_actions.animate_unit( { flag = "defend", hits = true, { "filter", { id = unit_to_harm.id } },
						{ "primary_attack", primary_attack },
						{ "secondary_attack", secondary_attack }, with_bars = true },
						{ "facing", { x = harmer.x, y = harmer.y } } )
				else
					wesnoth.wml_actions.animate_unit( { flag = "defend", hits = true, { "filter", { id = unit_to_harm.id } },
						{ "primary_attack", primary_attack },
						{ "secondary_attack", secondary_attack }, with_bars = true } )
				end
			end

			wesnoth.float_label( unit_to_harm.x, unit_to_harm.y, string.format( "<span foreground='red'>%s</span>", text ) )

			if unit_to_harm.hitpoints < 1 then
				local uth_cfg = unit_to_harm.__cfg
				local added_exp
				if uth_cfg.level > 0 then
					added_exp = uth_cfg.level * 8
				else
					added_exp = 4
				end
				if harmer then
					wesnoth.wml_actions.store_unit { { "filter", { id = harmer.id } }, variable = "Lua_store_unit", kill = false }
					local harmer_variables = helper.get_child(harmer.__cfg, "variables")
					if harmer_variables.lua_delayed_exp then
						wesnoth.wml_actions.set_variable { name="Lua_store_unit.variables.lua_delayed_exp", add = added_exp }
					else
						wesnoth.wml_actions.set_variable { name="Lua_store_unit.variables.lua_delayed_exp", value = added_exp }
					end -- The exp will be added when combat ends
					wesnoth.wml_actions.unstore_unit { variable = "Lua_store_unit",
									find_vacant = false,
									animate = toboolean( animate ),
									fire_event = fire_event }
					wesnoth.set_variable ( "Lua_store_unit", nil )
				end
				wesnoth.wml_actions.kill({
					id = unit_to_harm.id,
					animate = toboolean( animate ),
					fire_event = fire_event
				})
			end

			if animate then
				wesnoth.delay(delay)
			end

			if variable then
				wesnoth.set_variable(string.format("%s[%d]", variable, index - 1), { harm_amount = damage })
			end
		end

		wesnoth.wml_actions.redraw {}
	end

	wesnoth.set_variable ( "this_unit" ) -- clearing this_unit
	end_var_scope("this_unit", this_unit)
end
