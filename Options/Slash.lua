-- Every setting in the options window can also be changed from chat:
--   /deadeye <setting> <value>          an Auto Shot bar setting, e.g. /deadeye width 250
--   /deadeye range <setting> <value>    a setting of another module (range, pet)
--   /deadeye <setting>                  show its current value and what it accepts
--   /deadeye settings [range|pet]       list the settings with their values
-- Setting names are the "slash" field of each option (see Options\Window.lua).
local _, ns = ...

local Slash = {}
ns.Slash = Slash

local ON = { on = true, yes = true, ["true"] = true, ["1"] = true, show = true, enable = true }
local OFF = { off = true, no = true, ["false"] = true, ["0"] = true, hide = true, disable = true }

local function Normalize(text)
	return (tostring(text or ""):lower():gsub("[^%w]", ""))
end

local function Values(spec)
	return type(spec.values) == "function" and spec.values() or spec.values
end

-- What to type for a dropdown option.
local function OptionName(option)
	if type(option.value) == "number" then
		return tostring(option.value)
	elseif option.value ~= "" then
		return option.value:lower()
	end
	return Normalize(option.text)
end

function Slash.ColorToHex(color)
	local hex = ""
	for i = 1, color[4] and 4 or 3 do
		hex = hex .. string.format("%02x", math.floor(color[i] * 255 + 0.5))
	end
	return hex
end

