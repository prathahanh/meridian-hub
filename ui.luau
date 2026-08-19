--// Meridian · interface polish
--//
--// Tooltips that follow the cursor, gradients, transparency, a backdrop blur
--// tied to the menu being open, and hover and tab animations. Everything here
--// reaches into Maclib's own instances, so this is the file that breaks if
--// Maclib renames something, and nothing else stops working when it does.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local UI = {}

-- Two colours only, white and black. Everything that used to be indigo and
-- teal now runs along this ramp, which is what keeps the window reading as one
-- clean object rather than a toy.
local ACCENT = Color3.fromRGB(255, 255, 255)
local ACCENT_TWO = Color3.fromRGB(26, 26, 28)

local MONO_RAMP = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(168, 168, 172)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(28, 28, 30)),
})

local FAST = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SMOOTH = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local ELEMENT_KINDS = {
	Toggle = true,
	Slider = true,
	Dropdown = true,
	Keybind = true,
	Button = true,
	Input = true,
	Colorpicker = true,
}

local function labelOf(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("TextLabel") and child.Name:match("Name$") then
			local text = child.Text or ""
			local cut = text:find(" • ")
			if cut then
				text = text:sub(1, cut - 1)
			end
			return text
		end
	end
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			return child.Text or ""
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- tooltip
--------------------------------------------------------------------------------

local function buildTooltip(core, parent)
	local holder = Instance.new("Frame")
	holder.Name = "Tip"
	holder.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.AutomaticSize = Enum.AutomaticSize.XY
	holder.Size = UDim2.fromOffset(0, 0)
	holder.ZIndex = 400
	holder.Visible = false
	holder.Parent = parent
	core:Track(holder)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = holder

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 7)
	padding.PaddingBottom = UDim.new(0, 7)
	padding.Parent = holder

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Parent = holder

	local strokeGradient = Instance.new("UIGradient")
	strokeGradient.Color = MONO_RAMP
	strokeGradient.Parent = stroke

	local background = Instance.new("UIGradient")
	background.Rotation = 90
	background.Color = ColorSequence.new(Color3.fromRGB(34, 34, 42), Color3.fromRGB(18, 18, 22))
	background.Parent = holder

	-- Fixed width with wrapping, and the height grows to fit. Automatic width
	-- was the bug: the text kept growing past the box it was supposed to sit in.
	local label = Instance.new("TextLabel")
	label.Name = "TipText"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.fromOffset(238, 0)
	label.TextWrapped = true
	label.RichText = true
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 12
	label.LineHeight = 1.15
	label.TextColor3 = Color3.fromRGB(228, 230, 240)
	label.TextTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.ZIndex = 401
	label.Parent = holder

	local shown = false

	local function show(text)
		label.Text = text
		holder.Visible = true
		shown = true
		TweenService:Create(holder, FAST, { BackgroundTransparency = 0.06 }):Play()
		TweenService:Create(label, FAST, { TextTransparency = 0 }):Play()
		TweenService:Create(stroke, FAST, { Transparency = 0.45 }):Play()
	end

	local function hide()
		shown = false
		TweenService:Create(holder, FAST, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, FAST, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, FAST, { Transparency = 1 }):Play()
		task.delay(0.2, function()
			if not shown then
				holder.Visible = false
			end
		end)
	end

	-- Keep the tooltip inside the window rather than the screen. Spilling past
	-- the menu edge over the game was what read as out of bounds.
	core:Connect(RunService.RenderStepped, function()
		if not holder.Visible then
			return
		end
		local mouse = UserInputService:GetMouseLocation()
		local size = holder.AbsoluteSize
		if size.X < 1 then
			return
		end

		local bounds = UI.Bounds
		local minX, minY, maxX, maxY = 8, 8, 1912, 1072
		if bounds and bounds.Parent then
			local origin, extent = bounds.AbsolutePosition, bounds.AbsoluteSize
			minX, minY = origin.X + 8, origin.Y + 8
			maxX, maxY = origin.X + extent.X - 8, origin.Y + extent.Y - 8
		end

		local x = mouse.X + 18
		local y = mouse.Y + 20
		if x + size.X > maxX then
			x = mouse.X - size.X - 14
		end
		if y + size.Y > maxY then
			y = mouse.Y - size.Y - 14
		end
		holder.Position = UDim2.fromOffset(math.max(x, minX), math.max(y, minY))
	end)

	return show, hide
end

--------------------------------------------------------------------------------
-- element polish
--------------------------------------------------------------------------------

