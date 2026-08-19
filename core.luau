--// Prism · shared core
--// Everything that is not specific to one game lives here. A game module gets
--// this table as `core` and never touches services or cleanup itself.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local Core = {}
Core.__index = Core

function Core.new(info)
	local self = setmetatable({}, Core)
	self.Name = info.Name or "Prism"
	self.Version = info.Version or "0.0"
	self.Alive = true
	self.Flags = {}
	self._conns = {}
	self._loops = {}
	self._objects = {}
	self._restore = {}
	self._notify = nil
	-- Notifications, waiting to be dressed. A frame does not carry how long it
	-- lives or a handle to cancel it, and the interface needs both.
	self.Pending = {}
	return self
end

--------------------------------------------------------------------------------
-- lifetime
--------------------------------------------------------------------------------

function Core:Connect(signal, fn)
	local conn = signal:Connect(fn)
	table.insert(self._conns, conn)
	return conn
end

-- A named loop. Starting one that already exists replaces it, so a toggle
-- flipped twice never leaves two copies running.
function Core:Loop(name, interval, fn)
	self:StopLoop(name)
	local record = { alive = true }
	self._loops[name] = record
	record.thread = task.spawn(function()
		while record.alive and self.Alive do
			-- xpcall rather than pcall, so a loop that breaks says where. A bare
			-- message with no line in it cost a long time once already.
			local ok, err = xpcall(fn, function(problem)
				return tostring(problem) .. "\n" .. debug.traceback(nil, 2)
			end)
			if not ok then
				warn(("[%s] loop %s: %s"):format(self.Name, name, tostring(err)))
				task.wait(1)
			end
			task.wait(interval)
		end
	end)
	return record
end

function Core:StopLoop(name)
	local record = self._loops[name]
	if not record then
		return
	end
	record.alive = false
	self._loops[name] = nil
end

function Core:Track(object)
	table.insert(self._objects, object)
	return object
end

-- Point an ImageLabel at the first id in the list that actually renders, and
-- keep pointing every label that asked for the same key at it.
--
-- This exists because a re-uploaded asset is useless until its privacy is set
-- to open use, and that has now caught us three times. Labels take the first id
-- straight away, which is the one meant to be shown, and drop to a later one
-- only if it turns out not to be public on this account.
--
-- The probe is PreloadAsync's status callback, not IsLoaded. Roblox does not
-- fetch an image that is not actually on screen, so the old probe - a 1x1 label
-- inside a disabled ScreenGui - reported false for every id including ones
-- known to work, and the fallback was the only branch that ever ran.
function Core:UseAsset(key, ids, label)
	self._assets = self._assets or {}
	local record = self._assets[key]

	if not record then
		record = { current = ids[1], users = {} }
		self._assets[key] = record

		task.spawn(function()
			local content = game:GetService("ContentProvider")

			for _, id in ipairs(ids) do
				local probe = Instance.new("ImageLabel")
				probe.Image = id
				local fetched = false
				pcall(function()
					content:PreloadAsync({ probe }, function(_, status)
						fetched = status == Enum.AssetFetchStatus.Success
					end)
				end)
				probe:Destroy()

				if fetched then
					if record.current ~= id then
						record.current = id
						for _, user in ipairs(record.users) do
							pcall(function()
								user.Image = id
							end)
						end
					end
					break
				end
			end
		end)
	end

	if label then
		label.Image = record.current
		table.insert(record.users, label)
	end
	return record
end

-- Replace a field on someone else's table and remember how to put it back.
function Core:Override(tbl, key, value)
	table.insert(self._restore, { tbl = tbl, key = key, old = tbl[key] })
	tbl[key] = value
end

function Core:Restore(tbl, key)
	for i = #self._restore, 1, -1 do
		local entry = self._restore[i]
		if entry.tbl == tbl and entry.key == key then
			tbl[key] = entry.old
			table.remove(self._restore, i)
			return
		end
	end
end

--------------------------------------------------------------------------------
-- the control index, which is what makes the search possible
--------------------------------------------------------------------------------

-- Every control in the hub is created through a section, so wrapping the tab
-- group once catches all of them without a single call site having to register
-- itself. A game module writes its tabs exactly as it always did and gets
-- indexed for free.
--
-- The wrappers forward by hand rather than through an __index metatable,
-- because a metatable would hand Maclib's own methods the proxy as `self` and
-- they read fields off it.
local NAMED = {
	Toggle = true,
	Slider = true,
	Dropdown = true,
	Keybind = true,
	Colorpicker = true,
	Button = true,
	Input = true,
}

local PLAIN = { "Header", "Paragraph", "Label", "SubLabel", "Divider", "Spacer" }

-- Reads as one path rather than a filename, and matches the separator the
-- dropdowns already use for their value.
local SEPARATOR = " • "

function Core:IndexTabs(tabGroup)
	self.Controls = self.Controls or {}
	local controls = self.Controls

	local group = {}

	function group:Tab(options)
		local tab = tabGroup:Tab(options)
		local tabName = (options and options.Name) or "Tab"

		local tabProxy = {
			_real = tab,
			Name = tabName,
		}

		function tabProxy:Select()
			return tab:Select()
		end

		function tabProxy:InsertConfigSection(side)
			return tab:InsertConfigSection(side)
		end

		function tabProxy:Section(sectionOptions)
			local section = tab:Section(sectionOptions)
			local side = (sectionOptions and sectionOptions.Side) or "Left"
			local proxy = { _real = section }

			-- The last header written into this section names the group the
			-- controls under it belong to, which is what turns a bare "Reach"
			-- into "Combat \ Aura \ Reach" in the search.
			local group = nil

			for kind in pairs(NAMED) do
				proxy[kind] = function(_, config, flag)
					local control = section[kind](section, config, flag)
					if config and config.Name then
						controls[#controls + 1] = {
							name = config.Name,
							kind = kind,
							tab = tabName,
							tabObject = tab,
							group = group,
							side = side,
							control = control,
							flag = flag,
							path = group and (tabName .. SEPARATOR .. group .. SEPARATOR .. config.Name)
								or (tabName .. SEPARATOR .. config.Name),
						}
					end
					return control
				end
			end

			for _, kind in ipairs(PLAIN) do
				proxy[kind] = function(_, config, flag)
					if kind == "Header" and config then
						group = config.Text or config.Name or group
					end
					return section[kind](section, config, flag)
				end
			end

			return proxy
		end

		return tabProxy
	end

	return group
end

