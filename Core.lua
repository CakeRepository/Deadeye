-- ForeverHunter: a hunter toolkit for World of Warcraft: Forever.
-- Core: saved variables, the module registry, slash commands and shared helpers.
-- Features live in Modules\*.lua and register themselves with ns:NewModule().
local addonName, ns = ...

ns.name = addonName
ns.title = "|cffaad372Forever|rHunter"
ns.version = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"

---------------------------------------------------------------------------
-- Secret values
---------------------------------------------------------------------------
-- Forever runs the Midnight (12.x) addon rules: in combat, APIs such as
-- UnitAttackSpeed return "secret" values that addon code may store or hand to
-- widgets but must not compare, branch on or do math with (doing so raises a
-- Lua error). Always check a value from such an API before using it.
local issecretvalue = issecretvalue

function ns.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) or false
end

-- Returns value if it is a plain, non-nil value, otherwise fallback.
-- The secrecy check must come first: even comparing a secret to nil is unsafe.
function ns.Readable(value, fallback)
	if ns.IsSecret(value) then
		return fallback
	end
	if value == nil then
		return fallback
	end
	return value
end

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------
local function Stringify(...)
	local parts = {}
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if ns.IsSecret(value) then
			parts[#parts + 1] = "<secret>"
		elseif type(value) == "number" and value ~= math.floor(value) then
			parts[#parts + 1] = string.format("%.3f", value)
		else
			parts[#parts + 1] = tostring(value)
		end
	end
	return table.concat(parts, " ")
end

function ns.Print(...)
	print(ns.title .. ": " .. Stringify(...))
end

function ns.Debug(...)
	if ns.db and ns.db.debug then
		print(string.format("|cff888888[FH %.2f]|r %s", GetTime(), Stringify(...)))
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Creates a frame that calls handler:EVENT_NAME(...) for each registered event.
function ns.CreateEventFrame(handler)
	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(_, event, ...)
		local method = handler[event]
		if method then
			method(handler, ...)
		end
	end)
	return frame
end

---------------------------------------------------------------------------
-- Modules and saved variables
---------------------------------------------------------------------------
-- A module is a plain table with optional hooks:
--   module:OnInitialize()     saved variables are ready (module.db)
--   module:ShouldEnable()     return false to stay off (e.g. wrong class)
--   module:OnEnable()         the player is logged in; create frames, register events
--   module:OnSettingsReset()  module.db was just reset to its defaults
--   module:GetOptionSections() pages for the options window (see Options\Window.lua)
--   module:SetPreview(on)     the options window opened or closed
-- module.db is the module's own table inside ForeverHunterDB.modules.
ns.modules = {}
local moduleOrder = {}

function ns:NewModule(name, defaults)
	local module = { name = name, defaults = defaults or {} }
	self.modules[name] = module
	moduleOrder[#moduleOrder + 1] = module
	return module
end

local function CopyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			CopyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
	return target
end

function ns.CopyTable(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in pairs(value) do
		copy[key] = ns.CopyTable(inner)
	end
	return copy
end

-- Settings are addressed with dotted paths such as "colors.reload".
function ns.GetPath(tbl, path)
	for key in path:gmatch("[^%.]+") do
		if type(tbl) ~= "table" then
			return nil
		end
		tbl = tbl[key]
	end
	return tbl
end

function ns.SetPath(tbl, path, value)
	local last
	for key in path:gmatch("[^%.]+") do
		if last then
			if type(tbl[last]) ~= "table" then
				tbl[last] = {}
			end
			tbl = tbl[last]
		end
		last = key
	end
	tbl[last] = value
end

-- Replaced by the options window; modules call it after changing settings
-- outside the window (e.g. dragging the bar) so open controls stay in sync.
function ns.OptionsChanged() end

local function InitializeDB()
	if type(ForeverHunterDB) ~= "table" then
		ForeverHunterDB = {}
	end
	local db = ForeverHunterDB
	db.version = db.version or 1
	if db.locked == nil then
		db.locked = true -- one lock for every ForeverHunter frame (see Frames.lua)
	end
	if type(db.modules) ~= "table" then
		db.modules = {}
	end
	for _, module in ipairs(moduleOrder) do
		local saved = db.modules[module.name]
		-- freshSettings tells a module's migrations there was nothing saved before.
		module.freshSettings = type(saved) ~= "table"
		if module.freshSettings then
			saved = {}
			db.modules[module.name] = saved
		end
		module.db = CopyDefaults(saved, module.defaults)
	end
	ns.db = db
end

function ns:ResetSettings()
	ForeverHunterDB.modules = {}
	InitializeDB()
	for _, module in ipairs(moduleOrder) do
		if module.enabled and module.OnSettingsReset then
			module:OnSettingsReset()
		end
	end
	ns.OptionsChanged()
end

---------------------------------------------------------------------------
-- Slash commands: /fh <command> [args]
---------------------------------------------------------------------------
local commands, commandOrder = {}, {}

-- usage is what /fh help prints (e.g. "scale <0.5-3>"); commands without a
-- description still work but are left out of the help list.
function ns:RegisterCommand(name, usage, description, handler)
	if not commands[name] then
		commandOrder[#commandOrder + 1] = name
	end
	commands[name] = { usage = usage, description = description, handler = handler }
end

local function PrintHelp()
	ns.Print("v" .. ns.version .. " - /fh opens the options. Commands:")
	for _, name in ipairs(commandOrder) do
		local command = commands[name]
		if command.description then
			print(string.format("  |cffffd100/fh %s|r  %s", command.usage, command.description))
		end
	end
	print("  Any setting: |cffffd100/fh <setting> <value>|r, e.g. /fh width 250 or /fh texture flat.")
end

function ns:RunCommand(input)
	local name, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	name = name:lower()
	if name == "" and ns.OptionsWindow then
		ns.OptionsWindow:Toggle()
		return
	end
	if name == "" or name == "help" then
		PrintHelp()
		return
	end
	local command = commands[name]
	if command then
		command.handler(rest)
	elseif not ns.Slash.Handle(ns.Slash.MainModule(), name, rest) then
		ns.Print("Unknown command or setting '" .. name .. "'. Type /fh help or /fh settings.")
	end
end

SLASH_FOREVERHUNTER1 = "/fh"
SLASH_FOREVERHUNTER2 = "/foreverhunter"
SlashCmdList.FOREVERHUNTER = function(input)
	ns:RunCommand(input)
end

local function RegisterCoreCommands()
	local function OpenOptions()
		ns.OptionsWindow:Open()
	end
	ns:RegisterCommand("move", "move", "Unlock every ForeverHunter frame to drag it; run again to lock.", function()
		ns:SetLocked(not ns.db.locked)
	end)
	ns:RegisterCommand("lock", "lock", nil, function()
		ns:SetLocked(true)
	end)
	ns:RegisterCommand("unlock", "unlock", nil, function()
		ns:SetLocked(false)
	end)
	ns:RegisterCommand("options", "options", "Open the options window (or just type /fh).", OpenOptions)
	ns:RegisterCommand("config", "config", nil, OpenOptions)
	ns:RegisterCommand("debug", "debug", "Log Auto Shot events to chat (useful for bug reports).", function()
		ns.db.debug = not ns.db.debug
		ns.Print("Debug logging", ns.db.debug and "on." or "off.")
	end)
	ns:RegisterCommand("reset", "reset", "Reset all settings and the bar position.", function()
		ns:ResetSettings()
		ns.Print("Settings reset to defaults.")
	end)
end

---------------------------------------------------------------------------
-- Addon compartment (the addon button on the minimap)
---------------------------------------------------------------------------
function ForeverHunter_OnAddonCompartmentClick(_, buttonName)
	if buttonName == "RightButton" then
		ns:RunCommand("move")
	else
		ns.OptionsWindow:Toggle()
	end
end

function ForeverHunter_OnAddonCompartmentEnter(_, button)
	if not button then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText(ns.title)
	GameTooltip:AddLine("Left-click: options", 1, 1, 1)
	GameTooltip:AddLine("Right-click: unlock or lock the Auto Shot bar", 1, 1, 1)
	GameTooltip:AddLine("/fh help lists every command", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

function ForeverHunter_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, loadedAddon)
	if event == "ADDON_LOADED" then
		if loadedAddon ~= addonName then
			return
		end
		self:UnregisterEvent("ADDON_LOADED")
		InitializeDB()
		for _, module in ipairs(moduleOrder) do
			if module.OnInitialize then
				module:OnInitialize()
			end
		end
		ns.Slash.RegisterCommands()
		RegisterCoreCommands()
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		for _, module in ipairs(moduleOrder) do
			if not module.ShouldEnable or module:ShouldEnable() then
				module.enabled = true
				if module.OnEnable then
					module:OnEnable()
				end
			end
		end
		ns.OptionsWindow:RegisterSettingsCategory()
	end
end)

function ns:GetModules()
	return moduleOrder
end
