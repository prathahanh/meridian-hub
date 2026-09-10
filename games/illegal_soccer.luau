--// Meridian · Illegal Soccer
--// universe 10155360168
--//
--// Eight a side football with guns, jetpacks, grapples and no referee. The hub
--// is here to win matches, so everything in it either plays for you or takes a
--// limit off you. Nothing in here is a readout.
--//
--// Two facts decide how the file is built.
--//
--// The game keeps its tuning in plain Luau tables the client can reach: hitbox
--// sizes, the ball carrier speed penalty, the sprint multiplier. Those are
--// changed in place and put back on unload, which is why Ball Magnet and No
--// Slowdown are three lines each instead of a fight with the engine.
--//
--// And every action a player can take is a client function - Shoot, Pass,
--// SlideTackleInput, GoalkeeperDive - so the auto features press the game's own
--// buttons rather than forging packets. Charge timing, action ids and
--// sequencing all still come from the game, because the game is still doing it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Module = {
	GameId = 10155360168,
	Name = "Illegal Soccer",
}

Module.Tips = {
	["Ball Magnet"] = "The ball comes to you from much further away than it should.",
	["How Much Bigger"] = "Times normal. Ten is enormous and very obvious.",
	["Show The Box"] = "Draws your reach so you can see how big it is.",
	["Auto Dribble"] = "Their shots and passes stick to you too, not just your own team's.",
	["Auto Tackle"] = "Slide tackles whoever has the ball once they are close enough.",
	["Auto Goal"] = "Shoots at their goal on its own once you have the ball and are in range.",
	["Shoot From"] = "How close to their goal before it shoots.",
	["Auto Pass"] = "Passes to a team mate when someone closes you down.",
	["Auto Goalkeeper"] = "Dives to stop shots when you are the one in goal.",
	["No Slowdown"] = "Carrying the ball, charging a shot and aiming a gun stop slowing you down.",
	["Never Run Out"] = "Stamina stops dropping.",
	["Always Sprint"] = "Run at sprint speed without holding the key.",
	["Free Mouse"] = "Frees the cursor while the menu is open and gives it back when you close it.",
	["Aim For The Corner"] = "Shots go to the corner their keeper is furthest from.",
	["Silent Aim"] = "Guns hit who you pick, not where you point.",
	["Aim At"] = "Who to pick: nearest your crosshair, or nearest you.",
	["Only The Other Team"] = "Never picks a team mate.",
	["Aim Range"] = "How far away they can be.",
	["Anti AFK"] = "Stops Roblox idling you out.",
}

--------------------------------------------------------------------------------
-- file scope
--------------------------------------------------------------------------------
--
-- Build is ONE function against Luau's ceiling of 200 local registers, so every
-- feature lives out here and is handed what it needs once through a wire.

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

-- Every control's declared default has to reach the flag it writes. Sliders and
-- dropdowns definitely do not fire their own callback at build time and toggles
-- have been recorded both ways, so all three kinds are seeded here and every
-- read below is written to agree with the default its control shows.
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
				-- Spelled out, because `x and default or nil` yields nil for every
				-- toggle that defaults to false, which is most of them.
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
-- where the ball is, and whose goal is whose
--------------------------------------------------------------------------------
--
-- The match ball is not a part you can find in the workspace: every character
-- carries a small transparent Part called "Ball" which is a hitbox and a red
-- herring. The real one exists only through its renderer, and that renderer's
-- GetMovementState is the same table the game's own keeper prediction takes.

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
		return nil, renderer
	end
	return state, renderer
end

function predict.owner()
	local _, renderer = predict.ball()
	if not renderer then
		return nil
	end
	local ok, userId = pcall(renderer.GetOwnedUserId)
	return ok and userId or nil
end

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
	local model = team and data and data:FindFirstChild(team)
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

function predict.theirTeam()
	local mine = predict.myTeam()
	if not mine then
		return nil
	end
	return mine == "Team1" and "Team2" or "Team1"
end

