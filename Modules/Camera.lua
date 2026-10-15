-- Max camera distance: how far you can zoom out, which matters for watching
-- your pet and the mobs around you. It sets the game's
-- cameraDistanceMaxZoomFactor (1.0 is 15 yards, 2.6 is 39). The game keeps that
-- setting even without the addon, so it is only touched when you turn this on,
-- and turning it off puts the game's default back. A button (or
-- /deadeye camera zoomout) turns it on and zooms the camera all the way out.
local _, ns = ...
local L = ns.L

local Camera = ns:NewModule("Camera", {
	enabled = false,
	zoomFactor = 2.6,
})
Camera.title = L["Camera"]
Camera.slashPrefix = "camera"

local CVAR = "cameraDistanceMaxZoomFactor"
local ZOOM_OUT_YARDS = 50 -- more than the farthest the camera goes, so it stops at the max

local function SetFactor(value)
	C_CVar.SetCVar(CVAR, tostring(value))
end

-- Camera settings are applied out of combat, to stay clear of combat restrictions.
function Camera:Apply(restoreDefault)
	if InCombatLockdown() then
		self.pending = restoreDefault and "default" or "apply"
		return
	end
	self.pending = nil
	if self.db.enabled then
		SetFactor(self.db.zoomFactor)
	elseif restoreDefault then
		local default = C_CVar.GetCVarDefault(CVAR)
		if default then
			SetFactor(default)
		end
	end
end

-- Turns the max distance on and zooms all the way out to it. Out of combat
-- only, like the setting itself; a click in combat waits for the fight to end.
function Camera:ZoomOut()
	if not self.db.enabled then
		self.db.enabled = true
		ns.OptionsChanged()
	end
	if InCombatLockdown() then
		self.zoomAfterCombat = true
		self:Apply()
		ns.Print(L["The camera zooms out when this fight ends."])
		return
	end
	self.zoomAfterCombat = nil
	self:Apply()
	-- The next frame, so the new max distance is in place first.
	C_Timer.After(0, function()
		if not InCombatLockdown() then
			CameraZoomOut(ZOOM_OUT_YARDS)
		end
	end)
end

function Camera:OnOptionChanged(key)
	self:Apply(key == "enabled" and not self.db.enabled)
end

function Camera:OnSettingsReset()
	self:Apply(true)
end

function Camera:GetOptionSections()
	return {
		{
			name = L["Camera"],
			keys = { "enabled", "zoomFactor" },
			controls = {
				{ type = "toggle", label = L["Set the max camera distance"], key = "enabled", slash = "enabled" },
				{ type = "range", label = L["Max camera distance (zoom factor)"], key = "zoomFactor", min = 1, max = 2.6, step = 0.1, slash = "zoom" },
				{ type = "button", label = L["Zoom all the way out"], slash = "zoomout", width = 200,
					tooltip = L["Sets the max camera distance above, then zooms your camera out as far as it goes."],
					func = function() self:ZoomOut() end },
				{ type = "note", height = 46, text = L["1.0 is 15 yards, 2.6 is 39 yards (the most the game allows). Turning this off puts the game's default back."] },
			},
		},
	}
end

function Camera:ShouldEnable()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

function Camera:OnEnable()
	local events = ns.CreateEventFrame(self)
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	self.events = events
	if self.db.enabled then
		self:Apply()
	end
end

function Camera:PLAYER_REGEN_ENABLED()
	if self.pending then
		self:Apply(self.pending == "default")
	end
	if self.zoomAfterCombat then
		self:ZoomOut()
	end
end
