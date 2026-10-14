-- Controls for the options window. Widgets.Create builds one from a spec (see
-- Options\Window.lua) and returns a container frame with .height and :Refresh(),
-- which re-reads the setting. Every change calls ns.OptionsChanged() so the
-- rest of the open page can follow.
local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

local function Container(parent, width, height)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(width, height)
	frame.height = height
	return frame
end

local function Label(frame, text, font)
	local label = frame:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return label
end

local function AddTooltip(region, spec)
	if not spec.tooltip then
		return
	end
	region:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(spec.label or "", 1, 1, 1)
		GameTooltip:AddLine(spec.tooltip, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	region:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

local function Changed(set, value)
	set(value)
	ns.OptionsChanged()
end

function Widgets.toggle(parent, spec, width, get, set)
	local frame = Container(parent, width, 26)
	local check = CreateFrame("CheckButton", nil, frame, "MinimalCheckboxTemplate")
	check:SetSize(26, 26)
	check:SetPoint("LEFT", -4, 0)
	local label = Label(frame, spec.label)
	label:SetPoint("LEFT", check, "RIGHT", 2, 0)
	label:SetPoint("RIGHT", frame, "RIGHT")
	check:SetScript("OnClick", function(self)
		Changed(set, self:GetChecked() and true or false)
	end)
	AddTooltip(check, spec)
	frame.check = check
	function frame:Refresh()
		check:SetChecked(get() and true or false)
	end
	return frame
end

local function Decimals(step)
	local decimals = 0
	while step < 1 and decimals < 3 do
		step = step * 10
		decimals = decimals + 1
	end
	return decimals
end

-- Number formatting and snapping for "range" options, shared with Options\Slash.lua.
function Widgets.RangeFormat(spec)
	return "%." .. (spec.decimals or Decimals(spec.step or 1)) .. "f"
end

function Widgets.CleanRange(spec, value)
	local min, max, step = spec.min, spec.max, spec.step or 1
	value = min + math.floor((value - min) / step + 0.5) * step
	value = tonumber(string.format(Widgets.RangeFormat(spec), value))
	return math.max(min, math.min(max, value))
end

-- A slider plus a box for typing an exact value.
function Widgets.range(parent, spec, width, get, set)
	local frame = Container(parent, width, 46)
	local label = Label(frame, spec.label)
	label:SetPoint("TOPLEFT")
	local min, max, step = spec.min, spec.max, spec.step or 1
	local format = Widgets.RangeFormat(spec)

	local function Clean(value)
		return Widgets.CleanRange(spec, value)
	end

	local slider = CreateFrame("Slider", nil, frame, "UISliderTemplate")
	slider:SetPoint("TOPLEFT", 2, -22)
	slider:SetSize(width - 70, 16)
	slider:SetMinMaxValues(min, max)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)

	local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	box:SetSize(48, 20)
	box:SetPoint("LEFT", slider, "RIGHT", 14, 0)
	box:SetAutoFocus(false)
	box:SetJustifyH("CENTER")
	box:SetFontObject("GameFontHighlightSmall")

	local function Commit(value)
		value = Clean(value)
		if value ~= get() then
			Changed(set, value)
		end
	end

	-- frame.updating is set while Refresh moves the slider, so only drags count.
	slider:SetScript("OnValueChanged", function(_, value)
		if frame.updating then
			return
		end
		Commit(value)
		box:SetText(string.format(format, Clean(value)))
	end)
	box:SetScript("OnEnterPressed", function(self)
		local value = tonumber(self:GetText())
		if value then
			Commit(value)
		end
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(string.format(format, get()))
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusLost", function()
		frame:Refresh()
	end)
	AddTooltip(slider, spec)

	frame.slider, frame.box = slider, box
	function frame:Refresh()
		local value = get()
		frame.updating = true
		slider:SetValue(value)
		frame.updating = false
		if not box:HasFocus() then
			box:SetText(string.format(format, value))
		end
	end
	return frame
end

-- spec.values: list of { value = ..., text = ... }, or a function returning one.
function Widgets.select(parent, spec, width, get, set)
	local frame = Container(parent, width, 50)
	local label = Label(frame, spec.label)
	label:SetPoint("TOPLEFT")
	local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("TOPLEFT", 0, -18)
	dropdown:SetWidth(width - 12)
	dropdown:SetupMenu(function(_, root)
		local values = type(spec.values) == "function" and spec.values() or spec.values
		if #values > 18 then
			root:SetScrollMode(18 * 20)
		end
		for _, option in ipairs(values) do
			root:CreateRadio(option.text, function()
				return get() == option.value
			end, function()
				Changed(set, option.value)
			end)
		end
	end)
	frame.dropdown = dropdown
	function frame:Refresh()
		dropdown:GenerateMenu()
	end
	return frame