-- Where and when the ball crosses a goal, from the game's own solver, spin and
-- bounce included. Nil when it is not going in, which is most of the time.
function predict.crossing(state, team)
	local bits = predict.bits
	local goal = predict.goal(team)
	local world = predict.boundary()
	if not goal or not world or not state then
		return nil
	end
	local ok, position, at =
		pcall(bits.GKP.GetGoalCrossing, state, world, goal, Workspace:GetServerTimeNow(), 5)
	if not ok or position == nil then
		return nil
	end
	return position, at
end

--------------------------------------------------------------------------------
-- reach, which is what a ball magnet actually is here
--------------------------------------------------------------------------------
--
-- Gameplay.HitboxSettings is a plain table of sizes, and the game measures every
-- touch against it with its own ContainsPoint maths rather than Roblox's
-- Touched. That is what makes growing them safe: the usual trap, where
-- GetTouchingParts reports nothing without a TouchTransmitter so a bigger box
-- detects less than a small one, needs a Touched to fail at and there is none.
--
-- Every entry carrying a Size is scaled, rather than a list of names, so the
-- goalkeeper's boxes are covered by the same switch as an outfield player's
-- without having to know what the game calls them.

local reach = { bits = nil, base = {}, front = nil }

function reach.wire(bits)
	reach.bits = bits
	for key, box in pairs(bits.HitboxSettings) do
		if type(box) == "table" and box.Size ~= nil and typeof(box.Size) ~= "function" then
			reach.base[key] = box.Size
		end
	end
	local front = bits.HitboxSettings.FrontAssist
	if front then
		reach.front = { IncludesShots = front.IncludesShots, TeamMode = front.TeamMode }
	end
end

function reach.apply()
	local bits = reach.bits
	if not bits then
		return
	end
	local multiplier = 1
	if bits.F.ballMagnet == true then
		multiplier = math.clamp(tonumber(bits.F.reachAmount) or 1, 1, 25)
	end
	for key, base in pairs(reach.base) do
		local box = bits.HitboxSettings[key]
		if box then
			box.Size = base * multiplier
		end
	end

	-- FrontAssist ships as IncludesShots false with TeamMode "Allies", so the
	-- game's own assist only ever helps you collect a team mate's pass. Turning
	-- both round is what makes loose balls and their shots stick to you.
	local front = bits.HitboxSettings.FrontAssist
	if front and reach.front then
		if bits.F.autoDribble == true then
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
	for key, base in pairs(reach.base) do
		local box = bits.HitboxSettings[key]
		if box then
			box.Size = base
		end
	end
	local front = bits.HitboxSettings.FrontAssist
	if front and reach.front then
		front.IncludesShots = reach.front.IncludesShots
		front.TeamMode = reach.front.TeamMode
	end
end

--------------------------------------------------------------------------------
-- the box you can see
--------------------------------------------------------------------------------
--
-- A reach you cannot see is a number you have to take on trust, so this draws
-- the receive box at whatever size it currently is, adorned to the root so it
-- follows without anything being parented into the map.
--
-- Deliberately NOT gethui(). Real's gethui() returns CoreGui.RobloxGui, which is
-- a ScreenGui, and adornments and billboards nested inside a ScreenGui report
-- themselves visible and draw absolutely nothing.

local boxview = { bits = nil, holder = nil, box = nil }

function boxview.home()
	local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if gui then
		return gui
	end
	local fine, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	return fine and coreGui or nil
end

function boxview.wire(bits)
	boxview.bits = bits
end

function boxview.ensure()
	if boxview.holder and boxview.holder.Parent then
		return true
	end
	local parent = boxview.home()
	if not parent then
		return false
	end
	local holder = Instance.new("Folder")
	holder.Name = "MeridianReach"
	holder.Parent = parent
	boxview.holder = holder

	local box = Instance.new("BoxHandleAdornment")
	box.AlwaysOnTop = true
	box.ZIndex = 0
	box.Transparency = 0.82
	box.Color3 = Color3.fromRGB(120, 210, 255)
	box.Visible = false
	box.Parent = holder
	boxview.box = box
	return true
end

function boxview.clear()
	if boxview.holder then
		pcall(function()
			boxview.holder:Destroy()
		end)
	end
	boxview.holder, boxview.box = nil, nil
end

