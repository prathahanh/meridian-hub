--// Meridian · Illegal Soccer
--// universe 10155360168
--//
--// Eight-a-side football with guns, jetpacks, grapples, oil and no referee.
--// The hub is here to make somebody win it, not to farm it.
--//
--// The thing that decides what this file can do: the game simulates the ball
--// in Luau rather than leaving it to Roblox physics, and it ships the whole
--// simulator to the client. Ball.Physics can be called. GoalkeeperPrediction
--// can be called. So "where is this shot going, and when does it get there"
--// is not something to approximate with a parabola - it is one call against
--// the game's own maths, including spin, damping, bounce retention and the
--// real collision geometry.
--//
--// This first pass draws what it knows and touches nothing. Every control in
--// here is read-only on purpose: acting on the prediction - diving, placing a
--// shot, aiming a gun - moves the character, and moving the character while
--// somebody is playing is the one thing that makes a hub unusable. Those come
--// next, switchable and off by default.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Module = {
	GameId = 10155360168,
	Name = "Illegal Soccer",
}

-- Hover text. One line each, for somebody who has never seen the code. No
-- mechanisms, and no number that is not one you would actually set.
Module.Tips = {
	["Silent Aim"] = "Guns hit who you pick, not where you point.",
	["Aim At"] = "Who to pick: the one nearest your crosshair, or the one nearest you.",
	["Only The Other Team"] = "Never picks a team mate.",
	["Aim Range"] = "How far away they can be.",
	["Aim For The Corner"] = "Shots go to the corner their keeper is furthest from.",
	["Longer Reach"] = "Take, kick and tackle the ball from further away.",
	["How Much Further"] = "Two is plenty. Higher and the ball looks magnetic.",
	["Take Their Shots"] = "Their shots stick to you too, not just your team's passes.",
	["Never Run Out"] = "Stamina stops dropping.",
	["Always Sprint"] = "Run at sprint speed without holding the key.",
	["Free Mouse"] = "Unlocks the cursor so you can click the menu.",
	["Shot Preview"] = "Marks the spot on the goal a shot is going to cross.",
	["Draw The Flight"] = "Draws the ball's path to that spot.",
	["Both Goals"] = "Marks shots at their goal as well as yours.",
	["Path Detail"] = "How finely the path is drawn. Lower is lighter.",
	["Warn On Target"] = "Tells you when a shot is heading at your goal.",
	["Player ESP"] = "Draws everybody through walls.",
	["Team Colours"] = "Your team one colour, theirs another.",
	["Show Distance"] = "Adds how far away they are.",
	["Show Their Gadget"] = "Adds what they are carrying.",
	["Mark The Keeper"] = "Picks out whoever is in goal.",
	["Max Distance"] = "Stops drawing players past this.",
	["Text Size"] = "How big the names are.",
	["Item Box ESP"] = "Draws the crates.",
	["Anti AFK"] = "Stops Roblox idling you out.",
}

--------------------------------------------------------------------------------
-- file scope
--------------------------------------------------------------------------------
--
-- Build is ONE function against Luau's ceiling of 200 local registers. Features
-- live out here on tables and are handed what they need once, through a wire.
-- ./check.sh catches the ceiling; luau-analyze does not.

local journal = { keep = 50, entries = {} }