-- Headers read larger, control names read quieter. One text size for everything
-- is what made the panels feel flat.
local function setTypeScale(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("TextLabel") then
			if child.Name == "HeaderText" then
				child.TextSize = 15
				child.Font = Enum.Font.GothamBold
			elseif child.Name:match("Name$") then
				child.TextTransparency = 0.12
			end
		end
	end
end

-- Panels are left alone now. A gradient across something this big just reads as
-- a wash; the same gradient on a switch or a slider fill reads as finish.
local function polishSection(core, section)
	if section:GetAttribute("MeridianPolished") then
		return
	end
	section:SetAttribute("MeridianPolished", true)

	if section:IsA("Frame") then
		local stroke = section:FindFirstChildOfClass("UIStroke")
		if not stroke then
			stroke = Instance.new("UIStroke")
			stroke.Thickness = 1
			stroke.Transparency = 0.88
			stroke.Color = Color3.fromRGB(255, 255, 255)
			stroke.Parent = section
			core:Track(stroke)
		end
	end
end

-- The white mark first, the grey original as the fallback. core:UseAsset takes
-- the first that this account can actually fetch.
local LOGO_IDS = {
	"rbxassetid://123910318474386",
	"rbxassetid://140486334564423",
}

-- Maclib's colour picker ships a hue wheel at rbxassetid://2849458409 and that
-- asset no longer fetches: PreloadAsync reports Failure on a fresh client while
-- the picker's other two images report Success. So the wheel drew as a hole,
-- the crosshair sat on nothing, and the only usable part was typing hex.
--
-- The picker's maths never touched the image. It reads the click in polar
-- coordinates, hue from the angle and saturation from the radius, so the wheel
-- is pure decoration and any correct looking one works. 6020299385 is a real
-- HSV wheel, white in the middle out to full saturation at the rim, which is
-- what the dead one was.
--
-- The preview swatches were the other half. They show the chosen colour at its
-- own alpha over a transparency checker, so at alpha 0.85 there was almost
-- nothing to see. The colour now stays readable and the checker still shows
-- through enough to say that it is transparent.
local WHEEL_IDS = {
	"rbxassetid://6020299385",
	"rbxassetid://2849458409",
}

-- The chequerboard behind a colour well.
--
-- It is Maclib's way of saying "this colour is partly transparent", and it is
-- the pink and blue squares he pointed at. Two of them sit side by side in the
-- prompt as the old and new colour, and a third sits on the control row. At
-- the sizes they are drawn it reads as a pattern rather than as transparency.
--
-- The well becomes a flat dark chip instead, which is what everything else that
-- floats on this window is, and a translucent colour over it still reads as
-- translucent because it darkens.
local CHECKER = "rbxassetid://121484455191370"

local function flattenWells(core, root)
	for _, well in ipairs(root:GetDescendants()) do
		if well:IsA("ImageLabel") and well.Image == CHECKER then
			well.Image = ""
			well.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
			well.BackgroundTransparency = 0
			if not well:FindFirstChildOfClass("UIStroke") then
				local edge = Instance.new("UIStroke")
				edge.Color = ACCENT
				edge.Transparency = 0.85
				edge.Thickness = 1
				edge.Parent = well
				core:Track(edge)
			end
		end
	end
end

local function polishColorPicker(core, prompt)
	if prompt:GetAttribute("MeridianPicked") then
		return
	end
	prompt:SetAttribute("MeridianPicked", true)

	flattenWells(core, prompt)

	for _, descendant in ipairs(prompt:GetDescendants()) do
		if descendant.Name == "Wheel" and descendant:IsA("ImageButton") then
			core:UseAsset("colourwheel", WHEEL_IDS, descendant)

			local target = descendant:FindFirstChild("Target")
			if target and target:IsA("ImageLabel") then
				-- It is a thin ring on a bright wheel, so it needs an edge of
				-- its own to be findable at a glance.
				local edge = Instance.new("UIStroke")
				edge.Thickness = 2
				edge.Color = Color3.fromRGB(255, 255, 255)
				edge.Transparency = 0.15
				edge.Parent = target
				local shadow = Instance.new("UIStroke")
				shadow.Thickness = 3
				shadow.Color = Color3.fromRGB(0, 0, 0)
				shadow.Transparency = 0.55
				shadow.Parent = target
			end
		elseif descendant.Name == "Color" and descendant:IsA("Frame") then
			local well = descendant.Parent
			if well and (well.Name == "NewColor" or well.Name == "OldColor") then
				-- Maclib writes this every time the alpha moves, so it is
				-- watched rather than set once.
				local guard = false
				local function readable()
					if guard then
						return
					end
					guard = true
					if descendant.BackgroundTransparency > 0.45 then
						descendant.BackgroundTransparency = 0.45
					end
					guard = false
				end
				core:Connect(descendant:GetPropertyChangedSignal("BackgroundTransparency"), readable)
				readable()
			end
		end
	end
end

-- Sliders are 3 pixels tall with a 12 pixel head out of the box, which is a
-- fiddly target. Thicker bar, bigger head, and the head grows when grabbed.
local function growSlider(core, frame)
	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant.Name == "SliderBar" and descendant:IsA("GuiObject") then
			descendant.Size = UDim2.new(descendant.Size.X.Scale, descendant.Size.X.Offset, 0, 6)
		elseif descendant.Name == "SliderHead" and descendant:IsA("GuiObject") then
			descendant.Size = UDim2.fromOffset(16, 16)
		end
	end
end

-- Typing letters into a slider box left a string where a number belonged, which
-- is both a broken control and a good way to throw errors into the console.
local function guardNumbers(core, frame)
	for _, box in ipairs(frame:GetDescendants()) do
		if box:IsA("TextBox") and not box:GetAttribute("MeridianGuarded") then
			box:SetAttribute("MeridianGuarded", true)
			local lastGood = box.Text

			core:Connect(box.Focused, function()
				if tonumber(box.Text) then
					lastGood = box.Text
				end
			end)

			core:Connect(box.FocusLost, function()
				if box.Name == "SliderValue" and not tonumber(box.Text) then
					box.Text = lastGood
				elseif tonumber(box.Text) then
					lastGood = box.Text
				end
			end)
		end
	end
end

-- The small parts, which is where he wanted the colour.
local function paintControl(core, frame)
	local function gradientOn(instance, rotation)
		if not instance or instance:FindFirstChildOfClass("UIGradient") then
			return
		end
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = rotation or 0
		gradient.Color = MONO_RAMP
		gradient.Parent = instance
		core:Track(gradient)
	end

	flattenWells(core, frame)

	for _, descendant in ipairs(frame:GetDescendants()) do
		local name = descendant.Name
		if name == "TogglerHead" or name == "SliderHead" then
			gradientOn(descendant, 45)
		elseif name == "SliderBar" or name == "BinderBox" then
			gradientOn(descendant, 0)
		end
	end
end

-- Exactly one row may be lit at any moment. The previous build oversized the
-- highlight so neighbouring rows overlapped, every one of them lit at once, and
-- the tooltip never got a clean MouseLeave.
local active = nil

local function polishElement(core, frame, tips, show, hide)
	if frame:GetAttribute("MeridianPolished") then
		return
	end
	frame:SetAttribute("MeridianPolished", true)

	local highlight = Instance.new("Frame")
	highlight.Name = "Hover"
	highlight.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	highlight.BackgroundTransparency = 1
	highlight.BorderSizePixel = 0
	-- A child sits inside its parent's padding, and Maclib pads each row type by
	-- a different amount, which is why the dropdown rows were lit across 164 of
	-- their 222 pixels and looked half painted. Cancel the padding, then inset
	-- by a fixed few pixels so every row lights the same way.
	local pad = frame:FindFirstChildOfClass("UIPadding")
	local padLeft = pad and pad.PaddingLeft.Offset or 0
	local padRight = pad and pad.PaddingRight.Offset or 0
	local padTop = pad and pad.PaddingTop.Offset or 0
	local padBottom = pad and pad.PaddingBottom.Offset or 0

	-- Wider than the row rather than narrower, so the label always has clear
	-- space around it instead of sitting on the edge of the fill.
	highlight.Size = UDim2.new(1, padLeft + padRight + 10, 1, padTop + padBottom + 4)
	highlight.Position = UDim2.fromOffset(-padLeft - 5, -padTop - 2)
	highlight.ZIndex = math.max((frame.ZIndex or 1) - 1, 0)
	highlight.Parent = frame
	core:Track(highlight)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = highlight

	local gradient = Instance.new("UIGradient")
	gradient.Color = MONO_RAMP
	gradient.Rotation = 12
	gradient.Parent = highlight

	paintControl(core, frame)
	setTypeScale(frame)
	growSlider(core, frame)
	guardNumbers(core, frame)


	local label
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("TextLabel") and child.Name:match("Name$") then
			label = child
		end
	end
	-- Measured: the label's left edge sits exactly on the row's left edge, so
	-- inside the fill it had five pixels of air and looked about to fall out.
	-- Padding the label moves the text without moving the fill or the control
	-- beside it.
	if label and not label:FindFirstChildOfClass("UIPadding") then
		local inset = Instance.new("UIPadding")
		inset.PaddingLeft = UDim.new(0, 8)
		inset.Parent = label
	end

	-- Sliders and dropdowns already fill their row, so nudging the label there
	-- just crowds the control next to it.
	if frame.Name == "Slider" or frame.Name == "Dropdown" then
		label = nil
	end
	local restingX = label and label.Position or nil

	local name = labelOf(frame)
	local tip = name and tips[name] or nil

	-- Hold X over a keybind for two seconds and it clears. The box fills red
	-- while you hold, so it is obvious something is happening and obvious how to
	-- stop, and letting go early cancels it.
	if frame.Name == "Keybind" and name then
		local box = frame:FindFirstChild("BinderBox", true)
		local element = core.Keybinds and core.Keybinds[name]
		if box and element then
			-- Measured: BinderBox is a TextBox that draws its own letter, and
			-- this ScreenGui runs ZIndexBehavior.Sibling, where a child always
			-- draws over its parent no matter what ZIndex it is given. So the
			-- fill covered the key and no ZIndex could have saved it. It also
			-- has five pixels of padding each side, which is why a fill sized to
			-- the full row only ever covered eleven of its twenty-one pixels.
			-- The fill cancels that padding, and the letter is drawn again above
			-- it while the box's own text is hidden.
			local pad = box:FindFirstChildOfClass("UIPadding")
			local padLeft = pad and pad.PaddingLeft.Offset or 0
			local padRight = pad and pad.PaddingRight.Offset or 0
			local padTop = pad and pad.PaddingTop.Offset or 0
			local padBottom = pad and pad.PaddingBottom.Offset or 0
			local full = UDim2.new(1, padLeft + padRight, 1, padTop + padBottom)
			local empty = UDim2.new(0, 0, 1, padTop + padBottom)

			local fill = Instance.new("Frame")
			fill.Name = "ClearFill"
			fill.BackgroundColor3 = Color3.fromRGB(224, 90, 86)
			fill.BackgroundTransparency = 0.2
			fill.BorderSizePixel = 0
			fill.Size = empty
			fill.Position = UDim2.fromOffset(-padLeft, -padTop)
			fill.ZIndex = 1
			fill.Parent = box
			core:Track(fill)

			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(0, 5)
			round.Parent = fill

			local letter = Instance.new("TextLabel")
			letter.Name = "ClearLetter"
			letter.BackgroundTransparency = 1
			letter.Text = box.Text
			letter.TextSize = box.TextSize
			letter.TextColor3 = Color3.fromRGB(255, 255, 255)
			letter.TextTransparency = 1
			letter.Size = full
			letter.Position = UDim2.fromOffset(-padLeft, -padTop)
			letter.ZIndex = 3
			letter.Parent = box
			core:Track(letter)
			pcall(function()
				letter.FontFace = box.FontFace
			end)

			-- Every hold gets a number. The old version checked only whether a
			-- hold was in progress, so a delayed callback left over from an
			-- earlier press would fire against a later one, clear a bind nobody
			-- asked it to and leave the box stuck full red. That is the bug that
			-- looked like it was pressing itself. A stale token now does
			-- nothing, and the growth tween is cancelled rather than raced by a
			-- second tween pulling the other way.
			local over, token, growth = false, 0, nil

			core:Connect(frame.MouseEnter, function()
				over = true
			end)
			core:Connect(frame.MouseLeave, function()
				over = false
			end)

			local function release()
				token += 1
				if growth then
					growth:Cancel()
					growth = nil
				end
				TweenService:Create(fill, FAST, { Size = empty }):Play()
				TweenService:Create(letter, FAST, { TextTransparency = 1 }):Play()
				box.TextTransparency = 0
				box.TextEditable = true
				task.delay(0.1, function()
					core.SuppressKeybinds = false
				end)
			end

			core:Connect(UserInputService.InputBegan, function(input, typing)
				if typing or input.KeyCode ~= Enum.KeyCode.X or not over or growth then
					return
				end
				token += 1
				local mine = token

				-- X is also a feature key by default. While it is being held
				-- over a keybind row it means clear, not toggle.
				core.SuppressKeybinds = true
				letter.Text = box.Text
				letter.TextTransparency = 0
				box.TextTransparency = 1

				growth = TweenService:Create(fill, TweenInfo.new(2, Enum.EasingStyle.Linear), { Size = full })
				growth:Play()

				-- Clicking the box part way through a hold used to put a caret
				-- in it and turn the hold into typing, which left the fill
				-- animating across a box that was now growing to fit text. Once
				-- a press is clearly a hold rather than a keystroke, the box
				-- stops taking input until it ends.
				task.delay(0.35, function()
					if token == mine and growth then
						box.TextEditable = false
						pcall(function()
							box:ReleaseFocus()
						end)
					end
				end)

				task.delay(2.05, function()
					if token ~= mine or not over then
						return
					end
					pcall(function()
						element:Unbind()
					end)
					core:Notify("Meridian Hub", name .. " cleared", 3)
					release()
				end)
			end)

			core:Connect(UserInputService.InputEnded, function(input)
				if input.KeyCode == Enum.KeyCode.X and growth then
					release()
				end
			end)
		end
	end

	-- A tip may be a function so it can describe whatever the control is set to
	-- right now, rather than repeating one option forever.
	local function tipText()
		if type(tip) == "function" then
			local ok, value = pcall(tip)
			return ok and value or nil
		end
		return tip
	end

	-- Nothing about a switch says it can be pressed until the cursor is on it,
	-- so the knob lifts a little and the whole control brightens.
	local knob, knobSize
	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant.Name == "TogglerHead" or descendant.Name == "SliderHead" then
			knob = descendant
			knobSize = descendant.Size
		end
	end

	local function light(on)
		core.HoverLit = on
		TweenService:Create(highlight, FAST, { BackgroundTransparency = on and 0.94 or 1 }):Play()
		if knob and knobSize then
			local grown = UDim2.new(
				knobSize.X.Scale,
				knobSize.X.Offset + 2,
				knobSize.Y.Scale,
				knobSize.Y.Offset + 2
			)
			TweenService:Create(knob, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = on and grown or knobSize,
			}):Play()
		end
		if label and restingX then
			-- The row moves a little. That is the animation he was asking for,
			-- rather than a colour appearing out of nowhere.
			TweenService
				:Create(label, FAST, {
					Position = on and (restingX + UDim2.fromOffset(3, 0)) or restingX,
				})
				:Play()
		end
	end

	-- The tooltip waits. Appearing the instant the cursor crosses a row turned
	-- every pass across the panel into a flicker of boxes.
	local hovering = false

	core:Connect(frame.MouseEnter, function()
		if active and active ~= light then
			active(false)
		end
		active = light
		light(true)
		hovering = true

		local text = tipText()
		if not text then
			return
		end
		task.delay(2, function()
			if hovering and active == light then
				show(text)
			end
		end)
	end)

	core:Connect(frame.MouseLeave, function()
		hovering = false
		if active == light then
			active = nil
		end
		light(false)
		hide()
	end)
