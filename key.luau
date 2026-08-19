--// Meridian · access
--//
--// The key screen, built by hand rather than out of Maclib. Maclib gives you a
--// window with tabs, a profile card and a globe, and every one of those tells a
--// stranger something about the hub before they have earned the right to see
--// it. This shows four rows and a name, and nothing else.
--//
--// It also owns the unlock: the panel folds down into a loading card, the bar
--// tracks work that is genuinely happening, and then the hub fades up behind
--// it. Nothing here is a fake progress bar.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Access = {}

-- White mark first, the grey original as the fallback. core:UseAsset takes the
-- first that this account can actually fetch.
local MARK_IDS = {
	"rbxassetid://123910318474386",
	"rbxassetid://140486334564423",
}
local DISCORD_IDS = {
	"rbxassetid://100809646340840",
	"rbxassetid://119552564035204",
}

local MARK = MARK_IDS[1]
local KEY_ICON = "rbxassetid://7541891753"
local LOCK_ICON = "rbxassetid://10723434711"
local RESIZE_ICON = "rbxassetid://107014513554812"
local GLOW = "rbxassetid://8992230677"
-- Maclib's own button chevron, read off a live Button rather than picked to
-- look similar. A different arrow was the thing that made this screen read as
-- another library's work.
local CHEVRON = "rbxassetid://10709791437"

local DISCORD_ICON = DISCORD_IDS[1]

local PANEL_BG = Color3.fromRGB(15, 15, 15)
local TEXT = Color3.fromRGB(255, 255, 255)
local QUIET = Color3.fromRGB(146, 146, 154)

-- Measured off a live Maclib section so the rows here are the same object the
-- rest of the hub is made of, not an approximation of it.
local SECTION_TINT = Color3.fromRGB(255, 255, 255)
local SECTION_TRANSPARENCY = 0.98
local SECTION_STROKE = 0.88
local ROW_HEIGHT = 46

local MONO_RAMP = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(168, 168, 172)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(28, 28, 30)),
})

local FAST = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SMOOTH = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function tween(instance, info, goal)
	local play = TweenService:Create(instance, info, goal)
	play:Play()
	return play
end

local function corner(parent, radius)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, radius)
	round.Parent = parent
	return round
end

local function stroke(parent, transparency, gradient)
	local line = Instance.new("UIStroke")
	line.Thickness = 1
	line.Color = Color3.fromRGB(255, 255, 255)
	line.Transparency = transparency
	line.Parent = parent
	if gradient then
		local ramp = Instance.new("UIGradient")
		ramp.Color = MONO_RAMP
		ramp.Parent = line
		return line, ramp
	end
	return line
end

-- The mark is drawn in thin strokes, so one ImageLabel renders it grey however
-- white you colour it: the anti-aliasing along every stroke is mostly
-- background. Two stacked copies double the coverage of those strokes and it
-- reads white, without anyone having to redraw the artwork.
-- Measured, by rendering the mark at 1, 2, 4 and 8 stacked copies beside a pure
-- white square: all four are identically grey. Stacking only helps when the
-- greyness is anti-aliasing eating a thin white stroke. It is not. The uploaded
-- artwork is grey, and ImageColor3 multiplies, so nothing here can lighten it.
-- One layer, and the asset needs re-exporting white.
local function stackedImage(parent, image, size, layers)
	local holder = Instance.new("Frame")
	holder.Name = "Mark"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	holder.Parent = parent

	for index = 1, layers or 1 do
		local layer = Instance.new("ImageLabel")
		layer.Name = "Layer" .. index
		layer.BackgroundTransparency = 1
		layer.Image = image
		layer.ImageColor3 = Color3.fromRGB(255, 255, 255)
		layer.ImageTransparency = 0
		layer.Size = UDim2.fromScale(1, 1)
		layer.Parent = holder
	end

	return holder
end

local function brightMark(parent, size, layers)
	return stackedImage(parent, MARK, size, layers)
end

