-- The options window (/deadeye). Each enabled module can add pages by returning
-- them from module:GetOptionSections():
--   { name = "Bar",
--     keys = { "texture", ... },   -- settings that "Reset page" restores
--     controls = {                 -- laid out top to bottom in two columns
--       { type = "toggle" | "range" | "select" | "color" | "input" | "button" | "header" | "note",
--         label = "...", key = "path.in.module.db", ... },
--     } }
-- See Options\Widgets.lua for what each control type takes.
local _, ns = ...
local L = ns.L

local Window = {}
ns.OptionsWindow = Window

local WIDTH, HEIGHT = 720, 500
local NAV_WIDTH = 170
local TITLE_HEIGHT = 34
local FOOTER_HEIGHT = 46
local PADDING = 16
local COLUMN_GAP = 28
local SPACING = 8
local CONTENT_WIDTH = WIDTH - NAV_WIDTH - PADDING * 2
local CONTENT_HEIGHT = HEIGHT - TITLE_HEIGHT - FOOTER_HEIGHT - PADDING
local COLUMN_WIDTH = math.floor((CONTENT_WIDTH - COLUMN_GAP) / 2)
local RESET_CONFIRM_SECONDS = 3

local COLORS = {
	background = { 0.05, 0.05, 0.07, 0.97 },
	titleBar = { 0.11, 0.11, 0.14, 1 },
	nav = { 0.08, 0.08, 0.10, 1 },
	border = { 0.28, 0.28, 0.33, 1 },
	selected = { 0.67, 0.83, 0.45, 0.22 }, -- hunter green
}

local function Fill(frame, layer, color)
	local texture = frame:CreateTexture(nil, layer)
	texture:SetColorTexture(color[1], color[2], color[3], color[4])
	return texture
end

local function ForEachModule(callback)
	for _, module in ipairs(ns:GetModules()) do
		if module.enabled then
			callback(module)
		end
	end
end

