--// Meridian · Killer or Not
--// universe 10345286503
--//
--// A Murder Mystery 2 clone, and not a loose one: the game's own GameModes
--// table still carries MM2's place ids and still checks `game.GameId ==
--// 119460199`. Everything true of that client is worth trying here first.
--//
--// The one thing to know before reading any of this: the server hands every
--// client the entire round table, including which player is the murderer.
--// Nothing in this file infers a role, spies on a remote, or guesses from a
--// knife model. It reads the same table the scoreboard reads.
--//
--// The other thing to know is the trap. The game's own Leaderboard LocalScript
--// runs on RunService.Stepped and kicks you with "You have been banned from
--// MM2." the moment anything named exactly "ESP" appears as a child of
--// PlayerGui. It is a name check and nothing more, so this hub draws into a
--// folder called MeridianMarks. Never rename it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")

local Module = {
	GameId = 10345286503,
	Name = "Killer or Not",
}

-- Hover text. One line each, written for somebody who has never seen the code.
-- Nothing here explains a mechanism and no number appears unless it is one you
-- would actually set.
Module.Tips = {
	["Show The Killer"] = "Draws the killer through walls with their name and how far away they are.",
	["Show The Sheriff"] = "Draws the sheriff too, so you know who is carrying the gun.",
	["Show Everyone Else"] = "Draws the rest of the lobby as well, not just the two who matter.",
	["Hide The Dead"] = "Stops drawing anybody who is already out of the round.",
	["Show Their Perk"] = "Adds what the killer picked, so you know before they use it whether they can go invisible or see through walls.",
	["Tracers"] = "Draws a line from you to everybody being shown.",
	["How Far To Look"] = "Stops drawing people further away than this.",
	["Text Size"] = "How big the names above people are.",
	["Say Who It Is"] = "Tells you who the killer is the moment the round starts, instead of you reading it off a screen.",
	["Warn When They Are Close"] = "One warning when the killer gets near you, and nothing more until they have been away a while.",
	["Keep Away"] = "Walks you off when the killer gets close, and stops the coin run walking you into them.",
	["Keep Away Within"] = "How close the killer has to get before you are moved.",
	["Auto Coins"] = "Walks the map picking up coins until you have every one the round will give you.",
	["How Far For A Coin"] = "Stops it crossing the whole map for one coin.",
	["Give Up After"] = "How long to spend on one coin before writing it off and going for another. Some sit on furniture and cannot be walked to at all.",
	["Rest When Full"] = "Stands still once the round has given you everything it is going to. Off keeps it walking, which looks busier and earns nothing.",
	["Show Coins"] = "Draws every coin left on the map through walls.",
	["Show How Far"] = "Adds the distance to each coin.",
	["Anti AFK"] = "Stops Roblox idling you out. Switching it back off only takes hold the next time the hub loads.",
}

--------------------------------------------------------------------------------
-- file scope
--------------------------------------------------------------------------------
--
-- Build is ONE function against Luau's ceiling of 200 local registers. Every
-- feature past the first few lives out here on a table and is handed what it
-- needs once, through a wire function. `./check.sh games/killer_or_not.luau`
-- catches the ceiling; luau-analyze does not.

-- A rolling record of what the hub actually did, readable while it runs.
--
-- Steal An Egg learned this the expensive way: eleven switches turned out to do
-- nothing and every one of them looked correct in the source. They were found
-- by reading this during a live run.
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
-- fire their own callback at build time; whether a Toggle does has been recorded
-- both ways in this codebase, which is reason enough not to bet a switch on it.
--
-- In Steal An Egg the slider version of this shipped: the control read one thing
-- and the farm did another, for as long as the control had existed. That is the
-- worst kind of bug in a hub, because the person judging it is reading the
-- interface.
--
-- So every kind is seeded, and separately every read of a flag in this file is
-- written to agree with the default its control shows. Either alone would do;
-- together they mean a control cannot lie even if the other half is wrong.
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
				-- Toggles are seeded too, and the template does not do this.
				-- Whether Maclib fires a Toggle's own callback at build time has
				-- been recorded both ways in this codebase, so neither answer is
				-- worth betting a control on: seed it, and separately make every
				-- read of a flag agree with the default its control displays.
				-- Four switches in this file used to read as off while showing
				-- on, which is the worst kind of bug in a hub, because the person
				-- judging it is reading the interface.
				value = type(default) == "boolean" and default or nil
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
-- who everybody is
--------------------------------------------------------------------------------
--
-- ReplicatedStorage.Modules.CurrentRoundClient holds a table keyed by player
-- NAME, refreshed by the server on Remotes.Gameplay.PlayerDataChanged. Each row
-- carries Role, Dead, Perk, Knife, Gun, Coins and MaxCoins.
--
-- It is EMPTY between rounds. That is not a failure to read it, it is the
-- lobby, and everything downstream has to treat an empty table as "no round"
-- rather than as "nobody is the murderer".

local round = { bits = nil, data = {}, murderer = nil, sheriff = nil, tag = nil }

function round.wire(bits)
	round.bits = bits
end

