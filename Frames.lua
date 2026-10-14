-- Shared handling for Deadeye's on-screen frames (the Auto Shot bar, the
-- range text, the pet panel). They can be dragged while unlocked (/deadeye move) or
-- while Blizzard's Edit Mode is open. Each module keeps its frame's position in
-- module.db.position as the offset of the frame's center from the screen
-- center, in UIParent units, so it does not shift when the frame's scale changes.
local _, ns = ...

local Frames = {}
ns.Frames = Frames

local registered = {}
local editMode = false

function ns:IsUnlocked()
	return editMode or (ns.db ~= nil and ns.db.locked == false)
end

function ns:InEditMode()
	return editMode
end

local function NotifyModules()
	for _, entry in ipairs(registered) do
		if entry.module.enabled and entry.module.OnUnlockChanged then
			entry.module:OnUnlockChanged()
		end
	end
	ns.OptionsChanged()
end

function ns:SetLocked(locked, quiet)
	ns.db.locked = locked
	NotifyModules()
	if not quiet then
		ns.Print(locked and "Frames locked." or "Frames unlocked: drag the blue boxes where you want them, then type /deadeye lock.")
	end
end

-- label is shown on the blue drag overlay. keepMouse leaves mouse input on
-- while locked, for frames with tooltips.
function Frames.MakeMovable(module, frame, label, keepMouse)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetDontSavePosition(true) -- positions live in DeadeyeDB
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if ns:IsUnlocked() then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Frames.SavePosition(module, self)
		if module.OnDragged then
			module:OnDragged()
		end
		Frames.ApplyPosition(module, self)
		ns.OptionsChanged()
	end)

	local mover = CreateFrame("Frame", nil, frame)
	mover:SetAllPoints()
	mover:SetFrameLevel(frame:GetFrameLevel() + 10)
	local tint = mover:CreateTexture(nil, "OVERLAY")
	tint:SetAllPoints()
	tint:SetColorTexture(0.25, 0.6, 1, 0.35)
	local text = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER")
	text:SetText(label)
	mover:Hide()
	frame.mover = mover
	frame.keepMouse = keepMouse
	registered[#registered + 1] = { module = module, frame = frame }
end

function Frames.UpdateMover(frame)
	local unlocked = ns:IsUnlocked()
	frame:EnableMouse(unlocked or frame.keepMouse == true)
	frame.mover:SetShown(unlocked)
end

function Frames.ApplyPosition(module, frame)
	local position, scale = module.db.position, module.db.scale or 1
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", position.x / scale, position.y / scale)
end

function Frames.SavePosition(module, frame)
	local x, y = frame:GetCenter()
	local centerX, centerY = UIParent:GetCenter()
	if not (x and centerX) then
		return false
	end
	local scale = frame:GetScale()
	local position = module.db.position
	position.x = math.floor(x * scale - centerX + 0.5)
	position.y = math.floor(y * scale - centerY + 0.5)
	return true
end

-- Default height for the hunter HUD (bar, range strip, pet panel): about a third
-- of the way down from the center, which clears the character with the
-- default camera and stays above the action bars at common UI scales.
function Frames.DefaultHudY()
	return -math.floor(UIParent:GetHeight() * 0.3 + 0.5)
end

-- Option controls for a frame's position and scale (see Options\Window.lua).
-- The module's ApplyLayout() is expected to re-apply the position.
function Frames.PositionOptions(module)
	local halfWidth = math.floor(UIParent:GetWidth() / 2)
	local halfHeight = math.floor(UIParent:GetHeight() / 2)
	return {
		{ type = "toggle", label = "Unlock frames to drag them", slash = "unlocked",
			get = function() return ns:IsUnlocked() end,
			set = function(value) ns:SetLocked(not value, true) end },
		{ type = "range", label = "X offset from center", key = "position.x", min = -halfWidth, max = halfWidth, step = 1, slash = "x" },
		{ type = "range", label = "Y offset from center", key = "position.y", min = -halfHeight, max = halfHeight, step = 1, slash = "y" },
		{ type = "button", label = "Center horizontally", slash = "center", func = function()
			module.db.position.x = 0
			module:ApplyLayout()
		end },
		{ type = "range", label = "Scale", key = "scale", min = 0.5, max = 3, step = 0.05, slash = "scale" },
	}
end

-- Blizzard's Edit Mode unlocks every Deadeye frame while it is open.
if EventRegistry then
	EventRegistry:RegisterCallback("EditMode.Enter", function()
		editMode = true
		NotifyModules()
	end, Frames)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		editMode = false
		NotifyModules()
	end, Frames)
end