end

-- Colors are stored as { r, g, b } or, with spec.alpha, { r, g, b, a }.
function Widgets.color(parent, spec, width, get, set)
	local frame = Container(parent, width, 26)
	local swatch = CreateFrame("Button", nil, frame)
	swatch:SetSize(20, 20)
	swatch:SetPoint("LEFT", 2, 0)
	local edge = swatch:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(0.75, 0.75, 0.75, 1)
	local fill = swatch:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", 2, -2)
	fill:SetPoint("BOTTOMRIGHT", -2, 2)
	local label = Label(frame, spec.label)
	label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
	label:SetPoint("RIGHT", frame, "RIGHT")

	local function Apply(r, g, b, a)
		local color = { r, g, b }
		if spec.alpha then
			color[4] = a or 1
		end
		Changed(set, color)
		frame:Refresh()
	end
	swatch:SetScript("OnClick", function()
		local color = get()
		local function OnColorChanged()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			Apply(r, g, b, spec.alpha and ColorPickerFrame:GetColorAlpha() or nil)
		end
		ColorPickerFrame:SetupColorPickerAndShow({
			r = color[1],
			g = color[2],
			b = color[3],
			opacity = color[4] or 1,
			hasOpacity = spec.alpha and true or false,
			swatchFunc = OnColorChanged,
			opacityFunc = OnColorChanged,
			cancelFunc = function(previous)
				Apply(previous.r, previous.g, previous.b, previous.a)
			end,
		})
	end)
	AddTooltip(swatch, spec)

	frame.swatch = swatch
	function frame:Refresh()
		local color = get()
		fill:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	end
	return frame
end

function Widgets.input(parent, spec, width, get, set)
	local frame = Container(parent, width, 46)
	local label = Label(frame, spec.label)
	label:SetPoint("TOPLEFT")
	local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	box:SetSize(width - 20, 20)
	box:SetPoint("TOPLEFT", 6, -20)
	box:SetAutoFocus(false)
	box:SetMaxLetters(spec.maxLetters or 40)
	box:SetFontObject("GameFontHighlightSmall")
	local function Commit()
		local text = box:GetText()
		if text ~= get() then
			Changed(set, text)
		end
	end
	box:SetScript("OnEnterPressed", function(self)
		Commit()
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusLost", Commit)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(get() or "")
		self:ClearFocus()
	end)
	frame.box = box
	function frame:Refresh()
		if not box:HasFocus() then
			box:SetText(get() or "")
		end
	end
	return frame
end

function Widgets.button(parent, spec, width)
	local frame = Container(parent, width, 30)
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetSize(math.min(width - 10, spec.width or 180), 22)
	button:SetPoint("LEFT")
	button:SetText(spec.label)
	button:SetScript("OnClick", function()
		spec.func()
		ns.OptionsChanged()
	end)
	AddTooltip(button, spec)
	frame.button = button
	function frame:Refresh() end
	return frame
end

function Widgets.header(parent, spec, width)
	local frame = Container(parent, width, 26)
	local label = Label(frame, spec.label, "GameFontNormal")
	label:SetPoint("BOTTOMLEFT", 0, 5)
	local line = frame:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 0.82, 0, 0.3)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	function frame:Refresh() end
	return frame
end

function Widgets.note(parent, spec, width)
	local frame = Container(parent, width, spec.height or 34)
	local text = Label(frame, spec.text, "GameFontDisableSmall")
	text:SetPoint("TOPLEFT")
	text:SetPoint("TOPRIGHT")
	text:SetWordWrap(true)
	function frame:Refresh() end
	return frame
end

-- spec.key is a dotted path into module.db; spec.get / spec.set override it.
function Widgets.Accessors(module, spec)
	local get = spec.get or function()
		return ns.GetPath(module.db, spec.key)
	end
	local set = spec.set or function(value)
		ns.SetPath(module.db, spec.key, value)
		if module.OnOptionChanged then
			module:OnOptionChanged(spec.key)
		end
	end
	return get, set
end

function Widgets.Create(parent, spec, width, module)
	local build = Widgets[spec.type]
	if not build then
		error("ForeverHunter: unknown option type " .. tostring(spec.type))
	end
	local get, set = Widgets.Accessors(module, spec)
	local widget = build(parent, spec, width, get, set)
	widget.spec = spec
	return widget
end