-- Always the module's current table, never a copy of the reference.
--
-- The module does `PlayerData = <new table>` on every update rather than
-- editing in place, so a reference grabbed half a second ago is a whole round
-- out of date at exactly the moment a round changes. Held as a snapshot, this
-- put "Out this round" on the headline for twelve seconds while the character
-- was walking around alive, because the hub was still reading the table from
-- the round it had died in.
function round.table()
	local bits = round.bits
	local module = bits and bits.M
	return (module and module.PlayerData) or {}
end

-- Work out the two names that matter once a tick, so the ESP loop and the farm
-- loop are not each walking the table forty times a second. These are derived
-- values and may lag by one tick; the rows themselves never do.
function round.refresh()
	round.data = round.table()

	local murderer, sheriff, live = nil, nil, 0
	for name, row in pairs(round.data) do
		live = live + 1
		if row.Role == "Murderer" then
			murderer = name
		elseif row.Role == "Sheriff" then
			sheriff = name
		end
	end
	round.murderer, round.sheriff = murderer, sheriff

	-- A round is identified by who is playing what. The server sends the whole
	-- table on every change - a death, a join, a leave - so "the table changed"
	-- is not "a new round started", and announcing on every change would name
	-- the killer four times a round.
	round.tag = live > 0 and ((murderer or "?") .. "/" .. (sheriff or "?") .. "/" .. live) or nil
	return live > 0
end

function round.row(name)
	return name and round.table()[name] or nil
end

function round.mine()
	local bits = round.bits
	return bits and round.table()[bits.player.Name] or nil
end

function round.amDead()
	local row = round.mine()
	return row ~= nil and row.Dead == true
end

-- The character behind a name, only if it is actually in the world and alive.
function round.body(name)
	if not name then
		return nil
	end
	local player = Players:FindFirstChild(name)
	local model = player and player.Character
	if not model or not model.Parent then
		return nil
	end
	local part = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not part or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return model, part
end

function round.killerAt()
	local _, part = round.body(round.murderer)
	return part and part.Position or nil
end

--------------------------------------------------------------------------------
-- getting there
--------------------------------------------------------------------------------
--
-- Two things this game breaks that an outdoor game does not.
--
-- The maps are houses. Walking at a coin in a straight line puts you against a
-- wall and leaves you there, so the route is a real path.
--
-- And the game's own ControlModule calls Humanoid:Move every frame with what
-- the keyboard says, which is zero when nobody is holding a key - that cancels
-- MoveTo instantly. So this does not issue orders, it runs one step later in
-- the same frame and sets the direction itself.

local nav = {
	bits = nil,
	direction = nil,
	goal = nil,
	points = nil,
	index = 1,
	busy = false,
	failedAt = 0,
	noRoute = nil,
	bound = false,
}

local WAYPOINT_REACHED = 6
local ROUTE_MOVED = 18
local ROUTE_RETRY = 1.5
local ROUTE_LOST = 45
local LOOKAHEAD_STEPS = 8

function nav.wire(bits)
	nav.bits = bits
end

function nav.clear()
	nav.goal, nav.points, nav.index = nil, nil, 1
end

function nav.stop()
	nav.direction = nil
	nav.clear()
	local core = nav.bits and nav.bits.core
	local humanoid = core and core:Humanoid()
	if humanoid then
		pcall(function()
			humanoid:Move(Vector3.zero, false)
		end)
	end
end

