-- A small stand-in for the WoW: Forever client, just enough to load Deadeye
-- outside the game and drive it with events, clicks and a fake clock.
--
-- Each test gets its own "world": a fresh global environment, clock, frames and
-- saved variables. The environment is strict: reading a global the mock does not
-- define, or writing a global the addon is not expected to create, raises an
-- error, which catches typos in API names. Templates and font objects are limited
-- to ones confirmed to exist in the Forever client's UI source. Secret values
-- (Midnight/Forever combat restrictions) are tables that raise errors on
-- arithmetic, comparison, concatenation and indexing, like the real thing.
local H = {}

local SECRET_MT = {}
SECRET_MT.__index = function()
	error("attempt to index a secret value", 2)
end

function H.Secret(value)
	local secret = setmetatable({}, SECRET_MT)
	rawset(secret, 1, value)
	return secret
end

local POINTS = {
	TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
	LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
	BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
local LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true, HIGHLIGHT = true }
local STRATA = {
	BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true,
	FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true,
}
local SCRIPTS = {
	OnEvent = true, OnUpdate = true, OnDragStart = true, OnDragStop = true, OnShow = true,
	OnHide = true, OnEnter = true, OnLeave = true, OnMouseDown = true, OnMouseUp = true,
	OnClick = true, OnValueChanged = true, OnEnterPressed = true, OnEscapePressed = true,
	OnEditFocusLost = true, OnEditFocusGained = true, OnTextChanged = true, OnMouseWheel = true,
}
-- Font objects confirmed in the Forever client's Blizzard_Fonts_Shared.
local FONTS = {
	GameFontHighlightSmall = true, GameFontHighlightSmallOutline = true, GameFontNormalSmall = true,
	GameFontHighlight = true, GameFontNormal = true, NumberFontNormal = true,
	NumberFontNormalSmall = true, GameFontWhiteSmall = true, GameFontDisableSmall = true,
	GameFontNormalLarge = true, GameFontHighlightLarge = true, GameFontHighlightMedium = true,
}
-- Templates confirmed in the Forever client's UI source, by frame type.
local TEMPLATES = {
	CheckButton = { MinimalCheckboxTemplate = true, UICheckButtonTemplate = true },
	Slider = { UISliderTemplate = true },
	EditBox = { InputBoxTemplate = true },
	Button = { UIPanelButtonTemplate = true, UIPanelCloseButton = true, SecureActionButtonTemplate = true },
	DropdownButton = { WowStyle1DropdownTemplate = true },
}
local CLICKS = {}
for _, button in ipairs({ "Any", "LeftButton", "RightButton", "MiddleButton" }) do
	CLICKS[button .. "Up"], CLICKS[button .. "Down"] = true, true
end
local FRAME_TYPES = {
	Frame = true, StatusBar = true, Button = true, CheckButton = true,
	Slider = true, EditBox = true, DropdownButton = true,
}

-- Globals the addon is expected to create, or to read before they exist.
local ADDON_GLOBALS = {
	DeadeyeDB = true,
	SLASH_DEADEYE1 = true,
	SLASH_DEADEYE2 = true,
	Deadeye_OnAddonCompartmentClick = true,
	Deadeye_OnAddonCompartmentEnter = true,
	Deadeye_OnAddonCompartmentLeave = true,
}
-- Optional globals that are simply absent unless another addon provides them.
local OPTIONAL_GLOBALS = { LibStub = true }

local function check(condition, message)
	if not condition then
		error(message, 3)
	end
end

local function isNumber(value)
	return type(value) == "number"
end

local function isColor(r, g, b)
	return isNumber(r) and isNumber(g) and isNumber(b)
end

local function isSecret(value)
	return type(value) == "table" and getmetatable(value) == SECRET_MT
end

-- Widgets such as status bars accept secret values; addon code may only pass them on.
local function isNumberOrSecret(value)
	return isNumber(value) or isSecret(value)
end

---------------------------------------------------------------------------
-- Regions
---------------------------------------------------------------------------
local Region = {}
Region.__index = Region

function Region:SetPoint(point, a, b, c, d)
	check(POINTS[point], "SetPoint: bad point " .. tostring(point))
	local relativeTo, relativePoint, x, y
	if a == nil or isNumber(a) then
		relativeTo, relativePoint, x, y = self.parent, point, a or 0, b or 0
	else
		check(type(a) == "table", "SetPoint: relativeTo must be a region")
		relativeTo = a
		if isNumber(b) then
			relativePoint, x, y = point, b, c or 0
		else
			relativePoint, x, y = b or point, c or 0, d or 0
		end
	end
	check(POINTS[relativePoint], "SetPoint: bad relative point " .. tostring(relativePoint))
	check(isNumber(x) and isNumber(y), "SetPoint: offsets must be numbers")
	check(relativeTo ~= self, "SetPoint: a region cannot anchor to itself")
	for i, existing in ipairs(self.points) do
		if existing[1] == point then
			table.remove(self.points, i)
			break
		end
	end
	table.insert(self.points, { point, relativeTo, relativePoint, x, y })
end

function Region:GetPoint(index)
	local p = self.points[index or 1]
	if p then
		return p[1], p[2], p[3], p[4], p[5]
	end
end

function Region:ClearAllPoints()
	self.points = {}
end

function Region:SetAllPoints(relativeTo)
	self.allPoints = relativeTo or self.parent
end

function Region:SetSize(width, height)
	check(isNumber(width) and isNumber(height), "SetSize: numbers expected")
	self.width, self.height = width, height
end

function Region:SetWidth(width)
	check(isNumber(width), "SetWidth: number expected")
	self.width = width
end

function Region:SetHeight(height)
	check(isNumber(height), "SetHeight: number expected")
	self.height = height
end

