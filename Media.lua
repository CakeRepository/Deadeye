-- Bar textures, fonts and alert sounds offered in the options, plus anything
-- registered with LibSharedMedia-3.0 when another addon has loaded it.
local _, ns = ...
local L = ns.L

local Media = {}
ns.Media = Media

local TEXTURES = {
	{ value = "Blizzard", text = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
	{ value = "Flat", text = L["Flat"], path = "Interface\\Buttons\\WHITE8X8" },
	{ value = "Raid", text = L["Raid frame"], path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
	{ value = "Skills", text = L["Skill bar"], path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
}

-- A font file only has the letters it was made with. Russian clients get the
-- Cyrillic versions Blizzard ships; Korean and Chinese text needs the game's
-- own font, so there the other choices fall back to it.
local FONTS = {
	{ value = "Default", text = L["Game default"] },
	{ value = "Friz", text = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF", cyrillic = "Fonts\\FRIZQT___CYR.TTF" },
	{ value = "Arial", text = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
	{ value = "Skurri", text = "Skurri", path = "Fonts\\SKURRI.TTF", cyrillic = "Fonts\\SKURRI_CYR.TTF" },
	{ value = "Morpheus", text = "Morpheus", path = "Fonts\\MORPHEUS.TTF", cyrillic = "Fonts\\MORPHEUS_CYR.TTF" },
}
local GAME_FONT_ONLY = { koKR = true, zhCN = true, zhTW = true }

-- The file to use for a font choice in this client's language, or nil for the game font.
local function FontPath(item)
	if GAME_FONT_ONLY[ns.locale] then
		return nil
	elseif ns.locale == "ruRU" then
		return item.cyrillic
	end
	return item.path
end

local function SoundKit(name, fallback)
	return SOUNDKIT and SOUNDKIT[name] or fallback
end

local SOUNDS = {
	{ value = "NONE", text = L["None"] },
	{ value = "CLICK", text = L["Click"], id = SoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON", 856) },
	{ value = "PING", text = L["Map ping"], id = SoundKit("MAP_PING", 3175) },
	{ value = "TICK", text = L["Countdown tick"], id = SoundKit("UI_COUNTDOWN_TIMER", 158565) },
	{ value = "RAID_WARNING", text = L["Raid warning"], id = SoundKit("RAID_WARNING", 8959) },
	{ value = "ALARM", text = L["Alarm"], id = SoundKit("ALARM_CLOCK_WARNING_3", 12889) },
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
		if kind ~= "font" or item.value == "Default" or FontPath(item) then
			list[#list + 1] = { value = item.value, text = item.text }
		end
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
	if item then
		return FontPath(item) or Media.DefaultFont()
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