end

--------------------------------------------------------------------------------
-- sidebar and tab animation
--------------------------------------------------------------------------------

-- Every tab button sits inside one container. Binding the container is what made
-- hovering any tab light the entire sidebar, so bind the buttons themselves and
-- remember each one's resting transparency, since the selected tab has its own.
local function polishSidebar(core, base)
	local sidebar = base:FindFirstChild("Sidebar")
	local group = sidebar and sidebar:FindFirstChild("SidebarGroup")
	if not group then
		return
	end

	for _, descendant in ipairs(group:GetDescendants()) do
		if descendant.Name == "TabSwitcher" and descendant:IsA("GuiObject") then
			if not descendant:GetAttribute("MeridianTab") then
				descendant:SetAttribute("MeridianTab", true)

				local row = descendant
				core:Connect(row.MouseEnter, function()
					row:SetAttribute("Resting", row.BackgroundTransparency)
					row:SetAttribute("Hovering", true)
					TweenService:Create(row, FAST, { BackgroundTransparency = 0.93 }):Play()
				end)
				core:Connect(row.MouseLeave, function()
					local resting = row:GetAttribute("Resting")
					row:SetAttribute("Hovering", nil)
					TweenService:Create(row, FAST, { BackgroundTransparency = resting or 1 }):Play()
				end)
			end
		end
	end
end

-- Sections stack down the left when a tab only ever built one column, which is
-- what left the Settings tab needing a scroll while the right half sat empty.
-- Maclib's own config section ignores the side it is given, so it gets moved.
local function balanceColumns(core, elements)
	-- No memo flag here. Maclib reuses a single scrolling frame and rebuilds its
	-- contents on every tab change, so remembering that it was balanced once
	-- would leave every later tab alone. The check below is already idempotent.
	for _, scrolling in ipairs(elements:GetDescendants()) do
		if scrolling.Name == "ElementsScrolling" then
			local left = scrolling:FindFirstChild("Left")
			local right = scrolling:FindFirstChild("Right")
			if left and right then
				local leftSections, rightSections = {}, {}
				for _, child in ipairs(left:GetChildren()) do
					if child.Name == "Section" then
						table.insert(leftSections, child)
					end
				end
				for _, child in ipairs(right:GetChildren()) do
					if child.Name == "Section" then
						table.insert(rightSections, child)
					end
				end

				-- Move panels across until the columns are within one of each
				-- other. It used to move exactly one, and only when the right
				-- was empty, which was enough while Settings held two panels and
				-- wrong the moment the dashboard folded into it and Maclib added
				-- the config to the left on top of that.
				if #leftSections > #rightSections + 1 then
					while #leftSections > #rightSections + 1 do
						local moving = table.remove(leftSections)
						moving.Parent = right
						table.insert(rightSections, moving)
					end
				elseif #rightSections == 0 and #leftSections == 1 then
					-- A tab with one panel should use the whole width rather
					-- than sitting in a narrow column with nothing beside it.
					if left.Size.X.Scale < 0.9 then
						left:SetAttribute("MeridianWidth", tostring(left.Size))
						left.Size = UDim2.new(1, 0, left.Size.Y.Scale, left.Size.Y.Offset)
					end
				elseif left:GetAttribute("MeridianWidth") and #rightSections > 0 then
					left.Size = UDim2.new(0.5, 0, left.Size.Y.Scale, left.Size.Y.Offset)
					left:SetAttribute("MeridianWidth", nil)
				end
			end
		end
	end
end

-- Maclib's config panel is the only one in the hub with no title, which left a
-- nameless box of buttons sitting beside named panels. A real header is cloned
-- from a neighbouring section rather than built to look like one, so it can
-- never drift out of step with them, and LayoutOrder -1 puts it first because
-- every element Maclib adds sits at 0.
local function titleConfigSection(core, elements)
	local template, target
	for _, section in ipairs(elements:GetDescendants()) do
		if section.Name == "Section" then
			local header, isConfig
			for _, child in ipairs(section:GetDescendants()) do
				if child.Name == "Header" and child:IsA("GuiObject") then
					header = child
				elseif child:IsA("TextLabel") and child.Text == "Config Name" then
					isConfig = true
				end
			end
			if header and not isConfig then
				template = template or header
			elseif isConfig and not header then
				target = section
			end
		end
	end

	if not template or not target then
		return
	end

	local copy = template:Clone()
	copy.LayoutOrder = -1
	local text = copy:FindFirstChild("HeaderText")
	if text then
		text.Text = "Configs"
	end
	copy.Parent = target
	core:Track(copy)
end

-- Dropdown options are built when the list is opened, so they never got the
-- hover the rows above them have, and they looked unfinished next to everything
-- else. The sweep catches them once they exist.
local function polishOptions(core, elements)
	for _, option in ipairs(elements:GetDescendants()) do
		-- Exactly the option rows. Matching anything with a label inside the
		-- dropdown caught the inner text and the tick as well, which is what
		-- produced those half highlights.
		if option.Name == "Option" and option:IsA("TextButton") and not option:GetAttribute("MeridianOption") then
			option:SetAttribute("MeridianOption", true)

			if not option:FindFirstChildOfClass("UICorner") then
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 5)
				corner.Parent = option
			end

			core:Connect(option.MouseEnter, function()
				TweenService:Create(option, FAST, { BackgroundTransparency = 0.93 }):Play()
			end)
			core:Connect(option.MouseLeave, function()
				TweenService:Create(option, FAST, { BackgroundTransparency = 1 }):Play()
			end)
		end
	end