function Region:GetWidth()
	return self.width or 0
end

function Region:GetHeight()
	return self.height or 0
end

function Region:GetEffectiveScale()
	local scale, region = 1, self
	while region do
		scale = scale * (region.scale or 1)
		region = region.parent
	end
	return scale
end

-- Screen rectangle in the region's own units; only single-anchor layouts are
-- resolved, which covers the frames the addon positions.
function Region:GetRect()
	if self.isUIParent then
		return 0, 0, self.width, self.height
	end
	local p = self.points[1]
	if not p or #self.points ~= 1 then
		return nil
	end
	local rl, rb, rw, rh = p[2]:GetRect()
	if not rl then
		return nil
	end
	local ratio = p[2]:GetEffectiveScale() / self:GetEffectiveScale()
	local ax = (rl + rw * POINTS[p[3]][1]) * ratio
	local ay = (rb + rh * POINTS[p[3]][2]) * ratio
	local w, h = self.width or 0, self.height or 0
	return ax + p[4] - POINTS[p[1]][1] * w, ay + p[5] - POINTS[p[1]][2] * h, w, h
end

function Region:GetCenter()
	local left, bottom, width, height = self:GetRect()
	if left then
		return left + width / 2, bottom + height / 2
	end
end

function Region:Show()
	self.shown = true
end

function Region:Hide()
	self.shown = false
end

function Region:SetShown(shown)
	if shown then
		self:Show()
	else
		self:Hide()
	end
end

function Region:IsShown()
	return self.shown
end

function Region:IsVisible()
	local region = self
	while region do
		if not region.shown then
			return false
		end
		region = region.parent
	end
	return true
end

function Region:SetAlpha(alpha)
	check(isNumber(alpha), "SetAlpha: number expected")
	self.alpha = alpha
end

function Region:GetAlpha()
	return self.alpha
end

local Texture = setmetatable({}, { __index = Region })
Texture.__index = Texture

function Texture:SetColorTexture(r, g, b, a)
	check(isColor(r, g, b), "SetColorTexture: numbers expected")
	check(a == nil or isNumber(a), "SetColorTexture: alpha must be a number")
	self.color = { r, g, b, a or 1 }
end

function Texture:SetTexture(asset)
	check(asset == nil or type(asset) == "string" or isNumber(asset), "SetTexture: path or file id expected")
	self.texture = asset
end

function Texture:SetTexCoord(...)
	self.texCoord = { ... }
end

function Texture:SetAtlas(atlas)
	check(type(atlas) == "string", "SetAtlas: atlas name expected")
	self.atlas = atlas
	return true
end

function Texture:SetBlendMode(mode)
	check(mode == "ADD" or mode == "BLEND" or mode == "MOD" or mode == "ALPHAKEY" or mode == "DISABLE", "SetBlendMode: bad mode")
	self.blendMode = mode
end

function Texture:SetVertexColor(r, g, b, a)
	self.vertexColor = { r, g, b, a or 1 }
end

function Texture:SetDesaturated(desaturated)
	self.desaturated = not not desaturated
end

local FontString = setmetatable({}, { __index = Region })
FontString.__index = FontString

function FontString:SetText(text)
	check(text == nil or type(text) == "string" or isNumber(text), "SetText: string expected")
	self.text = text and tostring(text) or ""
end

function FontString:SetFormattedText(fmt, ...)
	self.text = string.format(fmt, ...)
end

function FontString:GetText()
	return self.text
end

function FontString:SetTextColor(r, g, b, a)
	check(isColor(r, g, b), "SetTextColor: numbers expected")
	self.textColor = { r, g, b, a or 1 }
end

function FontString:SetJustifyH(justify)
	check(justify == "LEFT" or justify == "CENTER" or justify == "RIGHT", "SetJustifyH: bad value")
	self.justifyH = justify
end

function FontString:SetFontObject(font)
	check(FONTS[font], "SetFontObject: unknown font object " .. tostring(font))
	self.fontObject = font
end

function FontString:SetFont(path, size, flags)
	check(type(path) == "string", "SetFont: path expected")
	check(isNumber(size) and size > 0, "SetFont: size expected")
	check(flags == nil or flags == "" or flags == "OUTLINE" or flags == "THICKOUTLINE", "SetFont: bad flags " .. tostring(flags))
	self.font = { path, size, flags }
	return true
end

function FontString:SetWordWrap(wrap)
	self.wordWrap = wrap
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local Frame = setmetatable({}, { __index = Region })
Frame.__index = Frame

-- A frame is protected if it comes from a secure template, or if a protected
-- frame is its child (at any depth) or is anchored to it. In combat the client
-- blocks the protected methods below on such frames (ADDON_ACTION_BLOCKED); the
-- mock records the call in world.blocked and leaves the frame as it was.
local function IsProtected(frame)
	if frame.protected then
		return true
	end
	for _, secure in ipairs(frame.world.protectedFrames) do
		local parent = secure.parent
		while parent do
			if parent == frame then
				return true
			end
			parent = parent.parent
		end
		for _, point in ipairs(secure.points) do
			if point[2] == frame then
				return true
			end
		end
	end
	return false
end