function Window:CollectSections()
	local sections = {}
	ForEachModule(function(module)
		if module.GetOptionSections then
			for _, section in ipairs(module:GetOptionSections()) do
				section.module = module
				sections[#sections + 1] = section
			end
		end
	end)
	return sections
end

function Window:Create()
	local frame = CreateFrame("Frame", "DeadeyeOptionsFrame", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	-- Hide before the scripts go on: hiding a new (shown) frame fires OnHide.
	frame:Hide()
	frame:SetScript("OnShow", function()
		self:OnShow()
	end)
	frame:SetScript("OnHide", function()
		self:OnHide()
	end)
	-- Escape closes it like Blizzard's own windows.
	if UISpecialFrames then
		table.insert(UISpecialFrames, frame:GetName())
	end

	Fill(frame, "BACKGROUND", COLORS.background):SetAllPoints()
	for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
		local line = Fill(frame, "BORDER", COLORS.border)
		line:SetPoint(edge[1])
		line:SetPoint(edge[2])
		line:SetHeight(1)
	end
	for _, edge in ipairs({ { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local line = Fill(frame, "BORDER", COLORS.border)
		line:SetPoint(edge[1])
		line:SetPoint(edge[2])
		line:SetWidth(1)
	end

	local titleBar = Fill(frame, "ARTWORK", COLORS.titleBar)
	titleBar:SetPoint("TOPLEFT", 1, -1)
	titleBar:SetPoint("TOPRIGHT", -1, -1)
	titleBar:SetHeight(TITLE_HEIGHT)
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", titleBar, "LEFT", PADDING, 0)
	title:SetText(ns.title)
	local version = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
	version:SetText("v" .. ns.version)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	local nav = CreateFrame("Frame", nil, frame)
	nav:SetPoint("TOPLEFT", 1, -(TITLE_HEIGHT + 1))
	nav:SetPoint("BOTTOMLEFT", 1, 1)
	nav:SetWidth(NAV_WIDTH)
	Fill(nav, "BACKGROUND", COLORS.nav):SetAllPoints()

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", NAV_WIDTH + PADDING, -(TITLE_HEIGHT + PADDING))
	content:SetSize(CONTENT_WIDTH, CONTENT_HEIGHT)

	self.frame, self.nav, self.content = frame, nav, content
	self.pages, self.navButtons = {}, {}
	self.sections = self:CollectSections()
	self:BuildNavigation()
	self:BuildFooter()

	if #self.sections == 0 then
		local empty = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		empty:SetPoint("TOPLEFT")
		empty:SetText(L["Nothing to set up on this character: Deadeye's features are for hunters."])
		self.emptyText = empty
	end
end

function Window:BuildNavigation()
	for index, section in ipairs(self.sections) do
		local button = CreateFrame("Button", nil, self.nav)
		button:SetSize(NAV_WIDTH - 16, 26)
		button:SetPoint("TOPLEFT", 8, -(PADDING + (index - 1) * 30))
		button.selected = Fill(button, "BACKGROUND", COLORS.selected)
		button.selected:SetAllPoints()
		button.selected:Hide()
		local highlight = button:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.07)
		local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("LEFT", 10, 0)
		text:SetText(section.name)
		button:SetScript("OnClick", function()
			self:SelectSection(index)
		end)
		self.navButtons[index] = button
	end
end

function Window:BuildFooter()
	local frame = self.frame
	local line = Fill(frame, "ARTWORK", COLORS.border)
	line:SetPoint("BOTTOMLEFT", NAV_WIDTH + 1, FOOTER_HEIGHT)
	line:SetPoint("BOTTOMRIGHT", -1, FOOTER_HEIGHT)
	line:SetHeight(1)

	local preview = CreateFrame("CheckButton", nil, frame, "MinimalCheckboxTemplate")
	preview:SetSize(26, 26)
	preview:SetPoint("BOTTOMLEFT", NAV_WIDTH + PADDING - 4, 10)
	preview:SetScript("OnClick", function(button)
		ns.db.previewInOptions = button:GetChecked() and true or false
		self:UpdatePreview()
	end)
	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", preview, "RIGHT", 2, 0)
	label:SetText(L["Live preview"])
	self.previewCheck = preview

	local unlock = CreateFrame("CheckButton", nil, frame, "MinimalCheckboxTemplate")
	unlock:SetSize(26, 26)
	unlock:SetPoint("LEFT", label, "RIGHT", 18, 0)
	unlock:SetScript("OnClick", function(button)
		ns:SetLocked(not button:GetChecked(), true)
	end)
	local unlockLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	unlockLabel:SetPoint("LEFT", unlock, "RIGHT", 2, 0)
	unlockLabel:SetText(L["Unlock frames"])
	self.unlockCheck = unlock

	local resetAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	resetAll:SetSize(120, 22)
	resetAll:SetPoint("BOTTOMRIGHT", -PADDING, 12)
	resetAll:SetText(L["Reset all"])
	resetAll:SetScript("OnClick", function()
		self:ResetAll()
	end)
	self.resetAllButton = resetAll

	local resetPage = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	resetPage:SetSize(120, 22)
	resetPage:SetPoint("RIGHT", resetAll, "LEFT", -8, 0)
	resetPage:SetText(L["Reset page"])
	resetPage:SetScript("OnClick", function()
		self:ResetPage()
	end)
	self.resetPageButton = resetPage
end

function Window:BuildPage(section)
	local page = CreateFrame("Frame", nil, self.content)
	page:SetAllPoints()
	page.controls = {}
	local x, y = 0, 0
	for _, spec in ipairs(section.controls) do
		local widget = ns.Widgets.Create(page, spec, COLUMN_WIDTH, section.module)
		if y > 0 and y + widget.height > CONTENT_HEIGHT then
			x, y = x + COLUMN_WIDTH + COLUMN_GAP, 0
		end
		widget:SetPoint("TOPLEFT", x, -y)
		y = y + widget.height + SPACING
		page.controls[#page.controls + 1] = widget
	end
	return page
end

function Window:SelectSection(index)
	local section = self.sections[index]
	if not section then
		return
	end
	self.current = index
	if not self.pages[index] then
		self.pages[index] = self:BuildPage(section)
	end
	for i, page in pairs(self.pages) do
		page:SetShown(i == index)
	end
	for i, button in ipairs(self.navButtons) do
		button.selected:SetShown(i == index)
	end
	self.resetPageButton:SetEnabled(section.keys ~= nil)
	self:Refresh()
end

-- Re-reads every control on the visible page.
function Window:Refresh()
	local page = self.current and self.pages[self.current]
	if page then
		for _, widget in ipairs(page.controls) do
			widget:Refresh()
		end
	end
	self.previewCheck:SetChecked(ns.db.previewInOptions ~= false)
	self.unlockCheck:SetChecked(ns:IsUnlocked())
end

function Window:ResetPage()
	local section = self.sections[self.current]
	if not (section and section.keys) then
		return
	end
	local module = section.module
	for _, key in ipairs(section.keys) do
		ns.SetPath(module.db, key, ns.CopyTable(ns.GetPath(module.defaults, key)))
	end
	if module.OnSettingsReset then
		module:OnSettingsReset()
	end
	self:Refresh()
	ns.Print(L["Reset %s to defaults."]:format(section.name))
end

-- Asks for a second click within a few seconds before wiping everything.
function Window:ResetAll()
	local button = self.resetAllButton
	if self.confirmResetUntil and GetTime() < self.confirmResetUntil then
		self.confirmResetUntil = nil
		button:SetText(L["Reset all"])
		ns:ResetSettings()
		self:Refresh()
		ns.Print(L["All settings reset to defaults."])
		return
	end
	local deadline = GetTime() + RESET_CONFIRM_SECONDS
	self.confirmResetUntil = deadline
	button:SetText(L["Click to confirm"])
	C_Timer.After(RESET_CONFIRM_SECONDS, function()
		if self.confirmResetUntil == deadline then
			self.confirmResetUntil = nil
			button:SetText(L["Reset all"])
		end
	end)
end

function Window:UpdatePreview()
	local on = self.frame:IsShown() and ns.db.previewInOptions ~= false
	ForEachModule(function(module)
		if module.SetPreview then
			module:SetPreview(on)
		end
	end)
end

function Window:OnShow()
	if not self.current then
		self:SelectSection(1)
	end
	self.previewCheck:SetChecked(ns.db.previewInOptions ~= false)
	self:UpdatePreview()
	self:Refresh()
end

function Window:OnHide()
	self:UpdatePreview()
end

function Window:Open()
	if not self.frame then
		self:Create()
	end
	self.frame:Show()
end

function Window:Toggle()
	if self.frame and self.frame:IsShown() then
		self.frame:Hide()
	else
		self:Open()
	end
end

function Window:IsOpen()
	return self.frame ~= nil and self.frame:IsShown()
end

-- Finds a control on a page by its label; used by the tests.
function Window:GetControl(sectionName, label)
	for index, section in ipairs(self.sections or {}) do
		if section.name == sectionName then
			self:SelectSection(index)
			for _, widget in ipairs(self.pages[index].controls) do
				if widget.spec.label == label then
					return widget
				end
			end
		end
	end
end

-- Refreshes the open page on the next frame, so a control can finish handling
-- its own click or drag first and several changes cost one refresh.
function ns.OptionsChanged()
	if not Window:IsOpen() or Window.refreshQueued then
		return
	end
	Window.refreshQueued = true
	C_Timer.After(0, function()
		Window.refreshQueued = false
		if Window:IsOpen() then
			Window:Refresh()
		end
	end)
end

-- A page under Options > AddOns that points to the window.
function Window:RegisterSettingsCategory()
	if self.category or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		return
	end
	local panel = CreateFrame("Frame")
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(ns.title)
	local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetText(L["Deadeye's settings live in their own window with a live preview of the bar."])
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(220, 26)
	button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
	button:SetText(L["Open Deadeye options"])
	button:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() then
			HideUIPanel(SettingsPanel)
		end
		self:Open()
	end)
	self.category = Settings.RegisterCanvasLayoutCategory(panel, "Deadeye")
	Settings.RegisterAddOnCategory(self.category)
end