-- Kept as the fallback for a machine that cannot fetch the uploaded glyph.
local function drawDiscord(parent, size)
	local holder = Instance.new("Frame")
	holder.Name = "DiscordMark"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	holder.Parent = parent

	local shell = Instance.new("Frame")
	shell.Name = "Shell"
	shell.BackgroundColor3 = TEXT
	shell.BackgroundTransparency = 0.15
	shell.BorderSizePixel = 0
	shell.AnchorPoint = Vector2.new(0.5, 0.5)
	shell.Position = UDim2.fromScale(0.5, 0.45)
	shell.Size = UDim2.fromOffset(size, math.floor(size * 0.74))
	shell.Parent = holder
	corner(shell, math.floor(size * 0.34))

	for index = 1, 2 do
		local eye = Instance.new("Frame")
		eye.Name = "Eye" .. index
		eye.BackgroundColor3 = PANEL_BG
		eye.BorderSizePixel = 0
		eye.AnchorPoint = Vector2.new(0.5, 0.5)
		eye.Position = UDim2.fromScale(index == 1 and 0.32 or 0.68, 0.5)
		eye.Size = UDim2.fromOffset(math.max(2, size // 6), math.max(3, size // 5))
		eye.Parent = shell
		corner(eye, size)
	end

	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.BackgroundColor3 = TEXT
	tail.BackgroundTransparency = 0.15
	tail.BorderSizePixel = 0
	tail.Rotation = 20
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.fromScale(0.3, 0.88)
	tail.Size = UDim2.fromOffset(math.floor(size * 0.3), math.floor(size * 0.3))
	tail.Parent = holder
	corner(tail, 2)

	return holder
end

--------------------------------------------------------------------------------
-- the panel
--------------------------------------------------------------------------------

local WIDTH, HEIGHT = 404, 356

function Access.Ask(options)
	local core = options.core
	local brand = options.brand or "Meridian Hub"
	local discord = options.discord
	local verify = options.verify
	local onUnlocked = options.onUnlocked

	local parent = game:GetService("CoreGui")
	local ok, hidden = pcall(function()
		return gethui()
	end)
	if ok and hidden then
		parent = hidden
	end

	for _, existing in ipairs(parent:GetChildren()) do
		if existing.Name == "MeridianAccess" then
			pcall(function()
				existing:Destroy()
			end)
		end
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "MeridianAccess"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 100
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = parent
	core:Track(screen)

	-- Sweep any blur an earlier run left behind. If the script is replaced while
	-- this screen is still up there is no hub to unload, so that run's blur
	-- survived in Lighting at full strength and the game stayed soft forever.
	-- They stack, too: three of them were found during testing.
	for _, effect in ipairs(Lighting:GetChildren()) do
		if effect:IsA("BlurEffect") and effect.Name == "MeridianAccessBlur" then
			pcall(function()
				effect:Destroy()
			end)
		end
	end

	local blur = Instance.new("BlurEffect")
	blur.Name = "MeridianAccessBlur"
	blur.Size = 0
	blur.Parent = Lighting
	core:Track(blur)
	tween(blur, SMOOTH, { Size = 16 })

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	panel.BackgroundColor3 = PANEL_BG
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Parent = screen
	corner(panel, 12)

	local edge, edgeRamp = stroke(panel, 0.55, true)
	local phase = 0
	core:Connect(RunService.RenderStepped, function(dt)
		phase = (phase + dt * 6) % 360
		edgeRamp.Rotation = phase
	end)

	local grow = Instance.new("UIScale")
	grow.Scale = 0.94
	grow.Parent = panel
	tween(grow, TweenInfo.new(0.36, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })

	-- Dragging, because a panel pinned to the middle of the screen while the
	-- game is running underneath is a nuisance.
	do
		local dragging, startInput, startPos = false, nil, nil
		core:Connect(panel.InputBegan, function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging, startInput, startPos = true, input.Position, panel.Position
			end
		end)
		core:Connect(UserInputService.InputEnded, function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = false
			end
		end)
		core:Connect(UserInputService.InputChanged, function(input)
			if not dragging or not startInput then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				local delta = input.Position - startInput
				panel.Position = UDim2.new(
					startPos.X.Scale,
					startPos.X.Offset + delta.X,
					startPos.Y.Scale,
					startPos.Y.Offset + delta.Y
				)
			end
		end)
	end

	----------------------------------------------------------------------------
	-- window controls
	----------------------------------------------------------------------------
	--
	-- Without these you could not leave. The panel had no close, so anyone who
	-- opened it without a key was stuck with it on screen until they rejoined.

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = ""
	close.AutoButtonColor = false
	close.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	close.BackgroundTransparency = 0.92
	close.BorderSizePixel = 0
	close.Size = UDim2.fromOffset(26, 26)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.ZIndex = 20
	close.Parent = panel
	corner(close, 7)

	for index = 1, 2 do
		local bar = Instance.new("Frame")
		bar.BackgroundColor3 = TEXT
		bar.BackgroundTransparency = 0.25
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(11, 1)
		bar.Rotation = index == 1 and 45 or -45
		bar.ZIndex = 21
		bar.Parent = close
	end

	core:Connect(close.MouseEnter, function()
		tween(close, FAST, { BackgroundTransparency = 0.84 })
	end)
	core:Connect(close.MouseLeave, function()
		tween(close, FAST, { BackgroundTransparency = 0.92 })
	end)
	core:Connect(close.MouseButton1Click, function()
		task.spawn(function()
			tween(blur, SMOOTH, { Size = 0 })
			tween(grow, SMOOTH, { Scale = 0.94 })
			tween(panel, SMOOTH, { BackgroundTransparency = 1 })
			tween(edge, SMOOTH, { Transparency = 1 })
			for _, descendant in ipairs(panel:GetDescendants()) do
				if descendant:IsA("TextLabel") or descendant:IsA("TextBox") then
					tween(descendant, SMOOTH, { TextTransparency = 1 })
				elseif descendant:IsA("ImageLabel") then
					tween(descendant, SMOOTH, { ImageTransparency = 1 })
				elseif descendant:IsA("GuiObject") then
					tween(descendant, SMOOTH, { BackgroundTransparency = 1 })
				end
			end
			task.wait(0.32)
			pcall(function()
				screen:Destroy()
			end)
			pcall(function()
				blur:Destroy()
			end)
			core:Unload()
			getgenv().Meridian = nil
		end)
	end)

	-- The same grip the hub uses, same asset, same lift.
	local grip = Instance.new("TextButton")
	grip.Name = "ResizeGrip"
	grip.Text = ""
	grip.AutoButtonColor = false
	grip.BackgroundTransparency = 1
	grip.Size = UDim2.fromOffset(22, 22)
	grip.AnchorPoint = Vector2.new(1, 1)
	grip.Position = UDim2.new(1, -6, 1, -6)
	grip.ZIndex = 20
	grip.Parent = panel

	local gripMark = Instance.new("ImageLabel")
	gripMark.Name = "GripMark"
	gripMark.BackgroundTransparency = 1
	gripMark.Image = RESIZE_ICON
	gripMark.ImageColor3 = Color3.fromRGB(255, 255, 255)
	gripMark.ImageTransparency = 0.6
	gripMark.AnchorPoint = Vector2.new(0.5, 0.5)
	gripMark.Position = UDim2.fromScale(0.5, 0.5)
	gripMark.Size = UDim2.fromOffset(13, 13)
	gripMark.ZIndex = 20
	gripMark.Parent = grip

	core:Connect(grip.MouseEnter, function()
		tween(gripMark, FAST, { ImageTransparency = 0.1, Size = UDim2.fromOffset(16, 16) })
	end)
	core:Connect(grip.MouseLeave, function()
		tween(gripMark, FAST, { ImageTransparency = 0.6, Size = UDim2.fromOffset(13, 13) })
	end)

	do
		local resizing, startInput, startSize = false, nil, nil
		core:Connect(grip.InputBegan, function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				resizing, startInput, startSize = true, input.Position, panel.AbsoluteSize
			end
		end)
		core:Connect(UserInputService.InputEnded, function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				resizing = false
			end
		end)
		core:Connect(UserInputService.InputChanged, function(input)
			if not resizing or not startInput then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				local delta = input.Position - startInput
				panel.Size = UDim2.fromOffset(
					math.clamp(startSize.X + delta.X, 340, 720),
					math.clamp(startSize.Y + delta.Y, 300, 620)
				)
			end
		end)
	end

	----------------------------------------------------------------------------
	-- head
	----------------------------------------------------------------------------

	-- Both sit on the panel rather than a header frame, so the ceremony can move
	-- the mark to the middle of the whole panel rather than the middle of a
	-- strip at the top of it.
	local mark = brightMark(panel, 76)
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.new(0.5, 0, 0, 62)
	-- Explicitly above the glow. Relying on the default left the light sitting
	-- over the logo rather than behind it.
	mark.ZIndex = 6
	for _, layer in ipairs(mark:GetChildren()) do
		layer.ZIndex = 6
		core:UseAsset("mark", MARK_IDS, layer)
	end

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Text = brand
	title.Font = Enum.Font.GothamBold
	title.TextSize = 19
	title.TextColor3 = TEXT
	title.Size = UDim2.new(1, 0, 0, 24)
	title.Position = UDim2.new(0, 0, 0, 96)
	title.Parent = panel

	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	rule.BackgroundTransparency = 0.9
	rule.BorderSizePixel = 0
	rule.Size = UDim2.new(1, -44, 0, 1)
	rule.Position = UDim2.new(0, 22, 0, 132)
	rule.Parent = panel

	----------------------------------------------------------------------------
	-- rows
	----------------------------------------------------------------------------

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.new(0, 22, 0, 152)
	rows.Size = UDim2.new(1, -44, 0, 160)
	rows.Parent = panel

	local stack = Instance.new("UIListLayout")
	stack.Padding = UDim.new(0, 10)
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Parent = rows

	-- Same fill, same corner, same stroke as a Maclib section, plus the mono
	-- gradient the rest of the hub carries on its edges.
	local function makeRow(order, height)
		local row = Instance.new("Frame")
		row.Name = "Row" .. order
		row.LayoutOrder = order
		row.BackgroundColor3 = SECTION_TINT
		row.BackgroundTransparency = SECTION_TRANSPARENCY
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, height or ROW_HEIGHT)
		row.Parent = rows
		corner(row, 8)
		local edge, ramp = stroke(row, SECTION_STROKE, true)
		ramp.Rotation = 20
		row:SetAttribute("Edge", true)
		return row, edge
	end

	-- Stacked, and never dimmed. A single layer renders these marks grey however
	-- white you colour them, because most of every thin stroke is anti-aliased
	-- into the background behind it.
	local function iconInto(row, image, size)
		local icon = stackedImage(row, image, size or 18, 1)
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 16, 0.5, 0)
		return icon
	end

	local function chevronInto(row)
		local chevron = Instance.new("ImageLabel")
		chevron.Name = "Chevron"
		chevron.BackgroundTransparency = 1
		chevron.Image = CHEVRON
		chevron.ImageColor3 = Color3.fromRGB(255, 255, 255)
		chevron.ImageTransparency = 0.5
		chevron.Size = UDim2.fromOffset(15, 15)
		chevron.AnchorPoint = Vector2.new(1, 0.5)
		chevron.Position = UDim2.new(1, -16, 0.5, 0)
		chevron.Parent = row
		return chevron
	end

	-- row one: the key itself
	local keyRow = makeRow(1)
	iconInto(keyRow, LOCK_ICON)

	local field = Instance.new("TextBox")
	field.Name = "Field"
	field.BackgroundTransparency = 1
	field.ClearTextOnFocus = false
	field.Text = ""
	field.PlaceholderText = "Key"
	field.PlaceholderColor3 = Color3.fromRGB(104, 104, 112)
	field.Font = Enum.Font.GothamMedium
	field.TextSize = 13
	field.TextColor3 = TEXT
	field.TextXAlignment = Enum.TextXAlignment.Left
	field.AnchorPoint = Vector2.new(0, 0.5)
	field.Position = UDim2.new(0, 46, 0.5, 0)
	field.Size = UDim2.new(1, -92, 1, -10)
	field.Parent = keyRow

	local submit = Instance.new("TextButton")
	submit.Name = "Submit"
	submit.Text = ""
	submit.AutoButtonColor = false
	submit.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	submit.BackgroundTransparency = 1
	submit.BorderSizePixel = 0
	submit.Size = UDim2.fromOffset(30, 30)
	submit.AnchorPoint = Vector2.new(1, 0.5)
	submit.Position = UDim2.new(1, -9, 0.5, 0)
	submit.Parent = keyRow
	corner(submit, 7)

	local submitIcon = Instance.new("ImageLabel")
	submitIcon.Name = "Chevron"
	submitIcon.BackgroundTransparency = 1
	submitIcon.Image = CHEVRON
	submitIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
	submitIcon.ImageTransparency = 0.5
	submitIcon.Size = UDim2.fromOffset(15, 15)
	submitIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	submitIcon.Position = UDim2.fromScale(0.5, 0.5)
	submitIcon.Parent = submit

	-- rows two and three: where a key comes from, and where we live
	local function linkRow(order, text, build)
		local row = makeRow(order)
		build(row)

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Text = text
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 13
		label.TextColor3 = TEXT
		label.TextTransparency = 0.12
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.new(0, 46, 0.5, 0)
		label.Size = UDim2.new(1, -84, 1, 0)
		label.Parent = row

		local chevron = chevronInto(row)

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.Parent = row

		-- The same lift the hub's own rows use: the fill brightens and the
		-- chevron steps in a little. No colour that is not on the grey ramp.
		core:Connect(hit.MouseEnter, function()
			tween(row, FAST, { BackgroundTransparency = 0.94 })
			tween(chevron, FAST, { ImageTransparency = 0.2, Position = UDim2.new(1, -13, 0.5, 0) })
		end)
		core:Connect(hit.MouseLeave, function()
			tween(row, FAST, { BackgroundTransparency = SECTION_TRANSPARENCY })
			tween(chevron, FAST, { ImageTransparency = 0.5, Position = UDim2.new(1, -16, 0.5, 0) })
		end)

		return row, hit
	end

	local status

	local _, getHit = linkRow(2, "Get a key", function(row)
		iconInto(row, KEY_ICON)
	end)
	local _, discordHit = linkRow(3, "Discord", function(row)
		local icon = iconInto(row, DISCORD_ICON, 18)
		for _, layer in ipairs(icon:GetChildren()) do
			core:UseAsset("discord", DISCORD_IDS, layer)
		end
	end)

	status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Text = ""
	status.Font = Enum.Font.GothamMedium
	status.TextSize = 12
	status.TextColor3 = QUIET
	status.TextTransparency = 0.15
	status.Size = UDim2.new(1, -44, 0, 18)
	status.Position = UDim2.new(0, 22, 1, -30)
	status.Parent = panel

	----------------------------------------------------------------------------
	-- unlocking
	----------------------------------------------------------------------------

	local finished = false
	local checking = false

	local function say(text, bad)
		status.Text = text
		status.TextColor3 = bad and Color3.fromRGB(214, 96, 92) or QUIET
	end

	-- The panel folds down into a loading card. Everything that was a key screen
	-- fades out first so the two never overlap.
	local function ceremony()
		-- The close cross and the resize grip belong to the key screen, not to
		-- the unlock. Leaving them on top of the glow while everything else
		-- fades meant the one moment that is supposed to be just the mark had
		-- two pieces of window furniture floating over it.
		for _, chrome in ipairs({ close, grip }) do
			chrome.Active = false
			for _, descendant in ipairs(chrome:GetDescendants()) do
				if descendant:IsA("ImageLabel") then
					tween(descendant, FAST, { ImageTransparency = 1 })
				elseif descendant:IsA("GuiObject") then
					tween(descendant, FAST, { BackgroundTransparency = 1 })
				end
			end
			tween(chrome, FAST, { BackgroundTransparency = 1 })
		end
		task.delay(0.22, function()
			close.Visible = false
			grip.Visible = false
		end)

		for _, instance in ipairs({ rows, rule, status }) do
			for _, descendant in ipairs(instance:GetDescendants()) do
				if descendant:IsA("TextLabel") or descendant:IsA("TextBox") then
					tween(descendant, FAST, { TextTransparency = 1 })
				elseif descendant:IsA("ImageLabel") then
					tween(descendant, FAST, { ImageTransparency = 1 })
				elseif descendant:IsA("GuiObject") then
					tween(descendant, FAST, { BackgroundTransparency = 1 })
				elseif descendant:IsA("UIStroke") then
					tween(descendant, FAST, { Transparency = 1 })
				end
			end
			if instance:IsA("TextLabel") then
				tween(instance, FAST, { TextTransparency = 1 })
			else
				tween(instance, FAST, { BackgroundTransparency = 1 })
			end
		end
		task.wait(0.2)
		rows.Visible = false
		rule.Visible = false
		status.Visible = false

		-- The panel keeps its size. Folding it down to a smaller card made the
		-- unlock read as the window shrinking rather than as the hub loading.
		tween(title, FAST, { TextTransparency = 1 })
		tween(mark, TweenInfo.new(0.44, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(118, 118),
			Position = UDim2.new(0.5, 0, 0.40, 0),
		})

		-- A soft light behind the mark, rising with the bar. It is the one place
		-- in the whole hub that gets to be theatrical.
		local glow = Instance.new("ImageLabel")
		glow.Name = "Glow"
		glow.BackgroundTransparency = 1
		glow.Image = GLOW
		glow.ImageColor3 = Color3.fromRGB(255, 255, 255)
		glow.ImageTransparency = 1
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.new(0.5, 0, 0.40, 0)
		glow.Size = UDim2.fromOffset(240, 240)
		-- Beneath the mark, and wide enough to read as light around it rather
		-- than a bright disc on top of it.
		glow.ZIndex = 1
		glow.Parent = panel
		tween(glow, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			ImageTransparency = 0.78,
			Size = UDim2.fromOffset(430, 430),
		})

		local track = Instance.new("Frame")
		track.Name = "Track"
		track.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		track.BackgroundTransparency = 0.9
		track.BorderSizePixel = 0
		track.AnchorPoint = Vector2.new(0.5, 0.5)
		track.Position = UDim2.new(0.5, 0, 0.7, 0)
		track.Size = UDim2.fromOffset(276, 6)
		track.Parent = panel
		corner(track, 3)

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		fill.BackgroundTransparency = 0.05
		fill.BorderSizePixel = 0
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.Parent = track
		corner(fill, 3)

		local ceremonyApi = {}

		-- The label argument is kept so the caller still reads as a list of named
		-- steps, but nothing is printed. The mark and the bar are the whole card.
		function ceremonyApi:Step(fraction, _label)
			tween(fill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0),
			})
			task.wait(0.3)
		end

		function ceremonyApi:Finish(after)
			tween(fill, FAST, { Size = UDim2.new(1, 0, 1, 0) })
			task.wait(0.45)

			-- The beat. The card goes and the mark is left alone in the middle
			-- of the screen for a moment, growing very slightly. Standing still
			-- for three quarters of a second is the whole difference between
			-- something opening and a progress bar finishing.
			local hold = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			tween(track, hold, { BackgroundTransparency = 1 })
			tween(fill, hold, { BackgroundTransparency = 1 })
			tween(panel, hold, { BackgroundTransparency = 1 })
			tween(edge, hold, { Transparency = 1 })
			tween(mark, hold, { Size = UDim2.fromOffset(138, 138) })
			-- The light swells as the card falls away, so the beat has something
			-- happening in it rather than being a pause.
			tween(glow, hold, { ImageTransparency = 0.62, Size = UDim2.fromOffset(600, 600) })
			task.wait(0.8)

			-- Then it dissolves outward and hands over.
			local away = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			tween(blur, away, { Size = 0 })
			tween(grow, away, { Scale = 1.06 })
			for _, descendant in ipairs(panel:GetDescendants()) do
				if descendant:IsA("TextLabel") then
					tween(descendant, away, { TextTransparency = 1 })
				elseif descendant:IsA("ImageLabel") then
					tween(descendant, away, { ImageTransparency = 1 })
				elseif descendant:IsA("Frame") then
					tween(descendant, away, { BackgroundTransparency = 1 })
				end
			end
			task.wait(0.42)
			pcall(function()
				screen:Destroy()
			end)
			pcall(function()
				blur:Destroy()
			end)
			if after then
				after()
			end
		end

		return ceremonyApi
	end

	local function attempt()
		if checking or finished then
			return
		end
		local typed = field.Text or ""
		if typed:gsub("%s", "") == "" then
			say("Enter a key.", true)
			return
		end

		checking = true
		say("Checking")

		local pass = false
		local okCheck, result = pcall(verify, typed)
		pass = okCheck and result == true
		task.wait(0.25)

		if not pass then
			checking = false
			say("That key was not accepted.", true)
			-- A short shake reads as refusal without a word of explanation.
			local home = panel.Position
			for _, offset in ipairs({ 7, -6, 4, -2, 0 }) do
				panel.Position = home + UDim2.fromOffset(offset, 0)
				task.wait(0.035)
			end
			panel.Position = home
			return
		end

		finished = true
		field:ReleaseFocus()
		say("Welcome back.")
		task.wait(0.2)

		local rite = ceremony()
		if onUnlocked then
			onUnlocked(rite)
		end
	end

	core:Connect(submit.MouseButton1Click, function()
		task.spawn(attempt)
	end)
	core:Connect(submit.MouseEnter, function()
		tween(submit, FAST, { BackgroundTransparency = 0.92 })
		tween(submitIcon, FAST, { ImageTransparency = 0.15 })
	end)
	core:Connect(submit.MouseLeave, function()
		tween(submit, FAST, { BackgroundTransparency = 1 })
		tween(submitIcon, FAST, { ImageTransparency = 0.5 })
	end)

	-- Pressing enter is what anyone will actually do, so it submits rather than
	-- quietly dropping focus.
	core:Connect(field.FocusLost, function(enterPressed)
		if enterPressed then
			task.spawn(attempt)
		end
	end)

	core:Connect(getHit.MouseButton1Click, function()
		if discord then
			setclipboard(discord)
			say("Discord link copied.")
		end
	end)
	core:Connect(discordHit.MouseButton1Click, function()
		if discord then
			setclipboard(discord)
			say("Discord link copied.")
		end
	end)

	task.defer(function()
		field:CaptureFocus()
	end)

	return screen