local function Blocked(frame, method)
	if frame.world.inCombat and IsProtected(frame) then
		local blocked = frame.world.blocked
		blocked[#blocked + 1] = method .. " on " .. (frame.name or "a protected frame")
		return true
	end
	return false
end

for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize", "SetWidth", "SetHeight" }) do
	local base = Region[method]
	Frame[method] = function(self, ...)
		if not Blocked(self, method) then
			return base(self, ...)
		end
	end
end

function Frame:Show()
	if Blocked(self, "Show") then
		return
	end
	local was = self.shown
	self.shown = true
	if not was and self.scripts.OnShow then
		self.scripts.OnShow(self)
	end
end

function Frame:Hide()
	if Blocked(self, "Hide") then
		return
	end
	local was = self.shown
	self.shown = false
	if was and self.scripts.OnHide then
		self.scripts.OnHide(self)
	end
end

function Frame:GetName()
	return self.name
end

function Frame:SetScript(name, handler)
	check(SCRIPTS[name], "SetScript: unknown script " .. tostring(name))
	check(handler == nil or type(handler) == "function", "SetScript: function expected")
	check(not (self.protected and name == "OnClick"), "SetScript: OnClick would replace the secure click handler")
	self.scripts[name] = handler
end

function Frame:SetAttribute(name, value)
	check(type(name) == "string", "SetAttribute: name expected")
	if not Blocked(self, "SetAttribute") then
		self.attributes[name] = value
	end
end

function Frame:GetAttribute(name)
	return self.attributes[name]
end

function Frame:GetScript(name)
	return self.scripts[name]
end

function Frame:RegisterEvent(event)
	check(type(event) == "string", "RegisterEvent: string expected")
	if self.world.unknownEvents[event] then
		error('Attempt to register unknown event "' .. event .. '"', 2)
	end
	self.events[event] = true
	return true
end

function Frame:RegisterUnitEvent(event, unit1, unit2)
	if self.world.unknownEvents[event] then
		error('Attempt to register unknown event "' .. event .. '"', 2)
	end
	check(type(unit1) == "string", "RegisterUnitEvent: unit expected")
	self.events[event] = { [unit1] = true }
	if unit2 then
		self.events[event][unit2] = true
	end
	return true
end

function Frame:UnregisterEvent(event)
	self.events[event] = nil
end

function Frame:IsEventRegistered(event)
	return self.events[event] ~= nil
end

function Frame:CreateTexture(name, layer)
	check(layer == nil or LAYERS[layer], "CreateTexture: bad layer " .. tostring(layer))
	return setmetatable({ parent = self, shown = true, alpha = 1, points = {} }, Texture)
end

function Frame:CreateFontString(name, layer, template)
	check(layer == nil or LAYERS[layer], "CreateFontString: bad layer " .. tostring(layer))
	check(template == nil or FONTS[template], "CreateFontString: unknown font object " .. tostring(template))
	return setmetatable({ parent = self, shown = true, alpha = 1, points = {}, text = "", fontObject = template }, FontString)
end

function Frame:SetFrameStrata(strata)
	check(STRATA[strata], "SetFrameStrata: bad strata " .. tostring(strata))
	if not Blocked(self, "SetFrameStrata") then
		self.strata = strata
	end
end

function Frame:SetFrameLevel(level)
	check(isNumber(level), "SetFrameLevel: number expected")
	self.level = level
end

function Frame:GetFrameLevel()
	if self.level then
		return self.level
	end
	return self.parent and self.parent.GetFrameLevel and self.parent:GetFrameLevel() + 1 or 0
end

function Frame:SetToplevel(toplevel)
	self.toplevel = toplevel
end

function Frame:SetClampedToScreen(clamped)
	self.clamped = clamped
end

function Frame:SetMovable(movable)
	self.movable = movable
end

function Frame:SetDontSavePosition(dontSave)
	self.dontSavePosition = dontSave
end

function Frame:SetUserPlaced(userPlaced)
	self.userPlaced = userPlaced
end

function Frame:RegisterForDrag(...)
	self.dragButtons = { ... }
end

function Frame:EnableMouse(enabled)
	if not Blocked(self, "EnableMouse") then
		self.mouseEnabled = not not enabled
	end
end

function Frame:StartMoving()
	check(self.movable, "StartMoving: frame is not movable")
	self.isMoving = true
end

-- Drops the frame where the test said the player released it (world.dropPoint).
function Frame:StopMovingOrSizing()
	self.isMoving = false
	local drop = self.world.dropPoint
	if drop then
		self.points = { { drop[1], self.world.env.UIParent, drop[2], drop[3], drop[4] } }
	end
end

function Frame:SetScale(scale)
	check(isNumber(scale) and scale > 0, "SetScale: positive number expected")
	if not Blocked(self, "SetScale") then
		self.scale = scale
	end
end

function Frame:GetScale()
	return self.scale
end

local StatusBar = setmetatable({}, { __index = Frame })
StatusBar.__index = StatusBar

function StatusBar:SetStatusBarTexture(asset)
	check(type(asset) == "string" or isNumber(asset), "SetStatusBarTexture: path or file id expected")
	self.barTexture = asset
end

function StatusBar:SetMinMaxValues(min, max)
	check(isNumberOrSecret(min) and isNumberOrSecret(max), "SetMinMaxValues: numbers expected")
	self.min, self.max = min, max
end

function StatusBar:SetValue(value)
	check(isNumberOrSecret(value), "SetValue: number expected")
	if isSecret(value) or isSecret(self.min) or isSecret(self.max) then
		self.value = value -- the client clamps secrets internally; tests only check it arrived
		return
	end
	self.value = math.max(self.min or 0, math.min(self.max or 1, value))
end

function StatusBar:GetValue()
	return self.value
end

function StatusBar:SetStatusBarColor(r, g, b, a)
	check(isColor(r, g, b), "SetStatusBarColor: numbers expected")
	self.barColor = { r, g, b, a or 1 }
end

function StatusBar:SetOrientation(orientation)
	check(orientation == "HORIZONTAL" or orientation == "VERTICAL", "SetOrientation: bad value")
	self.orientation = orientation
end

function StatusBar:SetReverseFill(reverse)
	self.reverseFill = not not reverse
end

local Button = setmetatable({}, { __index = Frame })
Button.__index = Button

function Button:SetText(text)
	self.text = text
end

function Button:GetText()
	return self.text
end

function Button:SetEnabled(enabled)
	self.enabled = not not enabled
end

function Button:Enable()
	self.enabled = true
end

function Button:Disable()
	self.enabled = false
end

function Button:IsEnabled()
	return self.enabled ~= false
end

function Button:Click(mouseButton)
	if self:IsEnabled() and self.scripts.OnClick then
		self.scripts.OnClick(self, mouseButton or "LeftButton", false)
	end
end

function Button:RegisterForClicks(...)
	self.clicks = {}
	for i = 1, select("#", ...) do
		local click = select(i, ...)
		check(CLICKS[click], "RegisterForClicks: bad click type " .. tostring(click))
		self.clicks[click] = true
	end
end

local CheckButton = setmetatable({}, { __index = Button })
CheckButton.__index = CheckButton

function CheckButton:SetChecked(checked)
	self.checked = not not checked
end

function CheckButton:GetChecked()
	return self.checked == true
end

function CheckButton:Click(mouseButton)
	self.checked = not self.checked
	Button.Click(self, mouseButton)
end

local Slider = setmetatable({}, { __index = Frame })
Slider.__index = Slider

function Slider:SetMinMaxValues(min, max)
	check(isNumber(min) and isNumber(max) and min <= max, "Slider:SetMinMaxValues: bad range")
	self.min, self.max = min, max
end

function Slider:SetValueStep(step)
	check(isNumber(step) and step > 0, "Slider:SetValueStep: positive number expected")
	self.step = step
end

function Slider:SetObeyStepOnDrag(obey)
	self.obeyStep = obey
end

function Slider:SetValue(value)
	check(isNumber(value), "Slider:SetValue: number expected")
	value = math.max(self.min or 0, math.min(self.max or 1, value))
	if value ~= self.value then
		self.value = value
		if self.scripts.OnValueChanged then
			self.scripts.OnValueChanged(self, value, false)
		end
	end
end

function Slider:GetValue()
	return self.value
end

local EditBox = setmetatable({}, { __index = Frame })
EditBox.__index = EditBox

function EditBox:SetText(text)
	check(type(text) == "string" or isNumber(text), "EditBox:SetText: string expected")
	self.text = tostring(text)
end

function EditBox:GetText()
	return self.text or ""
end

function EditBox:SetAutoFocus(autoFocus)
	self.autoFocus = autoFocus
end

function EditBox:SetJustifyH(justify)
	self.justifyH = justify
end

function EditBox:SetFontObject(font)
	check(FONTS[font], "EditBox:SetFontObject: unknown font object " .. tostring(font))
	self.fontObject = font
end

function EditBox:SetMaxLetters(letters)
	self.maxLetters = letters
end

function EditBox:SetFocus()
	if not self.focused then
		self.focused = true
		if self.scripts.OnEditFocusGained then
			self.scripts.OnEditFocusGained(self)
		end
	end
end

function EditBox:ClearFocus()
	if self.focused then
		self.focused = false
		if self.scripts.OnEditFocusLost then
			self.scripts.OnEditFocusLost(self)
		end
	end
end

function EditBox:HasFocus()
	return self.focused == true
end

-- A minimal Blizzard_Menu: SetupMenu(generator) calls generator(owner, root)
-- and the dropdown shows the selected radio's text.
local Dropdown = setmetatable({}, { __index = Frame })
Dropdown.__index = Dropdown

local function NewMenuDescription()
	local root = { items = {} }
	function root:CreateRadio(text, isSelected, setSelected, data)
		check(type(text) == "string", "CreateRadio: text expected")
		check(type(isSelected) == "function" and type(setSelected) == "function", "CreateRadio: callbacks expected")
		local item = { kind = "radio", text = text, isSelected = isSelected, setSelected = setSelected, data = data }
		self.items[#self.items + 1] = item
		return item
	end
	function root:CreateButton(text, callback, data)
		local item = { kind = "button", text = text, callback = callback, data = data }
		self.items[#self.items + 1] = item
		return item
	end
	function root:SetScrollMode(extent)
		check(isNumber(extent), "SetScrollMode: number expected")
		self.scrollExtent = extent
	end
	return root
end

function Dropdown:SetupMenu(generator)
	check(type(generator) == "function", "SetupMenu: generator expected")
	self.generator = generator
	self:GenerateMenu()
end

function Dropdown:GenerateMenu()
	local root = NewMenuDescription()
	self.generator(self, root)
	self.menu = root
	self.text = ""
	for _, item in ipairs(root.items) do
		if item.kind == "radio" and item.isSelected(item.data) then
			self.text = item.text
		end
	end
end

-- Test helper: choose the radio option with this text.
function Dropdown:Pick(text)
	for _, item in ipairs(self.menu.items) do
		if item.text == text then
			item.setSelected(item.data)
			self:GenerateMenu()
			return
		end
	end
	error("Dropdown:Pick: no option '" .. tostring(text) .. "'", 2)
end

local CLASSES = {
	Frame = Frame, StatusBar = StatusBar, Button = Button, CheckButton = CheckButton,
	Slider = Slider, EditBox = EditBox, DropdownButton = Dropdown,
}

---------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------
-- A few Classic foods (real item ids and levels) for the pet tests. diet is
-- the food type a pet must eat; buff food makes you well fed.
local ITEMS = {
	[117] = { name = "Tough Jerky", level = 5, diet = "Meat", icon = 133972 },
	[2287] = { name = "Haunch of Meat", level = 15, diet = "Meat", icon = 133970 },
	[3770] = { name = "Mutton Chop", level = 25, diet = "Meat", icon = 133974 },
	[3771] = { name = "Wild Hog Shank", level = 35, diet = "Meat", icon = 133971 },
	[8952] = { name = "Roasted Quail", level = 55, diet = "Meat", icon = 133973 },
	[12210] = { name = "Roast Raptor", level = 35, diet = "Meat", icon = 133969, buff = true },
	[787] = { name = "Slitherskin Mackerel", level = 5, diet = "Fish", icon = 133918 },
	[4540] = { name = "Tough Hunk of Bread", level = 5, diet = "Bread", icon = 133964 },
	[159] = { name = "Refreshing Spring Water", level = 5, icon = 132794 },
}

local STDLIB = {
	"assert", "error", "ipairs", "next", "pairs", "pcall", "rawequal", "rawget", "rawset",
	"select", "setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "xpcall",
	"math", "string", "table",
}

-- options: class, rangedSpeed (false = no ranged weapon), mainSpeed, worldLatency,
-- unknownEvents (set), missingGlobals (set of API names left undefined),
-- savedVariables (table)
function H.NewWorld(options)
	options = options or {}
	local rangedSpeed = options.rangedSpeed
	if rangedSpeed == nil then
		rangedSpeed = 2.0
	elseif rangedSpeed == false then
		rangedSpeed = nil
	end
	local W = {
		now = 1000,
		frames = {},
		timers = {},
		printed = {},
		sounds = {},
		blocked = {}, -- restricted calls the client would have blocked
		unknownEvents = options.unknownEvents or {},
		class = options.class or "HUNTER",
		rangedSpeed = rangedSpeed,
		mainSpeed = options.mainSpeed or 2.6,
		worldLatency = options.worldLatency or 80,
		statsSecret = false,
		inCombat = false,
		moving = false,
		falling = false,
		inRange = nil, -- Auto Shot range to the target: true, false or nil (no valid target)
		meleeInRange = nil, -- the same for melee abilities
		close = nil, -- CheckInteractDistance result (about 10 yards)
		hasTarget = false,
		pet = nil, -- { name =, level =, health =, healthMax =, dead =, happiness =, damage =, loyaltyRate =, loyalty =, diet =, training = { total, used } }
		dropPoint = nil,
		bags = {}, -- [bag] = { size = slots, [slot] = { itemID =, count = } }
		items = {}, -- [itemID] = { name =, level =, diet =, icon =, buff =, uncached = } (ITEMS)
		protectedFrames = {},
		casts = {}, -- spells cast by secure buttons
		used = {}, -- { bag =, slot = } items a secure button used as a spell's target
	}
	for itemID, item in pairs(ITEMS) do
		local copy = {}
		for key, value in pairs(item) do
			copy[key] = value
		end
		W.items[itemID] = copy
	end
	local env = {}
	W.env = env
	for _, name in ipairs(STDLIB) do
		env[name] = _G[name]
	end

	local function NewFrame(frameType, name, parent)
		local frame = setmetatable({
			world = W, frameType = frameType, name = name, parent = parent, shown = true,
			alpha = 1, scale = 1, points = {}, scripts = {}, events = {}, attributes = {},
		}, CLASSES[frameType])
		W.frames[#W.frames + 1] = frame
		if name then
			rawset(env, name, frame)
		end
		return frame
	end

	-- What SecureActionButton_OnClick (SecureTemplates.lua) does for type
	-- "spell": cast the spell, then, if it waits for an item target, use the
	-- item at target-bag / target-slot. It acts on the press or on the release,
	-- whichever the ActionButtonUseKeyDown setting picks, and ignores the other.
	local SUFFIXES = { LeftButton = "1", RightButton = "2", MiddleButton = "3" }
	local function SecureClick(button, mouseButton, down)
		if down ~= (W.cvars.ActionButtonUseKeyDown == "1") then
			return
		end
		local suffix = SUFFIXES[mouseButton] or ""
		local function Attribute(name)
			local value = button:GetAttribute(name .. suffix)
			if value == nil then
				value = button:GetAttribute(name)
			end
			return value
		end
		if Attribute("type") == "spell" then
			local spell = Attribute("spell")
			W.casts[#W.casts + 1] = spell
			local slot = Attribute("target-slot")
			if spell == 6991 and slot then -- Feed Pet waits for an item target
				W.used[#W.used + 1] = { bag = Attribute("target-bag"), slot = slot }
			end
		end
	end

	env.CreateFrame = function(frameType, name, parent, template)
		check(FRAME_TYPES[frameType], "CreateFrame: unsupported type " .. tostring(frameType))
		check(template == nil or (TEMPLATES[frameType] and TEMPLATES[frameType][template]),
			"CreateFrame: unknown template " .. tostring(template) .. " for " .. frameType)
		check(name == nil or type(name) == "string", "CreateFrame: name must be a string")
		local frame = NewFrame(frameType, name, parent)
		if template == "SecureActionButtonTemplate" then
			if W.inCombat then
				W.blocked[#W.blocked + 1] = "CreateFrame of a secure button"
			end
			frame.protected = true
			W.protectedFrames[#W.protectedFrames + 1] = frame
			frame.scripts.OnClick = SecureClick
		end
		return frame
	end
	env.UIParent = NewFrame("Frame", nil, nil)
	env.UIParent.isUIParent = true
	env.UIParent:SetSize(1920, 1080)

	local tooltip = NewFrame("Frame", nil, env.UIParent)
	function tooltip:SetOwner(owner)
		check(type(owner) == "table", "GameTooltip:SetOwner: owner expected")
		self.owner = owner
		self.lines = {}
	end
	function tooltip:SetText(text)
		self.lines[1] = text
	end
	function tooltip:AddLine(text)
		self.lines[#self.lines + 1] = text
	end
	tooltip:Hide()
	env.GameTooltip = tooltip

	env.SettingsPanel = NewFrame("Frame", nil, env.UIParent)
	env.SettingsPanel:Hide()
	env.HideUIPanel = function(frame)
		frame:Hide()
	end
	env.UISpecialFrames = {}

	env.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		W.printed[#W.printed + 1] = table.concat(parts, " ")
	end
	env.GetTime = function()
		return W.now
	end
	env.issecretvalue = function(value)
		return type(value) == "table" and getmetatable(value) == SECRET_MT
	end
	env.InCombatLockdown = function()
		return W.inCombat
	end

	local function stat(value)
		if W.statsSecret then
			return H.Secret(value)
		end
		return value
	end
	env.UnitClass = function(unit)
		check(unit == "player", "UnitClass: only the player is mocked")
		return W.class:sub(1, 1) .. W.class:sub(2):lower(), W.class, 3
	end
	env.UnitAttackSpeed = function(unit)
		check(unit == "player", "UnitAttackSpeed: only the player is mocked")
		return stat(W.mainSpeed), nil, W.rangedSpeed and stat(W.rangedSpeed)
	end
	env.UnitRangedDamage = function(unit)
		check(unit == "player", "UnitRangedDamage: only the player is mocked")
		return stat(W.rangedSpeed or 0), stat(10), stat(20), 0, 0, 1
	end
	env.UnitAffectingCombat = function()
		return W.inCombat
	end
	env.IsPlayerMoving = function()
		return W.moving
	end
	env.IsFalling = function()
		return W.falling
	end
	env.GetNetStats = function()
		return 0, 0, 40, W.worldLatency
	end
	env.C_Timer = {
		After = function(delay, callback)
			check(isNumber(delay) and type(callback) == "function", "C_Timer.After: bad arguments")
			W.timers[#W.timers + 1] = { at = W.now + delay, callback = callback }
		end,
	}
	local SPELL_NAMES = {
		[75] = "Auto Shot", [2973] = "Raptor Strike", [2974] = "Wing Clip", [1495] = "Mongoose Bite",
		[1130] = "Hunter's Mark", [14325] = "Hunter's Mark", [3044] = "Arcane Shot",
		[6991] = "Feed Pet", [19705] = "Well Fed",
	}
	local SPELL_TEXTURES = { [75] = 132222, [6991] = 132165 }
	local MELEE = { ["Raptor Strike"] = true, ["Wing Clip"] = true, ["Mongoose Bite"] = true }
	env.C_Spell = {
		IsSpellInRange = function(spell, unit)
			check(unit == "target", "IsSpellInRange: unexpected unit")
			if spell == 75 then
				return W.inRange
			elseif spell == "Hunter's Mark" then
				return W.hasTarget and W.markable ~= false or nil -- 100 yards: any attackable target
			end
			check(MELEE[spell], "IsSpellInRange: unexpected spell " .. tostring(spell))
			if spell == "Raptor Strike" then
				return W.meleeInRange
			end
			return nil -- not learned yet
		end,
		GetSpellTexture = function(spell)
			check(SPELL_TEXTURES[spell], "GetSpellTexture: unexpected spell " .. tostring(spell))
			return SPELL_TEXTURES[spell], SPELL_TEXTURES[spell]
		end,
		GetSpellName = function(spell)
			return SPELL_NAMES[spell]
		end,
	}
	env.UnitExists = function(unit)
		if unit == "target" then
			return W.hasTarget
		elseif unit == "pet" then
			return W.pet ~= nil
		end
		return unit == "player"
	end
	env.UnitIsDead = function(unit)
		check(unit == "pet", "UnitIsDead: only the pet is mocked")
		return W.pet ~= nil and W.pet.dead == true
	end
	env.UnitName = function(unit)
		check(unit == "pet", "UnitName: only the pet is mocked")
		return W.pet and W.pet.name, nil
	end
	env.UnitHealth = function(unit)
		check(unit == "pet", "UnitHealth: only the pet is mocked")
		return H.Secret(W.pet and W.pet.health or 0) -- SecretReturns in the API docs
	end
	env.UnitHealthMax = function(unit)
		check(unit == "pet", "UnitHealthMax: only the pet is mocked")
		return W.pet and W.pet.healthMax or 0
	end
	env.UnitLevel = function(unit)
		check(unit == "pet", "UnitLevel: only the pet is mocked")
		return W.pet and W.pet.level or 0
	end
	-- Bags hold { itemID, count } entries; the item details come from W.items.
	env.C_Container = {
		GetContainerNumSlots = function(bag)
			check(isNumber(bag), "GetContainerNumSlots: bag index expected")
			return W.bags[bag] and W.bags[bag].size or 0
		end,
		GetContainerItemInfo = function(bag, slot)
			check(isNumber(bag) and isNumber(slot), "GetContainerItemInfo: bag and slot expected")
			local entry = W.bags[bag] and W.bags[bag][slot]
			if not entry then
				return nil
			end
			local item = W.items[entry.itemID] or {}
			return {
				itemID = entry.itemID, stackCount = entry.count or 1, iconFileID = item.icon or 134400,
				itemName = item.name or "", hyperlink = "|Hitem:" .. entry.itemID .. "|h", quality = 1,
				isLocked = false, isBound = false,
			}
		end,
	}
	env.C_Item = {
		GetItemInfo = function(itemID)
			check(isNumber(itemID), "C_Item.GetItemInfo: item id expected")
			local item = W.items[itemID]
			if not item or item.uncached then
				return nil -- not in the client's item cache yet
			end
			return item.name, "|Hitem:" .. itemID .. "|h", 1, item.level, math.max(1, item.level - 10),
				"Consumable", "Food & Drink", 20, "", item.icon or 134400
		end,
	}
	env.C_TooltipInfo = {
		GetItemByID = function(itemID)
			check(isNumber(itemID), "GetItemByID: item id expected")
			local item = W.items[itemID]
			if not item then
				return nil
			end
			local use = "Use: Restores 243 health over 21 sec. Must remain seated while eating."
			if item.buff then
				use = use .. " If you spend at least 10 seconds eating you will become well fed and gain 6 Stamina and Spirit for 15 min."
			end
			return { type = 0, id = itemID, lines = { { leftText = item.name, type = 22 }, { leftText = use, type = 44 } } }
		end,
	}
	env.CheckInteractDistance = function(unit, index)
		check(unit == "target" and index == 3, "CheckInteractDistance: unexpected arguments")
		if W.inCombat then
			-- Restricted on enemies in combat. The client reports a blocked action,
			-- which pcall cannot hide, so record it rather than raising.
			W.blocked[#W.blocked + 1] = "CheckInteractDistance"
			return nil
		end
		return W.close
	end
	-- Target debuffs are secret in combat: the query returns nothing then,
	-- unless a test says this aura is readable (markReadableInCombat).
	env.C_UnitAuras = {
		GetAuraDataBySpellName = function(unit, name, filter)
			check(unit == "target" and name == "Hunter's Mark" and filter == "HARMFUL", "GetAuraDataBySpellName: unexpected arguments")
			if W.inCombat and not W.markReadableInCombat then
				return nil
			end
			return W.targetMarked and { name = name } or nil
		end,
	}
	local GAME_ERRORS = {
		[1] = "ERR_BADATTACKFACING", [2] = "SPELL_FAILED_UNIT_NOT_INFRONT", [3] = "SPELL_FAILED_LINE_OF_SIGHT",
		[4] = "SPELL_FAILED_TOO_CLOSE", [5] = "SPELL_FAILED_OUT_OF_RANGE", [6] = "ERR_OUT_OF_RANGE", [7] = "ERR_SPELL_COOLDOWN",
	}
	env.GetGameMessageInfo = function(index)
		check(isNumber(index), "GetGameMessageInfo: index expected")
		return GAME_ERRORS[index]
	end
	W.cvars = { cameraDistanceMaxZoomFactor = "1.9", ActionButtonUseKeyDown = "1" }
	env.C_CVar = {
		SetCVar = function(name, value)
			check(type(name) == "string" and type(value) == "string", "SetCVar: strings expected")
			W.cvars[name] = value
		end,
		GetCVar = function(name)
			return W.cvars[name]
		end,
		GetCVarDefault = function(name)
			return name == "cameraDistanceMaxZoomFactor" and "1.9" or nil
		end,
	}
	env.C_PetInfo = {
		GetPetHappiness = function()
			if W.pet then
				return W.pet.happiness, W.pet.damage, W.pet.loyaltyRate
			end
		end,
		GetPetLoyalty = function()
			return W.pet and W.pet.loyalty
		end,
		GetPetFoodTypes = function()
			return W.pet and W.pet.diet or {}
		end,
		GetPetTrainingPoints = function()
			if W.pet and W.pet.training then
				return W.pet.training[1], W.pet.training[2]
			end
			return 0, 0
		end,
		CanPetEatItem = function(itemID)
			check(isNumber(itemID), "CanPetEatItem: item id expected")
			local item = W.items[itemID]
			for _, diet in ipairs(W.pet and item and W.pet.diet or {}) do
				if diet == item.diet then
					return true
				end
			end
			return false
		end,
	}
	env.C_SwingTimer = {
		IsTargetWithinSwingRange = function(swingType)
			check(swingType == 2, "IsTargetWithinSwingRange: unexpected swing type")
			return nil -- broken on the beta builds that were tested
		end,
	}
	env.C_AddOns = {
		GetAddOnMetadata = function(addon, field)
			if addon == "Deadeye" and field == "Version" then
				return "0.2.0"
			end
		end,
	}
	env.Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
	env.SlashCmdList = {}
	env.GameFontHighlightSmall = {
		GetFont = function()
			return "Fonts\\FRIZQT__.TTF", 10, ""
		end,
	}
	env.SOUNDKIT = {
		IG_MAINMENU_OPTION_CHECKBOX_ON = 856,
		MAP_PING = 3175,
		UI_COUNTDOWN_TIMER = 158565,
		RAID_WARNING = 8959,
		ALARM_CLOCK_WARNING_3 = 12889,
	}
	env.PlaySound = function(id, channel)
		check(isNumber(id), "PlaySound: sound kit id expected")
		W.sounds[#W.sounds + 1] = { id = id, channel = channel }
	end
	env.ColorPickerFrame = {
		SetupColorPickerAndShow = function(_, info)
			check(isColor(info.r, info.g, info.b), "SetupColorPickerAndShow: r, g, b expected")
			check(type(info.swatchFunc) == "function", "SetupColorPickerAndShow: swatchFunc expected")
			W.colorPicker = info
			W.pickerColor = { info.r, info.g, info.b, info.opacity }
		end,
		GetColorRGB = function()
			return W.pickerColor[1], W.pickerColor[2], W.pickerColor[3]
		end,
		GetColorAlpha = function()
			return W.pickerColor[4] or 1
		end,
	}
	local callbacks = {}
	env.EventRegistry = {
		RegisterCallback = function(_, event, func, owner)
			check(type(event) == "string" and type(func) == "function", "RegisterCallback: bad arguments")
			callbacks[event] = callbacks[event] or {}
			table.insert(callbacks[event], { func, owner })
		end,
		TriggerEvent = function(_, event, ...)
			for _, callback in ipairs(callbacks[event] or {}) do
				callback[1](callback[2], ...)
			end
		end,
	}
	env.Settings = {
		RegisterCanvasLayoutCategory = function(frame, name)
			check(type(frame) == "table" and type(name) == "string", "RegisterCanvasLayoutCategory: bad arguments")
			local category = { frame = frame, name = name }
			function category:GetID()
				return 42
			end
			W.settingsCategory = category
			return category
		end,
		RegisterAddOnCategory = function(category)
			W.registeredCategory = category
		end,
		OpenToCategory = function(id)
			W.openedCategory = id
		end,
	}
	if options.savedVariables then
		env.DeadeyeDB = options.savedVariables
	end
	for name in pairs(options.missingGlobals or {}) do
		env[name] = nil
	end

	setmetatable(env, {
		__index = function(_, key)
			if ADDON_GLOBALS[key] or OPTIONAL_GLOBALS[key] or (options.missingGlobals and options.missingGlobals[key]) then
				return nil
			end
			error("read of undefined global '" .. tostring(key) .. "'", 2)
		end,
		__newindex = function(t, key, value)
			if not ADDON_GLOBALS[key] then
				error("write to unexpected global '" .. tostring(key) .. "'", 2)
			end
			rawset(t, key, value)
		end,
	})

	function W.Fire(event, ...)
		local unit = ...
		for _, frame in ipairs(W.frames) do
			local registration = frame.events[event]
			if registration and (registration == true or registration[unit]) then
				local onEvent = frame.scripts.OnEvent
				if onEvent then
					onEvent(frame, event, ...)
				end
			end
		end
	end

	local function RunTimers()
		local i = 1
		while i <= #W.timers do
			local timer = W.timers[i]
			if timer.at <= W.now + 1e-9 then
				table.remove(W.timers, i)
				timer.callback()
			else
				i = i + 1
			end
		end
	end

	local function RunOnUpdate(elapsed)
		for _, frame in ipairs(W.frames) do
			local onUpdate = frame.scripts.OnUpdate
			if onUpdate and frame:IsVisible() then
				onUpdate(frame, elapsed)
			end
		end
	end

	-- Advances the clock in small steps, running timers and OnUpdate scripts.
	function W.Advance(seconds, step)
		step = step or 0.02
		local target = W.now + seconds
		while W.now < target - 1e-9 do
			local delta = math.min(step, target - W.now)
			W.now = W.now + delta
			RunTimers()
			RunOnUpdate(delta)
		end
	end

	function W.Slash(input)
		W.env.SlashCmdList.DEADEYE(input)
	end

	-- A mouse click: the press, then the release, each running OnMouseDown /
	-- OnMouseUp and, if the button registered that click, OnClick.
	function W.Click(frame, mouseButton)
		mouseButton = mouseButton or "LeftButton"
		local clicks = frame.clicks or { LeftButtonUp = true } -- a Button's default
		for _, down in ipairs({ true, false }) do
			local direction = down and "Down" or "Up"
			local script = frame.scripts["OnMouse" .. direction]
			if script then
				script(frame, mouseButton)
			end
			if frame.scripts.OnClick and (clicks["Any" .. direction] or clicks[mouseButton .. direction]) then
				frame.scripts.OnClick(frame, mouseButton, down)
			end
		end
	end

	function W.IsProtected(frame)
		return IsProtected(frame)
	end

	function W.Printed(pattern)
		for _, line in ipairs(W.printed) do
			if line:find(pattern, 1, true) then
				return true
			end
		end
		return false
	end

	-- A player drag on a slider (snapped to its step, as SetObeyStepOnDrag does).
	function W.Drag(slider, value)
		if slider.obeyStep and slider.step then
			value = slider.min + math.floor((value - slider.min) / slider.step + 0.5) * slider.step
		end
		slider.value = math.max(slider.min, math.min(slider.max, value))
		slider.scripts.OnValueChanged(slider, slider.value, true)
	end

	-- Typing into an edit box and pressing Enter.
	function W.Type(box, text)
		box:SetFocus()
		box:SetText(text)
		box.scripts.OnEnterPressed(box)
	end

	-- The player picking a color (and alpha) in the open color picker.
	function W.PickColor(r, g, b, a)
		W.pickerColor = { r, g, b, a }
		W.colorPicker.swatchFunc()
		if W.colorPicker.hasOpacity then
			W.colorPicker.opacityFunc()
		end
	end

	return W
end

-- Loads the addon the way the client does: every file listed in the .toc, in
-- order, called with (addonName, namespace), then the login event sequence.
function H.LoadAddon(W, root)
	local files = {}
	for line in io.lines(root .. "/Deadeye.toc") do
		line = line:gsub("\r", "")
		if line ~= "" and not line:find("^##") then
			files[#files + 1] = line:gsub("\\", "/")
		end
	end
	local ns = {}
	for _, file in ipairs(files) do
		local chunk = assert(loadfile(root .. "/" .. file))
		setfenv(chunk, W.env)
		chunk("Deadeye", ns)
	end
	W.ns = ns
	W.Fire("ADDON_LOADED", "Deadeye")
	W.Fire("PLAYER_LOGIN")
	W.Fire("PLAYER_ENTERING_WORLD", true, false)
	return ns
end

---------------------------------------------------------------------------
-- Assertions
---------------------------------------------------------------------------
function H.Equal(actual, expected, what)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
	end
end

function H.Near(actual, expected, tolerance, what)
	if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
		error(string.format("%s: expected %s +/- %s, got %s", what or "value", tostring(expected), tostring(tolerance), tostring(actual)), 2)
	end
end

function H.True(value, what)
	if not value then
		error((what or "condition") .. " was not true", 2)
	end
end

function H.False(value, what)
	if value then
		error((what or "condition") .. " was not false", 2)
	end
end

function H.SameColor(actual, expected, what)
	for i = 1, 3 do
		if not actual or math.abs(actual[i] - expected[i]) > 1e-6 then
			error((what or "color") .. " does not match", 2)
		end
	end
end

return H