function boxview.tick()
	local bits = boxview.bits
	if not bits then
		return
	end
	if bits.F.showBox ~= true then
		if boxview.box and boxview.box.Visible then
			boxview.box.Visible = false
		end
		return
	end
	if not boxview.ensure() then
		return
	end

	local root = bits.core:Root()
	local settings = bits.HitboxSettings.Receive
	if not root or not settings or settings.Size == nil then
		boxview.box.Visible = false
		return
	end

	boxview.box.Adornee = root
	boxview.box.Size = settings.Size
	boxview.box.CFrame = settings.CFrameOffset or CFrame.new()
	boxview.box.Visible = true
end

--------------------------------------------------------------------------------
-- legs
--------------------------------------------------------------------------------

local boost = { bits = nil, on = false, unlocked = false, slow = nil }

function boost.wire(bits)
	boost.bits = bits
	local constants = bits.ActionMovement.Constants
	boost.slow = {
		BallCarrierJogSpeedMultiplier = constants.BallCarrierJogSpeedMultiplier,
		BallCarrierRunSpeedMultiplier = constants.BallCarrierRunSpeedMultiplier,
		ChargingWalkSpeedMultiplier = constants.ChargingWalkSpeedMultiplier,
	}
end

-- The actor is the PLAYER for stamina and the CHARACTER for a boost, inside the
-- same module. Passing one where the other belongs fails silently both ways.
function boost.actor()
	local bits = boost.bits
	local character = bits.core:Character()
	if not character then
		return nil, nil
	end
	local ok, actor = pcall(bits.Actors.GetFromCharacter, character)
	return ok and actor or nil, character
end

-- Carrying the ball costs 20% of your run speed and charging a shot costs half,
-- and both are plain numbers in ActionMovement.Constants rather than anything
-- that passes through Movement.SetMultiplier. Which is exactly why hooking
-- SetMultiplier looked correct and did nothing at all about carrying the ball.
function boost.slowdown()
	local bits = boost.bits
	if not bits or not boost.slow then
		return
	end
	local constants = bits.ActionMovement.Constants
	if bits.F.noSlowdown == true then
		constants.BallCarrierJogSpeedMultiplier = 1
		constants.BallCarrierRunSpeedMultiplier = 1
		constants.ChargingWalkSpeedMultiplier = 1
	else
		for key, value in pairs(boost.slow) do
			constants[key] = value
		end
	end
end

function boost.tick()
	local bits = boost.bits
	if not bits then
		return
	end
	local F, Sprint = bits.F, bits.Sprint
	boost.slowdown()

	local actor, character = boost.actor()
	if actor then
		if F.foreverStamina == true then
			pcall(Sprint.SetStaminaMultiplier, 0)
			pcall(Sprint.SetUnlimitedStamina, actor, "Meridian", true)
			boost.on = true
		elseif boost.on then
			pcall(Sprint.SetStaminaMultiplier, 1)
			pcall(Sprint.ClearUnlimitedStaminaSource, "Meridian")
			boost.on = false
		end

		-- ForceSprint and no SpeedMultiplier, because the multiplier is not ours
		-- to set: ApplyBoost with SpeedMultiplier 2 still leaves WalkSpeed at
		-- 25.6, and writing Humanoid.WalkSpeed = 40 decays back to 16 in three
		-- seconds. What the server does not own is whether you are sprinting.
		if F.alwaysSprint == true and character then
			pcall(Sprint.ApplyBoost, character, {
				ForceSprint = true,
				NoStaminaConsumption = true,
				SpeedMultiplier = 1,
				DurationSeconds = 2,
			})
		end
	end

	-- The cursor is freed while the hub window is OPEN and locked again the
	-- moment it closes. This game pins it to the centre of the screen because
	-- that is how you aim, so a switch that frees it all match takes the game
	-- away in order to fix a menu.
	local open = false
	if bits.window and bits.window.GetState then
		local fine, state = pcall(bits.window.GetState)
		open = fine and state == true
	end
	local wantFree = open and F.freeMouse ~= false
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
	if boost.slow then
		for key, value in pairs(boost.slow) do
			bits.ActionMovement.Constants[key] = value
		end
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
-- the gun
--------------------------------------------------------------------------------
--
-- Every gadget that shoots sends an AimRay carrying ClientHit = {Kind, UserId,
-- Position, RootLocalPosition}, and HitScan.CleanClientHit checks only the shape
-- of it: that UserId is an integer and the positions are finite. It never asks
-- whether the ray reaches that player. The one geometric rule in the whole path
-- is that the ray origin sits within twelve studs of your own character.
--
-- The ray is rewritten on its way past ItemCommands.FireEquipped rather than
-- forged, so the game still builds the action id, the shot time and the
-- sequencing. Copied, not edited: the caller reuses its own ray to draw the
-- muzzle flash, and writing through it would point the visuals somewhere the
-- player never aimed.