function journal.note(what)
	local list = journal.entries
	list[#list + 1] = { at = os.clock(), what = what }
	if #list > journal.keep then
		table.remove(list, 1)
	end
end

function journal.text()
	local out = {}
	local now = os.clock()
	for _, entry in ipairs(journal.entries) do
		out[#out + 1] = ("%5.1fs ago  %s"):format(now - entry.at, entry.what)
	end
	return table.concat(out, "\n")
end

--------------------------------------------------------------------------------

-- A control's declared default has to reach the flag it writes, and Maclib
-- cannot be relied on to carry it there. Sliders and Dropdowns definitely do not
-- fire their own callback at build time, and whether a Toggle does has been
-- recorded both ways in this codebase - which is reason enough not to bet a
-- switch on it. So every kind is seeded here, and separately every read of a
-- flag in this file is written to agree with the default its control shows.
local seeded = {}

function seeded.apply(core)
	local flags = core.Flags
	for _, entry in ipairs(core.Controls or {}) do
		local flag = entry.flag or entry.Flag
		local kind = entry.kind or entry.Kind
		if flag and flags[flag] == nil and (kind == "Slider" or kind == "Dropdown" or kind == "Toggle") then
			local settings = entry.control and entry.control.Settings
			local default = type(settings) == "table" and settings.Default or nil
			local value = nil
			if kind == "Slider" then
				value = tonumber(default)
			elseif kind == "Toggle" then
				-- Written out rather than as an and/or, because `x and default or
				-- nil` silently yields nil for every toggle whose default is
				-- false. That is most of them, and it is the difference between
				-- a switch that is off and a switch that is merely unset.
				if type(default) == "boolean" then
					value = default
				end
			elseif type(settings) == "table" then
				local options = settings.Options
				local index = tonumber(default)
				if type(options) == "table" and index then
					value = options[index]
				end
			end
			if value ~= nil then
				flags[flag] = value
				if type(settings.Callback) == "function" then
					pcall(settings.Callback, value)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- the ball, and where it is going
--------------------------------------------------------------------------------
--
-- Everything visual in this file comes from three calls the game makes itself.
--
-- The ball is not a part you can find in the workspace. Every character carries
-- a small transparent Part called "Ball" which is a hitbox and a red herring;
-- the match ball exists only through its renderer. GetOrCreateRenderer gives it
-- up, and its GetMovementState is the same table the game's own goalkeeper
-- prediction takes: Position, Velocity, Spin, Mode, and the timestamps.
--
-- The module-level GetMovementStateById and GetTargetVelocity helpers return
-- nil. Go through the renderer object.

local predict = { bits = nil, renderer = nil, world = nil, worldAt = 0 }

function predict.wire(bits)
	predict.bits = bits
end

function predict.ball()
	local bits = predict.bits
	if not bits then
		return nil
	end
	local renderer = predict.renderer
	if not renderer then
		local ok, made = pcall(bits.Renderer.GetOrCreateRenderer, bits.BallIds.MainMatch)
		if not ok or type(made) ~= "table" then
			return nil
		end
		renderer = made
		predict.renderer = renderer
	end
	local ok, state = pcall(renderer.GetMovementState)
	if not ok or type(state) ~= "table" or not state.Position then
		return nil
	end
	return state, renderer
end

-- The collision world the simulator bounces against. Rebuilt rarely: it is a
-- walk of the map's geometry and the map does not change mid-match.
function predict.boundary()
	local bits = predict.bits
	local now = os.clock()
	if predict.world and now - predict.worldAt < 10 then
		return predict.world
	end
	local ok, world = pcall(bits.Renderer.GetMatchBoundaryWorld, bits.BallIds.MainMatch)
	if ok and world then
		predict.world, predict.worldAt = world, now
	end
	return predict.world
end

function predict.goal(team)
	local data = Workspace:FindFirstChild("Map")
	data = data and data:FindFirstChild("Data")
	local model = data and data:FindFirstChild(team)
	local goal = model and model:FindFirstChild("Goal")
	return goal and goal:IsA("BasePart") and goal or nil
end

function predict.myTeam()
	local bits = predict.bits
	if not bits then
		return nil
	end
	local ok, name = pcall(bits.ActorTeams.GetActorTeamName, bits.player)
	return ok and name or nil
end

-- Where and when the ball crosses a goal, straight from the game's own solver.
-- Returns nil when it is not going in, which is most of the time.
function predict.crossing(state, team)
	local bits = predict.bits
	local goal = predict.goal(team)
	local world = predict.boundary()
	if not goal or not world or not state then
		return nil
	end
	local ok, position, at = pcall(
		bits.GKP.GetGoalCrossing,
		state,
		world,
		goal,
		Workspace:GetServerTimeNow(),
		5
	)
	if not ok or position == nil then
		return nil
	end
	return position, at
end

function predict.at(state, seconds)
	local bits = predict.bits
	local ok, position = pcall(bits.GKP.GetBallPositionAtTime, state, seconds)
	return ok and position or nil
end

function predict.moving(state)
	if not state then
		return false
	end
	local velocity = state.Velocity
	return velocity ~= nil and velocity.Magnitude > 4
end

--------------------------------------------------------------------------------
-- the gun, and the one thing this game trusts the client about
--------------------------------------------------------------------------------
--
-- Every gadget that shoots sends the server an AimRay:
--
--     {Origin, Direction, CameraCFrame, TargetPosition,
--      ClientHit = {Kind = "Character", UserId, Position, RootLocalPosition}}
--
-- HitScan.CleanClientHit is the only thing standing between that and the
-- server's damage, and all it checks is the SHAPE - that UserId is an integer
-- and the two positions are finite Vector3s. It never asks whether the ray
-- actually reaches that player, whether they are in front of you, or how far
-- away they are. The single geometric rule in the whole path is that your ray
-- Origin must be within 12 studs of your own character, and if it is not the
-- server just snaps the origin back to you and carries on.
--
-- So the client names who it hit and the server believes it.
--
-- This does NOT forge a packet. ItemCommands.FireEquipped is a plain function
-- on a shared module table, called with the ray one line before FireServer, so
-- the aim is rewritten on the way past and the game still builds the ActionId,
-- the ShotTime, the equip id and the sequencing itself. Nothing here has to
-- know how any of that works, which is why it keeps working when the game
-- changes. Core:Override puts the original function back when the hub unloads.

local aim = { bits = nil, last = nil, firedAt = 0, shots = 0 }

function aim.wire(bits)
	aim.bits = bits
end

-- Whoever the shot should really go to. Scored by angle from where the camera
-- is already pointing, so it takes the person you were roughly looking at
-- rather than snapping across the pitch at somebody behind you.
function aim.pick()
	local bits = aim.bits
	local F = bits.F
	local camera = Workspace.CurrentCamera
	local root = bits.core:Root()
	if not camera or not root then
		return nil
	end

	local mine = predict.myTeam()
	local reach = tonumber(F.aimRange) or 400
	local nearestToMe = F.aimTarget == "Nearest To You"
	local best, bestScore = nil, nil

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= bits.player then
			local character = player.Character
			local part = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if part and humanoid and humanoid.Health > 0 then
				local ok, team = pcall(bits.ActorTeams.GetActorTeamName, player)
				team = ok and team or nil
				-- Unknown team counts as fair game only when we do not know our
				-- own either; shooting a team mate is worse than not shooting.
				local enemy = F.aimEnemiesOnly == false or mine == nil or team ~= mine
				local distance = (part.Position - root.Position).Magnitude
				if enemy and distance <= reach then
					local score = distance
					if not nearestToMe then
						local toward = part.Position - camera.CFrame.Position
						score = toward.Magnitude > 0.01
								and (1 - camera.CFrame.LookVector:Dot(toward.Unit))
							or 0
					end
					if not bestScore or score < bestScore then
						best, bestScore = player, score
					end
				end
			end
		end
	end
	return best
end

function aim.rewrite(ray)
	local bits = aim.bits
	if not bits or bits.F.silentAim ~= true or type(ray) ~= "table" then
		return ray
	end
	local player = aim.pick()
	local character = player and player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	if not part then
		return ray
	end

	-- Copied rather than edited. The caller keeps a reference to the ray it
	-- built and uses it again for its own visuals; writing through it would
	-- make the muzzle flash point somewhere the player never aimed, which is
	-- the difference between a shot that lands and a shot that is obvious.
	local out = table.clone(ray)
	local hit = part.Position
	out.ClientHit = {
		Kind = "Character",
		UserId = player.UserId,
		Position = hit,
		RootLocalPosition = Vector3.zero,
	}
	out.TargetPosition = hit
	local origin = out.Origin
	if origin ~= nil then
		local offset = hit - origin
		if offset.Magnitude > 0.01 then
			out.Direction = offset.Unit
		end
	end

	aim.last, aim.firedAt = player.DisplayName, os.clock()
	aim.shots = aim.shots + 1
	journal.note("gun aimed at " .. player.Name)
	return out
end

--------------------------------------------------------------------------------
-- reach, and it is the one this game is built to give away
--------------------------------------------------------------------------------
--
-- Gameplay.HitboxSettings is a plain table of sizes on a shared module, and the
-- game measures every touch against it with its own Luau maths rather than with
-- Roblox's Touched. That matters, because the usual trap with a grown hitbox is
-- that BasePart:GetTouchingParts reports nothing without a TouchTransmitter, so
-- a bigger box detects less than a small one. None of that applies here:
-- nothing is touching anything, it is ContainsPoint against a Size.
--
--     Receive          5.5 x 5.25 x 5.5    taking the ball at your feet
--     AirReceive       5   x 9    x 5      taking it out of the air
--     AssistedReceive  8   x 9    x 8      the game's own generous one
--     Kick             6   x 7    x 7      how near the ball must be to strike
--     SlideTackle      5   x 5    x 5      the sliding challenge
--
-- The sizes are scaled in place and put back on unload. FrontAssist is a
-- separate thing worth having: it ships as IncludesShots = false with TeamMode
-- "Allies", so the assist only ever helps you receive a team mate's pass.
-- Turning both around is what makes it an interception.

local reach = { bits = nil, base = {}, front = nil }

reach.keys = { "Receive", "AirReceive", "AssistedReceive", "Kick", "SlideTackle" }

function reach.wire(bits)
	reach.bits = bits
	local settings = bits.HitboxSettings
	for _, key in ipairs(reach.keys) do
		local box = settings[key]
		if box and box.Size then
			reach.base[key] = box.Size
		end
	end
	local front = settings.FrontAssist
	if front then
		reach.front = { IncludesShots = front.IncludesShots, TeamMode = front.TeamMode }
	end
end

function reach.apply()
	local bits = reach.bits
	if not bits then
		return
	end
	local settings = bits.HitboxSettings
	local multiplier = 1
	if bits.F.reachOn == true then
		multiplier = math.clamp(tonumber(bits.F.reachAmount) or 1, 1, 6)
	end
	for _, key in ipairs(reach.keys) do
		local box, base = settings[key], reach.base[key]
		if box and base then
			box.Size = base * multiplier
		end
	end

	local front = settings.FrontAssist
	if front and reach.front then
		if bits.F.interceptShots == true then
			front.IncludesShots = true
			front.TeamMode = "Everyone"
		else
			front.IncludesShots = reach.front.IncludesShots
			front.TeamMode = reach.front.TeamMode
		end
	end
end

function reach.restore()
	local bits = reach.bits
	if not bits then
		return
	end
	local settings = bits.HitboxSettings
	for _, key in ipairs(reach.keys) do
		local box, base = settings[key], reach.base[key]
		if box and base then
			box.Size = base
		end
	end
	local front = settings.FrontAssist
	if front and reach.front then
		front.IncludesShots = reach.front.IncludesShots
		front.TeamMode = reach.front.TeamMode
	end
end

--------------------------------------------------------------------------------
-- legs
--------------------------------------------------------------------------------
--
-- Sprint keeps a boost overlay per actor - EndsAt, ForceSprint,
-- NoStaminaConsumption, SpeedMultiplier - and a stamina multiplier that scales
-- every drain in the game. Both are the game's own controls, reapplied on a
-- timer because a boost carries an expiry and the server hands out its own.
--
-- Expect the server to argue about the speed half. Characters carries
-- MovementSnapshot, MovementCorrection and MovementRehandshake remotes, which is
-- a movement anti-cheat with a correction channel, and a client that simply
-- decides it is faster is what that exists to pull back. The stamina half has
-- nothing of the kind pointed at it.

local boost = { bits = nil, on = false, unlocked = false }

function boost.wire(bits)
	boost.bits = bits
end

-- The actor is the PLAYER, not the character. Actors.GetFromCharacter returns
-- the Player object, and passing the character instead is why unlimited stamina
-- silently did nothing: HasUnlimitedStamina(character) is false while
-- HasUnlimitedStamina(player) is true, and neither errors.
function boost.actor()
	local bits = boost.bits
	local character = bits.core:Character()
	if not character then
		return nil, nil
	end
	local ok, actor = pcall(bits.Actors.GetFromCharacter, character)
	return ok and actor or nil, character
end

function boost.tick()
	local bits = boost.bits
	if not bits then
		return
	end
	local F, Sprint = bits.F, bits.Sprint
	local actor, character = boost.actor()
	if not actor then
		return
	end

	if F.foreverStamina == true then
		pcall(Sprint.SetStaminaMultiplier, 0)
		pcall(Sprint.SetUnlimitedStamina, actor, "Meridian", true)
		boost.on = true
	elseif boost.on then
		pcall(Sprint.SetStaminaMultiplier, 1)
		pcall(Sprint.ClearUnlimitedStaminaSource, "Meridian")
		boost.on = false
	end

	-- ForceSprint, and no SpeedMultiplier, because the multiplier is not ours to
	-- set. Measured: ApplyBoost with SpeedMultiplier 2 leaves WalkSpeed at 25.6,
	-- which is just what sprinting is worth, and writing Humanoid.WalkSpeed = 40
	-- by hand decays 40 -> 20.5 -> 16 over three seconds. The server owns the
	-- number. What it does not own is whether you are sprinting, so this holds
	-- you at a sprint permanently instead, which is 25.6 against a walk of 16.
	--
	-- DurationSeconds, not EndsAt. ApplyBoost hands it to BoostStacks.Add as the
	-- duration and the wrong key throws inside the game rather than in here.
	-- ApplyBoost keys by CHARACTER and SetUnlimitedStamina keys by PLAYER, in
	-- the same module. Passing one where the other belongs fails silently in
	-- both directions: the boost lands under a key nothing reads, and the
	-- stamina source is set for somebody who does not exist.
	if F.alwaysSprint == true and character then
		pcall(Sprint.ApplyBoost, character, {
			ForceSprint = true,
			NoStaminaConsumption = true,
			SpeedMultiplier = 1,
			DurationSeconds = 2,
		})
	end

	-- The game pins the cursor to the centre of the screen, which is what makes
	-- the hub window unclickable until this is on.
	local wantFree = F.freeMouse ~= false
	if wantFree ~= boost.unlocked then
		boost.unlocked = wantFree
		pcall(bits.MouseController.SetUnlocked, "Meridian", wantFree)
	end
end

function boost.restore()
	local bits = boost.bits
	if not bits then
		return
	end
	pcall(bits.Sprint.SetStaminaMultiplier, 1)
	pcall(bits.Sprint.ClearUnlimitedStaminaSource, "Meridian")
	pcall(bits.MouseController.SetUnlocked, "Meridian", false)
	local _, character = boost.actor()
	if character then
		pcall(bits.Sprint.ClearBoost, character)
	end
end

--------------------------------------------------------------------------------
-- putting it in the corner
--------------------------------------------------------------------------------
--
-- A shot is Kind "Kick" with PassType "Shot", and what reaches the server for a
-- kick is only Origin, Direction, CameraCFrame and IsAirborne. The ClientHit
-- and TargetPosition the guns lean on are stripped by GetLaunchAim before it
-- goes, so a kick is steered by Direction and nothing else. That is the whole
-- feature: point it at a corner instead of at whatever the camera was on.
--
-- Which corner is not a preset. Every other script for this game offers "top
-- left" and "bottom right" as fixed choices; this reads where their keeper
-- actually is and takes the far post.

local strike = { bits = nil, last = nil }

function strike.wire(bits)
	strike.bits = bits
end

-- The four corners of the mouth, inset so a shot is not scraping the frame.
function strike.corners(goal)
	local half = goal.Size * 0.5
	local inset = 3
	local out = {}
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			out[#out + 1] = goal.Position
				+ Vector3.new((half.X - inset) * sx, (half.Y - inset) * sy, 0)
		end
	end
	return out
end

function strike.keeperAt(team)
	local bits = strike.bits
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character:GetAttribute("ActiveGoalkeeper") == true then
			local ok, name = pcall(bits.ActorTeams.GetActorTeamName, player)
			if ok and name == team then
				local part = character:FindFirstChild("HumanoidRootPart")
				return part and part.Position or nil
			end
		end
	end
	return nil
end

-- The corner their keeper is furthest from.
function strike.target()
	local mine = predict.myTeam()
	if not mine then
		return nil
	end
	local theirs = mine == "Team1" and "Team2" or "Team1"
	local goal = predict.goal(theirs)
	if not goal then
		return nil
	end
	local keeper = strike.keeperAt(theirs)
	local best, bestScore = nil, nil
	for _, corner in ipairs(strike.corners(goal)) do
		local score = keeper and (corner - keeper).Magnitude or corner.Y
		if not bestScore or score > bestScore then
			best, bestScore = corner, score
		end
	end
	return best
end

function strike.rewrite(command)
	local bits = strike.bits
	if not bits or bits.F.cornerAim ~= true or type(command) ~= "table" then
		return command
	end
	if command.Kind ~= "Kick" or command.PassType ~= "Shot" then
		return command
	end
	local aimDirection = command.AimDirection
	if type(aimDirection) ~= "table" or aimDirection.Origin == nil then
		return command
	end
	local corner = strike.target()
	if not corner then
		return command
	end

	local offset = corner - aimDirection.Origin
	if offset.Magnitude < 1 then
		return command
	end

	local out = table.clone(command)
	local aimed = table.clone(aimDirection)
	aimed.Direction = offset.Unit
	out.AimDirection = aimed
	strike.last = corner
	journal.note("shot aimed at a corner")
	return out
end

--------------------------------------------------------------------------------
-- what gets drawn
--------------------------------------------------------------------------------
--
-- The holder goes in gethui() rather than PlayerGui, and it is re-made whenever
-- it disappears. Both halves of that were paid for in another game: PlayerGui
-- there was swept clean of anything the game had not put in it, and an ESP that
-- is off for the rest of the night with its switch still reading on is worse
-- than one that was never built.

local marks = { people = {}, boxes = {}, path = {}, pins = {}, holder = nil }

-- NOT gethui(), and this is the bug that made the whole thing invisible while
-- every property read back correct.
--
-- Real's gethui() returns CoreGui.RobloxGui, which is a ScreenGui. A
-- BillboardGui nested inside a ScreenGui does not render at all - it takes an
-- Adornee, reports Enabled true, and draws nothing. Checking the pool and
-- finding "12 of 30 lit" therefore proves nothing, which is exactly how this
-- shipped: the flags were watched instead of the screen.
--
-- A BillboardGui has to hang off PlayerGui or CoreGui directly.
function marks.home()
	local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if gui then
		return gui
	end
	local fine, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	return fine and coreGui or nil
end

function marks.label(parent)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 32)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.Parent = parent

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamMedium
	text.TextSize = 16
	text.TextStrokeTransparency = 0.4
	text.RichText = true
	text.Parent = billboard

	return { billboard = billboard, text = text, target = nil }
end

function marks.person(parent)
	local slot = marks.label(parent)
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.75
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = parent
	slot.highlight = highlight
	return slot
end

-- A path segment, and a pin standing on the goal line.
--
-- Both are CylinderHandleAdornment rather than anything drawn on the screen. A
-- 2D line has to be re-projected every time the camera moves; an adornment is
-- real geometry that turns with the world by itself and still draws through
-- walls. Adorned to Terrain, its CFrame is world space, so nothing has to be
-- parented into the map.
function marks.rod(parent, radius)
	local rod = Instance.new("CylinderHandleAdornment")
	rod.Radius = radius
	rod.AlwaysOnTop = true
	rod.ZIndex = 0
	rod.Transparency = 0.3
	rod.Visible = false
	rod.Adornee = Workspace.Terrain
	rod.Parent = parent
	return rod
end

function marks.ensure(people, boxes, path)
	local holder = marks.holder
	if holder and holder.Parent then
		return true
	end
	local parent = marks.home()
	if not parent then
		return false
	end

	-- Rebuilt from empty rather than added to. A second pass that appended
	-- would leave the loops holding slots inside a destroyed folder, and the
	-- count of what is drawn would stop meaning anything.
	marks.people, marks.boxes, marks.path, marks.pins = {}, {}, {}, {}

	local made = Instance.new("Folder")
	made.Name = "MeridianMarks"
	made.Parent = parent
	marks.holder = made

	for _ = 1, people do
		marks.people[#marks.people + 1] = marks.person(made)
	end
	for _ = 1, boxes do
		marks.boxes[#marks.boxes + 1] = marks.label(made)
	end
	for _ = 1, path do
		marks.path[#marks.path + 1] = marks.rod(made, 0.22)
	end
	for _ = 1, 2 do
		marks.pins[#marks.pins + 1] = { rod = marks.rod(made, 0.55), slot = marks.label(made) }
	end
	return true
end

function marks.clear()
	if marks.holder then
		pcall(function()
			marks.holder:Destroy()
		end)
	end
	marks.holder = nil
	marks.people, marks.boxes, marks.path, marks.pins = {}, {}, {}, {}
end

function marks.hideFrom(pool, index)
	for slot = index, #pool do
		local mark = pool[slot]
		if not mark.billboard.Enabled and not mark.target then
			break
		end
		mark.billboard.Enabled = false
		mark.billboard.Adornee = nil
		if mark.highlight then
			mark.highlight.Enabled = false
			mark.highlight.Adornee = nil
		end
		mark.target = nil
	end
end

function marks.rodBetween(rod, from, to, colour)
	local offset = to - from
	local length = offset.Magnitude
	if length < 0.05 then
		rod.Visible = false
		return
	end
	rod.Height = length
	rod.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	rod.Color3 = colour
	rod.Visible = true
end

marks.colours = {
	Mine = Color3.fromRGB(120, 210, 255),
	Theirs = Color3.fromRGB(255, 110, 110),
	Neutral = Color3.fromRGB(232, 236, 240),
	Keeper = Color3.fromRGB(255, 208, 84),
	Danger = Color3.fromRGB(255, 82, 82),
	Chance = Color3.fromRGB(120, 255, 170),
	Box = Color3.fromRGB(190, 150, 255),
	Landing = Color3.fromRGB(255, 255, 255),
}

--------------------------------------------------------------------------------
-- the shot preview
--------------------------------------------------------------------------------

local shot = { bits = nil, saidAt = 0, said = nil, live = nil }

function shot.wire(bits)
	shot.bits = bits
end

function shot.hide()
	for _, rod in ipairs(marks.path) do
		if rod.Visible then
			rod.Visible = false
		end
	end
	for _, pin in ipairs(marks.pins) do
		if pin.rod.Visible then
			pin.rod.Visible = false
		end
		pin.slot.billboard.Enabled = false
		pin.slot.billboard.Adornee = nil
	end
	shot.live = nil
end

-- One pin per goal: a post standing on the spot the ball will cross, with how
-- long until it gets there.
function shot.pin(index, position, seconds, colour, caption)
	local pin = marks.pins[index]
	if not pin then
		return
	end
	marks.rodBetween(pin.rod, position - Vector3.new(0, 6, 0), position + Vector3.new(0, 6, 0), colour)
	pin.slot.text.Text = ("%s · %.1fs"):format(caption, math.max(seconds, 0))
	pin.slot.text.TextColor3 = colour
	pin.slot.billboard.Adornee = Workspace.Terrain
	pin.slot.billboard.StudsOffsetWorldSpace = position + Vector3.new(0, 8, 0)
	pin.slot.billboard.Enabled = true
end

function shot.tick()
	local bits = shot.bits
	if not bits then
		return
	end
	local F, core = bits.F, bits.core

	if F.shotPreview == false then
		shot.hide()
		return
	end
	if not marks.ensure(bits.slots.people, bits.slots.boxes, bits.slots.path) then
		return
	end

	local state = predict.ball()
	if not state or not predict.moving(state) then
		shot.hide()
		return
	end

	local mine = predict.myTeam()
	local theirs = mine == "Team1" and "Team2" or "Team1"
	local now = Workspace:GetServerTimeNow()

	local danger, dangerAt = nil, nil
	if mine then
		danger, dangerAt = predict.crossing(state, mine)
	end
	local chance, chanceAt = nil, nil
	if F.bothGoals ~= false and theirs then
		chance, chanceAt = predict.crossing(state, theirs)
	end

	shot.live = danger ~= nil

	if danger then
		shot.pin(1, danger, (dangerAt or now) - now, marks.colours.Danger, "On your goal")
	else
		local pin = marks.pins[1]
		if pin then
			pin.rod.Visible = false
			pin.slot.billboard.Enabled = false
		end
	end

	if chance then
		shot.pin(2, chance, (chanceAt or now) - now, marks.colours.Chance, "On their goal")
	else
		local pin = marks.pins[2]
		if pin then
			pin.rod.Visible = false
			pin.slot.billboard.Enabled = false
		end
	end

	-- The flight itself, sampled through the game's own simulator so bounces
	-- and curve are in it rather than a straight line that lies about both.
	if F.drawFlight ~= false then
		local points = math.clamp(math.floor(tonumber(F.pathDetail) or 18), 4, 40)
		local horizon = danger and math.max((dangerAt or now) - now, 0.05)
			or chance and math.max((chanceAt or now) - now, 0.05)
			or 1.5
		local step = horizon / points
		local previous = state.Position
		local colour = danger and marks.colours.Danger
			or chance and marks.colours.Chance
			or marks.colours.Neutral
		for i = 1, points do
			local rod = marks.path[i]
			if not rod then
				break
			end
			local here = predict.at(state, step * i)
			if here then
				marks.rodBetween(rod, previous, here, colour)
				previous = here
			else
				rod.Visible = false
			end
		end
		for i = points + 1, #marks.path do
			if not marks.path[i].Visible then
				break
			end
			marks.path[i].Visible = false
		end
	else
		for _, rod in ipairs(marks.path) do
			if rod.Visible then
				rod.Visible = false
			end
		end
	end

	-- Said once per shot, not once per tick. A shot that takes a second to
	-- arrive is one event to a person and forty to a loop.
	if F.warnOnTarget ~= false and danger then
		local key = tostring(state.MovementSequence or state.FlightStartedAt)
		if shot.said ~= key and os.clock() - shot.saidAt > 1.5 then
			shot.said, shot.saidAt = key, os.clock()
			local seconds = math.max((dangerAt or now) - now, 0)
			journal.note(("shot on your goal in %.1fs"):format(seconds))
			core:Notify(Module.Name, ("Shot on your goal · %.1fs"):format(seconds), 3)
		end
	end
end

--------------------------------------------------------------------------------
-- everybody else
--------------------------------------------------------------------------------

local people = { bits = nil }

function people.wire(bits)
	people.bits = bits
end

function people.gadget(character)
	local bits = people.bits
	local ok, model = pcall(bits.HeldItems.FindModel, character)
	if not ok or not model then
		return nil
	end
	local id = model:GetAttribute(bits.ItemIds.AttributeName)
	return id and tostring(id) or nil
end

function people.tick()
	local bits = people.bits
	if not bits then
		return
	end
	local F, core = bits.F, bits.core

	if F.playerEsp ~= true then
		marks.hideFrom(marks.people, 1)
		return
	end
	local root = core:Root()
	if not root or not marks.ensure(bits.slots.people, bits.slots.boxes, bits.slots.path) then
		marks.hideFrom(marks.people, 1)
		return
	end

	local mine = predict.myTeam()
	local reach = tonumber(F.espRange) or 900
	local size = tonumber(F.espTextSize) or 16
	local slot = 0

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= bits.player and slot < #marks.people then
			local character = player.Character
			local part = character and character:FindFirstChild("HumanoidRootPart")
			if part then
				local distance = (part.Position - root.Position).Magnitude
				if distance <= reach then
					slot = slot + 1
					local mark = marks.people[slot]

					local ok, team = pcall(bits.ActorTeams.GetActorTeamName, player)
					team = ok and team or nil
					local keeper = character:GetAttribute("ActiveGoalkeeper") == true

					local colour = marks.colours.Neutral
					if F.teamColours ~= false and team then
						colour = team == mine and marks.colours.Mine or marks.colours.Theirs
					end
					if keeper and F.markKeeper ~= false then
						colour = marks.colours.Keeper
					end

					local text = player.DisplayName
					if keeper and F.markKeeper ~= false then
						text = text .. " · keeper"
					end
					if F.showGadget ~= false then
						local held = people.gadget(character)
						if held then
							text = text .. " · " .. held
						end
					end
					if F.showDistance ~= false then
						text = ("%s · %dm"):format(text, math.floor(distance))
					end

					mark.text.Text = text
					mark.text.TextColor3 = colour
					mark.text.TextSize = size
					mark.billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
					mark.billboard.Adornee = part
					mark.billboard.Enabled = true
					mark.highlight.Adornee = character
					mark.highlight.FillColor = colour
					mark.highlight.OutlineColor = colour
					mark.highlight.Enabled = true
					mark.target = part
				end
			end
		end
	end

	marks.hideFrom(marks.people, slot + 1)
end

function people.boxes()
	local bits = people.bits
	if not bits then
		return
	end
	local F, core = bits.F, bits.core

	if F.boxEsp ~= true then
		marks.hideFrom(marks.boxes, 1)
		return
	end
	local root = core:Root()
	local misc = Workspace:FindFirstChild("Misc")
	local folder = misc and misc:FindFirstChild("Items")
	if not root or not folder or not marks.ensure(bits.slots.people, bits.slots.boxes, bits.slots.path) then
		marks.hideFrom(marks.boxes, 1)
		return
	end

	local slot = 0
	for _, thing in ipairs(folder:GetChildren()) do
		if slot >= #marks.boxes then
			break
		end
		local part = thing:IsA("BasePart") and thing
			or (thing:IsA("Model") and (thing.PrimaryPart or thing:FindFirstChildWhichIsA("BasePart")))
		if part then
			slot = slot + 1
			local mark = marks.boxes[slot]
			mark.text.Text = ("Crate · %dm"):format(math.floor((part.Position - root.Position).Magnitude))
			mark.text.TextColor3 = marks.colours.Box
			mark.text.TextSize = tonumber(F.espTextSize) or 16
			mark.billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
			mark.billboard.Adornee = part
			mark.billboard.Enabled = true
			mark.target = part
		end
	end
	marks.hideFrom(marks.boxes, slot + 1)
end

--------------------------------------------------------------------------------

function Module.Build(ctx)
	journal.entries = {}

	local core, tabGroup = ctx.core, ctx.TabGroup
	local F = core.Flags
	local LocalPlayer = Players.LocalPlayer

	----------------------------------------------------------------------------
	-- the game's own modules
	----------------------------------------------------------------------------

	local Client = ReplicatedStorage:WaitForChild("Client")
	local Modules = ReplicatedStorage:WaitForChild("Modules")

	local bits = {
		F = F,
		core = core,
		player = LocalPlayer,
		Renderer = require(Client.Gameplay.Ball.Renderer),
		BallIds = require(Modules.Ball.BallIds),
		GKP = require(Modules.Gameplay.GoalkeeperPrediction),
		Physics = require(Modules.Ball.Physics),
		ActorTeams = require(Client.Gameplay.ActorTeams),
		HeldItems = require(Modules.Items.HeldItems),
		ItemIds = require(Modules.Items.ItemIds),
		HitboxSettings = require(Modules.Gameplay.HitboxSettings),
		Sprint = require(Modules.Actions.Sprint),
		Actors = require(Modules.Characters.Actors),
		MouseController = require(Client.MouseController),
		slots = { people = 16, boxes = 12, path = 40 },
	}

	predict.wire(bits)
	shot.wire(bits)
	people.wire(bits)
	aim.wire(bits)
	reach.wire(bits)
	boost.wire(bits)
	strike.wire(bits)

	core:Track(function()
		reach.restore()
		boost.restore()
	end)

	-- A shot is steered on the way out, the same way the guns are.
	local ActionRemoteProtocol = require(Modules.Actions.ActionRemoteProtocol)
	local sendAction = ActionRemoteProtocol.Send
	core:Override(ActionRemoteProtocol, "Send", function(command)
		return sendAction(strike.rewrite(command))
	end)

	-- The aim rewrite goes in before anything else, and comes back out on
	-- unload because Core:Override remembers what was there.
	local ItemCommands = require(Modules.Items.ItemCommands)
	local fireEquipped = ItemCommands.FireEquipped
	core:Override(ItemCommands, "FireEquipped", function(ray, ...)
		return fireEquipped(aim.rewrite(ray), ...)
	end)
	local continueSequence = ItemCommands.ContinueGunSequence
	core:Override(ItemCommands, "ContinueGunSequence", function(ray, ...)
		return continueSequence(aim.rewrite(ray), ...)
	end)

	----------------------------------------------------------------------------
	-- loops, registered before a single tab exists
	----------------------------------------------------------------------------
	--
	-- That ordering is load bearing. Maclib yields while it builds elements, and
	-- a thread that has yielded spawns children with no capability to touch an
	-- Instance at all, so a loop created after the tabs runs forever and draws
	-- nothing. setthreadidentity does not fix it; registering first does.

	marks.ensure(bits.slots.people, bits.slots.boxes, bits.slots.path)
	core:Track(function()
		marks.clear()
	end)

	-- The ball moves at a hundred studs a second, so the preview is a per-frame
	-- job and not a timer. Everything else is a search and runs slowly.
	core:Connect(RunService.Heartbeat, function()
		shot.tick()
	end)

	core:Loop("people", 0.2, function()
		people.tick()
	end)

	core:Loop("boxes", 0.5, function()
		people.boxes()
	end)

	core:Loop("legs", 0.5, function()
		boost.tick()
	end)

	core:Loop("stats", 1, function()
		local carried = core.Stats or {}
		local state = predict.ball()
		carried.Holding = state and tostring(state.Mode) or "no ball"
		core.Stats = carried

		local team = predict.myTeam()
		if not team then
			core.Headline = "In the lobby"
		elseif shot.live then
			core.Headline = "Shot on your goal"
		elseif state and predict.moving(state) then
			core.Headline = ("Ball moving · %d studs a second"):format(math.floor(state.Velocity.Magnitude))
		else
			core.Headline = nil
		end
	end)

	core.Journal = journal
	core.Predict = predict

	----------------------------------------------------------------------------
	-- anti AFK
	----------------------------------------------------------------------------
	--
	-- Disabling the Idled connections is quieter than pretending to click. It
	-- only goes one way though, and the switch says so rather than showing a
	-- state the client is not in: Real's connection:Enable() is a no-op on a
	-- native connection and leaves Enabled false however happily it returns.
	core.SetAntiAfk = function(on)
		local restored = true
		local ok = pcall(function()
			for _, connection in ipairs(getconnections(LocalPlayer.Idled)) do
				if on then
					connection:Disable()
				else
					connection:Enable()
					if connection.Enabled ~= true then
						restored = false
					end
				end
			end
		end)
		return ok, restored
	end

	task.spawn(function()
		if F.antiAfk == false then
			return
		end
		local ok = core.SetAntiAfk(true)
		if not ok then
			core:Connect(LocalPlayer.Idled, function()
				if F.antiAfk == false then
					return
				end
				pcall(function()
					local VirtualUser = game:GetService("VirtualUser")
					VirtualUser:CaptureController()
					VirtualUser:ClickButton2(Vector2.new())
				end)
			end)
		end
	end)

	----------------------------------------------------------------------------
	-- the interface, and it is last on purpose
	----------------------------------------------------------------------------

	local aimTab = tabGroup:Tab({ Name = "Aim", Image = "rbxassetid://10734949856" })
	local reachTab = tabGroup:Tab({ Name = "Body", Image = "rbxassetid://10723415903" })
	local matchTab = tabGroup:Tab({ Name = "Match", Image = "rbxassetid://10723407389" })
	local playersTab = tabGroup:Tab({ Name = "Players", Image = "rbxassetid://10747373176" })
	local playerTab = tabGroup:Tab({ Name = "Session", Image = "rbxassetid://10734898355" })

	local aimLeft = aimTab:Section({ Side = "Left" })
	local reachLeft = reachTab:Section({ Side = "Left" })
	local reachRight = reachTab:Section({ Side = "Right" })
	local matchLeft = matchTab:Section({ Side = "Left" })
	local matchRight = matchTab:Section({ Side = "Right" })
	local playersLeft = playersTab:Section({ Side = "Left" })
	local playersRight = playersTab:Section({ Side = "Right" })
	local sessionLeft = playerTab:Section({ Side = "Left" })

	----------------------------------------------------------------- aim · left

	aimLeft:Header({ Text = "Guns" })

	aimLeft:Toggle({
		Name = "Silent Aim",
		Default = false,
		Callback = function(state)
			F.silentAim = state
		end,
	}, "silentAim")

	aimLeft:Dropdown({
		Name = "Aim At",
		Multi = false,
		Required = true,
		Options = { "Nearest To Crosshair", "Nearest To You" },
		Default = 1,
		Callback = function(value)
			F.aimTarget = value
		end,
	}, "aimTarget")

	aimLeft:Toggle({
		Name = "Only The Other Team",
		Default = true,
		Callback = function(state)
			F.aimEnemiesOnly = state
		end,
	}, "aimEnemiesOnly")

	aimLeft:Divider()

	aimLeft:Toggle({
		Name = "Aim For The Corner",
		Default = false,
		Callback = function(state)
			F.cornerAim = state
		end,
	}, "cornerAim")

	aimLeft:Slider({
		Name = "Aim Range",
		Default = 400,
		Minimum = 50,
		Maximum = 1200,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.aimRange = value
		end,
	}, "aimRange")

	--------------------------------------------------------------- reach · left

	reachLeft:Header({ Text = "Reach" })

	reachLeft:Toggle({
		Name = "Longer Reach",
		Default = false,
		Callback = function(state)
			F.reachOn = state
			reach.apply()
		end,
	}, "reachOn")

	reachLeft:Slider({
		Name = "How Much Further",
		Default = 2,
		Minimum = 1,
		Maximum = 6,
		DisplayMethod = "Value",
		Precision = 1,
		Callback = function(value)
			F.reachAmount = value
			reach.apply()
		end,
	}, "reachAmount")

	reachLeft:Toggle({
		Name = "Take Their Shots",
		Default = false,
		Callback = function(state)
			F.interceptShots = state
			reach.apply()
		end,
	}, "interceptShots")

	-------------------------------------------------------------- reach · right

	reachRight:Header({ Text = "Legs" })

	reachRight:Toggle({
		Name = "Never Run Out",
		Default = false,
		Callback = function(state)
			F.foreverStamina = state
		end,
	}, "foreverStamina")

	reachRight:Toggle({
		Name = "Always Sprint",
		Default = false,
		Callback = function(state)
			F.alwaysSprint = state
			if not state then
				boost.restore()
			end
		end,
	}, "alwaysSprint")

	reachRight:Divider()

	reachRight:Toggle({
		Name = "Free Mouse",
		Default = true,
		Callback = function(state)
			F.freeMouse = state
		end,
	}, "freeMouse")

	--------------------------------------------------------------- match · left

	matchLeft:Header({ Text = "The Shot" })

	matchLeft:Toggle({
		Name = "Shot Preview",
		Default = true,
		Callback = function(state)
			F.shotPreview = state
			if not state then
				shot.hide()
			end
		end,
	}, "shotPreview")

	matchLeft:Toggle({
		Name = "Draw The Flight",
		Default = true,
		Callback = function(state)
			F.drawFlight = state
		end,
	}, "drawFlight")

	matchLeft:Toggle({
		Name = "Both Goals",
		Default = true,
		Callback = function(state)
			F.bothGoals = state
		end,
	}, "bothGoals")

	matchLeft:Slider({
		Name = "Path Detail",
		Default = 18,
		Minimum = 4,
		Maximum = 40,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.pathDetail = value
		end,
	}, "pathDetail")

	-------------------------------------------------------------- match · right

	matchRight:Header({ Text = "Warnings" })

	matchRight:Toggle({
		Name = "Warn On Target",
		Default = true,
		Callback = function(state)
			F.warnOnTarget = state
		end,
	}, "warnOnTarget")

	------------------------------------------------------------- players · left

	playersLeft:Header({ Text = "People" })

	playersLeft:Toggle({
		Name = "Player ESP",
		Default = false,
		Callback = function(state)
			F.playerEsp = state
		end,
	}, "playerEsp")

	playersLeft:Toggle({
		Name = "Team Colours",
		Default = true,
		Callback = function(state)
			F.teamColours = state
		end,
	}, "teamColours")

	playersLeft:Toggle({
		Name = "Mark The Keeper",
		Default = true,
		Callback = function(state)
			F.markKeeper = state
		end,
	}, "markKeeper")

	playersLeft:Toggle({
		Name = "Show Their Gadget",
		Default = true,
		Callback = function(state)
			F.showGadget = state
		end,
	}, "showGadget")

	playersLeft:Toggle({
		Name = "Show Distance",
		Default = true,
		Callback = function(state)
			F.showDistance = state
		end,
	}, "showDistance")

	------------------------------------------------------------ players · right

	playersRight:Header({ Text = "On The Pitch" })

	playersRight:Toggle({
		Name = "Item Box ESP",
		Default = false,
		Callback = function(state)
			F.boxEsp = state
		end,
	}, "boxEsp")

	playersRight:Slider({
		Name = "Max Distance",
		Default = 900,
		Minimum = 100,
		Maximum = 2000,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.espRange = value
		end,
	}, "espRange")

	playersRight:Slider({
		Name = "Text Size",
		Default = 16,
		Minimum = 10,
		Maximum = 24,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.espTextSize = value
		end,
	}, "espTextSize")

	------------------------------------------------------------- session · left

	sessionLeft:Header({ Text = "Session" })

	sessionLeft:Toggle({
		Name = "Anti AFK",
		Default = true,
		Callback = function(state)
			F.antiAfk = state
			local ok, restored = core.SetAntiAfk(state)
			if not state and ok and not restored then
				core:Notify(
					Module.Name,
					"Roblox will idle you out again from the next time the hub loads. It cannot be put back mid-session.",
					7
				)
			end
		end,
	}, "antiAfk")

	-- Every declared default, copied into the flags now that the controls
	-- exist. Nothing here yields, which Build may not do.
	seeded.apply(core)

	return {
		Tabs = {
			Aim = aimTab,
			Body = reachTab,
			Match = matchTab,
			Players = playersTab,
			Session = playerTab,
		},
		Default = aimTab,
		Tips = Module.Tips,
	}
end

return Module
