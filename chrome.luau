--// Prism · window chrome
--//
--// Maclib gives a macOS window and then drags it with a little move icon,
--// which is the one un-macOS thing about it. This reaches into the window it
--// built and changes four things: drag from the title bar like a real window,
--// resize from the bottom corner, a wider sidebar, and the gradients.
--//
--// It touches Maclib's own instances by name, so if a Maclib update renames
--// Base, Sidebar, Content or Topbar, this file is where it breaks and nothing
--// else stops working.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Chrome = {}

local MIN_WIDTH, MIN_HEIGHT = 680, 460

local function findBase(title)
	local roots = {}
	local ok, hidden = pcall(function()
		return gethui()
	end)
	if ok and hidden then
		table.insert(roots, hidden)
	end
	table.insert(roots, game:GetService("CoreGui"))

	for _, root in ipairs(roots) do
		for _, gui in ipairs(root:GetChildren()) do
			if gui:IsA("ScreenGui") then
				local base = gui:FindFirstChild("Base")
				local sidebar = base and base:FindFirstChild("Sidebar")
				local label = sidebar
					and sidebar:FindFirstChild("Information")
					and sidebar.Information:FindFirstChild("InformationHolder")
					and sidebar.Information.InformationHolder:FindFirstChild("TitleFrame")
					and sidebar.Information.InformationHolder.TitleFrame:FindFirstChild("Title")
				if label and label.Text == title then
					return base
				end
			end
		end
	end
	return nil
end

-- One drag implementation, pointed at whatever handles are passed in.
local function makeDraggable(core, base, handles)
	local dragging = false
	local dragStart, startPos

	for _, handle in ipairs(handles) do
		core:Connect(handle.InputBegan, function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = true
				dragStart = input.Position
				startPos = base.Position
			end
		end)
	end

	core:Connect(UserInputService.InputEnded, function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)

	core:Connect(UserInputService.InputChanged, function(input)
		if not dragging or not dragStart then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local delta = input.Position - dragStart
			base.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end
	end)
end

local function layout(base, width, height, sidebarScale)
	local content = base:FindFirstChild("Content")
	local sidebar = base:FindFirstChild("Sidebar")
	if not content or not sidebar then
		return
	end
	base.Size = UDim2.fromOffset(width, height)
	sidebar.Size = UDim2.new(sidebarScale, 0, 1, 0)
	content.Size = UDim2.new(0, math.floor(width * (1 - sidebarScale)), 1, 0)
end

local function addResizeGrip(core, base, sidebarScale)
	local grip = Instance.new("TextButton")
	grip.Name = "ResizeGrip"
	grip.Text = ""
	grip.AutoButtonColor = false
	grip.BackgroundTransparency = 1
	-- Pulled in from the corner. The old grip sat at -2, so its mark hung over
	-- the rounded edge and appeared outside the window the moment it was
	-- dragged. ClipsDescendants on the grip keeps it honest either way.
	grip.Size = UDim2.fromOffset(22, 22)
	grip.AnchorPoint = Vector2.new(1, 1)
	grip.Position = UDim2.new(1, -6, 1, -6)
	grip.ClipsDescendants = false
	grip.ZIndex = 50
	grip.Parent = base
	core:Track(grip)

	-- His own resize mark, stacked so it reads white rather than grey.
	local marks = {}
	for index = 1, 3 do
		local layer = Instance.new("ImageLabel")
		layer.Name = "GripMark" .. index
		layer.BackgroundTransparency = 1
		layer.Image = "rbxassetid://107014513554812"
		layer.ImageColor3 = Color3.fromRGB(255, 255, 255)
		layer.ImageTransparency = 0.6
		layer.AnchorPoint = Vector2.new(0.5, 0.5)
		layer.Position = UDim2.fromScale(0.5, 0.5)
		layer.Size = UDim2.fromOffset(13, 13)
		layer.ZIndex = 50
		layer.Parent = grip
		table.insert(marks, layer)
	end

	-- The same lift the globe has: brightens and grows a little, nothing more.
	core:Connect(grip.MouseEnter, function()
		for _, layer in ipairs(marks) do
			TweenService:Create(layer, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				ImageTransparency = 0.1,
				Size = UDim2.fromOffset(16, 16),
			}):Play()
		end
	end)
	core:Connect(grip.MouseLeave, function()
		for _, layer in ipairs(marks) do
			TweenService:Create(layer, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				ImageTransparency = 0.6,
				Size = UDim2.fromOffset(13, 13),
			}):Play()
		end
	end)

	local resizing = false
	local startInput, startSize

	core:Connect(grip.InputBegan, function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			resizing = true
			startInput = input.Position
			startSize = base.AbsoluteSize
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
			local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
				or Vector2.new(1920, 1080)
			local width = math.clamp(startSize.X + delta.X, MIN_WIDTH, viewport.X - 20)
			local height = math.clamp(startSize.Y + delta.Y, MIN_HEIGHT, viewport.Y - 20)
			layout(base, math.floor(width), math.floor(height), sidebarScale)
		end
	end)
