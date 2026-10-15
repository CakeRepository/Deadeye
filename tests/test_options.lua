-- The options window and the /deadeye <setting> <value> chat commands.
local H, ROOT = ...

local RANGED = 2

local tests = {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

local function Setup(options)
	local W = H.NewWorld(options)
	H.LoadAddon(W, ROOT)
	local window = W.ns.OptionsWindow
	return W, window, W.ns.modules.AutoShot, W.ns.modules.AutoShot.bar
end

local function Open(W)
	W.Slash("")
	return W.ns.OptionsWindow
end

test("/deadeye opens and closes the window; Escape support and the AddOns page are set up", function()
	local W, window = Setup()
	H.True(W.registeredCategory ~= nil, "category under Options > AddOns")
	H.Equal(W.registeredCategory.name, "Deadeye", "category name")
	Open(W)
	H.True(window:IsOpen(), "open")
	H.Equal(W.env.UISpecialFrames[1], "DeadeyeOptionsFrame", "closes with Escape")
	local pages = 0
	for _, module in ipairs(W.ns:GetModules()) do
		if module.enabled and module.GetOptionSections then
			pages = pages + #module:GetOptionSections()
		end
	end
	H.Equal(#window.sections, pages, "every module's pages")
	H.Equal(#window.navButtons, pages, "a button for each in the list")
	H.True(pages >= 14, "Auto Shot, range, ammo, pet and camera pages at least")
	H.True(window.navButtons[1].selected:IsShown(), "first page selected")
	W.Slash("")
	H.False(window:IsOpen(), "closed")
	-- The button on the Options > AddOns page opens the window.
	W.Slash("options")
	window.frame:Hide()
	local panel = W.registeredCategory.frame
	local button
	for _, frame in ipairs(W.frames) do
		if frame.parent == panel and frame.frameType == "Button" then
			button = frame
		end
	end
	W.env.SettingsPanel:Show()
	button:Click()
	H.True(window:IsOpen(), "opened from the AddOns page")
	H.False(W.env.SettingsPanel:IsShown(), "Blizzard's settings panel steps aside")
end)

test("the live preview loops fake shots only while the window is open", function()
	local W, window, AS, bar = Setup()
	Open(W)
	H.True(AS.state.preview, "preview on")
	H.True(bar:IsVisible(), "bar shown")
	H.True(AS.state.fake, "fake cycle running")
	W.Advance(2.5)
	H.True(AS.state.fake, "still looping")
	window.previewCheck:Click()
	H.False(W.env.DeadeyeDB.previewInOptions, "preview setting saved")
	H.False(AS.state.preview, "preview off")
	H.False(bar:IsVisible(), "bar hidden without the preview")
	window.previewCheck:Click()
	H.True(bar:IsVisible(), "preview back on")
	window.frame:Hide()
	H.False(AS.state.preview, "preview stops when the window closes")
	H.False(bar:IsVisible(), "bar hidden again")
	H.Equal(AS.state.start, nil, "fake cycle cleared")
end)

test("real shots take over from the preview", function()
	local W, window, AS = Setup()
	Open(W)
	W.Fire("START_AUTOREPEAT_SPELL")
	H.False(AS.state.fake, "fake cycle dropped when Auto Shot starts")
	W.Fire("PLAYER_SWING", 2.0, RANGED)
	H.False(AS.state.fake, "real cycle")
	W.Fire("STOP_AUTOREPEAT_SPELL")
	W.Advance(2.1)
	H.True(AS.state.fake, "preview resumes after shooting stops")
end)

test("controls change settings and the bar follows", function()
	local W, window, AS, bar = Setup()
	Open(W)
	local width = window:GetControl("Position & Size", "Width")
	W.Drag(width.slider, 301.4)
	H.Equal(AS.db.width, 301, "slider snaps to whole pixels")
	H.Equal(bar.width, 301, "bar width")
	W.Advance(0.02)
	H.Equal(width.box:GetText(), "301", "number box follows the slider")
	W.Type(width.box, "250")
	H.Equal(AS.db.width, 250, "typed value")
	W.Type(width.box, "nonsense")
	H.Equal(AS.db.width, 250, "bad input ignored")
	H.Equal(width.box:GetText(), "250", "box shows the real value again")

	local scale = window:GetControl("Position & Size", "Scale")
	W.Type(scale.box, "1.234")
	H.Equal(AS.db.scale, 1.25, "scale snaps to its 0.05 step")

	local orientation = window:GetControl("Position & Size", "Orientation")
	H.Equal(orientation.dropdown.text, "Horizontal", "dropdown shows the current choice")
	orientation.dropdown:Pick("Vertical")
	H.Equal(AS.db.orientation, "VERTICAL", "picked")
	H.Equal(AS.db.height, 250, "width and height swapped")
	W.Advance(0.02)
	H.Equal(window:GetControl("Position & Size", "Height").box:GetText(), "250", "other controls refresh")

	local spark = window:GetControl("Bar", "Spark at the fill edge")
	H.True(spark.check:GetChecked(), "checkbox shows the setting")
	spark.check:Click()
	H.False(AS.db.showSpark, "unchecked")

	local reload = window:GetControl("Colors", "Reloading (move freely)")
	reload.swatch:Click()
	W.PickColor(0.1, 0.2, 0.3)
	H.SameColor(AS.db.colors.reload, { 0.1, 0.2, 0.3 }, "picked color")
	W.colorPicker.cancelFunc({ r = 0.95, g = 0.6, b = 0.15 })
	H.SameColor(AS.db.colors.reload, { 0.95, 0.6, 0.15 }, "cancel restores the color")

	local background = window:GetControl("Bar", "Background")
	background.swatch:Click()
	H.True(W.colorPicker.hasOpacity, "background offers opacity")
	W.PickColor(0.2, 0.2, 0.2, 0.8)
	H.Near(AS.db.background[4], 0.8, 1e-6, "opacity saved")

	local wording = window:GetControl("Wording", "While reloading")
	W.Type(wording.box, "Move!")
	H.Equal(AS.db.labels.reload, "Move!", "wording saved")
end)

test("dragging the bar updates the open position controls", function()
	local W, window, AS, bar = Setup()
	Open(W)
	local x = window:GetControl("Position & Size", "X offset from center")
	H.False(window.unlockCheck:GetChecked(), "footer shows the locked state")
	window:GetControl("Position & Size", "Unlock frames to drag them").check:Click()
	H.False(W.env.DeadeyeDB.locked, "unlocked from the window")
	W.dropPoint = { "CENTER", "CENTER", 120, 40 }
	bar.scripts.OnDragStop(bar)
	W.Advance(0.02)
	H.Equal(AS.db.position.x, 120, "position from the drag")
	H.Equal(x.box:GetText(), "120", "X control refreshed")
	H.True(window.unlockCheck:GetChecked(), "footer shows the unlocked state")
end)

test("reset page and reset all", function()
	local W, window, AS = Setup()
	Open(W)
	W.Slash("width 400")
	W.Slash("texture flat")
	window:GetControl("Position & Size", "Width")
	window.resetPageButton:Click()
	H.Equal(AS.db.width, 220, "page reset")
	H.Equal(AS.db.texture, "Flat", "other pages untouched")
	window.resetAllButton:Click()
	H.Equal(AS.db.texture, "Flat", "first click only asks")
	H.Equal(window.resetAllButton:GetText(), "Click to confirm", "asks for confirmation")
	window.resetAllButton:Click()
	H.Equal(AS.db.texture, "Blizzard", "second click resets everything")
	window.resetAllButton:Click()
	W.Advance(3.1)
	H.Equal(window.resetAllButton:GetText(), "Reset all", "confirmation expires")
end)

test("chat settings understand colors, choices and toggles", function()
	local W, window, AS = Setup()
	W.Slash("aimcolor #00ff00")
	H.SameColor(AS.db.colors.aim, { 0, 1, 0 }, "hex with #")
	W.Slash("aimcolor 0.5 0.5 0.5")
	H.SameColor(AS.db.colors.aim, { 0.5, 0.5, 0.5 }, "0-1 values")
	W.Slash("background 00000080")
	H.Near(AS.db.background[4], 128 / 255, 1e-6, "hex with opacity")
	W.Slash("aimcolor purple")
	H.True(W.Printed("Couldn't use 'purple' for Aim window (stand still)"), "bad color explained")
	W.Slash("label ins")
	H.Equal(AS.db.labelPosition, "LEFT", "prefix of the shown text picks the first match")
	W.Slash("label center")
	H.Equal(AS.db.labelPosition, "CENTER", "exact name")
	W.Slash("outline none")
	H.Equal(AS.db.fontOutline, "", "'none' for an empty value")
	W.Slash("spark toggle")
	H.False(AS.db.showSpark, "toggle flips")
	W.Slash("spark yes")
	H.True(AS.db.showSpark, "yes means on")
	W.Slash("center")
	H.True(W.Printed("Center horizontally: done."), "buttons run from chat")
	W.Slash("settings")
	H.True(W.Printed("Auto Shot bar settings"), "listing title")
	H.True(W.Printed("    width  220"), "listing shows values")
	H.True(W.Printed("    aimcolor  808080"), "colors listed as hex")
	H.True(W.Printed("  |cffffd100Timing & Alerts|r"), "listing grouped by page")
end)

test("prefixed chat settings reach the range and pet modules", function()
	local W, window = Setup()
	local Range, Pet = W.ns.modules.Range, W.ns.modules.Pet
	W.Slash("range fontsize 20")
	H.Equal(Range.db.fontSize, 20, "range setting")
	W.Slash("range off")
	H.False(Range.db.enabled, "/deadeye range off")
	W.Slash("range on")
	H.True(Range.db.enabled, "/deadeye range on")
	W.Slash("pet width 220")
	H.Equal(Pet.db.width, 220, "pet setting")
	W.Slash("pet bogus 1")
	H.True(W.Printed("No pet setting called 'bogus'"), "unknown prefixed setting")
	W.Slash("range")
	H.True(W.Printed("Range indicator settings"), "/deadeye range lists its settings")
	W.Slash("settings pet")
	H.True(W.Printed("Pet panel settings"), "/deadeye settings pet")
end)

return tests