end

--------------------------------------------------------------------------------
-- reveal
--------------------------------------------------------------------------------

-- The hub arrives one band at a time: the frame, then its name, then the tabs
-- one after another, then the panels. Transparency only. Scaling text is what
-- made the old tab animation re-render the font mid-tween, and it is not worth
-- doing anywhere.
function Access.Reveal(core, base)
	if not base then
		return
	end

	local sidebar = base:FindFirstChild("Sidebar")
	local content = base:FindFirstChild("Content")
	local switchers = sidebar
		and sidebar:FindFirstChild("SidebarGroup")
		and sidebar.SidebarGroup:FindFirstChild("TabSwitchers")

	-- Which row a tab button belongs to, so they can come in one by one.
	local rowOrder = {}
	if switchers then
		local index = 0
		for _, descendant in ipairs(switchers:GetDescendants()) do
			if descendant.Name == "TabSwitcher" and descendant:IsA("GuiObject") then
				index += 1
				rowOrder[descendant] = index
			end
		end
	end

	-- The order things arrive in, and it is the order that carries the whole
	-- moment: the frame, then the name, then the top bar, then each tab landing
	-- one after another, then the profile, and the panels last of all.
	local function bandOf(instance)
		local walker = instance
		while walker and walker ~= base do
			if rowOrder[walker] then
				return 3 + rowOrder[walker] * 0.5
			end
			if walker.Name == "UserInfo" then
				return 7
			end
			if walker.Name == "Information" then
				return 1
			end
			if walker.Name == "Topbar" then
				return 2
			end
			if walker.Name == "Elements" then
				return 7.6
			end
			walker = walker.Parent
		end
		return 0
	end

	local records = {}
	local function remember(instance, property)
		local value = instance[property]
		if value >= 1 then
			return
		end
		table.insert(records, {
			instance = instance,
			property = property,
			value = value,
			delay = bandOf(instance) * 0.11,
		})
		instance[property] = 1
	end

	for _, descendant in ipairs(base:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			remember(descendant, "TextTransparency")
			remember(descendant, "BackgroundTransparency")
		elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			remember(descendant, "ImageTransparency")
			remember(descendant, "BackgroundTransparency")
		elseif descendant:IsA("GuiObject") then
			remember(descendant, "BackgroundTransparency")
		elseif descendant:IsA("UIStroke") then
			remember(descendant, "Transparency")
		end
	end

	local baseTransparency = base.BackgroundTransparency
	base.BackgroundTransparency = 1
	local baseStroke = base:FindFirstChildOfClass("UIStroke")
	local baseStrokeTransparency = baseStroke and baseStroke.Transparency
	if baseStroke then
		baseStroke.Transparency = 1
	end

	base.Visible = true

	tween(base, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = baseTransparency,
	})
	if baseStroke then
		tween(baseStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = baseStrokeTransparency,
		})
	end

	for _, record in ipairs(records) do
		tween(
			record.instance,
			TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.18 + record.delay),
			{ [record.property] = record.value }
		)
	end
end

return Access