end

local function addGradients(core, base)
	local stroke = base:FindFirstChildOfClass("UIStroke")
	if stroke then
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 120, 124)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 24, 26)),
		})
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.5, 0.75),
			NumberSequenceKeypoint.new(1, 0.35),
		})
		gradient.Parent = stroke
		core:Track(gradient)

		local phase = 0
		core:Connect(RunService.RenderStepped, function(dt)
			phase = (phase + dt * 6) % 360
			gradient.Rotation = phase
		end)
	end

end

local function openAnimation(base)
	local scale = base:FindFirstChildOfClass("UIScale")
	if not scale then
		return
	end
	scale.Scale = 0.94
	TweenService
		:Create(scale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

-- Maclib's minimize button hides the window down its own path, which leaves the
-- state its keybind reads untouched, so pressing K afterwards had nothing to
-- restore. Taking the button over means there is one way in and one way out:
-- minimize is exactly what K does, so K always brings it back.
local function ownMinimize(core, base, window)
	if not window then
		return
	end
	local controls = base:FindFirstChild("Sidebar")
	controls = controls and controls:FindFirstChild("WindowControls")
	controls = controls and controls:FindFirstChild("Controls")
	local button = controls and controls:FindFirstChild("Minimize")
	if not button or button:GetAttribute("MeridianOwned") then
		return
	end

	if typeof(getconnections) ~= "function" then
		return
	end

	local ok = pcall(function()
		for _, signal in ipairs({ button.MouseButton1Click, button.Activated }) do
			for _, connection in ipairs(getconnections(signal)) do
				connection:Disable()
			end
		end
	end)
	if not ok then
		return
	end

	button:SetAttribute("MeridianOwned", true)
	core:Connect(button.MouseButton1Click, function()
		pcall(function()
			window:SetState(false)
		end)
	end)
end

-- Handed out so the window can be hidden the instant it is built, before the
-- unlock ceremony has finished and anyone has seen it.
function Chrome.Find(title, attempts)
	for _ = 1, attempts or 20 do
		local base = findBase(title)
		if base then
			return base
		end
		task.wait(0.03)
	end
	return nil
end

--// Apply everything. Safe to call on a window that has already been set up.
function Chrome.Apply(core, title, options)
	options = options or {}
	local sidebarScale = options.sidebarScale or 0.355

	local base
	for _ = 1, 40 do
		base = findBase(title)
		if base then
			break
		end
		task.wait(0.05)
	end
	if not base then
		warn("[Prism] window chrome could not find the Maclib window")
		return nil
	end

	local content = base:FindFirstChild("Content")
	local sidebar = base:FindFirstChild("Sidebar")

	-- The move icon goes, since the title bar does its job now.
	local moveIcon = content
		and content:FindFirstChild("Topbar")
		and content.Topbar:FindFirstChild("Elements")
		and content.Topbar.Elements:FindFirstChild("MoveIcon")
	if moveIcon then
		moveIcon.Visible = false
	end

	-- Anything that is not a control is a drag handle. Buttons sink their own
	-- input, so clicking a tab still selects it rather than dragging the window.
	local handles = {}
	local function handle(instance)
		if instance and instance:IsA("GuiObject") then
			table.insert(handles, instance)
		end
	end

	if content then
		handle(content:FindFirstChild("Topbar"))
	end
	if sidebar then
		handle(sidebar)
		handle(sidebar:FindFirstChild("Information"))
		handle(sidebar:FindFirstChild("WindowControls"))
		local group = sidebar:FindFirstChild("SidebarGroup")
		if group then
			handle(group)
			handle(group:FindFirstChild("UserInfo"))
			handle(group:FindFirstChild("TabSwitchers"))
		end
		local holder = sidebar:FindFirstChild("Information")
		holder = holder and holder:FindFirstChild("InformationHolder")
		handle(holder)
		handle(holder and holder:FindFirstChild("TitleFrame"))
	end
	makeDraggable(core, base, handles)

	addResizeGrip(core, base, sidebarScale)
	addGradients(core, base)
	layout(base, base.AbsoluteSize.X, base.AbsoluteSize.Y, sidebarScale)
	ownMinimize(core, base, options.window)

	-- When the unlock ceremony is running it owns the entrance, and two openings
	-- on top of each other is worse than either.
	if not options.skipOpen then
		openAnimation(base)
	end

	return base
end

return Chrome
