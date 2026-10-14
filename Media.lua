-- Bar textures, fonts and alert sounds offered in the options, plus anything
-- registered with LibSharedMedia-3.0 when another addon has loaded it.
local _, ns = ...

local Media = {}
ns.Media = Media

local TEXTURES = {
	{ value = "Blizzard", text = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
	{ value = "Flat", text = "Flat", path = "Interface\\Buttons\\WHITE8X8" },
	{ value = "Raid", text = "Raid frame", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
	{ value = "Skills", text = "Skill bar", path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
}

local FONTS = {
	{ value = "Default", text = "Game default" },
	{ value = "Friz", text = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
	{ value = "Arial", text = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
	{ value = "Skurri", text = "Skurri", path = "Fonts\\SKURRI.TTF" },
	{ value = "Morpheus", text = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
}

local function SoundKit(name, fallback)
	return SOUNDKIT and SOUNDKIT[name] or fallback
end

local SOUNDS = {
	{ value = "NONE", text = "None" },
	{ value = "CLICK", text = "Click", id = SoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON", 856) },
	{ value = "PING", text = "Map ping", id = SoundKit("MAP_PING", 3175) },
	{ value = "TICK", text = "Countdown tick", id = SoundKit("UI_COUNTDOWN_TIMER", 158565) },
	{ value = "RAID_WARNING", text = "Raid warning", id = SoundKit("RAID_WARNING", 8959) },
	{ value = "ALARM", text = "Alarm", id = SoundKit("ALARM_CLOCK_WARNING_3", 12889) },
}

local SHARED_MEDIA_PREFIX = "LSM:"

local function SharedMedia()
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function Find(list, value)
	for _, item in ipairs(list) do
		if item.value == value then
			return item
		end
	end
end

-- Options for a dropdown: kind is "statusbar" or "font".
function Media.List(kind)
	local list = {}
	for _, item in ipairs(kind == "font" and FONTS or TEXTURES) do
		list[#list + 1] = { value = item.value, text = item.text }
	end
	local lsm = SharedMedia()
	if lsm then
		for _, name in ipairs(lsm:List(kind)) do
			list[#list + 1] = { value = SHARED_MEDIA_PREFIX .. name, text = name .. " (SharedMedia)" }
		end
	end
	return list
end

local function FetchShared(kind, value)
	if type(value) == "string" and value:sub(1, #SHARED_MEDIA_PREFIX) == SHARED_MEDIA_PREFIX then
		local lsm = SharedMedia()
		return lsm and lsm:Fetch(kind, value:sub(#SHARED_MEDIA_PREFIX + 1), true)
	end
end

function Media.Texture(value)
	local item = Find(TEXTURES, value)
	return item and item.path or FetchShared("statusbar", value) or TEXTURES[1].path
end

function Media.DefaultFont()
	local font = GameFontHighlightSmall and GameFontHighlightSmall:GetFont()
	return font or "Fonts\\FRIZQT__.TTF"
end

function Media.Font(value)
	local item = Find(FONTS, value)
	if item and item.path then
		return item.path
	end
	return FetchShared("font", value) or Media.DefaultFont()
end

-- Falls back to the game font if the chosen file is missing.
function Media.ApplyFont(fontString, font, size, outline)
	if not fontString:SetFont(Media.Font(font), size, outline) then
		fontString:SetFont(Media.DefaultFont(), size, outline)
	end
end

function Media.Sounds()
	return SOUNDS
end

function Media.Sound(value)
	local item = Find(SOUNDS, value)
	return item and item.id
end