-- Accepts "ff8800", "#ff8800", "ff8800cc", "1 0.5 0" or "255 128 0".
function Slash.ParseColor(text, withAlpha)
	local parts = {}
	local hex = text:match("^#?(%x+)$")
	if hex and (#hex == 6 or #hex == 8) then
		for i = 1, #hex, 2 do
			parts[#parts + 1] = tonumber(hex:sub(i, i + 1), 16) / 255
		end
	else
		local numbers = {}
		for number in text:gmatch("[%d%.]+") do
			numbers[#numbers + 1] = tonumber(number)
		end
		if #numbers < 3 then
			return nil
		end
		local scale = (numbers[1] > 1 or numbers[2] > 1 or numbers[3] > 1) and 255 or 1
		for i = 1, math.min(#numbers, 4) do
			local value = numbers[i]
			if i <= 3 then
				value = value / scale
			elseif value > 1 then
				value = value / 255
			end
			parts[i] = math.max(0, math.min(1, value))
		end
	end
	local color = { parts[1], parts[2], parts[3] }
	if withAlpha then
		color[4] = parts[4] or 1
	end
	return color
end

-- Exact option names win over the shown text, which wins over the start of either.
local function ParseSelect(spec, text)
	local wanted = Normalize(text)
	if wanted == "" then
		return nil
	end
	local values = Values(spec)
	for _, option in ipairs(values) do
		if Normalize(OptionName(option)) == wanted then
			return option.value
		end
	end
	for _, option in ipairs(values) do
		if Normalize(option.text) == wanted then
			return option.value
		end
	end
	for _, option in ipairs(values) do
		local name, label = Normalize(OptionName(option)), Normalize(option.text)
		if name:sub(1, #wanted) == wanted or label:sub(1, #wanted) == wanted then
			return option.value
		end
	end
end

local function Describe(spec, value)
	if spec.type == "toggle" then
		return value and "on" or "off"
	elseif spec.type == "range" then
		return string.format(ns.Widgets.RangeFormat(spec), value)
	elseif spec.type == "color" then
		return Slash.ColorToHex(value)
	elseif spec.type == "select" then
		for _, option in ipairs(Values(spec)) do
			if option.value == value then
				return OptionName(option)
			end
		end
	elseif spec.type == "input" then
		return '"' .. tostring(value) .. '"'
	end
	return tostring(value)
end

local function Accepts(spec)
	if spec.type == "toggle" then
		return "on, off or toggle"
	elseif spec.type == "range" then
		local format = ns.Widgets.RangeFormat(spec)
		return "a number from " .. string.format(format, spec.min) .. " to " .. string.format(format, spec.max)
	elseif spec.type == "color" then
		return "a hex color like ff8800" .. (spec.alpha and " (add two digits for opacity)" or "")
	elseif spec.type == "select" then
		local names = {}
		for _, option in ipairs(Values(spec)) do
			names[#names + 1] = OptionName(option)
		end
		return table.concat(names, ", ")
	elseif spec.type == "input" then
		return "any text"
	end
	return "nothing"
end

local function Command(module, spec)
	return "/deadeye " .. (module.slashPrefix and module.slashPrefix .. " " or "") .. spec.slash
end

local function Settings(module)
	local list, byName = {}, {}
	for _, section in ipairs(module:GetOptionSections()) do
		for _, spec in ipairs(section.controls) do
			if spec.slash then
				list[#list + 1] = { spec = spec, section = section.name }
				byName[spec.slash] = spec
			end
		end
	end
	return list, byName
end

function Slash.Apply(module, spec, text)
	local get, set = ns.Widgets.Accessors(module, spec)
	if spec.type == "button" then
		spec.func()
		ns.OptionsChanged()
		ns.Print(spec.label .. ": done.")
		return
	end
	if text == "" then
		ns.Print(string.format("%s is %s. Change it with %s <%s>.", spec.label, Describe(spec, get()), Command(module, spec), Accepts(spec)))
		return
	end
	local value
	if spec.type == "toggle" then
		local lower = text:lower()
		if ON[lower] then
			value = true
		elseif OFF[lower] then
			value = false
		elseif lower == "toggle" then
			value = not get()
		end
	elseif spec.type == "range" then
		local number = tonumber(text)
		value = number and ns.Widgets.CleanRange(spec, number)
	elseif spec.type == "select" then
		value = ParseSelect(spec, text)
	elseif spec.type == "color" then
		value = Slash.ParseColor(text, spec.alpha)
	elseif spec.type == "input" then
		value = text
	end
	if value == nil then
		ns.Print(string.format("Couldn't use '%s' for %s. Expected %s.", text, spec.label, Accepts(spec)))
		return
	end
	set(value)
	ns.OptionsChanged()
	ns.Print(string.format("%s set to %s.", spec.label, Describe(spec, get())))
end

function Slash.List(module)
	local list = Settings(module)
	ns.Print((module.title or module.name) .. " settings, change one with /deadeye " .. (module.slashPrefix and module.slashPrefix .. " " or "") .. "<setting> <value>:")
	local section
	for _, entry in ipairs(list) do
		if entry.section ~= section then
			section = entry.section
			print("  |cffffd100" .. section .. "|r")
		end
		local spec = entry.spec
		local value = spec.type == "button" and "(action)" or Describe(spec, (ns.Widgets.Accessors(module, spec))())
		print("    " .. spec.slash .. "  " .. value)
	end
end

-- Handles /deadeye <name> <value> for a module. Returns false if name is not one of its settings.
function Slash.Handle(module, name, text)
	if not (module and module.enabled and module.GetOptionSections) then
		return false
	end
	local _, byName = Settings(module)
	local spec = byName[name]
	if not spec then
		return false
	end
	Slash.Apply(module, spec, text)
	return true
end

-- The module whose settings need no prefix (the Auto Shot bar).
function Slash.MainModule()
	for _, module in ipairs(ns:GetModules()) do
		if module.enabled and not module.slashPrefix and module.GetOptionSections then
			return module
		end
	end
end

local function SplitFirst(text)
	local first, rest = text:match("^%s*(%S*)%s*(.-)%s*$")
	return first:lower(), rest
end

-- Registers /deadeye settings and one /deadeye <prefix> command per prefixed module.
function Slash.RegisterCommands()
	for _, module in ipairs(ns:GetModules()) do
		local prefix = module.slashPrefix
		if prefix then
			ns:RegisterCommand(prefix, prefix .. " <setting> <value>", "Change " .. (module.title or module.name) .. " settings (/deadeye " .. prefix .. " settings lists them).", function(text)
				if not module.enabled then
					ns.Print((module.title or module.name) .. " only runs on hunters.")
					return
				end
				local name, value = SplitFirst(text)
				if name == "" or name == "settings" or name == "list" then
					Slash.List(module)
				elseif (ON[name] or OFF[name]) and value == "" and Slash.Handle(module, "enabled", name) then
					return
				elseif not Slash.Handle(module, name, value) then
					ns.Print("No " .. prefix .. " setting called '" .. name .. "'. Type /deadeye " .. prefix .. " settings.")
				end
			end)
		end
	end
	local function ListSettings(text)
		local name = SplitFirst(text)
		for _, module in ipairs(ns:GetModules()) do
			if module.enabled and module.GetOptionSections and (module.slashPrefix or "") == name then
				Slash.List(module)
				return
			end
		end
		local main = Slash.MainModule()
		if main and name == "" then
			Slash.List(main)
		else
			ns.Print("Nothing to list for '" .. name .. "'.")
		end
	end
	ns:RegisterCommand("settings", "settings [range|pet]", "List settings you can change with /deadeye <setting> <value>.", ListSettings)
	ns:RegisterCommand("list", "list", nil, ListSettings)
end