-- Ranked, so an exact word beats a stray substring. Returns at most `limit`.
function Core:SearchControls(query, limit)
	local out = {}
	if type(query) ~= "string" then
		return out
	end
	local needle = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if needle == "" then
		return out
	end

	for _, entry in ipairs(self.Controls or {}) do
		local name = entry.name:lower()
		local score
		if name == needle then
			score = 0
		elseif name:sub(1, #needle) == needle then
			score = 1
		elseif name:find(needle, 1, true) then
			score = 2
		elseif entry.group and entry.group:lower():find(needle, 1, true) then
			score = 3
		elseif entry.tab:lower():find(needle, 1, true) then
			score = 4
		end
		if score then
			out[#out + 1] = { entry = entry, score = score }
		end
	end

	table.sort(out, function(a, b)
		if a.score ~= b.score then
			return a.score < b.score
		end
		if a.entry.tab ~= b.entry.tab then
			return a.entry.tab < b.entry.tab
		end
		return a.entry.name < b.entry.name
	end)

	local results = {}
	for i = 1, math.min(#out, limit or 12) do
		results[i] = out[i].entry
	end
	return results
end

function Core:Unload()
	self.Alive = false
	for name in pairs(self._loops) do
		self:StopLoop(name)
	end
	for _, conn in ipairs(self._conns) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	for i = #self._restore, 1, -1 do
		local entry = self._restore[i]
		pcall(function()
			entry.tbl[entry.key] = entry.old
		end)
	end
	for _, object in ipairs(self._objects) do
		pcall(function()
			if typeof(object) == "Instance" then
				object:Destroy()
			elseif type(object) == "function" then
				object()
			end
		end)
	end
	self._conns = {}
	self._objects = {}
	self._restore = {}
end

--------------------------------------------------------------------------------
-- talking to the user
--------------------------------------------------------------------------------

function Core:SetNotifier(fn)
	self._notify = fn
end

function Core:Notify(title, description, lifetime)
	if not self._notify then
		return nil
	end
	lifetime = lifetime or 4

	-- Queued rather than passed, because Maclib builds the frame inside the
	-- call and the interface hears about it through ChildAdded. They come out
	-- in the order they went in, which is the order the frames are created.
	local pending = { lifetime = lifetime }
	table.insert(self.Pending, pending)
	-- Nothing has ever left one behind, but a queue that only the interface
	-- drains is a queue that grows for good if the interface is not there.
	while #self.Pending > 8 do
		table.remove(self.Pending, 1)
	end

	local ok, handle = pcall(self._notify, title, description, lifetime)
	pending.handle = ok and handle or nil
	return pending.handle
end

--------------------------------------------------------------------------------
-- character
--------------------------------------------------------------------------------

function Core:Character()
	local char = LocalPlayer.Character
	if not char or not char.Parent then
		return nil
	end
	return char
end

function Core:Humanoid()
	local char = self:Character()
	return char and char:FindFirstChildOfClass("Humanoid") or nil
end

function Core:Root()
	local char = self:Character()
	return char and char:FindFirstChild("HumanoidRootPart") or nil
end

function Core:Alive2()
	local hum = self:Humanoid()
	return hum ~= nil and hum.Health > 0
end

function Core:DistanceTo(position)
	local root = self:Root()
	if not root then
		return math.huge
	end
	return (root.Position - position).Magnitude
end

--------------------------------------------------------------------------------
-- targets
--
-- A game module supplies a `list()` returning candidate models. Everything below
-- is generic: it only needs a HumanoidRootPart and a Humanoid.
--------------------------------------------------------------------------------

local function rootOf(model)
	return model and model:FindFirstChild("HumanoidRootPart") or nil
end

function Core:PickTarget(list, opts)
	opts = opts or {}
	local mode = opts.mode or "Closest"
	local maxRange = opts.range or math.huge
	local myRoot = self:Root()
	if not myRoot then
		return nil
	end

	local camera = Workspace.CurrentCamera
	local best, bestScore = nil, math.huge

	for _, model in ipairs(list) do
		local root = rootOf(model)
		local hum = model:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			local distance = (root.Position - myRoot.Position).Magnitude
			if distance <= maxRange then
				local score
				if mode == "Weakest" or mode == "Lowest Health" then
					-- Health first, and distance as much or as little as the
					-- caller says. A nudge is right for the aura, which is not
					-- going anywhere. It is wrong for the farm: at 0.05 a
					-- hundred studs cost five health, so it crossed the arena
					-- for anyone slightly hurt and spent nearly three quarters
					-- of a run in transit, taking hits the whole way. Measured
					-- on Fly: 16 samples in range out of 60.
					score = hum.Health + distance * (opts.distanceWeight or 0.05)
				elseif mode == "Crosshair" and camera then
					local point, onScreen = camera:WorldToViewportPoint(root.Position)
					if onScreen then
						local centre = camera.ViewportSize / 2
						score = (Vector2.new(point.X, point.Y) - centre).Magnitude
					else
						score = math.huge
					end
				else
					score = distance
				end
				if score < bestScore then
					best, bestScore = model, score
				end
			end
		end
	end
	return best
end

-- Turn to face a position. Yaw only, so the character never tips over.
--
-- Nothing this game sends over the wire carries a direction. Big Beam invokes
-- StartSkill with a name and a timestamp and nothing else, and the server
-- builds the hitbox out of HumanoidRootPart.CFrame * HitboxOffset. Aiming is
-- entirely a question of which way the root points when the server reads it.
--
-- And the root cannot be written. This game locks the mouse by default, which
-- is what the "Unlock Camera: Shift" prompt on the HUD is about, and while it
-- is locked the control module copies the camera's yaw onto the root every
-- frame. Measured in game: root yaw and camera yaw agree to two decimal
-- places, and a root CFrame written by hand is gone again inside 200ms.
--
-- Writing the camera instead is what he felt as his view being yanked and
-- thrown back. The camera module recomputes from its own stored angles on the
-- very next frame and undoes it, so the aim never landed either.
--
-- So move the mouse. The camera module reads mouse deltas, and a turn it
-- performed itself is a turn that sticks and eases the way its own turns do.
-- How many pixels a radian costs depends on the player's sensitivity slider,
-- so it is measured on the first turn and remembered, sign included.
-- How far the mouse may be moved in one frame, in pixels, and how much of a
-- turn that is allowed to buy.
--
-- 200 was cautious: at the sensitivity measured here, around 400 pixels to the
-- radian, one frame could only correct 26 degrees and the aim sat 36 degrees
-- off while the farm flew around its target. Raising it to 900 made it worse,
-- 61 degrees, and the instrumentation said why: **the learned gain came back
-- positive**, so it was turning away from the target and correcting back, over
-- and over. 1176 of 3403 steps started more than 90 degrees off.
--
-- A single frame turn of more than 180 degrees wraps, and a wrapped angle has
-- the opposite sign, so `pixels / turned` learns a gain pointing the wrong way.
-- Three defences, all cheap:
--
--   * the step is capped by the turn it buys, not just by pixels
--   * a sample is only learned from if the turn was small enough to be
--     unambiguous
--   * the sign is not learned at all. Moving the mouse right always decreases
--     yaw in this convention, on every machine, so only the magnitude varies.
--     Measured on three separate sessions: -305, -432, -382.
--
-- And a fourth, which is the one that actually decided it: **pixels per radian
-- is only linear for small moves.** Roblox smooths a large per-frame mouse
-- delta, so a 558 pixel step bought about 30 degrees instead of the 80 it was
-- asked for, the learned gain jumped from 400 to 1138, the next step was bigger
-- still, and the aim ended up 98 degrees off on average. The step stays in the
-- linear region and only measurements taken there are believed.
local TURN_STEP = 260
local TURN_MAX_ARC = math.rad(34)
local TURN_LEARN_ARC = math.rad(15)
local TURN_FIRST_STEP = 45

-- Where the shaking came from, and it was not the gain.
--
-- The old step was proportional and had no floor: `pixels = -off * gain`, then
-- forced to at least one pixel in whichever direction it pointed. So once the
-- aim was on target it never stopped. Every frame it measured a fraction of a
-- degree of error, rounded that up to a whole pixel, overshot by a fraction of
-- a degree the other way, and did it again. A limit cycle at sixty hertz, and
-- under shiftlock the camera *is* the aim, so the whole view buzzed.
--
-- Three things fix it and all three are worth having on their own:
--
--   * **A deadband with hysteresis.** Inside TURN_CLOSE it stops. It does not
--     start again until the error has grown past TURN_RESUME, so a target
--     drifting around the edge of the deadband cannot chatter the loop on and
--     off either.
--   * **A rate limit in degrees a second**, rather than "as far as the gain
--     says in one frame". This is the number he asked to be able to set: it is
--     how fast the view sweeps, and it is the difference between the camera
--     panning onto someone and the camera teleporting onto them.
--   * **A sub-pixel carry.** Wanting 0.4 of a pixel used to mean moving a whole
--     one. Now the remainder is banked and spent when it adds up, so small
--     corrections stay small instead of being rounded into a jolt.
local TURN_CLOSE = math.rad(2.5)
local TURN_RESUME = math.rad(9)
local TURN_RATE = math.rad(420)
local TURN_EASE = 0.25
local TURN_DT_MIN, TURN_DT_MAX = 1 / 240, 1 / 20

-- Following, as opposed to catching up.
--
-- Easing alone cannot track something that keeps moving. The loop settles where
-- its correction per frame equals the speed the target's bearing is changing,
-- so there is always a lag, and the faster the target circles the worse it is.
-- Flying a standoff of eleven studs at a hundred and twenty a second swings the
-- bearing round at about 625 degrees a second, which at a quarter of the error
-- a frame settles some forty degrees behind.
--
-- The fix is to stop asking the correction to do two jobs. How fast the target
-- is moving is measurable, so it is measured and added straight in: the aim
-- moves at the target's own rate, and the eased term is left to do nothing but
-- close whatever gap remains. That term is what the speed slider governs, and
-- it is the only part that could ever jerk - following at the same rate as the
-- thing you are following is smooth by construction.
--
-- Guarded, because a target that changes is not a target that moved fast: a
-- reading older than this, or an implied rate above it, is thrown away.
local TURN_FOLLOW_STALE = 0.25
local TURN_FOLLOW_MAX = math.rad(900)

local function wrapAngle(angle)
	while angle > math.pi do
		angle -= math.pi * 2
	end
	while angle < -math.pi do
		angle += math.pi * 2
	end
	return angle
end

local function flatYaw(vector)
	return math.atan2(-vector.X, -vector.Z)
end

-- Is something else holding the view, so that turning means moving the mouse
-- rather than turning the character?
--
-- This used to answer yes whenever the camera was within two studs of the
-- character, on the reasoning that first person means the camera sits inside
-- you. It does - but so does an ordinary third person camera that has been
-- pushed in by a wall, and **the farm flies through walls constantly**. Live in
-- a fourteen player server that misread first person over and over, took the
-- mouse path, found native input unavailable, and span: measured at 13,020
-- calls in a single frame, eight frames a second.
--
-- So it asks the two things that actually mean the view is locked, and neither
-- of them can be faked by geometry.
function Core:MouseLocked()
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		return true
	end
	if LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson then
		return true
	end
	return false
end

-- One correction step, and the piece everything else is built on. Returns true
-- when it is already pointing close enough, which is also how a caller knows it
-- can stop.
-- How fast the view is allowed to sweep, in radians a second. His slider, in
-- degrees, lands on Flags.faceSpeed.
function Core:AimRate()
	local set = tonumber(self.Flags and self.Flags.faceSpeed)
	if not set then
		return TURN_RATE
	end
	return math.rad(math.clamp(set, 60, 1200))
end

-- Seconds since the last correction, so a rate in degrees a second means the
-- same thing at thirty frames as at a hundred and forty. Clamped at both ends:
-- a hitch must not buy a huge turn, and two steps in the same frame must not
-- divide by nothing.
function Core:AimDelta()
	local now = os.clock()
	local last = self._turnAt
	self._turnAt = now
	if not last then
		return TURN_DT_MAX
	end
	return math.clamp(now - last, TURN_DT_MIN, TURN_DT_MAX)
end

-- Returns two things: whether it is already pointing close enough, and whether
-- it has already given up a frame. The second is not a detail - a caller that
-- loops on this must know, or the one path that returns without waiting turns
-- the whole loop into a busy wait. That is not hypothetical: it is what the
-- eight frames a second above actually were.
function Core:FaceStep(position, tolerance)
	local root = self:Root()
	if not root then
		return false, false
	end
	tolerance = tolerance or TURN_CLOSE

	local at = root.Position
	local flat = Vector3.new(position.X - at.X, 0, position.Z - at.Z)
	if flat.Magnitude < 0.05 then
		return true, false
	end

	local locked = self:MouseLocked()
	local camera = Workspace.CurrentCamera

	-- Out of shiftlock, go straight onto the bearing.
	--
	-- Smoothing exists because a camera that jerks is horrible to sit behind.
	-- Out of shiftlock there is no camera in this at all: the view stays
	-- wherever he left it and only the character turns, which nobody feels.
	-- Easing it costs accuracy and buys nothing.
	--
	-- And it costs a great deal of accuracy. Flying a standoff of eleven studs
	-- at a hundred and twenty a second swings the bearing to the target round
	-- at about 625 degrees a second. An eased turn settles where its correction
	-- per frame matches that, which at a quarter of the error is 42 degrees
	-- behind - measured live at 82, against 3 for the version that snapped.
	-- **You cannot both ease and track something orbiting that fast**, so the
	-- two cases are answered differently rather than compromised into one.
	if not locked then
		root.CFrame = CFrame.lookAt(at, Vector3.new(position.X, at.Y, position.Z))
		self._turnSettled = false
		return true, false
	end

	local before = flatYaw(camera and camera.CFrame.LookVector or root.CFrame.LookVector)
	local off = wrapAngle(flatYaw(flat) - before)

	-- The deadband, with hysteresis. Settled stays settled until the target has
	-- drifted properly off, not merely past the line.
	if self._turnSettled then
		if math.abs(off) < TURN_RESUME then
			return true, false
		end
		self._turnSettled = false
	elseif math.abs(off) < tolerance then
		self._turnSettled = true
		self._turnCarry = 0
		return true, false
	end

	-- Ease toward it and cap the speed. `off * TURN_EASE` is what makes the
	-- sweep decelerate as it arrives instead of stopping dead; the rate cap is
	-- what stops it starting like a whip.
	local dt = self:AimDelta()
	local ceiling = self:AimRate() * dt
	local step = math.clamp(off * TURN_EASE, -ceiling, ceiling)

	-- Plus however fast the target itself is going round. Uncapped on purpose:
	-- this is not a correction, it is keeping pace, and clamping it would put
	-- the lag straight back.
	local bearing = flatYaw(flat)
	local now = os.clock()
	local last = self._turnBearing
	if last and (now - last.at) < TURN_FOLLOW_STALE and (now - last.at) > 0 then
		local rate = wrapAngle(bearing - last.bearing) / (now - last.at)
		if math.abs(rate) < TURN_FOLLOW_MAX then
			step += rate * dt
		end
	end
	self._turnBearing = { bearing = bearing, at = now }

	if not camera or type(mousemoverel) ~= "function" then
		return false, false
	end
	-- Native input goes nowhere while the window is in the background, so this
	-- says so rather than pretending to have aimed. It is also the single most
	-- common state this thing runs in, because alt-tabbing is normal, so the
	-- caller has to be told it did not wait.
	if isrbxactive and not isrbxactive() then
		return false, false
	end

	-- Magnitude only. The sign is fixed.
	self._turnGain = math.clamp(math.abs(self._turnGain or 160), 80, 700)

	-- Capped by the arc it buys as well as by raw pixels, so one frame can
	-- never turn far enough for the measurement below to wrap.
	local limit = math.min(TURN_STEP, self._turnGain * TURN_MAX_ARC)
	if not self._turnLearned then
		limit = math.min(limit, TURN_FIRST_STEP)
	end

	-- Bank the fraction of a pixel rather than rounding it up to a whole one.
	-- Rounding up is what kept the view buzzing after it had arrived.
	local wanted = math.clamp(-step * self._turnGain, -limit, limit) + (self._turnCarry or 0)
	local pixels = wanted >= 0 and math.floor(wanted) or math.ceil(wanted)
	self._turnCarry = math.clamp(wanted - pixels, -1, 1)
	if pixels == 0 then
		return false, false
	end

	mousemoverel(pixels, 0)
	task.wait()

	local turned = wrapAngle(flatYaw(camera.CFrame.LookVector) - before)
	if math.abs(turned) > 0.004 and math.abs(turned) < TURN_LEARN_ARC and math.abs(pixels) >= 2 then
		local learned = math.abs(pixels / turned)
		if learned >= 80 and learned <= 700 then
			self._turnGain = learned
			self._turnLearned = true
		end
	end
	-- The only path that waited: task.wait above, to let the camera actually
	-- move before measuring how far it went.
	return false, true
end

-- Is it pointing at that, right now? Callers about to fire something wait on
-- this rather than on a fixed number of frames.
function Core:FacingWithin(position, tolerance)
	local root = self:Root()
	if not root then
		return false
	end
	local at = root.Position
	local flat = Vector3.new(position.X - at.X, 0, position.Z - at.Z)
	if flat.Magnitude < 0.05 then
		return true
	end
	local camera = Workspace.CurrentCamera
	local look = (self:MouseLocked() and camera) and camera.CFrame.LookVector or root.CFrame.LookVector
	-- Wider than the aim's own resume threshold on purpose. The aim is allowed
	-- to sit still inside a few degrees rather than chase every fraction of
	-- one, so asking it to be tighter than that just means every caller waits
	-- out its timeout and then fires anyway. Facing is cosmetic here in any
	-- case: above 8.1 studs the box is centred and symmetric.
	return math.abs(wrapAngle(flatYaw(flat) - flatYaw(look))) < (tolerance or math.rad(11))
end

-- Turn until it is pointing there or the time runs out. Kept for the odd
-- one-shot; anything that fires an animation should be using LockFacing.
function Core:FacePosition(position, seconds)
	local deadline = os.clock() + (seconds or 0.2)
	repeat
		local settled, yielded = self:FaceStep(position)
		if settled then
			return true
		end
		if not yielded then
			RunService.RenderStepped:Wait()
		end
	until os.clock() >= deadline
	return false
end

-- Hold on a target for as long as an animation runs.
--
-- This is the shape he asked for and the old one-shot turn was wrong twice
-- over: it snapped once and then let go, so a two second cast drifted off
-- whoever it was aimed at, and it ran on every punch as well, which is what he
-- felt as his view being yanked while a skill sat on a twelve second cooldown.
--
-- `where` is a function rather than a position, so the lock follows them if
-- they move. Out of shiftlock this is the character turning; in shiftlock it is
-- the mouse, because a locked camera is the only thing the root follows.
function Core:LockFacing(where, seconds)
	-- This used to refuse outright when Flags.autoFace was false, which was
	-- fine while one switch answered for the whole hub. It does not survive a
	-- game giving the aura, the farm and a named target one switch each: the
	-- aura's would have silently turned the other two off as well. Whether to
	-- turn is the game module's decision and it is made at the call site.
	self._lockWhere = where
	self._lockUntil = os.clock() + (seconds or 0.5)

	if self._lockRunning then
		return
	end
	-- A fresh lock is usually a fresh target, and the bearing to a different
	-- person has nothing to do with how fast the last one was moving.
	self._turnBearing = nil
	self._lockRunning = true

	task.spawn(function()
		-- Out of shiftlock the humanoid turns itself toward whatever direction
		-- it is walking, which fights a lock the whole time the farm is moving.
		-- Off while the lock holds, and back to whatever it was afterwards.
		local restore = nil
		if not self:MouseLocked() then
			local hum = self:Humanoid()
			if hum then
				restore = hum.AutoRotate
				hum.AutoRotate = false
				-- Also on unload. Without this, quitting the hub while a lock
				-- was holding left the character unable to turn toward where it
				-- was walking, and nothing in the game puts that back.
				self:Track(function()
					local live = self:Humanoid()
					if live then
						live.AutoRotate = true
					end
				end)
			end
		end

		while self.Alive and os.clock() < (self._lockUntil or 0) do
			local ok, at = pcall(self._lockWhere)
			if not ok or not at then
				break
			end
			-- Exactly one frame per turn of this loop, whichever way FaceStep
			-- went. It reports whether it waited; every path that did not, waits
			-- here. Anything less careful than that is a busy loop the first
			-- time an unusual state comes up, and it will be a state nobody
			-- thought to test - the one that actually happened was a camera
			-- pushed against a wall while the window was in the background.
			local _, yielded = self:FaceStep(at)
			if not yielded then
				RunService.RenderStepped:Wait()
			end
		end

		if restore ~= nil then
			local hum = self:Humanoid()
			if hum then
				hum.AutoRotate = restore
			end
		end
		self._lockRunning = false
		self._lockWhere = nil
	end)
end

function Core:ReleaseFacing()
	self._lockUntil = 0
end

-- Walk toward a position using the character's own legs. This is the only
-- approach that leaves the physics alone: writing CFrame every frame makes the
-- solver invent enormous velocities, which is felt in game as being flung on
-- every hit, and it is also what a server distance check is looking for.
-- The player's own control module calls Humanoid:Move every single frame with
-- whatever the keyboard is doing, including a zero vector when it is doing
-- nothing, and that cancels MoveTo. So a farm that only calls MoveTo twitches
-- forward and stops, over and over. The controls have to be switched off while
-- something else is steering.
function Core:SetControls(enabled)
	if self._controlsEnabled == enabled then
		return
	end
	local ok, controls = pcall(function()
		local PlayerModule = require(LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		return PlayerModule:GetControls()
	end)
	if not ok or not controls then
		return
	end
	self._controlsEnabled = enabled
	pcall(function()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

function Core:StartControlWatcher()
	self._controlsEnabled = true
	self:Track(function()
		self:SetControls(true)
	end)
	-- Hands the keyboard back on its own a moment after whatever was steering
	-- stops asking, so turning the farm off never leaves the character frozen.
	self:Loop("controls", 0.2, function()
		if self._steerUntil and os.clock() < self._steerUntil then
			return
		end
		self:SetControls(true)
	end)
end

-- Getting caught on a wall, a rock or another player is normal for anything
-- that walks in a straight line. Escalating gets out of nearly all of it: jump
-- first, then push sideways, and only lift the character as a last resort.
-- A jump does nothing against a wall you are pressed into, which is what it kept
-- doing. So this climbs instead: it keeps lifting until the character starts
-- covering ground again, which is the only thing that proves the obstacle is
-- cleared. Height is capped so it cannot ascend forever if the block is
-- something else entirely.
local CLIMB_SPEED = 34
local CLIMB_CEILING = 80

function Core:Unstick(severity)
	local root, hum = self:Root(), self:Humanoid()
	if not root or not hum or hum.Health <= 0 then
		return
	end
	self._climbing = true
	self._climbFrom = self._climbFrom or root.Position.Y
	self._climbUntil = os.clock() + 3
	if severity and severity >= 2 then
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end

function Core:Climbing()
	if not self._climbing then
		return false
	end
	local root = self:Root()
	if not root or os.clock() > (self._climbUntil or 0) then
		self._climbing, self._climbFrom = false, nil
		return false
	end
	if self._climbFrom and root.Position.Y - self._climbFrom > CLIMB_CEILING then
		self._climbing, self._climbFrom = false, nil
		return false
	end
	return true
end

-- Applied by whatever is steering, so the climb wins over the approach.
--
-- It used to climb at a flat 34 studs a second and keep only two fifths of its
-- horizontal push, whatever the approach was doing. At an Approach Speed of 120
-- that reads as the character stopping to think about the obstacle: it arrives
-- at a wall doing 120, and then crawls over it doing 34. It matches the
-- approach now, and keeps three quarters of the push, so getting unstuck is
-- part of the run rather than an interruption to it.
function Core:ClimbVelocity(velocity)
	if not self:Climbing() then
		return velocity
	end
	local rate = math.clamp(tonumber(self.ApproachSpeed) or CLIMB_SPEED, CLIMB_SPEED, 220)
	return Vector3.new(velocity.X * 0.75, rate, velocity.Z * 0.75)
end

function Core:StartUnstuck()
	local lastPosition, stuckFor = nil, 0

	self:Loop("unstuck", 0.25, function()
		local root = self:Root()
		if not root then
			return
		end

		local steering = self._steerUntil ~= nil and os.clock() < self._steerUntil
		if not steering then
			lastPosition, stuckFor = root.Position, 0
			self._climbing, self._climbFrom = false, nil
			return
		end

		local here = Vector3.new(root.Position.X, 0, root.Position.Z)
		local before = lastPosition and Vector3.new(lastPosition.X, 0, lastPosition.Z)
		local progress = before and (here - before).Magnitude or 0
		lastPosition = root.Position

		if progress < 0.6 then
			stuckFor += 0.25
		else
			-- Moving again. Whatever it was, it is behind us.
			stuckFor = 0
			self._climbing, self._climbFrom = false, nil
		end

		if stuckFor >= 0.75 and self.Flags.unstuck ~= false then
			self:Unstick(stuckFor)
		end

	end)

	-- The lift has to be written every frame, not four times a second. Gravity
	-- is 196 studs per second squared here, so a climb velocity applied on a
	-- quarter second timer is cancelled long before the next one arrives and
	-- the character sits there bobbing against whatever it is caught on. This
	-- is why walking "stayed stuck": it was jumping in place.
	self:Connect(RunService.Heartbeat, function()
		local root = self:Root()
		if not root then
			return
		end

		-- Whatever FlyToward last asked for, held until it asks for something
		-- else. Same reason as the climb: a velocity set on a timer is half
		-- eaten by gravity before the timer comes round again.
		if self._steerVelocityUntil and os.clock() < self._steerVelocityUntil then
			root.AssemblyLinearVelocity = self._steerVelocity or root.AssemblyLinearVelocity
		end

		if self:Climbing() then
			root.AssemblyLinearVelocity = self:ClimbVelocity(root.AssemblyLinearVelocity)
		end
	end)
end

-- Flying to the target instead of walking to it. Walls, ledges and the whole
-- problem of pathing across an arena stop existing, and it is physics driven
-- rather than a teleport, so the server still sees a character that travelled.
function Core:FlyToward(position, standoff, speed)
	local root, hum = self:Root(), self:Humanoid()
	if not root or not hum or hum.Health <= 0 then
		return false
	end

	self._steerUntil = os.clock() + 0.4

	local offset = position - root.Position
	local distance = offset.Magnitude
	if distance <= (standoff or 0) then
		-- Hover. Overwriting velocity every tick is what holds the character up,
		-- so zero means stay exactly here rather than fall.
		root.AssemblyLinearVelocity = Vector3.zero
		self._steerVelocity = Vector3.zero
		self._steerVelocityUntil = os.clock() + 0.25
		return true
	end

	-- Ease off near the target so it does not overshoot and orbit, but only
	-- close in. The old `distance * 3` throttled the entire approach, so a run
	-- from 60 studs was capped nowhere near the slider and the number looked
	-- like it did nothing.
	local wanted = speed or 70
	if distance < 12 then
		wanted = math.min(wanted, math.max(distance * 4, 8))
	end
	local velocity = self:ClimbVelocity(offset.Unit * wanted)
	root.AssemblyLinearVelocity = velocity

	-- And held every frame until the next call. Gravity is 196 studs per second
	-- squared here, so a velocity written twenty times a second is most of the
	-- way back to falling before it is written again, and the approach sags into
	-- an arc that reads as far slower than the slider claims.
	self._steerVelocity = velocity
	self._steerVelocityUntil = os.clock() + 0.25
	return false
end

function Core:WalkToward(position, standoff, speed)
	local root, hum = self:Root(), self:Humanoid()
	if not root or not hum then
		return false
	end
	standoff = standoff or 0
	local offset = position - root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude

	-- A humanoid does not brake, and MoveTo will not do it for you. At the 120
	-- studs a second the approach slider was asking for, it sailed straight
	-- past the standoff and the farm orbited its target instead of standing
	-- next to it: 41, 51 and 88 studs on three consecutive samples while it was
	-- supposed to be holding 11. So the speed tapers on the way in, full pace
	-- while there is room and an ordinary walk by the time it arrives.
	--
	-- This is only a request. The speed loop is what actually writes
	-- WalkSpeed, because the game overwrites it constantly.
	local top = math.max(speed or 16, 16)
	local brakeFrom = math.max(standoff * 3, 36)
	if distance >= brakeFrom then
		self.WalkWant = top
	else
		local part = math.clamp((distance - standoff) / math.max(brakeFrom - standoff, 1), 0, 1)
		self.WalkWant = 16 + (top - 16) * part
	end

	if distance <= standoff then
		self._steerUntil = nil
		self:SetControls(true)
		return true
	end

	self._steerUntil = os.clock() + 0.5
	self:SetControls(false)
	hum:MoveTo(root.Position + flat.Unit * math.min(distance - standoff, 60))
	return false
end

-- An actual teleport rather than a fast walk, and the loudest thing in the hub.
--
-- A jump of any size is instant; it is the size of one that gets noticed. So a
-- gap the game will not argue with is crossed in one go, and only a longer one
-- is walked in hops of `maxStep` until what remains is short enough to finish
-- directly. `direct` is that threshold.
function Core:BlinkTo(position, standoff, maxStep, direct)
	local root = self:Root()
	if not root then
		return false
	end
	self._steerUntil = os.clock() + 0.4

	local offset = position - root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 0.25 then
		return true
	end

	standoff = standoff or 3
	local stand = Vector3.new(position.X, position.Y, position.Z) - flat.Unit * standoff
	local togo = stand - root.Position

	-- Already standing where it wants to be. Without this it rewrote the CFrame
	-- twenty times a second for a fraction of a stud, because the target is
	-- never perfectly still, and each write interrupted the swing. Measured:
	-- Teleport held position better than Fly (61 percent of samples in range
	-- against 56) and still landed half the hits.
	if togo.Magnitude < 2 then
		return true
	end

	-- Position only, rotation untouched. Turning the character here fought the
	-- camera every frame under shiftlock and bought nothing: an extended punch
	-- box is centred and symmetric, so which way it faces does not matter.
	local function moveTo(point)
		root.CFrame = CFrame.new(point) * (root.CFrame - root.CFrame.Position)
		root.AssemblyLinearVelocity = Vector3.zero
	end

	if maxStep and togo.Magnitude > (direct or maxStep) then
		moveTo(root.Position + togo.Unit * maxStep)
		return false
	end

	moveTo(stand)
	return true
end

-- Kept for the rare case where walking cannot get there, and deliberately not
-- wired to anything by default.
function Core:StepToward(position, maxStuds, standoff)
	local root = self:Root()
	if not root then
		return false
	end
	standoff = standoff or 0
	local offset = position - root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	if distance <= standoff then
		return true
	end
	local step = math.min(distance - standoff, maxStuds)
	local direction = flat.Unit
	root.CFrame = CFrame.lookAt(root.Position + direction * step, root.Position + direction * (step + 1))
	root.AssemblyLinearVelocity = Vector3.zero
	return false
end

--------------------------------------------------------------------------------
-- ESP
--
-- Highlight plus a name tag, refreshed on a timer rather than every frame. The
-- game module says what to list and what to call each thing.
--------------------------------------------------------------------------------

local function hiddenParent()
	local ok, hidden = pcall(function()
		return gethui()
	end)
	if ok and hidden then
		return hidden
	end
	return game:GetService("CoreGui")
end

function Core:StartESP(config)
	self:StopESP()
	local parent = hiddenParent()
	local holder = Instance.new("Folder")
	holder.Name = "\0PrismESP"
	holder.Parent = parent
	self:Track(holder)
	self._espHolder = holder

	local entries = {}

	local function clear(model)
		local entry = entries[model]
		if not entry then
			return
		end
		if entry.highlight then
			entry.highlight:Destroy()
		end
		if entry.billboard then
			entry.billboard:Destroy()
		end
		entries[model] = nil
	end

	self:Loop("esp", config.interval or 0.25, function()
		if not self.Flags[config.flag] then
			for model in pairs(entries) do
				clear(model)
			end
			return
		end

		local wanted = {}
		local myRoot = self:Root()
		for _, model in ipairs(config.list()) do
			local root = rootOf(model)
			local hum = model:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				local distance = myRoot and (root.Position - myRoot.Position).Magnitude or 0
				if distance <= (config.maxDistance and config.maxDistance() or 5000) then
					wanted[model] = true
					local entry = entries[model]
					if not entry then
						entry = {}
						local highlight = Instance.new("Highlight")
						highlight.FillTransparency = 1
						highlight.OutlineTransparency = 0
						highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
						highlight.Adornee = model
						highlight.Parent = holder
						entry.highlight = highlight

						local billboard = Instance.new("BillboardGui")
						billboard.Size = UDim2.fromOffset(200, 34)
						billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
						billboard.AlwaysOnTop = true
						billboard.Adornee = root
						billboard.Parent = holder

						local label = Instance.new("TextLabel")
						label.BackgroundTransparency = 1
						label.Size = UDim2.fromScale(1, 1)
						label.Font = Enum.Font.GothamMedium
						label.TextSize = 17
						label.TextStrokeTransparency = 0.4
						label.TextColor3 = Color3.new(1, 1, 1)
						label.Parent = billboard
						entry.billboard = billboard
						entry.label = label

						entries[model] = entry
					end

					local colour = config.colour and config.colour(model) or Color3.fromRGB(255, 255, 255)
					entry.colour = colour
					entry.highlight.OutlineColor = colour
					entry.highlight.FillColor = colour
					entry.highlight.FillTransparency = config.fill and (1 - config.fill()) or 1
					entry.label.TextColor3 = colour
					entry.label.Text = config.label(model, distance)
					if config.textSize then
						local size = config.textSize()
						if entry.label.TextSize ~= size then
							entry.label.TextSize = size
							-- The billboard has to grow with the text or a long
							-- name at 28 is clipped by its own box.
							entry.billboard.Size = UDim2.fromOffset(math.max(200, size * 16), size * 2)
						end
					end
					if entry.billboard.Adornee ~= root then
						entry.billboard.Adornee = root
					end
				end
			end
		end

		for model in pairs(entries) do
			if not wanted[model] or not model.Parent then
				clear(model)
			end
		end
	end)

	-- Tracers, drawn in the world rather than on the screen.
	--
	-- These were Drawing lines running from the bottom of the viewport to each
	-- player, which is the usual thing and is not what he asked for: a 2D
	-- overlay always starts at the same place on screen no matter where you are
	-- looking. A CylinderHandleAdornment is actual geometry, it runs root to
	-- root, it turns with the world, and AlwaysOnTop still draws it through
	-- walls. Its height runs along local Z, so it is aimed with lookAt and then
	-- pushed half its own length forward to sit between the two points.
	local beams = {}

	self:Track(function()
		for _, beam in pairs(beams) do
			pcall(function()
				beam:Destroy()
			end)
		end
	end)

	self:Connect(RunService.Heartbeat, function()
		local myRoot = self:Root()
		local on = self.Flags[config.flag] and self.Flags.espTracers and myRoot ~= nil

		for model, entry in pairs(entries) do
			local root = on and model:FindFirstChild("HumanoidRootPart") or nil
			local beam = beams[model]

			if root then
				if not beam then
					beam = Instance.new("CylinderHandleAdornment")
					beam.Radius = 0.06
					beam.AlwaysOnTop = true
					beam.ZIndex = 0
					beam.Transparency = 0.35
					beam.Parent = holder
					beams[model] = beam
				end
				beam.Adornee = myRoot
				local rel = myRoot.CFrame:PointToObjectSpace(root.Position)
				local length = rel.Magnitude
				if length > 0.5 then
					beam.Height = length
					beam.CFrame = CFrame.lookAt(Vector3.zero, rel) * CFrame.new(0, 0, -length / 2)
					beam.Color3 = entry.colour or Color3.fromRGB(255, 255, 255)
					beam.Visible = true
				else
					beam.Visible = false
				end
			elseif beam then
				beam.Visible = false
			end
		end

		for model, beam in pairs(beams) do
			if not entries[model] then
				pcall(function()
					beam:Destroy()
				end)
				beams[model] = nil
			end
		end
	end)
end

function Core:StopESP()
	self:StopLoop("esp")
	if self._espHolder then
		pcall(function()
			self._espHolder:Destroy()
		end)
		self._espHolder = nil
	end
end

--------------------------------------------------------------------------------
-- movement helpers shared by every game
--------------------------------------------------------------------------------

function Core:StartInfiniteJump()
	self:Connect(UserInputService.JumpRequest, function()
		if not self.Flags.infJump then
			return
		end
		local hum = self:Humanoid()
		if hum and hum.Health > 0 then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)
end

-- Writing Humanoid.WalkSpeed does not work in a game that recomputes it every
-- frame, which is most of them and Ability Arena in particular: it puts the
-- value back inside half a second. Setting the source it computes from does
-- work, and it keeps the game's own sprint and status effect multipliers
-- instead of fighting them.
function Core:StartSpeed(getSpeed)
	local StarterPlayer = game:GetService("StarterPlayer")
	local base = StarterPlayer.CharacterWalkSpeed
	self.DefaultWalkSpeed = base

	self:Track(function()
		StarterPlayer.CharacterWalkSpeed = base
	end)

	-- Two layers, because one is not enough here. Ability Arena reads
	-- StarterPlayer.CharacterWalkSpeed for the lobby, but once deployed it
	-- writes the humanoid from constants it captured when the module first
	-- loaded, so changing StarterPlayer alone works in the lobby and does
	-- nothing in the arena. Watching the property and putting the value back
	-- the instant anything changes it covers both, and costs nothing when the
	-- feature is off.
	local writing = false

	local function wantedSpeed()
		local wanted = getSpeed()
		if not wanted or wanted <= base + 0.05 then
			return nil
		end
		return wanted
	end

	local function apply(hum)
		if writing or not hum or hum.Health <= 0 then
			return
		end
		local wanted = wantedSpeed()
		if not wanted then
			return
		end
		if math.abs(hum.WalkSpeed - wanted) > 0.05 then
			writing = true
			hum.WalkSpeed = wanted
			writing = false
		end
	end

	local function watch(character)
		local hum = character:FindFirstChildOfClass("Humanoid")
		if not hum then
			hum = character:WaitForChild("Humanoid", 10)
		end
		if not hum then
			return
		end
		self:Connect(hum:GetPropertyChangedSignal("WalkSpeed"), function()
			apply(hum)
		end)
		apply(hum)
	end

	if LocalPlayer.Character then
		task.spawn(watch, LocalPlayer.Character)
	end
	self:Connect(LocalPlayer.CharacterAdded, function(character)
		task.spawn(watch, character)
	end)

	self:Loop("speed", 0.25, function()
		local wanted = wantedSpeed()
		local target = wanted or base
		if math.abs(StarterPlayer.CharacterWalkSpeed - target) > 0.01 then
			StarterPlayer.CharacterWalkSpeed = target
		end
		apply(self:Humanoid())
	end)

	-- The vrrr.
	--
	-- Writing WalkSpeed every frame while the game writes it back every frame is
	-- two owners fighting over one number, and the character buzzes. Raising
	-- WalkSpeed at all only asks the humanoid to accelerate harder; it still has
	-- to fight contact with the ground, which is the drag.
	--
	-- So the speed is driven directly instead. Once a frame the horizontal
	-- velocity is set to exactly where the character is being asked to go, times
	-- the number on the slider. Vertical is left alone, so gravity, jumps and
	-- falling all still work. It is smooth because velocity is continuous, it is
	-- exact because nothing else touches it, and the game can rewrite WalkSpeed
	-- as often as it likes without any of it mattering.
	--
	-- The slope limit still goes up: at speed a humanoid catches on kerbs it
	-- would stroll over, and being stopped dead by a two stud lip was the other
	-- half of what felt like friction.
	local slopeBase = nil

	self:Connect(RunService.Heartbeat, function()
		local hum, root = self:Humanoid(), self:Root()
		if not hum or not root or hum.Health <= 0 then
			return
		end

		local wanted = wantedSpeed()
		if not wanted then
			if slopeBase ~= nil and hum.MaxSlopeAngle > slopeBase then
				hum.MaxSlopeAngle = slopeBase
			end
			return
		end

		if slopeBase == nil then
			slopeBase = hum.MaxSlopeAngle
		end
		if hum.MaxSlopeAngle < 88 then
			hum.MaxSlopeAngle = 89
		end

		-- Flying and the farm each own the whole velocity while they run.
		if self.Flags.fly then
			return
		end
		if self._steerUntil and os.clock() < self._steerUntil then
			return
		end

		local move = hum.MoveDirection
		if move.Magnitude < 0.05 then
			return
		end

		-- A floor, never a cap. The humanoid is still doing the walking and
		-- StarterPlayer is still carrying the speed; this only tops the
		-- horizontal velocity back up to what was asked for whenever contact
		-- with the ground, a kerb or another player has dragged it under.
		-- Writing it outright would mean two owners of one number and a
		-- character that buzzes, which is the thing being fixed.
		local velocity = root.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		if flat.Magnitude >= wanted - 0.5 then
			return
		end
		local push = move.Unit * wanted
		root.AssemblyLinearVelocity = Vector3.new(push.X, velocity.Y, push.Z)
	end)
end

-- Anti void, and the two before it were both wrong because they asked the wrong
-- question.
--
-- A fixed floor height fired long after the kill bricks had already got him.
-- Measuring the drop from the ground he left treated every deliberate descent
-- as a fall, so it yanked him back mid farm. Asking "is there anything under
-- me" was worse in both directions at once: over a gap he was going to clear it
-- said no ground and grabbed him mid jump, and over the actual void it hit the
-- kill floor 70 studs down, called that ground, and let him die on it.
--
-- The honest question is not whether something is under him. It is whether the
-- first thing he will meet is the thing that kills him. So the ray includes the
-- kill bricks and looks at what it hits:
--
--   normal geometry  -> he lands on it, nothing to do
--   a kill brick     -> he is going to die on it
--   nothing at all   -> open void
--
-- And it acts late on purpose. Catching the moment the ray sees a kill brick
-- would still grab him at the top of a jump across a gap, because at the top of
-- that arc there genuinely is a kill floor below him. Waiting until he is close
-- to it means any jump he was going to make has already landed, and the only
-- ones left are the ones that were going to kill him.
function Core:StartAntiVoid(config)
	config = config or {}
	local deadly = config.deadly
	local probe = config.probe or 800
	local margin = config.margin or 25

	local lastSafe, lastSave, caughtAt = nil, 0, 0

	local GROUNDED = {
		[Enum.HumanoidStateType.Running] = true,
		[Enum.HumanoidStateType.RunningNoPhysics] = true,
		[Enum.HumanoidStateType.Landed] = true,
		[Enum.HumanoidStateType.Climbing] = true,
	}

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	self:Loop("antivoid", 0.08, function()
		local root, hum, char = self:Root(), self:Humanoid(), self:Character()
		if not root or not hum or not char or hum.Health <= 0 then
			return
		end

		if GROUNDED[hum:GetState()] then
			-- Only every so often, so a save is never taken during the stumble
			-- off a ledge and then used as the place to put him back.
			if os.clock() - lastSave > 0.4 then
				lastSafe, lastSave = root.CFrame, os.clock()
			end
			return
		end

		if not self.Flags.antiVoid or not lastSafe then
			return
		end

		-- Flying is his own descent and he can fly back out of it.
		if self.Flags.fly then
			return
		end

		-- Rising, hovering or being carried is not falling.
		if root.AssemblyLinearVelocity.Y > -10 then
			return
		end

		-- And still above where he took off is not falling either. This is what
		-- keeps an ordinary jump untouched even when the gap he is clearing has
		-- something fatal at the bottom of it: at the top of that arc he is
		-- above the ledge he left, so there is nothing to save him from yet.
		if root.Position.Y > lastSafe.Position.Y - 5 then
			return
		end

		local effects = Workspace:FindFirstChild("Effects")
		params.FilterDescendantsInstances = effects and { char, effects } or { char }

		local hit = Workspace:Raycast(root.Position, Vector3.new(0, -probe, 0), params)

		if hit then
			-- Something to land on, and it is survivable. Nothing to do.
			if not deadly or not deadly(hit.Instance) then
				return
			end
			-- It is not survivable, but let the fall play out until he is
			-- close enough that no jump could have saved him.
			if root.Position.Y - hit.Position.Y > margin then
				return
			end
		end

		if os.clock() - caughtAt < 1.5 then
			return
		end
		caughtAt = os.clock()

		root.CFrame = lastSafe + Vector3.new(0, 5, 0)
		root.AssemblyLinearVelocity = Vector3.zero
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		self:Notify("Anti void", "Caught you on the way down", 2)
	end)
end

-- Jump, and the same lesson walk speed taught.
--
-- Writing Humanoid.JumpHeight does nothing here: the value reads back
-- unchanged within a frame, because the game holds it. Writing the property it
-- is computed from, StarterPlayer.CharacterJumpHeight, does work and it sticks
-- without anything having to hold it there. Measured both ways before writing
-- this: a direct humanoid write of 40 read back as 7.2, the StarterPlayer write
-- of 30 reached the humanoid and survived the connection being dropped.
--
-- Which of the two properties is live depends on UseJumpPower, so both are
-- handled rather than one being assumed.
function Core:StartJump(getPower)
	local StarterPlayer = game:GetService("StarterPlayer")
	local usePower = StarterPlayer.CharacterUseJumpPower
	local base = usePower and StarterPlayer.CharacterJumpPower or StarterPlayer.CharacterJumpHeight
	self.DefaultJump = base

	self:Track(function()
		pcall(function()
			if usePower then
				StarterPlayer.CharacterJumpPower = base
			else
				StarterPlayer.CharacterJumpHeight = base
			end
		end)
	end)

	local function wanted()
		local power = getPower()
		if not power or power <= base + 0.05 then
			return nil
		end
		return power
	end

	self:Loop("jump", 0.25, function()
		local target = wanted() or base
		pcall(function()
			if usePower then
				if math.abs(StarterPlayer.CharacterJumpPower - target) > 0.05 then
					StarterPlayer.CharacterJumpPower = target
				end
			elseif math.abs(StarterPlayer.CharacterJumpHeight - target) > 0.05 then
				StarterPlayer.CharacterJumpHeight = target
			end
		end)

		-- The source covers a fresh character; this covers one that was already
		-- standing there when the toggle went on.
		local hum = self:Humanoid()
		if not hum or hum.Health <= 0 then
			return
		end
		pcall(function()
			if hum.UseJumpPower then
				if math.abs(hum.JumpPower - target) > 0.05 then
					hum.JumpPower = target
				end
			elseif math.abs(hum.JumpHeight - target) > 0.05 then
				hum.JumpHeight = target
			end
		end)
	end)
end

-- Flying through another player at speed is what was throwing him into a
-- ragdoll: the humanoid collides, the solver tips it over, and the game's own
-- ragdoll takes the character from there. So collisions come off for as long as
-- fly is on, and the root is held upright every frame. Both are undone the
-- moment it goes off, and the original CanCollide of each part is remembered
-- rather than assumed, because a character has parts that were never solid.
function Core:SetCharacterCollision(on)
	local char = self:Character()
	if not char then
		return
	end
	self._solid = self._solid or {}

	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			if on then
				local was = self._solid[part]
				if was ~= nil then
					part.CanCollide = was
				end
			else
				if self._solid[part] == nil then
					self._solid[part] = part.CanCollide
				end
				part.CanCollide = false
			end
		end
	end

	if on then
		self._solid = {}
	end
end

function Core:StartFly(getSpeed)
	local camera = Workspace.CurrentCamera
	local flying = false

	self:Track(function()
		if flying then
			self:SetCharacterCollision(true)
		end
	end)

	self:Connect(RunService.RenderStepped, function()
		if not self.Flags.fly then
			return
		end
		local root, hum = self:Root(), self:Humanoid()
		if not root or not hum or hum.Health <= 0 or not camera then
			return
		end

		if not flying then
			flying = true
			self:SetCharacterCollision(false)
		end

		-- Setting it once is not enough. The game puts the Torso back solid on
		-- its own - measured: every other part stays off, the Torso alone comes
		-- back - and the Torso is the part that actually collides with another
		-- player. So it is reasserted a few times a second for as long as fly
		-- is on. Rechecking a handful of parts is cheaper than the ragdoll.
		if os.clock() - (self._collisionAt or 0) > 0.3 then
			self._collisionAt = os.clock()
			self:SetCharacterCollision(false)
		end

		-- Holding the root upright and still is what actually stops the flop.
		-- Yaw is kept so the character still faces where it is going.
		root.AssemblyAngularVelocity = Vector3.zero
		local _, yaw = root.CFrame:ToEulerAnglesYXZ()
		root.CFrame = CFrame.new(root.Position) * CFrame.fromEulerAnglesYXZ(0, yaw, 0)

		local direction = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			direction += camera.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			direction -= camera.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			direction -= camera.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			direction += camera.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			direction += Vector3.yAxis
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			direction -= Vector3.yAxis
		end

		hum.PlatformStand = true
		if direction.Magnitude > 0 then
			root.AssemblyLinearVelocity = direction.Unit * getSpeed()
		else
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)

	-- Give the character back when the toggle goes off.
	self:Loop("flyoff", 0.2, function()
		if self.Flags.fly then
			return
		end
		if flying then
			flying = false
			self:SetCharacterCollision(true)
		end
		local hum = self:Humanoid()
		if hum and hum.PlatformStand then
			hum.PlatformStand = false
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)

	-- A fresh character has fresh parts, so the remembered CanCollide values
	-- belong to a body that no longer exists.
	self:Connect(LocalPlayer.CharacterAdded, function()
		self._solid = {}
		if flying then
			task.delay(0.5, function()
				if self.Flags.fly then
					self:SetCharacterCollision(false)
				end
			end)
		end
	end)
end

--------------------------------------------------------------------------------
-- box view
--
-- Draws a box in the world with a wire edge. This exists so a reach number can
-- be checked against what it actually covers rather than believed, which is the
-- only way to tell a slider that means studs from one that does not.
--
-- It lives in workspace.Effects when the game has one, because a game that
-- keeps an Effects folder already excludes it from its own hit queries.
--------------------------------------------------------------------------------

function Core:BoxView(name)
	local home = Workspace:FindFirstChild("Effects") or Workspace

	local box = Instance.new("Part")
	box.Name = name or "MeridianBox"
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	box.Material = Enum.Material.SmoothPlastic
	box.Size = Vector3.one
	box.Transparency = 1

	self:Track(box)

	local view = { Part = box }
	local shown = false

	function view:Show(cframe, size, colour, transparency)
		box.CFrame = cframe
		box.Size = size
		box.Color = colour
		box.Transparency = transparency
		if not shown then
			shown = true
			box.Parent = home
		end
	end

	function view:Hide()
		if shown then
			shown = false
			box.Parent = nil
		end
	end

	return view
end

return Core