-- ComputeAsync yields, and neither the farm loop nor Build may yield, so the
-- route is worked out on its own thread and the loop reads whatever is ready.
function nav.plan(goal)
	if nav.busy or os.clock() - nav.failedAt < ROUTE_RETRY then
		return
	end
	nav.busy = true
	task.spawn(function()
		local core = nav.bits and nav.bits.core
		local root = core and core:Root()
		if root then
			local path = PathfindingService:CreatePath({
				AgentRadius = 2.5,
				AgentHeight = 5,
				AgentCanJump = true,
				AgentMaxSlope = 60,
			})
			local ok = pcall(function()
				path:ComputeAsync(root.Position, goal)
			end)
			if ok and path.Status == Enum.PathStatus.Success then
				nav.goal = goal
				nav.points = path:GetWaypoints()
				nav.noRoute = nil
				-- The first waypoint is where we already are.
				nav.index = math.min(2, #nav.points)
			else
				nav.clear()
				nav.failedAt = os.clock()
				-- Remembered rather than just counted, so whoever asked for this
				-- goal can stop asking. A coin standing on a table answers
				-- NoPath every time, and waiting out Give Up After on each one
				-- is eighteen seconds of walking into furniture.
				nav.noRoute = goal
			end
		end
		nav.busy = false
	end)
end

function nav.flat(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

nav.sight = RaycastParams.new()
nav.sight.FilterType = Enum.RaycastFilterType.Exclude
nav.sight.IgnoreWater = true

-- How far along the route to aim. Aiming a fixed distance ahead is what parks a
-- character against a corner: on a route that turns, the point twenty studs
-- along is through the wall, and steering at a point through a wall walks into
-- the wall. So aim as far ahead as can actually be seen and no further.
function nav.canSee(from, to)
	local core = nav.bits and nav.bits.core
	local character = core and core:Character()
	nav.sight.FilterDescendantsInstances = character and { character } or {}
	local eye = from + Vector3.new(0, 2, 0)
	local aim = Vector3.new(to.X, from.Y + 2, to.Z)
	local reach = aim - eye
	if reach.Magnitude < 0.5 then
		return true
	end
	return Workspace:Raycast(eye, reach, nav.sight) == nil
end

function nav.lookAhead(from)
	local points = nav.points
	if not points then
		return nil, nil
	end

	local nearest, nearestAt = nav.index, math.huge
	for i = nav.index, math.min(nav.index + 12, #points) do
		local distance = nav.flat(points[i].Position, from)
		if distance < nearestAt then
			nearest, nearestAt = i, distance
		end
	end
	-- A long way from every waypoint means the route describes a journey we are
	-- no longer on: knocked off a ledge, killed and respawned, map swapped
	-- under us between rounds. Throw it away rather than steering back onto it.
	if nearestAt > ROUTE_LOST then
		nav.clear()
		return nil, nil
	end
	nav.index = nearest
	if nearestAt <= WAYPOINT_REACHED and nav.index < #points then
		nav.index = nav.index + 1
	end

	local pick = nav.index
	for i = nav.index + 1, math.min(nav.index + LOOKAHEAD_STEPS, #points) do
		if not nav.canSee(from, points[i].Position) then
			break
		end
		pick = i
	end
	return points[pick], points[nav.index]
end

-- One step of a walk. Returns true once we are standing at the goal.
function nav.walkTo(goal, standoff)
	local core = nav.bits and nav.bits.core
	local root, humanoid = core and core:Root(), core and core:Humanoid()
	if not root or not humanoid or humanoid.Health <= 0 then
		nav.direction = nil
		return false
	end

	if nav.flat(goal, root.Position) <= (standoff or 0) then
		nav.clear()
		nav.direction = nil
		return true
	end

	if not nav.goal or (goal - nav.goal).Magnitude > ROUTE_MOVED then
		nav.plan(goal)
	end

	local aim, next_ = nav.lookAhead(root.Position)
	local target = aim and aim.Position or goal

	-- Jump waypoints have to be acted on as they come up, or the character runs
	-- at a step and stands there.
	if next_ and next_.Action == Enum.PathWaypointAction.Jump then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	local flat = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
	if flat.Magnitude < 0.5 then
		nav.direction = nil
		return false
	end
	nav.direction = flat.Unit
	return false
end

-- Straight away from a position, ignoring the route entirely. Used when the
-- killer is close enough that the shortest path somewhere is the wrong idea.
function nav.away(from)
	local core = nav.bits and nav.bits.core
	local root = core and core:Root()
	if not root then
		return
	end
	local offset = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
	if offset.Magnitude < 0.5 then
		-- Standing inside them. Any direction beats none.
		offset = Vector3.new(1, 0, 0)
	end
	nav.clear()
	nav.direction = offset.Unit
end

--------------------------------------------------------------------------------
-- the coins
--------------------------------------------------------------------------------
--
-- Coins are CollectionService-tagged "CoinVisual" parts sitting under
-- Workspace.<map>.CoinContainer, and the map model is renamed every round, so
-- they are found by tag and never by path. Collection is a real touch handled
-- by the server: you walk into one and it is yours.
--
-- Two things had to be learned by watching it fail. Pathfinding answers NoPath
-- for coins on furniture, and a farm that simply takes the nearest one will
-- retry the same unreachable coin forever - it did, three times in a row on one
-- eight-stud coin. So a coin that could not be reached is put aside for a while
-- and something else is chosen.

local farm = {
	bits = nil,
	target = nil,
	since = 0,
	skip = {},
	taken = 0,
	seenCoins = nil,
	closest = math.huge,
	gainedAt = 0,
	warnedAt = 0,
	said = nil,
}

-- Weak keys, because the keys are coins and the map is rebuilt every round.
-- Two hundred coins a round against a strong table is two hundred parts a round
-- that cannot be collected, all night.
setmetatable(farm.skip, { __mode = "k" })

function farm.wire(bits)
	farm.bits = bits
end

function farm.forget()
	farm.target = nil
	farm.since = 0
	farm.closest = math.huge
	farm.gainedAt = 0
	nav.noRoute = nil
end

function farm.cap()
	local row = round.mine()
	if not row then
		return nil, nil
	end
	return tonumber(row.Coins) or 0, tonumber(row.MaxCoins) or 0
end

function farm.full()
	local have, most = farm.cap()
	return have ~= nil and most ~= nil and most > 0 and have >= most
end

-- How many coins this session has actually earned, taken off the game's own
-- tally rather than counted by us.
--
-- The first version counted a coin every time the one it was walking at
-- vanished, which is wrong in the ordinary case: eight people are running at
-- the same coins and most of the ones that vanish were somebody else's. It
-- resets to zero at the start of every round, so a fall is a new round and not
-- a loss.
function farm.count()
	local have = farm.cap()
	if have == nil then
		return
	end
	local before = farm.seenCoins
	if before ~= nil and have > before then
		farm.taken = farm.taken + (have - before)
		journal.note(("collected a coin · %d this round"):format(have))
	end
	farm.seenCoins = have
end

function farm.live()
	local out = {}
	local now = os.clock()
	for _, part in ipairs(CollectionService:GetTagged("CoinVisual")) do
		if part:IsA("BasePart") and part.Parent and not part:GetAttribute("Delete") then
			if (farm.skip[part] or 0) < now then
				out[#out + 1] = part
			end
		end
	end
	return out
end

-- The nearest coin worth the walk. Height is a filter and not a tiebreak: a
-- coin fifteen studs above the floor is on top of something, and the walk to it
-- ends against the furniture rather than at the coin.
function farm.pick(from, reach)
	local best, bestAt = nil, math.huge
	for _, part in ipairs(farm.live()) do
		local offset = part.Position - from
		if math.abs(offset.Y) <= 14 then
			local distance = offset.Magnitude
			if distance <= reach and distance < bestAt then
				best, bestAt = part, distance
			end
		end
	end
	return best, bestAt
end

-- Getting away from the killer, and it is deliberately not part of the coin
-- run any more.
--
-- It started life inside farm.tick, after the switch that turns collecting on.
-- That made a Round tab safety switch quietly depend on a Coins tab farming
-- switch: with Auto Coins off, Keep Away did nothing at all, and the control
-- read on the whole time. It also wrote the headline itself, which the stats
-- loop then overwrote a second later, so there was no way to see it working
-- either.
--
-- Now it runs first, whatever else is on, and leaves a mark behind it.
function farm.fleeing()
	return farm.fleeUntil ~= nil and os.clock() < farm.fleeUntil
end

function farm.keepAway()
	local bits = farm.bits
	if not bits then
		return false
	end
	local F, core = bits.F, bits.core
	if F.keepAway ~= true or round.murderer == bits.player.Name then
		return false
	end

	local root = core:Root()
	if not root or round.amDead() then
		return false
	end

	local at = round.killerAt()
	if not at or (at - root.Position).Magnitude > (tonumber(F.keepAwayRange) or 30) then
		return false
	end

	if not farm.fleeing() then
		journal.note(("keeping away from %s"):format(tostring(round.murderer)))
	end
	farm.fleeUntil = os.clock() + 1
	farm.forget()
	nav.away(at)
	return true
end

function farm.tick()
	local bits = farm.bits
	if not bits then
		return
	end
	local F, core = bits.F, bits.core

	if F.autoCoins ~= true then
		if farm.target then
			farm.forget()
			nav.stop()
		end
		return
	end

	local root = core:Root()
	if not root or round.amDead() then
		-- Dead players cannot pick anything up, and the lobby has no coins.
		if farm.target then
			farm.forget()
			nav.stop()
		end
		return
	end

	if farm.full() then
		if farm.target then
			farm.forget()
		end
		if F.coinsRest ~= false then
			nav.stop()
		end
		return
	end

	local target = farm.target
	if target and (not target.Parent or target:GetAttribute("Delete")) then
		-- It went. Whether we were the one who took it is not something the coin
		-- can answer - eight other people are running at the same coins - so the
		-- count comes off the game's own tally instead, in farm.count below, and
		-- this only means "stop walking at that one".
		farm.forget()
		target = nil
	end

	if target then
		local why = nil
		local gap = (target.Position - root.Position).Magnitude

		-- Closing, or at least not stalled? Then keep going, whatever the clock
		-- says. Only a walk that has stopped getting nearer is a walk to give up
		-- on, and the two coins that cost the most were a coin fifteen studs
		-- away for thirty-six seconds and one directly overhead for eighteen.
		if gap < farm.closest - 1 then
			farm.closest, farm.gainedAt = gap, os.clock()
		elseif os.clock() - farm.gainedAt > 7 then
			why = "no nearer for seven seconds"
		end

		if nav.noRoute and (nav.noRoute - target.Position).Magnitude < 1 then
			-- The route said there is no way there. Asking again in eighteen
			-- seconds will get the same answer, because the furniture has not
			-- moved.
			why = "no route to it"
		elseif os.clock() - farm.since > (tonumber(F.coinsGiveUp) or 18) then
			why = "took too long"
		end

		if why then
			-- Put it aside rather than throwing it away: a coin unreachable from
			-- this room is perfectly reachable from the top of the stairs.
			farm.skip[target] = os.clock() + 25
			journal.note("gave up on a coin · " .. why)
			farm.forget()
			target = nil
		end
	end

	if not target then
		local reach = tonumber(F.coinsRange) or 400
		local chosen = farm.pick(root.Position, reach)
		if not chosen then
			nav.stop()
			return
		end
		farm.target, farm.since = chosen, os.clock()
		farm.closest = (chosen.Position - root.Position).Magnitude
		farm.gainedAt = os.clock()
		nav.noRoute = nil
		nav.clear()
		target = chosen
	end

	-- Standoff zero, and that is the whole of one wasted round.
	--
	-- The first version asked to be walked to within two studs of a coin, the
	-- way the egg farm stands next to an egg before it asks the server for it.
	-- There is no asking here: the server holds the coin's own .Touched and the
	-- only way to collect one is to be in it. So the walk stopped two studs
	-- short, stood there until Give Up After wrote the coin off, picked the next
	-- one, and did it again - eighty seconds, a hundred and sixteen coins on the
	-- map, and zero of fifty collected.
	local arrived = nav.walkTo(target.Position, 0)

	-- Still there with nothing between us. Coins sit a little above the floor
	-- and the character's own capsule can ride over one without the parts ever
	-- meeting, so a hop is what closes it.
	if arrived or (target.Position - root.Position).Magnitude < 4 then
		if os.clock() - farm.since > 1.5 then
			local humanoid = core:Humanoid()
			if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- what gets drawn
--------------------------------------------------------------------------------
--
-- A pool built once and re-pointed, rather than instances created and destroyed
-- as people and coins come and go.
--
-- Where it is parented was measured rather than chosen, and the obvious answer
-- was wrong. PlayerGui is where the egg farm keeps its marks, so this started
-- there, and the whole ESP silently drew nothing: this game removes anything it
-- did not put in PlayerGui itself. A bare folder left there was gone inside
-- twenty seconds, every time.
--
-- So the holder is re-made whenever it disappears, wherever it is put. That is
-- worth doing even once a container is known to survive: the alternative is an
-- ESP that works until something clears it and is then off for the rest of the
-- night with the switch still reading on.

local marks = { people = {}, coins = {}, holder = nil }

-- Never PlayerGui first. Beyond the sweeping, the game's own Leaderboard script
-- kicks anyone with a PlayerGui child called "ESP", which is a reminder of how
-- closely that one container is watched.
function marks.home()
	local ok, hidden = pcall(function()
		return gethui()
	end)
	if ok and typeof(hidden) == "Instance" then
		return hidden
	end
	local fine, core = pcall(function()
		return game:GetService("CoreGui")
	end)
	if fine and core then
		return core
	end
	return Players.LocalPlayer:FindFirstChild("PlayerGui")
end

function marks.slot(parent, withHighlight)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 34)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.Parent = parent

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.TextStrokeTransparency = 0.4
	label.RichText = true
	label.Parent = billboard

	local highlight = nil
	if withHighlight then
		highlight = Instance.new("Highlight")
		highlight.FillTransparency = 0.7
		highlight.OutlineTransparency = 0.1
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Enabled = false
		highlight.Parent = parent
	end

	-- Drawn in the world rather than on the screen. A 2D line has to be
	-- re-projected every time the camera moves; a CylinderHandleAdornment is
	-- real geometry that turns with the world on its own and still draws
	-- through walls.
	local tracer = Instance.new("CylinderHandleAdornment")
	tracer.Radius = 0.05
	tracer.AlwaysOnTop = true
	tracer.ZIndex = 0
	tracer.Transparency = 0.35
	tracer.Visible = false
	tracer.Parent = parent

	return {
		billboard = billboard,
		label = label,
		highlight = highlight,
		tracer = tracer,
		target = nil,
		colour = nil,
	}
end

-- Called at the top of every drawing loop, and it costs one Parent check when
-- there is nothing to do.
--
-- The pools are rebuilt from empty rather than added to. A second call that
-- appended would leave the loops holding forty-eight slots, half of them
-- pointing at billboards inside a destroyed folder, and the count of what is
-- drawn would quietly stop meaning anything.
function marks.ensure(people, coins)
	local holder = marks.holder
	if holder and holder.Parent then
		return true
	end

	local parent = marks.home()
	if not parent then
		return false
	end

	marks.people, marks.coins = {}, {}
	local made = Instance.new("Folder")
	made.Name = "MeridianMarks"
	made.Parent = parent
	marks.holder = made

	for _ = 1, people do
		marks.people[#marks.people + 1] = marks.slot(made, true)
	end
	for _ = 1, coins do
		marks.coins[#marks.coins + 1] = marks.slot(made, true)
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
	marks.people, marks.coins = {}, {}
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

marks.colours = {
	Murderer = Color3.fromRGB(255, 82, 82),
	Sheriff = Color3.fromRGB(96, 170, 255),
	Innocent = Color3.fromRGB(226, 232, 238),
	Dead = Color3.fromRGB(120, 126, 134),
	Coin = Color3.fromRGB(255, 208, 84),
}

--------------------------------------------------------------------------------

function Module.Build(ctx)
	journal.entries = {}

	local core, tabGroup = ctx.core, ctx.TabGroup
	local F = core.Flags
	local LocalPlayer = Players.LocalPlayer

	----------------------------------------------------------------------------
	-- the game's own modules
	----------------------------------------------------------------------------
	--
	-- CurrentRoundClient is required rather than read off a remote, because it
	-- is the same instance every other client script holds: it keeps itself up
	-- to date and it exposes a BindableEvent that fires when it does.

	local Modules = ReplicatedStorage:WaitForChild("Modules")
	local CurrentRound = require(Modules:WaitForChild("CurrentRoundClient"))

	local bits = {
		F = F,
		core = core,
		player = LocalPlayer,
		M = CurrentRound,
	}
	round.wire(bits)
	nav.wire(bits)
	farm.wire(bits)

	round.refresh()

	----------------------------------------------------------------------------
	-- loops, and they are registered before a single tab exists
	----------------------------------------------------------------------------
	--
	-- That ordering is load bearing. Maclib yields while it builds elements, and
	-- a thread that has yielded spawns children with no capability to touch an
	-- Instance at all - so a loop created after the tabs runs forever and draws
	-- nothing, warning "the current thread cannot access Instance" every tick.
	-- setthreadidentity does not fix it, because capability is not identity.

	local PEOPLE_SLOTS, COIN_SLOTS = 24, 40
	marks.ensure(PEOPLE_SLOTS, COIN_SLOTS)
	core:Track(function()
		marks.clear()
	end)

	-- Names and lines move with the camera, so they are re-pointed every frame,
	-- while who is worth drawing is worked out four times a second. Those are
	-- different questions at different rates and running both at the slow one is
	-- what makes a tracer jump instead of follow.
	core:Connect(RunService.Heartbeat, function()
		local myRoot = core:Root()
		local on = myRoot ~= nil and F.espTracers == true
		for _, pool in ipairs({ marks.people, marks.coins }) do
			for _, mark in ipairs(pool) do
				local target = on and mark.target or nil
				if target and target.Parent then
					local relative = myRoot.CFrame:PointToObjectSpace(target.Position)
					local length = relative.Magnitude
					if length > 0.5 then
						mark.tracer.Adornee = myRoot
						mark.tracer.Height = length
						mark.tracer.CFrame = CFrame.lookAt(Vector3.zero, relative)
							* CFrame.new(0, 0, -length / 2)
						mark.tracer.Color3 = mark.colour or marks.colours.Innocent
						mark.tracer.Visible = true
					else
						mark.tracer.Visible = false
					end
				elseif mark.tracer.Visible then
					mark.tracer.Visible = false
					mark.tracer.Adornee = nil
				end
			end
		end
	end)

	-- The steering step. One frame later than the game's own ControlModule and
	-- in the same frame, so ours is the one that lands.
	core:Track(function()
		nav.direction = nil
		pcall(function()
			RunService:UnbindFromRenderStep("MeridianKONSteer")
		end)
	end)

	pcall(function()
		RunService:BindToRenderStep("MeridianKONSteer", Enum.RenderPriority.Input.Value + 5, function()
			local humanoid = core:Humanoid()
			if not humanoid or humanoid.Health <= 0 then
				return
			end
			if nav.direction then
				humanoid:Move(nav.direction, false)
			end
		end)
	end)

	local function roleOf(name)
		local row = round.row(name)
		if not row then
			return nil, false
		end
		return row.Role, row.Dead == true
	end

	local function wanted(name)
		local role, dead = roleOf(name)
		if not role then
			return false
		end
		if dead and F.espHideDead ~= false then
			return false
		end
		if role == "Murderer" then
			return F.espKiller ~= false
		end
		if role == "Sheriff" then
			return F.espSheriff ~= false
		end
		return F.espEveryone == true
	end

	core:Loop("people", 0.25, function()
		local myRoot = core:Root()
		if F.espKiller == false and F.espSheriff == false and F.espEveryone ~= true then
			marks.hideFrom(marks.people, 1)
			return
		end
		if not myRoot or not marks.ensure(PEOPLE_SLOTS, COIN_SLOTS) then
			marks.hideFrom(marks.people, 1)
			return
		end

		local reach = tonumber(F.espRange) or 1200
		local size = tonumber(F.espTextSize) or 16
		local slot = 0

		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer and wanted(player.Name) and slot < #marks.people then
				local model, part = round.body(player.Name)
				if model and part then
					local distance = (part.Position - myRoot.Position).Magnitude
					-- The killer is never filtered out by distance. Dying moves
					-- you to a spectator spot two thousand studs from the map,
					-- so a range that is sensible while you are playing hides
					-- the one person worth watching the moment you are not.
					if distance <= reach or round.murderer == player.Name then
						local role, dead = roleOf(player.Name)
						slot = slot + 1
						local mark = marks.people[slot]
						local colour = dead and marks.colours.Dead
							or marks.colours[role]
							or marks.colours.Innocent

						local text = ("%s · %s · %dm"):format(player.DisplayName, role, math.floor(distance))
						if dead then
							text = text .. " · out"
						end
						if F.espPerk ~= false and role == "Murderer" then
							local row = round.row(player.Name)
							local perk = row and row.Perk
							if perk and perk ~= "" then
								text = text .. " · " .. tostring(perk)
							end
						end

						mark.label.Text = text
						mark.label.TextColor3 = colour
						mark.label.TextSize = size
						mark.billboard.Adornee = part
						mark.billboard.Enabled = true
						mark.highlight.Adornee = model
						mark.highlight.FillColor = colour
						mark.highlight.OutlineColor = colour
						mark.highlight.Enabled = true
						mark.target = part
						mark.colour = colour
					end
				end
			end
		end

		marks.hideFrom(marks.people, slot + 1)
	end)

	core:Loop("coinEsp", 0.3, function()
		if F.coinEsp ~= true then
			marks.hideFrom(marks.coins, 1)
			return
		end
		local myRoot = core:Root()
		if not myRoot or not marks.ensure(PEOPLE_SLOTS, COIN_SLOTS) then
			marks.hideFrom(marks.coins, 1)
			return
		end

		-- Nearest first, and inside the same range everything else obeys.
		--
		-- Without both of those this drew forty of the two hundred coins the map
		-- accumulates over a round, chosen in whatever order the tag list came
		-- back in - which, watched from the spectator spot after dying, meant
		-- forty labels reading "Coin · 2365m" and not one of them near anybody.
		local reach = tonumber(F.espRange) or 1200
		local list = {}
		for _, part in ipairs(farm.live()) do
			local distance = (part.Position - myRoot.Position).Magnitude
			if distance <= reach then
				list[#list + 1] = { part = part, distance = distance }
			end
		end
		table.sort(list, function(a, b)
			return a.distance < b.distance
		end)

		local slot = 0
		local size = tonumber(F.espTextSize) or 16
		for _, entry in ipairs(list) do
			if slot >= #marks.coins then
				break
			end
			slot = slot + 1
			local mark = marks.coins[slot]
			local part, distance = entry.part, entry.distance
			mark.label.Text = F.coinEspDistance ~= false
					and ("Coin · %dm"):format(math.floor(distance))
				or "Coin"
			mark.label.TextColor3 = marks.colours.Coin
			mark.label.TextSize = size
			mark.billboard.Adornee = part
			mark.billboard.Enabled = true
			mark.highlight.Adornee = part
			mark.highlight.FillColor = marks.colours.Coin
			mark.highlight.OutlineColor = marks.colours.Coin
			mark.highlight.Enabled = true
			mark.target = part
			mark.colour = marks.colours.Coin
		end
		marks.hideFrom(marks.coins, slot + 1)
	end)

	-- The round table, and the two things worth saying out loud about it.
	--
	-- The server resends the whole table on any change, so this fires several
	-- times a round. `round.tag` is what makes "a new round started" different
	-- from "somebody died", and without it the killer gets named four times.
	core:Loop("round", 0.5, function()
		local live = round.refresh()
		if not live then
			farm.said = nil
			return
		end

		if F.sayKiller ~= false and round.tag ~= farm.said and round.murderer then
			farm.said = round.tag
			local row = round.row(round.murderer)
			local perk = row and row.Perk
			local mine = round.mine()
			local body = ("%s is the killer"):format(round.murderer)
			if perk and perk ~= "" then
				body = body .. (" · %s"):format(tostring(perk))
			end
			if mine and mine.Role == "Murderer" then
				body = "You are the killer"
			elseif mine and mine.Role == "Sheriff" then
				body = body .. " · you have the gun"
			end
			journal.note(body)
			core:Notify(Module.Name, body, 7)
		end
	end)

	-- One warning, not a stream of them. A killer who walks past you twice is
	-- one event to a person and two hundred to a loop.
	core:Loop("warn", 0.4, function()
		if F.warnClose == false then
			return
		end
		local root = core:Root()
		local at = round.killerAt()
		if not root or not at or round.murderer == LocalPlayer.Name then
			return
		end
		local distance = (at - root.Position).Magnitude
		local within = tonumber(F.keepAwayRange) or 30
		if distance <= within then
			if os.clock() - farm.warnedAt > 12 then
				farm.warnedAt = os.clock()
				journal.note(("killer within %d studs"):format(math.floor(distance)))
				core:Notify(Module.Name, ("%s is %d studs away"):format(
					tostring(round.murderer), math.floor(distance)), 4)
			end
		elseif distance > within * 2 then
			-- Away again. The next approach is allowed to speak immediately.
			farm.warnedAt = 0
		end
	end)

	core:Loop("coins", 0.15, function()
		-- Getting away wins over collecting, always, and it has to be able to
		-- win on a tick where collecting is switched off entirely.
		if farm.keepAway() then
			return
		end
		farm.tick()
	end)

	core:Loop("stats", 1, function()
		farm.count()
		local carried = core.Stats or {}
		local have, most = farm.cap()
		carried.Hits = farm.taken
		carried.Total = have or 0
		carried.Holding = (have and most and most > 0)
				and ("%d of %d this round"):format(have, most)
			or "waiting for a round"
		core.Stats = carried

		-- One writer for the headline. It used to have two, and the loop that
		-- ran seven times a second lost every time to the one that ran once.
		if not round.tag then
			core.Headline = "In the lobby"
		elseif round.amDead() then
			core.Headline = "Out this round"
		elseif farm.fleeing() then
			core.Headline = "Getting away from " .. tostring(round.murderer)
		elseif F.autoCoins == true and farm.full() then
			core.Headline = "Every coin this round will give"
		elseif farm.target then
			core.Headline = ("Coin · %d studs away"):format(
				math.floor(nav.flat(farm.target.Position, (core:Root() or {}).Position or Vector3.zero)))
		elseif round.murderer then
			core.Headline = round.murderer .. " is the killer"
		else
			core.Headline = nil
		end
	end)

	-- Published so the hub can be asked what it thinks while it is running,
	-- rather than only after something has already gone wrong. The headline
	-- said "Out this round" for twelve seconds after the character was alive
	-- again, and there was no way to see whose view of the round was stale
	-- without this.
	core.Journal = journal
	core.Round = round
	core.Farm = farm

	----------------------------------------------------------------------------
	-- anti AFK
	----------------------------------------------------------------------------
	--
	-- Disabling the Idled connections is quieter than pretending to click:
	-- VirtualUser is a CoreScript API, and a normal script reaching for it every
	-- twenty minutes all night is a loud thing to be doing.
	--
	-- But it only goes one way, and the switch used to pretend otherwise.
	-- Measured here: this game has exactly one Idled handler, it is a native
	-- connection rather than a Luau one (LuaConnection false, Function nil), and
	-- Real's `connection:Enable()` returns perfectly happily on those and leaves
	-- Enabled false. Off, off, off, three times in a row, with the toggle
	-- reading whatever the user had just clicked.
	--
	-- So the switch does what it can and says what it cannot, rather than
	-- showing a state the client is not in.
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

	local roundTab = tabGroup:Tab({ Name = "Round", Image = "rbxassetid://10747373176" })
	local coinsTab = tabGroup:Tab({ Name = "Coins", Image = "rbxassetid://10723415903" })
	local playerTab = tabGroup:Tab({ Name = "Player", Image = "rbxassetid://10734898355" })

	local roundLeft = roundTab:Section({ Side = "Left" })
	local roundRight = roundTab:Section({ Side = "Right" })
	local coinsLeft = coinsTab:Section({ Side = "Left" })
	local coinsRight = coinsTab:Section({ Side = "Right" })
	local playerLeft = playerTab:Section({ Side = "Left" })

	--------------------------------------------------------------- round · left

	roundLeft:Header({ Text = "The Killer" })

	roundLeft:Toggle({
		Name = "Show The Killer",
		Default = true,
		Callback = function(state)
			F.espKiller = state
		end,
	}, "espKiller")

	roundLeft:Toggle({
		Name = "Show Their Perk",
		Default = true,
		Callback = function(state)
			F.espPerk = state
		end,
	}, "espPerk")

	roundLeft:Toggle({
		Name = "Say Who It Is",
		Default = true,
		Callback = function(state)
			F.sayKiller = state
		end,
	}, "sayKiller")

	roundLeft:Toggle({
		Name = "Warn When They Are Close",
		Default = true,
		Callback = function(state)
			F.warnClose = state
		end,
	}, "warnClose")

	roundLeft:Divider()

	roundLeft:Toggle({
		Name = "Keep Away",
		Default = false,
		Callback = function(state)
			F.keepAway = state
			if not state then
				nav.stop()
			end
		end,
	}, "keepAway")

	roundLeft:Slider({
		Name = "Keep Away Within",
		Default = 30,
		Minimum = 10,
		Maximum = 90,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.keepAwayRange = value
		end,
	}, "keepAwayRange")

	-------------------------------------------------------------- round · right

	roundRight:Header({ Text = "Everybody Else" })

	roundRight:Toggle({
		Name = "Show The Sheriff",
		Default = true,
		Callback = function(state)
			F.espSheriff = state
		end,
	}, "espSheriff")

	roundRight:Toggle({
		Name = "Show Everyone Else",
		Default = false,
		Callback = function(state)
			F.espEveryone = state
		end,
	}, "espEveryone")

	roundRight:Toggle({
		Name = "Hide The Dead",
		Default = true,
		Callback = function(state)
			F.espHideDead = state
		end,
	}, "espHideDead")

	roundRight:Toggle({
		Name = "Tracers",
		Default = false,
		Callback = function(state)
			F.espTracers = state
		end,
	}, "espTracers")

	roundRight:Slider({
		Name = "How Far To Look",
		Default = 1200,
		Minimum = 100,
		Maximum = 3000,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.espRange = value
		end,
	}, "espRange")

	roundRight:Slider({
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

	--------------------------------------------------------------- coins · left

	coinsLeft:Header({ Text = "Collect" })

	coinsLeft:Toggle({
		Name = "Auto Coins",
		Default = false,
		Callback = function(state)
			F.autoCoins = state
			if not state then
				farm.forget()
				nav.stop()
			end
		end,
	}, "autoCoins")

	coinsLeft:Toggle({
		Name = "Rest When Full",
		Default = true,
		Callback = function(state)
			F.coinsRest = state
		end,
	}, "coinsRest")

	coinsLeft:Slider({
		Name = "How Far For A Coin",
		Default = 400,
		Minimum = 50,
		Maximum = 1500,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.coinsRange = value
		end,
	}, "coinsRange")

	coinsLeft:Slider({
		Name = "Give Up After",
		Default = 18,
		Minimum = 5,
		Maximum = 60,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.coinsGiveUp = value
		end,
	}, "coinsGiveUp")

	-------------------------------------------------------------- coins · right

	coinsRight:Header({ Text = "See Them" })

	coinsRight:Toggle({
		Name = "Show Coins",
		Default = false,
		Callback = function(state)
			F.coinEsp = state
		end,
	}, "coinEsp")

	coinsRight:Toggle({
		Name = "Show How Far",
		Default = true,
		Callback = function(state)
			F.coinEspDistance = state
		end,
	}, "coinEspDistance")

	-------------------------------------------------------------- player · left

	playerLeft:Header({ Text = "Session" })

	playerLeft:Toggle({
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

	-- Every slider and dropdown default, copied into the flags now that the
	-- controls exist. Nothing here yields, which Build may not do.
	seeded.apply(core)

	-- main.luau selects the default tab itself, after the chrome is on. Doing it
	-- from in here runs the tab transition before the window is finished.
	return {
		Tabs = {
			Round = roundTab,
			Coins = coinsTab,
			Player = playerTab,
		},
		Default = roundTab,
		Tips = Module.Tips,
	}
end

return Module