end

-- The globe opens the global settings and is a 16 pixel target, which is a
-- coin toss with a mouse. The icon moves into a child so the button itself can
-- be twice the size without the picture growing with it.
local function growGlobeButton(core, base)
	local holder = base:FindFirstChild("Sidebar")
	holder = holder and holder:FindFirstChild("Information")
	holder = holder and holder:FindFirstChild("InformationHolder")
	local globe = holder and holder:FindFirstChild("GlobalSettingsButton")
	if not globe or globe:GetAttribute("MeridianGrown") then
		return
	end
	globe:SetAttribute("MeridianGrown", true)

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = globe.Image
	icon.ImageTransparency = globe.ImageTransparency
	icon.Size = UDim2.fromOffset(16, 16)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = globe
	core:Track(icon)

	globe.Image = ""
	globe.Size = UDim2.fromOffset(30, 30)

	-- It has to look pressable. A dim icon that lifts and brightens under the
	-- cursor is the whole difference between a button and a decoration.
	icon.ImageTransparency = 0.45
	core:Connect(globe.MouseEnter, function()
		TweenService:Create(icon, FAST, {
			ImageTransparency = 0,
			Size = UDim2.fromOffset(19, 19),
		}):Play()
	end)
	core:Connect(globe.MouseLeave, function()
		TweenService:Create(icon, FAST, {
			ImageTransparency = 0.45,
			Size = UDim2.fromOffset(16, 16),
		}):Play()
	end)
end


-- A single figure in the top bar, only while there is one worth showing. The
-- rate is the thing anyone actually watches, and it was buried in a paragraph
-- on one tab.
local function headlineReadout(core, base)
	local content = base:FindFirstChild("Content")
	local topbar = content and content:FindFirstChild("Topbar")
	local holder = topbar and topbar:FindFirstChild("Elements")
	if not holder or holder:FindFirstChild("Headline") then
		return
	end

	local label = Instance.new("TextLabel")
	label.Name = "Headline"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(1, 0.5)
	label.Position = UDim2.new(1, 0, 0.5, 0)
	label.Size = UDim2.fromOffset(200, 20)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 12
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.Parent = holder
	core:Track(label)

	core:Loop("headline", 0.5, function()
		local text = core.Headline
		if text and text ~= "" then
			if label.Text ~= text then
				label.Text = text
			end
			TweenService:Create(label, SMOOTH, { TextTransparency = 0.25 }):Play()
		else
			TweenService:Create(label, SMOOTH, { TextTransparency = 1 }):Play()
		end
	end)
end

-- Notifications arrive as stock Maclib frames, which do not match the window
-- they pop out of. Same monochrome edge, same corner, and they slide in from
-- the right rather than appearing.
local TITLE_TT, BODY_TT = 0.12, 0.25

local ARRIVE = TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function polishNotifications(core, gui)
	local holder = gui:FindFirstChild("Notifications")
	if not holder then
		return
	end

	local function dress(frame)
		if not frame:IsA("GuiObject") or frame:GetAttribute("MeridianDressed") then
			return
		end
		frame:SetAttribute("MeridianDressed", true)

		-- What core:Notify put aside when it made this one: how long it lives,
		-- for the countdown, and the handle to cancel it, for the close button.
		-- The frame itself carries neither.
		local pending = table.remove(core.Pending or {}, 1) or {}
		local lifetime = tonumber(pending.lifetime) or 5

		-- Connections here are deliberately raw rather than core:Connect. One
		-- of these is created per notification and the frame takes them with it
		-- when it goes; tracking them would grow a table that only ever grows.
		local stroke = frame:FindFirstChildOfClass("UIStroke")
		if stroke and not stroke:FindFirstChildOfClass("UIGradient") then
			stroke.Transparency = 0.45
			local gradient = Instance.new("UIGradient")
			gradient.Color = MONO_RAMP
			gradient.Rotation = 25
			gradient.Parent = stroke
		end

		local info = frame:FindFirstChild("NotificationInformation")
		local title = info and info:FindFirstChild("NotificationTitle")
		local body = info and info:FindFirstChild("NotificationDescription")

		if title and title:IsA("TextLabel") then
			title.Font = Enum.Font.GothamBold
			title.TextSize = 13
			local gutter = title:FindFirstChildOfClass("UIPadding")
			if gutter then
				-- Maclib leaves 25 on the right. A close button needs more.
				gutter.PaddingRight = UDim.new(0, 36)
			end
		end
		if body and body:IsA("TextLabel") then
			body.TextTransparency = BODY_TT
		end

		------------------------------------------------------------------------
		-- the mark, moved to the left so the corner is free
		------------------------------------------------------------------------

		local indent = info and info:FindFirstChildOfClass("UIPadding")

		local mark = Instance.new("ImageLabel")
		mark.Name = "Mark"
		mark.BackgroundTransparency = 1
		mark.ImageColor3 = Color3.fromRGB(255, 255, 255)
		mark.ImageTransparency = 1
		mark.Size = UDim2.fromOffset(22, 22)
		mark.Position = UDim2.new(0, 10, 0, 11)
		mark.ZIndex = 20
		mark.Parent = frame
		core:UseAsset("mark", LOGO_IDS, mark)

		if indent then
			indent.PaddingLeft = UDim.new(0, 40)
		end
		-- An indent with nothing in it is worse than no indent, so if the
		-- image never fetches both the mark and the space go away.
		task.delay(0.6, function()
			if mark.Parent and not mark.IsLoaded then
				mark:Destroy()
				if indent then
					indent.PaddingLeft = UDim.new(0, 10)
				end
			end
		end)

		------------------------------------------------------------------------
		-- close, the same cross the key panel uses
		------------------------------------------------------------------------

		local close = Instance.new("TextButton")
		close.Name = "Close"
		close.Text = ""
		close.AutoButtonColor = false
		close.BackgroundColor3 = ACCENT
		close.BackgroundTransparency = 1
		close.BorderSizePixel = 0
		close.Size = UDim2.fromOffset(20, 20)
		close.AnchorPoint = Vector2.new(1, 0)
		close.Position = UDim2.new(1, -9, 0, 10)
		close.ZIndex = 25
		close.Parent = frame

		local closeRound = Instance.new("UICorner")
		closeRound.CornerRadius = UDim.new(0, 6)
		closeRound.Parent = close

		-- Two bars rather than an image, so there is no asset here that can
		-- fail to fetch and leave an invisible button behind.
		local bars = {}
		for index = 1, 2 do
			local bar = Instance.new("Frame")
			bar.BackgroundColor3 = Color3.fromRGB(228, 230, 238)
			bar.BackgroundTransparency = 1
			bar.BorderSizePixel = 0
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(0.5, 0.5)
			bar.Size = UDim2.fromOffset(9, 1)
			bar.Rotation = index == 1 and 45 or -45
			bar.ZIndex = 26
			bar.Parent = close
			bars[index] = bar
		end

		close.MouseEnter:Connect(function()
			TweenService:Create(close, FAST, { BackgroundTransparency = 0.88 }):Play()
			for _, bar in ipairs(bars) do
				TweenService:Create(bar, FAST, { BackgroundTransparency = 0.05 }):Play()
			end
		end)
		close.MouseLeave:Connect(function()
			TweenService:Create(close, FAST, { BackgroundTransparency = 1 }):Play()
			for _, bar in ipairs(bars) do
				TweenService:Create(bar, FAST, { BackgroundTransparency = 0.35 }):Play()
			end
		end)
		close.MouseButton1Click:Connect(function()
			local handle = pending.handle
			local cancelled = false
			if handle then
				cancelled = pcall(function()
					handle:Cancel()
				end)
			end
			if not cancelled and frame.Parent then
				frame:Destroy()
			end
		end)

		------------------------------------------------------------------------
		-- how long is left
		------------------------------------------------------------------------

		local countdown = Instance.new("Frame")
		countdown.Name = "Countdown"
		countdown.BackgroundColor3 = ACCENT
		countdown.BackgroundTransparency = 1
		countdown.BorderSizePixel = 0
		countdown.AnchorPoint = Vector2.new(0, 1)
		countdown.Position = UDim2.new(0, 10, 1, -6)
		countdown.Size = UDim2.new(1, -20, 0, 2)
		countdown.ZIndex = 22
		countdown.Parent = frame

		local countdownRound = Instance.new("UICorner")
		countdownRound.CornerRadius = UDim.new(1, 0)
		countdownRound.Parent = countdown

		-- Linear, because a bar that says how much time is left and then eases
		-- is a bar that lies about it.
		TweenService:Create(countdown, TweenInfo.new(lifetime, Enum.EasingStyle.Linear), {
			Size = UDim2.new(0, 0, 0, 2),
		}):Play()

		------------------------------------------------------------------------
		-- arriving
		------------------------------------------------------------------------
		--
		-- The old version tweened frame.Position and nothing ever moved. The
		-- holder runs a UIListLayout, which owns Position and rewrites it every
		-- frame, so the whole animation was a no-op and only Maclib's own exit
		-- was ever visible. Only the contents can slide, so the contents slide
		-- and the frame fades in underneath them.

		local restingFill = frame.BackgroundTransparency
		local restingEdge = stroke and stroke.Transparency or 1
		frame.BackgroundTransparency = 1
		if stroke then
			stroke.Transparency = 1
		end
		if title then
			title.TextTransparency = 1
		end
		if body then
			body.TextTransparency = 1
		end

		local sliders = {}
		for _, child in ipairs({ info, frame:FindFirstChild("NotificationControls"), mark, close, countdown }) do
			if child and child:IsA("GuiObject") then
				local home = child.Position
				table.insert(sliders, { child = child, home = home })
				child.Position = home + UDim2.fromOffset(24, 0)
			end
		end

		TweenService:Create(frame, FADE, { BackgroundTransparency = restingFill }):Play()
		if stroke then
			TweenService:Create(stroke, FADE, { Transparency = restingEdge }):Play()
		end
		if title then
			TweenService:Create(title, FADE, { TextTransparency = TITLE_TT }):Play()
		end
		if body then
			TweenService:Create(body, FADE, { TextTransparency = BODY_TT }):Play()
		end
		TweenService:Create(mark, FADE, { ImageTransparency = 0.15 }):Play()
		TweenService:Create(countdown, FADE, { BackgroundTransparency = 0.55 }):Play()
		for _, bar in ipairs(bars) do
			TweenService:Create(bar, FADE, { BackgroundTransparency = 0.35 }):Play()
		end
		for _, slide in ipairs(sliders) do
			TweenService:Create(slide.child, ARRIVE, { Position = slide.home }):Play()
		end

		-- Exactly the bug the tabs had, and it was mine both times: a UIScale on
		-- something holding text asks Roblox to raster the font at a fractional
		-- size, so it redraws at a different one partway through. Notifications
		-- slide and fade, and that is all. Any scale Maclib left behind is
		-- pinned to 1 rather than animated.
		local scale = frame:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 1
		end
	end

	for _, child in ipairs(holder:GetChildren()) do
		dress(child)
	end
	core:Connect(holder.ChildAdded, function(child)
		task.defer(dress, child)
	end)