local aim = { bits = nil, last = nil, shots = 0 }

function aim.wire(bits)
	aim.bits = bits
end

function aim.pick()
	local bits = aim.bits
	local F = bits.F
	local camera = Workspace.CurrentCamera
	local root = bits.core:Root()
	if not camera or not root then
		return nil
	end

	local mine = predict.myTeam()
	local far = tonumber(F.aimRange) or 400
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
				local enemy = F.aimEnemiesOnly == false or mine == nil or team ~= mine
				local distance = (part.Position - root.Position).Magnitude
				if enemy and distance <= far then
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

	aim.last = player.DisplayName
	aim.shots = aim.shots + 1
	return out
end

--------------------------------------------------------------------------------
-- putting it in the corner
--------------------------------------------------------------------------------
--
-- What reaches the server for a kick is only Origin, Direction, CameraCFrame and
-- IsAirborne: GetLaunchAim strips the ClientHit and TargetPosition the guns lean
-- on. So a shot is steered by Direction and nothing else.
--
-- Which corner is not a preset. The other scripts for this game offer a fixed
-- "top left"; this reads where their keeper is standing as you strike.

local strike = { bits = nil, last = nil }

function strike.wire(bits)
	strike.bits = bits
end

function strike.corners(goal)
	local half = goal.Size * 0.5
	local inset = 3
	local out = {}
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			out[#out + 1] = goal.Position + Vector3.new((half.X - inset) * sx, (half.Y - inset) * sy, 0)
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

function strike.target()
	local theirs = predict.theirTeam()
	local goal = theirs and predict.goal(theirs)
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
	journal.note("shot sent at a corner")
	return out
end

--------------------------------------------------------------------------------
-- playing for you
--------------------------------------------------------------------------------
--
-- Each of these presses the game's own buttons. Shoot, Pass and SlideTackleInput
-- are the client modules the keyboard already talks to, so charge timing, action
-- ids and sequencing keep coming from the game.
--
-- Everything is gated. An action asked for twice a second is the thing that gets
-- accounts removed, so each carries its own cooldown and none of them fire while
-- the character is down or the match has not started.

local auto = { bits = nil, next = {}, charging = nil }

function auto.wire(bits)
	auto.bits = bits
end

function auto.due(key, seconds)
	local now = os.clock()
	if now < (auto.next[key] or 0) then
		return false
	end
	auto.next[key] = now + seconds
	return true
end

function auto.ready()
	local bits = auto.bits
	local character = bits.core:Character()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	if character:GetAttribute("Ragdolled") == true then
		return nil
	end
	if predict.myTeam() == nil then
		return nil
	end
	return character, root
end

function auto.mine()
	local bits = auto.bits
	return bits ~= nil and predict.owner() == bits.player.UserId
end

function auto.nearest(root, wantMate)
	local bits = auto.bits
	local mine = predict.myTeam()
	local best, bestAt = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= bits.player then
			local character = player.Character
			local part = character and character:FindFirstChild("HumanoidRootPart")
			if part then
				local ok, team = pcall(bits.ActorTeams.GetActorTeamName, player)
				local same = ok and team ~= nil and team == mine
				if ok and team ~= nil and same == wantMate then
					local distance = (part.Position - root.Position).Magnitude
					if distance < bestAt then
						best, bestAt = player, distance
					end
				end
			end
		end
	end
	return best, bestAt
end

-- A charged action is press, hold, release. Releasing on the same frame you
-- pressed produces a tap with nothing behind it, which is why these hold.
function auto.charge(module, seconds, why)
	if auto.charging then
		return
	end
	auto.charging = why
	task.spawn(function()
		pcall(module.HandleInputBegan)
		task.wait(seconds)
		pcall(module.HandleInputEnded)
		journal.note(why)
		auto.charging = nil
	end)
end

function auto.tackle(root)
	local bits = auto.bits
	if bits.F.autoTackle ~= true then
		return false
	end
	local carrier = predict.owner()
	if not carrier or carrier == bits.player.UserId then
		return false
	end
	local holder = Players:GetPlayerByUserId(carrier)
	if not holder then
		return false
	end
	local ok, team = pcall(bits.ActorTeams.GetActorTeamName, holder)
	if ok and team == predict.myTeam() then
		return false
	end
	local part = holder.Character and holder.Character:FindFirstChild("HumanoidRootPart")
	if not part or (part.Position - root.Position).Magnitude > 22 then
		return false
	end
	if not auto.due("tackle", 2.5) then
		return false
	end
	pcall(bits.SlideTackleInput.HandleInputBegan)
	journal.note("tackled " .. holder.Name)
	return true
end

function auto.shoot(root)
	local bits = auto.bits
	if bits.F.autoGoal ~= true or not auto.mine() then
		return false
	end
	local theirs = predict.theirTeam()
	local goal = theirs and predict.goal(theirs)
	if not goal then
		return false
	end
	local far = tonumber(bits.F.shootFrom) or 120
	if (goal.Position - root.Position).Magnitude > far then
		return false
	end
	if not auto.due("shoot", 1.5) then
		return false
	end
	auto.charge(bits.Shoot, 0.55, "shot at goal")
	return true
end

function auto.pass(root)
	local bits = auto.bits
	if bits.F.autoPass ~= true or not auto.mine() then
		return false
	end
	local _, enemyAt = auto.nearest(root, false)
	if enemyAt > 18 then
		return false
	end
	local mate = auto.nearest(root, true)
	if not mate then
		return false
	end
	if not auto.due("pass", 2) then
		return false
	end
	auto.charge(bits.Pass, 0.3, "passed to " .. mate.Name)
	return true
end

-- Diving is the keeper's whole job, and the game hands over both halves of it:
-- GetGoalCrossing says where the ball crosses and when, GoalkeeperDive names the
-- directions it will accept.
function auto.keeper(root)
	local bits = auto.bits
	local character = bits.core:Character()
	if bits.F.autoKeeper ~= true or not character then
		return false
	end
	if character:GetAttribute("ActiveGoalkeeper") ~= true then
		return false
	end
	local mine = predict.myTeam()
	local state = predict.ball()
	if not mine or not state then
		return false
	end
	local where, at = predict.crossing(state, mine)
	if not where then
		return false
	end
	local left = (at or 0) - Workspace:GetServerTimeNow()
	-- Too early and you dive before they have shot; too late and you are
	-- watching it go in. Half a second out is where a dive still arrives.
	if left > 0.55 or left < 0.05 then
		return false
	end
	if not auto.due("dive", 1.2) then
		return false
	end

	local sideways = where.X - root.Position.X
	local name = "Middle"
	if sideways > 4 then
		name = "Right"
	elseif sideways < -4 then
		name = "Left"
	end
	local ok = pcall(function()
		local choice = bits.GoalkeeperDive.GetDirectionChoiceByName(name)
		bits.GoalkeeperDive.Run(character, choice)
	end)
	journal.note(("dived %s, %.2fs out (%s)"):format(name, left, ok and "ok" or "refused"))
	return ok
end

function auto.tick()
	local bits = auto.bits
	if not bits then
		return
	end
	local _, root = auto.ready()
	if not root then
		return
	end
	-- Order is priority: keeping it out of the net beats taking it off somebody,
	-- which beats shooting, which beats passing.
	if auto.keeper(root) then
		return
	end
	if auto.tackle(root) then
		return
	end
	if auto.shoot(root) then
		return
	end
	auto.pass(root)
end

--------------------------------------------------------------------------------

function Module.Build(ctx)
	journal.entries = {}

	local core, tabGroup = ctx.core, ctx.TabGroup
	local F = core.Flags
	local LocalPlayer = Players.LocalPlayer

	local Client = ReplicatedStorage:WaitForChild("Client")
	local Modules = ReplicatedStorage:WaitForChild("Modules")

	local bits = {
		F = F,
		core = core,
		player = LocalPlayer,
		window = ctx.Window,
		Renderer = require(Client.Gameplay.Ball.Renderer),
		BallIds = require(Modules.Ball.BallIds),
		GKP = require(Modules.Gameplay.GoalkeeperPrediction),
		ActorTeams = require(Client.Gameplay.ActorTeams),
		HitboxSettings = require(Modules.Gameplay.HitboxSettings),
		Sprint = require(Modules.Actions.Sprint),
		Actors = require(Modules.Characters.Actors),
		ActionMovement = require(Modules.Actions.ActionMovement),
		MouseController = require(Client.MouseController),
		Shoot = require(Client.Gameplay.Actions.Shoot),
		Pass = require(Client.Gameplay.Actions.Pass),
		SlideTackleInput = require(Client.Gameplay.Actions.SlideTackleInput),
		GoalkeeperDive = require(Modules.Actions.GoalkeeperDive),
	}

	predict.wire(bits)
	reach.wire(bits)
	boxview.wire(bits)
	boost.wire(bits)
	aim.wire(bits)
	strike.wire(bits)
	auto.wire(bits)

	core:Track(function()
		reach.restore()
		boost.restore()
		boxview.clear()
	end)

	-- The gun's aim, rewritten on the way past.
	local ItemCommands = require(Modules.Items.ItemCommands)
	local fireEquipped = ItemCommands.FireEquipped
	core:Override(ItemCommands, "FireEquipped", function(ray, ...)
		return fireEquipped(aim.rewrite(ray), ...)
	end)
	local continueSequence = ItemCommands.ContinueGunSequence
	core:Override(ItemCommands, "ContinueGunSequence", function(ray, ...)
		return continueSequence(aim.rewrite(ray), ...)
	end)

	-- The shot's aim, the same way.
	local ActionRemoteProtocol = require(Modules.Actions.ActionRemoteProtocol)
	local sendAction = ActionRemoteProtocol.Send
	core:Override(ActionRemoteProtocol, "Send", function(command)
		return sendAction(strike.rewrite(command))
	end)

	----------------------------------------------------------------------------
	-- loops, registered before a single tab exists
	----------------------------------------------------------------------------
	--
	-- Maclib yields while it builds elements, and a thread that has yielded
	-- spawns children with no capability to touch an Instance, so a loop created
	-- after the tabs runs forever and draws nothing.

	core:Loop("legs", 0.4, function()
		boost.tick()
	end)

	core:Loop("auto", 0.15, function()
		auto.tick()
	end)

	core:Connect(RunService.Heartbeat, function()
		boxview.tick()
	end)

	core:Loop("stats", 1, function()
		local carried = core.Stats or {}
		carried.Hits = aim.shots
		carried.Holding = auto.mine() and "on the ball" or "off it"
		core.Stats = carried

		if predict.myTeam() == nil then
			core.Headline = "In the lobby"
		elseif auto.mine() then
			core.Headline = "You have it"
		else
			core.Headline = nil
		end
	end)

	core.Journal = journal

	----------------------------------------------------------------------------
	-- anti AFK
	----------------------------------------------------------------------------
	--
	-- Only goes one way: Real's connection:Enable() is a no-op on a native
	-- connection and leaves Enabled false however happily it returns.

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
		if F.antiAfk ~= false then
			core.SetAntiAfk(true)
		end
	end)

	----------------------------------------------------------------------------
	-- the interface
	----------------------------------------------------------------------------

	local ballTab = tabGroup:Tab({ Name = "Ball", Image = "rbxassetid://10723407389" })
	local bodyTab = tabGroup:Tab({ Name = "Body", Image = "rbxassetid://10723415903" })
	local aimTab = tabGroup:Tab({ Name = "Aim", Image = "rbxassetid://10734949856" })

	local ballLeft = ballTab:Section({ Side = "Left" })
	local ballRight = ballTab:Section({ Side = "Right" })
	local bodyLeft = bodyTab:Section({ Side = "Left" })
	local bodyRight = bodyTab:Section({ Side = "Right" })
	local aimLeft = aimTab:Section({ Side = "Left" })

	---------------------------------------------------------------- ball · left

	ballLeft:Header({ Text = "The Ball" })

	ballLeft:Toggle({
		Name = "Ball Magnet",
		Default = false,
		Callback = function(state)
			F.ballMagnet = state
			reach.apply()
		end,
	}, "ballMagnet")

	ballLeft:Slider({
		Name = "How Much Bigger",
		Default = 6,
		Minimum = 1,
		Maximum = 25,
		DisplayMethod = "Value",
		Precision = 1,
		Callback = function(value)
			F.reachAmount = value
			reach.apply()
		end,
	}, "reachAmount")

	ballLeft:Toggle({
		Name = "Show The Box",
		Default = false,
		Callback = function(state)
			F.showBox = state
		end,
	}, "showBox")

	ballLeft:Toggle({
		Name = "Auto Dribble",
		Default = false,
		Callback = function(state)
			F.autoDribble = state
			reach.apply()
		end,
	}, "autoDribble")

	--------------------------------------------------------------- ball · right

	ballRight:Header({ Text = "Playing For You" })

	ballRight:Toggle({
		Name = "Auto Tackle",
		Default = false,
		Callback = function(state)
			F.autoTackle = state
		end,
	}, "autoTackle")

	ballRight:Toggle({
		Name = "Auto Goal",
		Default = false,
		Callback = function(state)
			F.autoGoal = state
		end,
	}, "autoGoal")

	ballRight:Slider({
		Name = "Shoot From",
		Default = 120,
		Minimum = 40,
		Maximum = 300,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.shootFrom = value
		end,
	}, "shootFrom")

	ballRight:Toggle({
		Name = "Auto Pass",
		Default = false,
		Callback = function(state)
			F.autoPass = state
		end,
	}, "autoPass")

	ballRight:Toggle({
		Name = "Auto Goalkeeper",
		Default = false,
		Callback = function(state)
			F.autoKeeper = state
		end,
	}, "autoKeeper")

	---------------------------------------------------------------- body · left

	bodyLeft:Header({ Text = "Legs" })

	bodyLeft:Toggle({
		Name = "No Slowdown",
		Default = false,
		Callback = function(state)
			F.noSlowdown = state
			boost.slowdown()
		end,
	}, "noSlowdown")

	bodyLeft:Toggle({
		Name = "Never Run Out",
		Default = false,
		Callback = function(state)
			F.foreverStamina = state
		end,
	}, "foreverStamina")

	bodyLeft:Toggle({
		Name = "Always Sprint",
		Default = false,
		Callback = function(state)
			F.alwaysSprint = state
			if not state then
				boost.restore()
			end
		end,
	}, "alwaysSprint")

	--------------------------------------------------------------- body · right

	bodyRight:Header({ Text = "Session" })

	bodyRight:Toggle({
		Name = "Free Mouse",
		Default = true,
		Callback = function(state)
			F.freeMouse = state
		end,
	}, "freeMouse")

	bodyRight:Toggle({
		Name = "Anti AFK",
		Default = true,
		Callback = function(state)
			F.antiAfk = state
			core.SetAntiAfk(state)
		end,
	}, "antiAfk")

	----------------------------------------------------------------- aim · left

	aimLeft:Header({ Text = "Aim" })

	aimLeft:Toggle({
		Name = "Aim For The Corner",
		Default = false,
		Callback = function(state)
			F.cornerAim = state
		end,
	}, "cornerAim")

	aimLeft:Divider()

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

	seeded.apply(core)

	return {
		Tabs = {
			Ball = ballTab,
			Body = bodyTab,
			Aim = aimTab,
		},
		Default = ballTab,
		Tips = Module.Tips,
	}
end

return Module