end

-- A bar that slides down the sidebar to whichever tab is selected. This is the
-- one piece of motion that carries the whole window: the panels change, and the
-- eye follows something continuous instead of a cut.
-- The mark, beside the name in the sidebar and small on every notification.
local function brandMark(core, base)
	local holder = base:FindFirstChild("Sidebar")
	holder = holder and holder:FindFirstChild("Information")
	holder = holder and holder:FindFirstChild("InformationHolder")
	local titleFrame = holder and holder:FindFirstChild("TitleFrame")
	if not titleFrame or holder:FindFirstChild("Mark") then
		return
	end

	-- Larger than the name beside it. It is the brand, and it is the one thing on
	-- this window anyone needs to remember.
	local mark = Instance.new("ImageLabel")
	mark.Name = "Mark"
	mark.BackgroundTransparency = 1
	mark.ImageColor3 = Color3.fromRGB(255, 255, 255)
	mark.Size = UDim2.fromOffset(50, 50)
	mark.AnchorPoint = Vector2.new(0, 0.5)
	mark.Position = UDim2.new(0, -4, 0.5, 0)
	mark.ZIndex = 3
	mark.Parent = holder
	core:Track(mark)
	core:UseAsset("mark", LOGO_IDS, mark)

	-- Only move the title over once the image actually renders. Reserving the
	-- space for an asset that never loads just truncates the name for nothing.
	for _ = 1, 60 do
		if mark.IsLoaded then
			break
		end
		task.wait(0.25)
	end

	if not mark.IsLoaded then
		mark:Destroy()
		return
	end

	local shift = Instance.new("UIPadding")
	shift.PaddingLeft = UDim.new(0, 54)
	shift.Parent = titleFrame
	core:Track(shift)
end

local function slidingIndicator(core, base)
	local sidebar = base:FindFirstChild("Sidebar")
	local group = sidebar and sidebar:FindFirstChild("SidebarGroup")
	local switchers = group and group:FindFirstChild("TabSwitchers")
	if not switchers or switchers:FindFirstChild("Indicator") then
		return
	end

	-- Not inside TabSwitchersScrollingFrame. That frame carries a UIListLayout,
	-- which owns the position of every child it has, so an indicator parented
	-- there was laid out as one more list item and parked below the last tab as
	-- a stray white sliver that no Position assignment could move.
	local indicator = Instance.new("Frame")
	indicator.Name = "Indicator"
	indicator.BorderSizePixel = 0
	indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	indicator.BackgroundTransparency = 0.25
	indicator.AnchorPoint = Vector2.new(0, 0.5)
	indicator.Size = UDim2.fromOffset(3, 0)
	indicator.Position = UDim2.fromOffset(2, 0)
	indicator.ZIndex = 5
	indicator.Visible = false
	indicator.Parent = switchers
	core:Track(indicator)

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = indicator

	-- Which tab is open is a fact the top bar already states. Guessing it from
	-- background transparency picked the wrong row, because a hovered tab and a
	-- selected tab are both lit, and the last match won rather than the right
	-- one. Matching the name is exact.
	local content = base:FindFirstChild("Content")
	local current = content
		and content:FindFirstChild("Topbar")
		and content.Topbar:FindFirstChild("Elements")
		and content.Topbar.Elements:FindFirstChild("CurrentTab")

	local function labelIn(row)
		for _, descendant in ipairs(row:GetDescendants()) do
			if descendant:IsA("TextLabel") and descendant.Text ~= "" then
				return descendant.Text
			end
		end
		return nil
	end

	local lastY = nil
	core:Loop("indicator", 0.08, function()
		if not current then
			return
		end
		local selected
		for _, descendant in ipairs(switchers:GetDescendants()) do
			if descendant.Name == "TabSwitcher" and descendant:IsA("GuiObject") then
				if labelIn(descendant) == current.Text then
					selected = descendant
					break
				end
			end
		end
		if not selected then
			return
		end

		-- Measured against the holder rather than the scroller, so it stays with
		-- its tab when the list scrolls and works across both tab groups.
		local y = selected.AbsolutePosition.Y - switchers.AbsolutePosition.Y + selected.AbsoluteSize.Y / 2
		local x = selected.AbsolutePosition.X - switchers.AbsolutePosition.X + 2

		-- Shrinking the window scrolls the selected tab out of the list, and the
		-- indicator followed it straight out of the window and sat in the sky.
		-- Nothing clips it, so it has to check for itself.
		local height = switchers.AbsoluteSize.Y
		if y < 10 or y > height - 10 then
			indicator.Visible = false
			lastY = nil
			return
		end

		if lastY and math.abs(y - lastY) < 0.5 then
			return
		end
		lastY = y

		if not indicator.Visible then
			indicator.Visible = true
			indicator.Position = UDim2.fromOffset(x, y)
			indicator.Size = UDim2.fromOffset(3, 18)
			return
		end

		TweenService:Create(indicator, TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(x, y),
		}):Play()
	end)
end

-- Panels arrive one after another rather than all at once when a tab opens.
local function animateTabs(core, base)
	local content = base:FindFirstChild("Content")
	local topbar = content and content:FindFirstChild("Topbar")
	local current = topbar
		and topbar:FindFirstChild("Elements")
		and topbar.Elements:FindFirstChild("CurrentTab")
	if not content or not current then
		return
	end

	-- Measured, frame by frame, across a switch from Farm to Combat: the old
	-- version slammed a UIScale from 1 to 0.985 in a single frame, held it there
	-- for nine frames because the delay sat inside the tween, then crept back.
	-- The label's height went 13 to 12 as it did, because a 13 pixel font scaled
	-- by 0.985 is 12.8 and Roblox rasters that at a different size. That is the
	-- snap and the font change together, and no amount of easing fixes it,
	-- because the fault is scaling type at all.
	--
	-- So nothing here touches scale. The panel slides, the edges fade in, and
	-- the glyphs are never redrawn at a size they were not authored at.
	local function play()
		-- Looked up here, not captured. Maclib replaces this frame on a tab
		-- change, so a reference taken once animates a panel nobody can see.
		local elements = content:FindFirstChild("Elements")
		if not elements then
			return
		end
		for _, scrolling in ipairs(elements:GetChildren()) do
			if scrolling:IsA("ScrollingFrame") and scrolling.Visible then
				scrolling.Position = UDim2.fromOffset(0, 12)
				TweenService:Create(
					scrolling,
					TweenInfo.new(0.36, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
					{ Position = UDim2.fromOffset(0, 0) }
				):Play()

				local index = 0
				for _, column in ipairs(scrolling:GetChildren()) do
					if column:IsA("Frame") then
						for _, section in ipairs(column:GetChildren()) do
							if section.Name == "Section" then
								-- Any UIScale left over from the old build has to
								-- go, or it keeps whatever value it was last
								-- tweened to and the type stays off-size forever.
								local stale = section:FindFirstChildOfClass("UIScale")
								if stale then
									stale.Scale = 1
									stale:Destroy()
								end

								local stroke = section:FindFirstChildOfClass("UIStroke")
								if stroke then
									index += 1
									stroke.Transparency = 1
									TweenService:Create(
										stroke,
										TweenInfo.new(
											0.42,
											Enum.EasingStyle.Quad,
											Enum.EasingDirection.Out,
											0,
											false,
											index * 0.06
										),
										{ Transparency = 0.88 }
									):Play()
								end
							end
						end
					end
				end
			end
		end
	end

	-- A poll on a timer meant up to a frame of the new tab sitting at rest
	-- before anything touched it, which is the jump that came first. The signal
	-- fires in the same frame the tab changes.
	core:Connect(current:GetPropertyChangedSignal("Text"), function()
		task.defer(play)
	end)
end

--------------------------------------------------------------------------------
-- backdrop blur, on while the menu is open
--------------------------------------------------------------------------------

-- There is no backdrop blur any more. It softened the entire game, which is
-- unusable for anyone who wants to play with the menu open, and it was the
-- thing that stayed on screen after minimising. Any left behind by an older
-- run gets cleared here so nobody inherits one.
local function clearBlur(core, window)
	for _, effect in ipairs(Lighting:GetChildren()) do
		if effect:IsA("BlurEffect") and effect.Name:match("^Meridian") then
			pcall(function()
				effect:Destroy()
			end)
		end
	end

	-- Maclib's own acrylic sits behind the window panel rather than over the
	-- game, so it stays, but it still has to go off when the window hides or it
	-- leaves a soft rectangle floating over nothing.
	local open = nil
	local acrylicWanted = nil

	core:Loop("blur", 0.2, function()
		local state = false
		pcall(function()
			state = window:GetState()
		end)
		if state == open then
			return
		end
		open = state
		pcall(function()
			if not state then
				acrylicWanted = window:GetAcrylicBlurState()
				window:SetAcrylicBlurState(false)
			elseif acrylicWanted then
				window:SetAcrylicBlurState(true)
			end
		end)
	end)
end

-- A soft light under the cursor, only inside the window. It lifts and brightens
-- while a row is lit, so the thing you are pointing at feels picked out rather
-- than just recoloured.
local function cursorLight(core, base)
	if base:FindFirstChild("CursorLight") then
		return
	end

	-- The resting light was doing the hovered light's job: bright enough that
	-- hovering barely read as a change, and bright enough to wash across the
	-- panels on its own. Everything moves down one step. Hover now looks the
	-- way resting used to, and resting is quieter than either.
	local REST, LIT = 560, 620

	local light = Instance.new("ImageLabel")
	light.Name = "CursorLight"
	light.BackgroundTransparency = 1
	light.Image = "rbxassetid://8992230677"
	light.ImageColor3 = Color3.fromRGB(255, 255, 255)
	light.ImageTransparency = 0.958
	light.AnchorPoint = Vector2.new(0.5, 0.5)
	light.Size = UDim2.fromOffset(REST, REST)
	-- Behind everything. The sidebar and the content area are both fully
	-- transparent frames, so a light underneath them still reads through the
	-- window, but it no longer washes across the panels and the type sitting on
	-- top of it. Wider and weaker at the same time, which is the combination he
	-- asked for: more light, less brightness.
	light.ZIndex = 0
	light.Visible = false
	light.Parent = base
	core:Track(light)

	-- MouseMoved hands back coordinates in the same space as AbsolutePosition.
	-- GetMouseLocation does not: it leaves out the top bar inset, which is why
	-- the light sat about sixty pixels above the cursor instead of on it.
	local targetX, targetY, currentX, currentY

	core:Connect(base.MouseMoved, function(x, y)
		targetX = x - base.AbsolutePosition.X
		targetY = y - base.AbsolutePosition.Y
		if not currentX then
			currentX, currentY = targetX, targetY
		end
		light.Visible = true
	end)

	core:Connect(base.MouseLeave, function()
		light.Visible = false
	end)

	local size, transparency = REST, 0.958

	core:Connect(RunService.RenderStepped, function(dt)
		if not targetX or not light.Visible then
			return
		end

		-- Eased by hand rather than tweened, because a tween restarted every
		-- frame never arrives anywhere. The position lags well behind the
		-- cursor on purpose: a light pinned exactly to the pointer reads as a
		-- cursor, one that trails reads as light.
		local follow = math.min(dt * 6, 1)
		currentX += (targetX - currentX) * follow
		currentY += (targetY - currentY) * follow
		light.Position = UDim2.fromOffset(currentX, currentY)

		local wantSize = core.HoverLit and LIT or REST
		local wantTransparency = core.HoverLit and 0.93 or 0.958
		local step = math.min(dt * 3, 1)
		size += (wantSize - size) * step
		transparency += (wantTransparency - transparency) * step

		light.Size = UDim2.fromOffset(size, size)
		light.ImageTransparency = transparency
	end)
end

--------------------------------------------------------------------------------
-- the search, in the topbar rather than in a tab of its own
--------------------------------------------------------------------------------

local SEARCH_ICONS = { "rbxassetid://7743878358", "rbxassetid://3926305904" }

-- Maclib's own numbers, read off the running window rather than invented.
--
-- There are two families here and the first version of this field belonged to
-- neither. A control sitting on a panel is white at 0.98 with a white stroke at
-- 0.88, and a Dropdown is white at 0.985 with a stroke at 0.95. Anything that
-- floats over the window - the colour picker prompt, a notification - is solid
-- RGB 15 with a 10 pixel corner and a white stroke at 0.90.
--
-- The field is a control, so it dresses as a control. The results panel floats,
-- so it dresses as a prompt.
local FIELD_REST, FIELD_HOVER, FIELD_FOCUS = 0.985, 0.955, 0.935
local EDGE_REST, EDGE_HOVER, EDGE_FOCUS = 0.95, 0.86, 0.76
local GLYPH_REST = Color3.fromRGB(138, 140, 148)
local GLYPH_LIVE = Color3.fromRGB(228, 230, 238)

-- The results list is a dropdown, so it is built out of a dropdown's parts and
-- not out of anything invented. Read off the running window:
--
--   Base            RGB 15 at 0.05, corner 10, white stroke at 0.90
--   GlobalSettings  RGB 15 at 0,    corner 10, white stroke at 0.90
--   Option row      transparent, corner 5, 30 tall, hover to 0.93
--   OptionName      size 13 at text transparency 0.20
--
-- The first version had rows at size 12 and full opacity, which made them the
-- brightest text anywhere in the window - brighter than the controls they point
-- at - and that is what he was looking at when he said the colours were wrong.
--
-- Nearly solid RGB 15 was right for a notification, which sits out on the
-- desktop with the game behind it, and wrong for this, which sits on the
-- window. Against panels that are 98 percent transparent it read as a hole
-- rather than a surface. Lighter, and enough of the tab shows through to say
-- it is floating over it.
local FLOAT_FILL = Color3.fromRGB(32, 32, 36)
local FLOAT_REST, FLOAT_EDGE = 0.18, 0.88
local ROW_TEXT, ROW_TEXT_LIT = 0.2, 0.05
local ROW_HOVER = 0.93

-- Finds a control's own frame in whichever tab is on screen, by its label.
-- Maclib hands back no reference to the instance it built, so the label is the
-- only handle there is.
local function frameFor(base, name)
	local content = base:FindFirstChild("Content")
	local elements = content and content:FindFirstChild("Elements")
	local scrolling = elements and elements:FindFirstChild("ElementsScrolling")
	if not scrolling then
		return nil
	end
	-- Climb to the control container, which is whatever sits directly inside a
	-- Section.
	local function climb(label)
		local frame = label
		while frame and frame.Parent and frame.Parent.Name ~= "Section" do
			frame = frame.Parent
			if frame == scrolling then
				return nil
			end
		end
		if frame and frame:IsA("GuiObject") then
			return frame
		end
		return nil
	end

	-- A dropdown does not label itself with its bare name. It reads
	-- "Skill Choice - Hardest That Reaches", so an exact match misses it
	-- entirely. Exact wins where it exists, prefix covers the rest.
	local fallback = nil
	for _, label in ipairs(scrolling:GetDescendants()) do
		if label:IsA("TextLabel") then
			if label.Text == name then
				local frame = climb(label)
				if frame then
					return frame
				end
			elseif not fallback and label.Text:sub(1, #name) == name then
				fallback = climb(label)
			end
		end
	end
	return fallback
end

-- Two pulses inside 0.65 seconds, a bit over 0.3 each, and brighter than they
-- were. It has to survive a tab switch happening around it and still be the
-- thing your eye lands on.
local function flash(core, frame)
	if not frame then
		return
	end
	local old = frame:FindFirstChild("MeridianFlash")
	if old then
		old:Destroy()
	end

	-- The same mono ramp every control is painted with, rather than a flat
	-- white block, which read as a selection instead of a highlight.
	--
	-- ZIndex has to clear the control's own children by a distance. At 30 a
	-- dropdown drew half its face back over the top of this and the highlight
	-- came out painted down one side only.
	local glow = Instance.new("Frame")
	glow.Name = "MeridianFlash"
	glow.BackgroundColor3 = ACCENT
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.Size = UDim2.fromScale(1, 1)
	glow.ZIndex = 200
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = glow
	local ramp = Instance.new("UIGradient")
	ramp.Rotation = 45
	ramp.Color = MONO_RAMP
	ramp.Parent = glow

	-- The other half of the half painted problem, and the half that survived
	-- the ZIndex fix. A UIPadding on the control shrinks anything sized in
	-- scale inside it, and a Dropdown pads 15 either side, so a full size
	-- highlight came out 30 pixels narrow with both ends of the row bare.
	-- Measured: glow 196 wide inside a 226 wide dropdown. Take the padding
	-- back, from every side, so this holds for whatever Maclib pads next.
	local inset = frame:FindFirstChildOfClass("UIPadding")
	if inset then
		local left, right = inset.PaddingLeft.Offset, inset.PaddingRight.Offset
		local top, bottom = inset.PaddingTop.Offset, inset.PaddingBottom.Offset
		glow.Position = UDim2.fromOffset(-left, -top)
		glow.Size = UDim2.new(1, left + right, 1, top + bottom)
	end

	glow.Parent = frame
	core:Track(glow)

	task.spawn(function()
		for _ = 1, 2 do
			if not glow.Parent then
				return
			end
			TweenService:Create(glow, TweenInfo.new(0.09), { BackgroundTransparency = 0.42 }):Play()
			task.wait(0.12)
			TweenService:Create(glow, TweenInfo.new(0.16), { BackgroundTransparency = 1 }):Play()
			task.wait(0.205)
		end
		glow:Destroy()
	end)
end

local function installSearch(core, base)
	local content = base:FindFirstChild("Content")
	local topbar = content and content:FindFirstChild("Topbar")
	local strip = topbar and topbar:FindFirstChild("Elements")
	if not strip or strip:FindFirstChild("MeridianSearch") then
		return
	end

	local ROWS = 8

	local holder = Instance.new("Frame")
	holder.Name = "MeridianSearch"
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -2, 0.5, 0)
	-- Scale rather than a fixed 236, so it keeps its proportions when the
	-- window is dragged smaller instead of eating the tab title.
	holder.Size = UDim2.new(0.58, 0, 0, 28)
	holder.BackgroundColor3 = ACCENT
	holder.BackgroundTransparency = FIELD_REST
	holder.BorderSizePixel = 0
	holder.ZIndex = 6
	holder.Parent = strip
	core:Track(holder)

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 7)
	round.Parent = holder

	local edge = Instance.new("UIStroke")
	edge.Color = ACCENT
	edge.Transparency = EDGE_REST
	edge.Thickness = 1
	edge.Parent = holder

	-- The tab title runs to 90% of the bar out of the box and would slide
	-- straight under a field this wide.
	local heading = strip:FindFirstChild("CurrentTab")
	if heading and heading:IsA("TextLabel") then
		heading.Size = UDim2.new(0.36, 0, heading.Size.Y.Scale, heading.Size.Y.Offset)
		heading.TextTruncate = Enum.TextTruncate.AtEnd
	end

	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.AnchorPoint = Vector2.new(0, 0.5)
	glyph.Position = UDim2.new(0, 9, 0.5, 0)
	glyph.Size = UDim2.fromOffset(13, 13)
	glyph.ImageColor3 = GLYPH_REST
	glyph.ZIndex = 7
	glyph.Parent = holder
	core:UseAsset("searchGlyph", SEARCH_ICONS, glyph)

	local box = Instance.new("TextBox")
	box.Name = "Field"
	box.BackgroundTransparency = 1
	box.Position = UDim2.fromOffset(29, 0)
	box.Size = UDim2.new(1, -38, 1, 0)
	box.Font = Enum.Font.GothamMedium
	box.TextSize = 12
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextColor3 = Color3.fromRGB(232, 233, 240)
	box.PlaceholderText = "Search Every Control"
	box.PlaceholderColor3 = Color3.fromRGB(118, 120, 128)
	box.Text = ""
	box.ClearTextOnFocus = false
	box.ZIndex = 7
	box.Parent = holder

	-- The results hang off Content rather than the topbar, so they cover the
	-- controls underneath instead of being clipped by a 63 pixel strip.
	local panel = Instance.new("Frame")
	panel.Name = "MeridianSearchResults"
	panel.Size = UDim2.fromOffset(320, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = FLOAT_FILL
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 40
	panel.Parent = content
	core:Track(panel)

	local panelRound = Instance.new("UICorner")
	panelRound.CornerRadius = UDim.new(0, 10)
	panelRound.Parent = panel

	local panelEdge = Instance.new("UIStroke")
	panelEdge.Color = ACCENT
	panelEdge.Transparency = 1
	panelEdge.Thickness = 1
	panelEdge.Parent = panel

	-- Same inner padding a dropdown gives its options.
	local inner = Instance.new("UIPadding")
	inner.Parent = panel

	inner.PaddingTop = UDim.new(0, 6)
	inner.PaddingBottom = UDim.new(0, 6)
	inner.PaddingLeft = UDim.new(0, 6)
	inner.PaddingRight = UDim.new(0, 6)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = panel

	local rows = {}
	local current = {}
	local shown = false

	----------------------------------------------------------------------------
	-- states
	----------------------------------------------------------------------------

	local hovering, focused = false, false

	local function paint()
		local live = hovering or focused
		local fill = focused and FIELD_FOCUS or (hovering and FIELD_HOVER or FIELD_REST)
		local line = focused and EDGE_FOCUS or (hovering and EDGE_HOVER or EDGE_REST)
		TweenService:Create(holder, SMOOTH, { BackgroundTransparency = fill }):Play()
		TweenService:Create(edge, SMOOTH, { Transparency = line }):Play()
		TweenService:Create(glyph, SMOOTH, { ImageColor3 = live and GLYPH_LIVE or GLYPH_REST }):Play()
	end

	-- Measured off the field itself every time rather than worked out from the
	-- topbar's padding. The field is sized in scale inside a padded strip and
	-- the panel is not, so any arithmetic linking the two is wrong the moment
	-- the window is resized.
	local function place()
		local x = holder.AbsolutePosition.X - content.AbsolutePosition.X
		local y = holder.AbsolutePosition.Y - content.AbsolutePosition.Y + holder.AbsoluteSize.Y + 8
		panel.Size = UDim2.new(0, math.max(holder.AbsoluteSize.X, 240), 0, 0)
		return x, y
	end

	local function show()
		local x, y = place()
		if shown then
			panel.Position = UDim2.fromOffset(x, y)
			return
		end
		shown = true
		panel.Visible = true
		panel.Position = UDim2.fromOffset(x, y - 10)
		panel.BackgroundTransparency = 1
		panelEdge.Transparency = 1
		TweenService:Create(panel, SMOOTH, {
			Position = UDim2.fromOffset(x, y),
			BackgroundTransparency = FLOAT_REST,
		}):Play()
		TweenService:Create(panelEdge, SMOOTH, { Transparency = FLOAT_EDGE }):Play()

		-- Staggered, so the list reads as arriving rather than appearing.
		for index, row in ipairs(rows) do
			row.TextTransparency = 1
			if row.Visible then
				task.delay(index * 0.025, function()
					if shown and row.Visible then
						TweenService:Create(row, SMOOTH, { TextTransparency = ROW_TEXT }):Play()
					end
				end)
			end
		end
	end

	local function hide()
		if not shown then
			return
		end
		shown = false
		local x, y = place()
		TweenService:Create(panel, FAST, {
			Position = UDim2.fromOffset(x, y - 8),
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(panelEdge, FAST, { Transparency = 1 }):Play()
		for _, row in ipairs(rows) do
			TweenService:Create(row, FAST, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		end
		task.delay(0.2, function()
			if not shown and panel.Parent then
				panel.Visible = false
			end
		end)
	end

	core:Connect(holder.MouseEnter, function()
		hovering = true
		paint()
	end)
	core:Connect(holder.MouseLeave, function()
		hovering = false
		paint()
	end)
	core:Connect(box.Focused, function()
		focused = true
		paint()
	end)

	----------------------------------------------------------------------------
	-- rows
	----------------------------------------------------------------------------

	for i = 1, ROWS do
		local row = Instance.new("TextButton")
		row.Name = "Row" .. i
		row.BackgroundColor3 = ACCENT
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 30)
		row.Font = Enum.Font.GothamMedium
		row.TextSize = 13
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextTruncate = Enum.TextTruncate.AtEnd
		row.TextColor3 = ACCENT
		row.TextTransparency = ROW_TEXT
		row.Text = ""
		row.AutoButtonColor = false
		row.Visible = false
		row.LayoutOrder = i
		row.ZIndex = 41
		row.Parent = panel

		local rowRound = Instance.new("UICorner")
		rowRound.CornerRadius = UDim.new(0, 5)
		rowRound.Parent = row

		local rowPad = Instance.new("UIPadding")
		rowPad.PaddingLeft = UDim.new(0, 9)
		rowPad.PaddingRight = UDim.new(0, 9)
		rowPad.Parent = row

		core:Connect(row.MouseEnter, function()
			TweenService:Create(row, FAST, {
				BackgroundTransparency = ROW_HOVER,
				TextTransparency = ROW_TEXT_LIT,
			}):Play()
		end)
		core:Connect(row.MouseLeave, function()
			TweenService:Create(row, FAST, {
				BackgroundTransparency = 1,
				TextTransparency = ROW_TEXT,
			}):Play()
		end)

		core:Connect(row.MouseButton1Click, function()
			local entry = current[i]
			if not entry then
				return
			end
			hide()
			box.Text = ""
			pcall(function()
				entry.tabObject:Select()
			end)
			-- The tab rebuilds its columns, so the frame does not exist for a
			-- couple of frames yet - and beyond that, the sidebar indicator is
			-- still sliding and the panels are still fading in. Flashing into
			-- the middle of that reads as part of the tab change rather than as
			-- "here it is", so it waits for the room to settle first.
			task.spawn(function()
				task.wait(0.34)
				for _ = 1, 40 do
					local frame = frameFor(base, entry.name)
					if frame then
						flash(core, frame)
						return
					end
					task.wait(0.05)
				end
			end)
		end)

		rows[i] = row
	end

	local function render(text)
		current = core:SearchControls(text, ROWS)
		for i = 1, ROWS do
			local entry, row = current[i], rows[i]
			if entry then
				row.Text = entry.path or entry.name
				row.Visible = true
			else
				row.Visible = false
			end
		end
		if #current > 0 then
			show()
		else
			hide()
		end
	end

	core:Connect(box:GetPropertyChangedSignal("Text"), function()
		render(box.Text)
	end)

	core:Connect(holder:GetPropertyChangedSignal("AbsoluteSize"), function()
		if shown then
			local x, y = place()
			panel.Position = UDim2.fromOffset(x, y)
		end
	end)

	-- Left open on purpose while something matches, so a row can still be
	-- clicked after the field loses focus.
	core:Connect(box.FocusLost, function()
		focused = false
		paint()
		if box.Text:gsub("%s", "") == "" then
			hide()
		end
	end)

	core:Connect(UserInputService.InputBegan, function(input, typing)
		if typing or not shown then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local mouse = UserInputService:GetMouseLocation()
		local top, size = panel.AbsolutePosition, panel.AbsoluteSize
		local field, fieldSize = holder.AbsolutePosition, holder.AbsoluteSize
		local inPanel = mouse.X >= top.X and mouse.X <= top.X + size.X
			and mouse.Y >= top.Y and mouse.Y <= top.Y + size.Y
		local inField = mouse.X >= field.X and mouse.X <= field.X + fieldSize.X
			and mouse.Y >= field.Y and mouse.Y <= field.Y + fieldSize.Y
		if not inPanel and not inField then
			hide()
		end
	end)
end

--------------------------------------------------------------------------------

function UI.Apply(core, base, window, tips)
	tips = tips or {}
	UI.Bounds = base
	core.Base = base

	-- Measured, the hard way: a game module's own closures may not *walk* the
	-- protected gui container. FindFirstChild and GetDescendants from one throw
	-- "the current thread cannot access Instance", and calling a function in
	-- this file from that stack inherits the same restriction. Writing a
	-- property on an instance it already holds is fine, which is exactly why
	-- Maclib's own UpdateBody keeps working from those loops.
	--
	-- So this file does the walking, once per sweep, and leaves modules a table
	-- of labels they only have to assign to. It is refreshed every sweep, so it
	-- also survives Maclib rebuilding the tab on each switch.
	core.Panels = core.Panels or {}

	-- The assignment itself has to happen in a closure from this file. Maclib's
	-- own UpdateBody keeps working from those same restricted loops for exactly
	-- this reason, while the identical line written inside a game module does
	-- not. No walking in here: the labels were already found by the sweep.
	function core.SetPanelText(title, header, body)
		local panel = core.Panels and core.Panels[title]
		if not panel then
			return false
		end
		if panel.Header and header then
			panel.Header.Text = header
		end
		if panel.Body and body then
			panel.Body.Text = body
		end
		return true
	end

	local show, hide = buildTooltip(core, base.Parent)

	local content = base:FindFirstChild("Content")
	if not content then
		return
	end

	-- Measured: Maclib does not merely refill the elements area on a tab change,
	-- it replaces the whole Elements frame. Holding a reference to it, which is
	-- what this did, meant every sweep after the first tab switch was polishing
	-- an orphan that had already left the DataModel: no hover on any row, no
	-- config panel moved across, nothing. It has to be looked up each pass.
	local watching = nil

	local function sweep()
		local elements = content:FindFirstChild("Elements")
		if not elements then
			return
		end

		if elements ~= watching then
			watching = elements
			core:Connect(elements.DescendantAdded, function()
				task.defer(sweep)
			end)
		end

		for _, descendant in ipairs(elements:GetDescendants()) do
			if descendant:IsA("Frame") then
				if descendant.Name == "SubLabel" then
					-- The descriptions live on hover now, so the wall of grey
					-- text under every control goes away.
					descendant.Visible = false
					descendant.Size = UDim2.new(1, 0, 0, 0)
				elseif descendant.Name == "Section" then
					polishSection(core, descendant)
					setTypeScale(descendant)
				elseif ELEMENT_KINDS[descendant.Name] then
					polishElement(core, descendant, tips, show, hide)
				end
			end
		end
		-- The picker prompts are built next to the window rather than inside the
		-- elements area, so they are found from the base instead.
		for _, descendant in ipairs(base:GetDescendants()) do
			if descendant.Name == "Prompt" and descendant.Parent and descendant.Parent.Name == "ColorPicker" then
				polishColorPicker(core, descendant)
			end
		end

		titleConfigSection(core, elements)
		balanceColumns(core, elements)
		polishOptions(core, elements)
		polishSidebar(core, base)

		local panels = {}
		for _, section in ipairs(elements:GetDescendants()) do
			if section.Name == "Section" then
				local title, header, body
				for _, label in ipairs(section:GetDescendants()) do
					if label.Name == "HeaderText" and label:IsA("TextLabel") then
						title = title or label.Text
					elseif label.Name == "ParagraphHeader" then
						header = label
					elseif label.Name == "ParagraphBody" then
						body = label
					end
				end
				if title and (header or body) then
					panels[title] = { Header = header, Body = body }
				end
			end
		end
		core.Panels = panels
	end

	-- A rebuilt tab has to be caught the moment it appears, and the slow loop
	-- behind it covers the case where the new frame arrives without a descendant
	-- event this connection is still attached to. Both are cheap: the visible
	-- tab is under a few hundred instances.
	sweep()
	core:Connect(content.ChildAdded, function(child)
		if child.Name == "Elements" then
			task.defer(sweep)
		end
	end)
	core:Loop("uiSweep", 0.35, sweep)

	polishSidebar(core, base)
	installSearch(core, base)
	growGlobeButton(core, base)
	polishNotifications(core, base.Parent)
	task.spawn(brandMark, core, base)
	slidingIndicator(core, base)
	animateTabs(core, base)
	clearBlur(core, window)
	cursorLight(core, base)
end

return UI
