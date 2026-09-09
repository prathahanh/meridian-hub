--// Meridian · Clean All The Leaves
--// universe 10539411000
--//
--// Two places share this module and only one of them is the game. The lobby
--// (92637789841354) picks a map, picks a difficulty and spends diamonds on the
--// upgrades you keep. Every map is a place of its own, and that is where
--// leaves, bags, dumpsters, vents and cash live. So a switch here asks which of
--// the two rooms it is standing in before it does anything, and the ones that
--// cannot work where you are say so instead of failing quietly.
--//
--// Three numbers in here were measured on a live client rather than guessed,
--// and each one changes what the farm is allowed to do.
--//
--// 1. A collect is accepted out to 32 studs and SILENTLY IGNORED past it. No
--//    refusal, no CollectDenied, the leaf simply stays. 28.8 and 30.9 banked;
--//    32.7, 34.2, 37.0, 38.8 and 40.5 did nothing at all. A farm reaching
--//    further looks perfectly healthy in its own log and banks nothing.
--//
--// 2. WalkSpeed is writable here and the server leaves it alone - set to 40 it
--//    was still 40 two seconds later. That is unusual for this kind of game and
--//    it is why there is a speed slider at all.
--//
--// 3. The game re-locks the cursor to the centre every frame, so freeing it
--//    once does nothing. The override has to run for as long as the menu is
--//    open, which is what Free Cursor does.
--//
--// The endpoints that are NOT here matter as much as the ones that are.
--// AutoCollect, AutoSell, AutoBuy, AutoVent, AutoWin, UnlockAllVents, SetCash
--// and GiveCash all exist in the Remotes folder and NOTHING in the game's own
--// client calls any of them - checked across all 165 decompiled client scripts.
--// There is no payload to copy and no way to know what the server does with
--// one, so there is no switch for them. Every other hub for this game ships an
--// "Auto Win"; this one will not ship a button whose only honest description is
--// "fires an unknown remote and hopes".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Module = {
	GameId = 10539411000,
	Name = "Clean All The Leaves",
}

-- Hover text. One line each, written for somebody who has never seen the code.
-- No mechanisms, and no number appears unless it is one you would actually set.
Module.Tips = {
	["Auto Clean"] = "Picks up every leaf it can reach, walks to the next pile when it runs out, and sells when the bag is full.",
	["Pick By"] = "Nearest clears the ground under you fastest. Biggest Pile walks to where the leaves actually are. Worth Most goes for the rare ones first.",
	["Reach"] = "How far it will grab from. The game stops accepting a grab a little past thirty, so the top of this slider is the real ceiling.",
	["Sell When Full"] = "Carries a full bag to the dumpster and empties it, then goes back to the leaves.",
	["Sell At"] = "How full the bag has to be before it is worth the walk. Below a hundred it leaves early, which pays when the dumpster is far.",
	["Stay Within"] = "How far it will wander from where you switched it on. Turn it up to clear a whole zone, down to work one corner.",
	["Unstick Me"] = "If it stops getting anywhere it lifts you clear, forgets the leaf it was heading for and picks another. It is what gets you out when you end up inside the scenery.",
	["Travel"] = "How it gets to the next pile. Walk is what a player does. Hop skips there in short steps. Teleport goes straight there and is by far the fastest, and by far the most obvious to anyone watching.",
	["Walk Speed"] = "How fast you move. This game lets you set it, which most do not.",
	["Free Cursor"] = "Gives you the mouse back whenever the menu is open, so you can actually click things. The game grabs it back every frame, so this has to keep taking it.",
	["Hands Off While Menu Is Open"] = "Stops the farm steering you while you have the menu up, so you can move yourself without fighting it.",
	["Everything Off"] = "Kills every switch at once and gives you back your controls and your mouse. Works even if something is stuck.",
	["Stop Everything"] = "The same as the panic key, for when you would rather click it.",
	["Auto Bag"] = "Buys the next bag size the moment you can afford it. This is the upgrade that decides how much of a run is walking.",
	["Auto Buy Tools"] = "Buys the rake and the leaf blower with run cash as soon as each is affordable.",
	["Auto Tool Upgrades"] = "Spends spare cash upgrading the tool you are actually using, cheapest first.",
	["Upgrade Which"] = "Which tool gets the spare cash.",
	["Auto Vents"] = "Opens the next vent as soon as it is affordable. A vent is how a zone gets cleared.",
	["Auto Start Run"] = "From the lobby, walks to a square and starts a run on its own.",
	["Map"] = "Which map to run. The later ones need the one before it cleared on Easy first.",
	["Difficulty"] = "Harder maps pay more diamonds and give you less time.",
	["Solo"] = "Starts the run with just you in it instead of waiting for a squad.",
	["Auto Diamond Upgrades"] = "Spends diamonds in the lobby on the upgrades you keep between runs.",
	["Buy Order"] = "Which lobby upgrade gets your diamonds first.",
	["Auto Class Spin"] = "Spins for a new class whenever you have the diamonds spare. Handy Man is the one worth chasing.",
	["Anti AFK"] = "Stops Roblox idling you out of a long run.",
}

--------------------------------------------------------------------------------
-- file scope
--------------------------------------------------------------------------------
--
-- Build is one function against Luau's ceiling of 200 local registers and this
-- game reaches it, so every feature past the first few lives out here on a
-- table and is handed what it needs once through a wire. That costs nothing
-- inside Build. ./check.sh catches the ceiling; luau-analyze does not.

local journal = { keep = 40, entries = {} }

function journal.note(what)
	local list = journal.entries
	list[#list + 1] = { at = os.clock(), what = what }
	while #list > journal.keep do
		table.remove(list, 1)
	end
end

-- Maclib does not fire ANY control's callback for its own declared default, and
-- that includes Toggles. This was watched happening rather than reasoned about:
-- Auto Bag, Auto Rake, Auto Vents and Sell When Full all shipped Default = true,
-- all drew as on, and all four flags read nil for a hundred and eight seconds of
-- live farming while cash climbed past the price of a bag upgrade and nothing
-- bought it. A switch drawn as on that behaves as off is the worst kind of bug
-- in a hub, because the person judging it is reading the interface.
--
-- The reference module seeds only Sliders and Dropdowns, which is why this had
-- to be found again here.
local seeded = {}

function seeded.apply(core)
	local flags = core.Flags
	for _, entry in ipairs(core.Controls or {}) do
		local flag = entry.flag or entry.Flag
		local kind = entry.kind or entry.Kind
		if flag and flags[flag] == nil
			and (kind == "Slider" or kind == "Dropdown" or kind == "Toggle")
		then
			local settings = entry.control and entry.control.Settings
			-- Not `... and settings.Default or nil`: that idiom turns a
			-- perfectly good `false` into nil, which is how every toggle
			-- declaring Default = false ends up unseeded.
			local default = nil
			if type(settings) == "table" then
				default = settings.Default
			end
			local value = nil
			if kind == "Slider" then
				value = tonumber(default)
			elseif kind == "Toggle" then
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
-- getting out of the way
--------------------------------------------------------------------------------
--
-- This section exists because of one sentence: "bro wait i cant even MOVE".
--
-- A farm that walks for you has to hold your controls, and this one held them
-- while the menu was open and kept holding them after the farm was switched
-- off. Both are now impossible. Three separate things guarantee it, because the
-- one that matters is whichever still works when something else is stuck.

local guard = { bits = nil, toggles = {}, cursorOn = false }

function guard.wire(bits)
	guard.bits = bits
end

-- Remember every toggle so the panic can put them all back to off *visibly*,
-- not just clear the flags behind a control that still reads on.
function guard.watch(flag, control)
	guard.toggles[flag] = control
end

function guard.menuOpen()
	local window = guard.bits and guard.bits.window
	if not window then
		return false
	end
	local ok, state = pcall(window.GetState, window)
	if ok then
		return state == true
	end
	return false
end

-- May the farm steer right now?
function guard.mayDrive()
	local F = guard.bits.F
	if F.leafHandsOff ~= false and guard.menuOpen() then
		return false
	end
	return true
end

-- The game writes MouseBehavior every frame, so freeing the cursor once does
-- nothing at all - measured: set to Default, and it was LockCenter again a
-- second and a half later. So this runs on RenderStepped and only while the
-- menu is actually open, because taking the mouse off somebody who is playing
-- would be its own bug.
function guard.cursorTick()
	local F = guard.bits.F
	local want = F.leafFreeCursor ~= false and guard.menuOpen()
	if want then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		guard.cursorOn = true
	elseif guard.cursorOn then
		-- Hand it back exactly once, then leave the game alone.
		guard.cursorOn = false
	end
end

-- Everything off, controls returned, mouse returned. This has to work when the
-- farm is mid-walk, mid-sell and holding the control module, so it does not ask
-- anything politely: it clears the flags, puts every toggle back to off on
-- screen, stops the loops that steer, and hands the legs back.
function guard.panic(quiet)
	local bits = guard.bits
	if not bits then
		return
	end
	local core, F = bits.core, bits.F
	for flag, control in pairs(guard.toggles) do
		F[flag] = false
		pcall(function()
			control:UpdateState(false)
		end)
	end
	pcall(function()
		core:SetControls(true)
	end)
	pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)
	local hum = core:Humanoid()
	if hum then
		pcall(function()
			hum.AutoRotate = true
			hum:Move(Vector3.zero, false)
		end)
	end
	journal.note("panic")
	if not quiet then
		core:Notify(Module.Name, "Everything off. You have your controls back.", 5)
	end
end

--------------------------------------------------------------------------------
-- reading the map
--------------------------------------------------------------------------------

-- Measured, not chosen. See the header. The slider tops out here because past
-- it the server stops answering without saying so.
local REACH_MAX = 30

-- Height is checked separately from distance, because the server checks it
-- separately. Two leaves 18.9 studs away, one 2.9 below and one 14.5 below:
-- the first banked, the second was ignored without a word. Eight is inside the
-- one that worked and well short of the one that did not.
local VERT = 8

local look = { sim = nil, simAt = 0, near = {}, scanAt = 0, best = nil }

-- The game's own client wrapper, which is why this module never has to guess at
-- a payload. LeafSim stamps each leaf with the epoch the server handed out and
-- fires CollectLeaf itself, so collecting is its collectMany and never a remote
-- call written here. It only exists in a map place, so a nil answer is also how
-- the rest of this file knows it is standing in the lobby.
function look.module()
	if look.sim then
		return look.sim
	end
	if os.clock() - look.simAt < 2 then
		return nil
	end
	look.simAt = os.clock()
	local player = Players.LocalPlayer
	local scripts = player and player:FindFirstChild("PlayerScripts")
	local mod = scripts and scripts:FindFirstChild("LeafSim")
	if not mod or not mod:IsA("ModuleScript") then
		return nil
	end
	local ok, value = pcall(require, mod)
	if ok and type(value) == "table" and type(value.collectMany) == "function" then
		look.sim = value
		return value
	end
	return nil
end

function look.inMap()
	return look.module() ~= nil
end

function look.value(sim, part)
	local ok, v = pcall(sim.leafValueOfPart, part)
	return (ok and tonumber(v)) or 1
end

-- One pass over the leaf folder, at most once a second.
--
-- A map holds upwards of thirteen thousand leaf parts and the farm ticks ten
-- times a second, so scanning every tick is a hundred and thirty thousand
-- distance tests a second for an answer that barely moves. Leaves do not run
-- away. The same pass also finds the thickest patch, because walking to where
-- the leaves are is worth far more than shaving a stud off the nearest one.
function look.scan(sim, root, anchor, wander)
	if os.clock() - look.scanAt < 1 then
		return look.near
	end
	look.scanAt = os.clock()

	local found, cells = {}, {}
	local bestCell, bestCount = nil, 0
	for _, part in ipairs(sim.folder:GetChildren()) do
		if part:IsA("BasePart") then
			local at = part.Position
			if (at - anchor).Magnitude <= wander then
				local off = at - root
				found[#found + 1] = {
					part = part,
					d = off.Magnitude,
					flat = Vector2.new(off.X, off.Z).Magnitude,
					dy = off.Y,
					v = look.value(sim, part),
				}
				-- Sixty-stud buckets, so a "pile" is about two reaches across
				-- and standing in the middle of one is worth the walk.
				local key = ("%d:%d"):format(math.floor(at.X / 60), math.floor(at.Z / 60))
				local cell = cells[key]
				if not cell then
					cell = { n = 0, x = 0, z = 0, y = at.Y }
					cells[key] = cell
				end
				cell.n = cell.n + 1
				cell.x = cell.x + at.X
				cell.z = cell.z + at.Z
				if cell.n > bestCount then
					bestCount, bestCell = cell.n, cell
				end
			end
		end
	end

	table.sort(found, function(a, b)
		return a.d < b.d
	end)
	-- Only the front of the list is ever used, and holding thirteen thousand
	-- entries alive between ticks shows up as frame time rather than as a bug.
	while #found > 100 do
		table.remove(found)
	end
	look.near = found
	look.best = bestCell and bestCount >= 8
		and Vector3.new(bestCell.x / bestCell.n, bestCell.y, bestCell.z / bestCell.n)
		or nil
	return found
end

-- Which leaf to walk at, given what the user asked for. `bad` is the set the
-- farm has already fired at and watched do nothing, so it does not walk back to
-- the spot it just gave up on.
function look.target(mode, bad)
	local list = look.near
	if #list == 0 then
		return nil
	end
	-- A leaf almost directly below you through a floor is not somewhere you can
	-- walk to. Its flat distance is already inside any standoff, so the walker
	-- reports "arrived" the instant it is asked and the farm stands there
	-- calling it nine times a second for ever - watched doing exactly that, 86
	-- walk calls in ten seconds and 0.0 studs of movement, with a thousand
	-- perfectly good leaves at its own level. Walking only helps when there is
	-- ground to cover.
	local function reachableByWalking(entry)
		return math.abs(entry.dy) <= VERT or entry.flat >= 15
	end

	local best, fallback = nil, nil
	for _, entry in ipairs(list) do
		if entry.part.Parent and not (bad and bad[entry.part]) then
			fallback = fallback or entry
		end
		if entry.part.Parent and not (bad and bad[entry.part]) and reachableByWalking(entry) then
			if mode == "Worth Most" then
				-- Value first, distance only as the tie-break. The rare leaves
				-- are worth five ordinary ones and there are about five of them
				-- in four thousand, so one is worth crossing a pile for.
				if not best or entry.v > best.v then
					best = entry
				end
			else
				-- The list is already sorted nearest first.
				return entry
			end
		end
	end
	return best or fallback
end

--------------------------------------------------------------------------------
-- the farm
--------------------------------------------------------------------------------

local SELL_TRY = 14

local farm = {
	bits = nil,
	nextGrab = 0,
	anchor = nil,
	sellTries = 0,
	badDump = {},
	stuckAt = nil,
	stuckSince = 0,
	working = 0,
	miss = 0,
	missAt = 0,
	bad = {},
	pending = nil,
	pendingBag = 0,
	movedFrom = nil,
}

function farm.wire(bits)
	farm.bits = bits
end

function farm.bag()
	local player = Players.LocalPlayer
	local held = tonumber(player:GetAttribute("Leaves")) or 0
	local cap = tonumber(player:GetAttribute("LeafCapacity")) or 25
	local endless = player:GetAttribute("InfiniteBag") == true
		or player:GetAttribute("OwnsInfiniteBag") == true
	return held, cap, endless
end

function farm.grabSize(sim)
	local ok, extra = pcall(sim.upgEffect, "Hand", "Hold")
	return 1 + ((ok and tonumber(extra)) or 0)
end

function farm.cooldown(sim)
	local ok, seconds = pcall(sim.upgEffect, "Hand", "Dexterity")
	return (ok and tonumber(seconds)) or 0.5
end

-- The nearest dumpster that has not already refused us.
--
-- Nearest alone is wrong, and the game says so out loud: "Unlock the Backyard
-- first to sell here!". A map's dumpsters sit in zones, a zone you have not
-- opened will not take your leaves, and the farm cannot know which is which
-- from the outside. It does not need to - it can notice. A dumpster that takes
-- a full bag and does nothing gets struck off and the next nearest is tried.
function farm.dumpster(from)
	local map = Workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Dumpsters")
	if not folder then
		return nil, nil
	end
	local best, bestModel, bestAway = nil, nil, math.huge
	for _, model in ipairs(folder:GetChildren()) do
		local ok, pivot = pcall(function()
			return model:GetPivot()
		end)
		if ok and not farm.badDump[model] then
			local away = (pivot.Position - from).Magnitude
			if away < bestAway then
				best, bestModel, bestAway = pivot.Position, model, away
			end
		end
	end
	if not best then
		-- Every one of them has refused. They cannot all be locked, so the
		-- reason was something else and the list is worth forgetting.
		farm.badDump = {}
	end
	return best, bestModel
end

-- One step of the trip home. Returns true while it still wants the legs.
--
-- The trip and the attempt are deliberately separate, and that is not tidiness.
-- A dumpster is a solid model whose pivot sits inside it, so a standoff tighter
-- than the model is a deadlock: the character walks up, stops against the side
-- about ten studs from the pivot, cannot close the gap through solid geometry,
-- and a walker that only sells once it reports "arrived" therefore never sells.
-- Watched happening: the bag sat at 75/75 for ninety seconds, five studs from
-- where it had sold successfully a minute earlier, while an EmptyBackpack fired
-- by hand from that exact spot emptied it 75 -> 4.
--
-- EmptyBackpack is a RemoteEvent and answers nothing, so "did it work" cannot be
-- asked, only observed. The bag going down is the only truth available.
function farm.sell(mayWalk)
	local bits = farm.bits
	local root = bits.core:Root()
	if not root then
		return false
	end
	local where, model = farm.dumpster(root.Position)
	if not where then
		bits.sayOnce("dump", "No dumpster here", "Nothing on this map takes a full bag, so selling is off.")
		return false
	end

	local off = where - root.Position
	local flat = Vector3.new(off.X, 0, off.Z).Magnitude
	local touching = Players.LocalPlayer:GetAttribute("HoveringDumpster") == true

	-- Height matters here too, and for a reason worth writing down: on Teleport
	-- the farm landed ON TOP of the dumpster - 3.4 studs away and 3.4 studs
	-- above it - where HoveringDumpster stays false and the server refuses
	-- every sell in silence. Six fired, nothing banked, bag stuck at 500.
	--
	-- So the last approach always walks, whatever Travel is set to. Dropping
	-- onto the lid is not being at the dumpster.
	if not touching and (flat > SELL_TRY or math.abs(off.Y) > 6) then
		if mayWalk then
			bits.core:WalkToward(where, 6, tonumber(bits.F.leafSpeed) or 24)
		end
		farm.sellTries = 0
		return true
	end

	-- Close enough to be worth asking. Keep pressing in while asking, since
	-- nearer is only ever better and standing still is what made the deadlock.
	if mayWalk then
		bits.core:WalkToward(where, 6, 20)
	end
	-- Standing on the lid is a place walking cannot leave: the flat distance to
	-- the dumpster is nearly zero, so the walker reports it has arrived and
	-- never moves, while the server refuses every sell because you are not
	-- beside the thing, you are on it. Step off deliberately.
	if not touching and farm.sellTries >= 3 then
		farm.sellTries = 0
		pcall(function()
			root.CFrame = CFrame.new(where + Vector3.new(9, 3, 0))
		end)
		return true
	end

	if not bits.due("empty", 1.5) then
		return true
	end

	local before = tonumber(Players.LocalPlayer:GetAttribute("Leaves")) or 0
	bits.ask("EmptyBackpack")
	farm.sellTries = farm.sellTries + 1
	if before > 0 and farm.sellTries >= 6 then
		farm.sellTries = 0
		if model then
			farm.badDump[model] = true
			journal.note("dumpster refused, trying another")
		else
			bits.refused("empty", 1.5)
			bits.sayOnce("empty", "Could not empty the bag",
				"No dumpster on this map is taking it.")
		end
	end
	return true
end

-- Standing still while under orders is the one thing that ends a night quietly,
-- so it gets noticed and acted on rather than logged.
--
-- Standing still on purpose is a different thing entirely: emptying the pile
-- you are standing in means not moving for as long as it takes, and a watcher
-- that cannot tell the two apart makes the farm jump every five seconds while
-- it works. So collecting stamps `working`, and this only counts the seconds
-- since the last thing it actually did.
function farm.stuck(root)
	if farm.bits.F.leafUnstick == false then
		return false
	end
	if os.clock() - farm.working < 3 then
		farm.stuckAt = nil
		return false
	end
	local here = root.Position
	if not farm.stuckAt or (here - farm.stuckAt).Magnitude > 4 then
		farm.stuckAt, farm.stuckSince = here, os.clock()
		return false
	end
	if os.clock() - farm.stuckSince < 5 then
		return false
	end
	farm.stuckAt, farm.stuckSince = here, os.clock()

	-- A jump does not free a character that is inside the scenery, and this one
	-- was: it walked under the porch and ended up embedded in the beams, where
	-- WalkToward, MoveTo and even Humanoid:Move all did precisely nothing and
	-- reported nothing. Lifting it straight up is the only thing that works,
	-- and this game allows it - a 25 stud lift and a 120 stud sideways move
	-- both held, with no reset and no complaint.
	pcall(function()
		root.CFrame = root.CFrame + Vector3.new(0, 12, 0)
	end)
	local hum = farm.bits.core:Humanoid()
	if hum then
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end)
	end
	-- Forget the patch it was walking at, so it picks somewhere else next tick.
	look.scanAt = 0
	look.best = nil
	journal.note("unstick")
	return true
end

-- Getting to a place, in whichever of the three ways the user has asked for.
--
-- Walking is what a player does and it is the default. The other two exist
-- because this game does not police position at all: a 120 stud jump held with
-- no reset, no rubber-band and no kick. Hop moves in short steps, which is what
-- most of this hub uses elsewhere; Teleport goes straight there and is the
-- fastest thing in the file by a distance.
function farm.travel(core, goal, standoff, speed)
	local mode = tostring(farm.bits.F.leafTravel or "Walk")
	if mode == "Teleport" then
		if not farm.bits.due("hop", 0.35) then
			return false
		end
		local root = core:Root()
		if root then
			pcall(function()
				root.CFrame = CFrame.new(goal + Vector3.new(0, 4, 0))
			end)
		end
		return true
	end
	if mode == "Hop" then
		if not farm.bits.due("hop", 0.35) then
			return false
		end
		return core:BlinkTo(goal, standoff, 40, 60)
	end
	return core:WalkToward(goal, standoff, speed)
end

-- One step per call, never two, and every step behind a gate.
function farm.tick()
	local bits = farm.bits
	if not bits or bits.F.autoClean ~= true then
		return false
	end
	local sim = look.module()
	if not sim then
		return false
	end
	local core = bits.core
	if not core:Alive2() then
		farm.anchor = nil
		return false
	end
	local root = core:Root()
	if not root then
		return false
	end

	-- The menu being open means the person is using it, so the farm does not
	-- get the legs. It does still get to pick up what is already within arm's
	-- reach, because that takes nothing away from them.
	--
	-- The first version of this stopped the whole farm while the menu was open,
	-- which reads fine and is useless: the menu is open at the moment you
	-- switch anything on, so Auto Clean appeared to do nothing until you closed
	-- the window. Every walk site asks this instead.
	local mayWalk = guard.mayDrive()
	if not mayWalk then
		core:SetControls(true)
	end
	if not farm.anchor then
		farm.anchor = root.Position
	end

	local hum = core:Humanoid()
	local speed = tonumber(bits.F.leafSpeed) or 16
	if hum and speed > 0 and math.abs(hum.WalkSpeed - speed) > 0.5 then
		-- Writable here, and it stays written. Checked: set 40, still 40 two
		-- seconds later.
		hum.WalkSpeed = speed
	end

	farm.stuck(root)

	-- Full bag first. Nothing else matters until it is empty again, and the game
	-- says how full it is rather than it being counted here.
	local held, cap, endless = farm.bag()
	local at = (tonumber(bits.F.leafSellAt) or 100) / 100
	if not endless and bits.F.leafSell ~= false and held >= math.max(1, math.floor(cap * at)) then
		return farm.sell(mayWalk)
	end
	farm.sellTries = 0

	local wander = tonumber(bits.F.leafWander) or 250
	local list = look.scan(sim, root.Position, farm.anchor, wander)
	if #list == 0 then
		-- Nothing left inside the leash. Say so once rather than stand there.
		bits.sayOnce("empty-area", "Nothing left to clean here",
			"Everything inside Stay Within is gone. Turn it up or move.")
		return false
	end

	local reach = math.clamp(tonumber(bits.F.leafReach) or REACH_MAX, 4, REACH_MAX)
	local mode = tostring(bits.F.leafPick or "Nearest")

	-- There is no rake switch here, and that is a decision rather than an
	-- omission. The rake sweeps a patch at once, which sounds strictly better
	-- than one leaf at a time, and measured against the hand it lost every
	-- time: it reaches nine studs where the hand reaches thirty, so holding the
	-- farm close enough to sweep meant it spent the run travelling and banked
	-- nothing, and left opportunistic it never fired once in four trials
	-- because the hand had already cleared everything underfoot. A switch that
	-- never fires is the thing LAUNCH.md says to take out.
	local walkTo = reach

	-- Grab first, walk second, and never the other way round.
	--
	-- The obvious shape - decide on a target, walk until you have arrived, then
	-- collect - deadlocks in this game, and it took a hook on both calls to see
	-- it. This module measured the distance to the leaf in three dimensions and
	-- decided 18.9 studs was too far to grab; Core:WalkToward measures the
	-- ground it has to cover, which is flat X and Z, and decided 12.05 studs
	-- was inside its standoff and it had arrived. Both were right and both were
	-- stable, so the farm stood on a ledge fourteen studs above a leaf calling
	-- WalkToward nine times a second, moving nowhere, collecting nothing, with
	-- six hundred and fifty-nine leaves inside its own reach the whole time.
	--
	-- Asking "is anything in reach" first cannot deadlock, because it is the
	-- same question the collect itself answers.
	-- Did the last grab actually land?
	--
	-- It has to be asked, because the server never says. Two leaves at exactly
	-- the same distance behaved differently - 3d 18.9 both, one 2.9 studs below
	-- and one 14.5 studs below - and only the near-level one banked. So the
	-- reach is not a sphere: something about the drop, a floor or a line of
	-- sight, is also being checked, and the refusal is silence either way.
	--
	-- Rather than reverse-engineer that geometry from two samples, the farm
	-- watches its own bag. A grab that does not move it is written off, the
	-- leaves it was aimed at are struck off, and after a few in a row it stops
	-- reaching from where it is standing and goes somewhere else.
	if farm.pending then
		if held > farm.pendingBag then
			farm.miss = 0
		else
			farm.miss = farm.miss + 1
			farm.missAt = os.clock()
			for _, part in ipairs(farm.pending) do
				farm.bad[part] = true
			end
		end
		farm.pending = nil
	end

	-- The write-off has to expire on its own, or it becomes the deadlock it was
	-- meant to prevent. It did: three misses stopped the farm reaching, and the
	-- only thing that cleared them was walking twenty-five studs, which a farm
	-- standing in the middle of a pile has no reason to do. Everything stopped
	-- and nothing said why.
	if farm.miss >= 3 and os.clock() - (farm.missAt or 0) > 10 then
		farm.miss = 0
		farm.bad = {}
	end

	local room = endless and 40 or math.max(0, cap - held)
	local batch, want = {}, math.min(farm.grabSize(sim), math.max(room, 0))
	if room > 0 and farm.miss < 3 then
		for _, entry in ipairs(list) do
			if #batch >= want then
				break
			end
			local off = entry.part.Position - root.Position
			-- Height is its own test, not part of the distance one.
			if entry.part.Parent == sim.folder
				and not farm.bad[entry.part]
				and math.abs(off.Y) <= VERT
				and off.Magnitude <= reach
			then
				batch[#batch + 1] = entry.part
			end
		end
	end

	if #batch > 0 then
		-- Standing still on purpose while the pile under us empties is not
		-- being stuck, so the watcher is told the legs are not wanted.
		farm.working = os.clock()
		if os.clock() < farm.nextGrab then
			return true
		end
		pcall(sim.collectMany, batch)
		farm.pending, farm.pendingBag = batch, held
		farm.nextGrab = os.clock() + math.max(farm.cooldown(sim), 0.1)
		-- The list is stale the moment a grab lands, and reusing it is how a
		-- farm ends up reaching for leaves already in its own bag.
		look.scanAt = 0
		return true
	end

	-- Nothing in reach, so go somewhere there is something. Walk to the
	-- thickest patch rather than the closest single leaf: clearing where the
	-- leaves actually are beats shaving a stud off the walk.
	local target = look.target(mode, farm.bad)
	if not target or not target.part.Parent then
		look.scanAt = 0
		return false
	end
	if not mayWalk then
		return false
	end

	-- Having moved is what makes a spot worth trying again, so the write-offs
	-- are forgiven on arrival somewhere new rather than on a timer.
	if not farm.movedFrom or (root.Position - farm.movedFrom).Magnitude > 25 then
		farm.movedFrom = root.Position
		farm.miss = 0
		farm.bad = {}
	end

	local goal = target.part.Position
	if mode == "Biggest Pile" and look.best then
		goal = look.best
	end
	-- A standoff well inside whatever is doing the collecting, so arriving and
	-- being able to grab are never two different answers again.
	farm.travel(core, goal, math.min(6, walkTo * 0.3), speed)
	return true
end

--------------------------------------------------------------------------------
-- what the cash is for
--------------------------------------------------------------------------------
--
-- Every purchase in a map is fired on a RemoteEvent, so none of them answer.
-- There is no refusal to count and nothing to back off from, which is the exact
-- shape that had Steal An Egg firing an unaffordable purchase every twenty
-- seconds all night. So each one records what was in the wallet when it asked
-- and does not ask again until there is more than there was. That covers both
-- "could not afford it" and "bought it, and the next one costs more".

local shop = { bits = nil, spentAt = {} }

function shop.wire(bits)
	shop.bits = bits
end

function shop.cash()
	return tonumber(Players.LocalPlayer:GetAttribute("Cash")) or 0
end

function shop.worthAsking(key)
	local mark = shop.spentAt[key]
	return mark == nil or shop.cash() > mark
end

function shop.spend(key, action, ...)
	shop.spentAt[key] = shop.cash()
	shop.bits.ask(action, ...)
end

function shop.config()
	local ok, cfg = pcall(require, ReplicatedStorage:FindFirstChild("UpgradeConfig"))
	if ok and type(cfg) == "table" then
		return cfg
	end
	return nil
end

-- The bag, which is the upgrade a run is shaped by: every level is fewer walks
-- to the dumpster and more of the run spent actually clearing.
function shop.bagTick()
	local bits = shop.bits
	if bits.F.leafAutoBag ~= true or not look.inMap() then
		return
	end
	local level = tonumber(Players.LocalPlayer:GetAttribute("BagLevel")) or 0
	local ok, cfg = pcall(require, ReplicatedStorage:FindFirstChild("BagConfig"))
	if not ok or type(cfg) ~= "table" or type(cfg.prices) ~= "table" then
		return
	end
	local price = cfg.prices[level + 1]
	if not price or shop.cash() < price then
		return
	end
	if not shop.worthAsking("bag") or not bits.due("bag", 4) then
		return
	end
	shop.spend("bag", "BuyBagUpgrade")
	bits.core:Notify(Module.Name, "Bought a bigger bag", 4)
end

-- The tools, cheapest first. The rake changes how the game is played and the
-- blower is the one after it.
function shop.toolTick()
	local bits = shop.bits
	if bits.F.leafAutoTools ~= true or not look.inMap() then
		return
	end
	local cfg = shop.config()
	if not cfg or type(cfg.shop) ~= "table" then
		return
	end
	local player = Players.LocalPlayer
	for _, key in ipairs({ "Rake", "LeafBlower" }) do
		local entry = cfg.shop[key]
		local price = entry and tonumber(entry.cash)
		local owned = player:GetAttribute("Owns" .. key) == true
		if price and not owned then
			if shop.cash() >= price and shop.worthAsking("tool" .. key)
				and bits.due("tool" .. key, 6)
			then
				shop.spend("tool" .. key, "BuyToolCash", key)
				bits.core:Notify(Module.Name, "Bought the " .. (entry.model or key), 5)
			end
			return
		end
	end
end

-- Upgrading whatever is actually in your hands, cheapest rung first.
function shop.upgradeTick()
	local bits = shop.bits
	if bits.F.leafAutoUpg ~= true or not look.inMap() then
		return
	end
	local cfg = shop.config()
	if not cfg or type(cfg.tools) ~= "table" then
		return
	end
	local player = Players.LocalPlayer
	local want = tostring(bits.F.leafUpgWhich or "Held Tool")
	local toolKey = want
	if want == "Held Tool" then
		toolKey = tostring(player:GetAttribute("SelectedTool") or "Hand")
	end
	local tool = cfg.tools[toolKey]
	if type(tool) ~= "table" or type(tool.order) ~= "table" then
		return
	end
	if tool.ownsAttr and player:GetAttribute(tool.ownsAttr) ~= true then
		return
	end
	if not shop.worthAsking("upg") or not bits.due("upg", 4) then
		return
	end
	for _, upgName in ipairs(tool.order) do
		local spec = tool.upgrades and tool.upgrades[upgName]
		local level = tonumber(player:GetAttribute(("Upg_%s_%s"):format(toolKey, upgName))) or 0
		local costs = type(spec) == "table" and spec.costs
		local price = type(costs) == "table" and tonumber(costs[level + 1]) or nil
		if price and shop.cash() >= price then
			shop.spend("upg", "BuyUpgrade", toolKey, upgName)
			journal.note(("BuyUpgrade %s %s"):format(toolKey, upgName))
			return
		end
	end
end

-- Vents are how a zone gets cleared, so an unopened one is the thing standing
-- between this run and the next map.
function shop.ventTick()
	local bits = shop.bits
	if bits.F.leafAutoVent ~= true or not look.inMap() then
		return
	end
	if not shop.worthAsking("vent") or not bits.due("vent", 8) then
		return
	end
	local map = Workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Vents")
	if not folder then
		return
	end
	for _, vent in ipairs(folder:GetChildren()) do
		local id = vent:GetAttribute("VentId") or vent:GetAttribute("Id") or vent.Name
		if vent:GetAttribute("Unlocked") ~= true and id then
			shop.spend("vent", "BuyVent", id)
			journal.note("BuyVent " .. tostring(id))
			return
		end
	end
end

--------------------------------------------------------------------------------
-- the lobby half
--------------------------------------------------------------------------------
--
-- Starting a run needs one thing nobody would guess: setting the squad size to
-- the number of people already on the square starts it immediately, because the
-- square is then full. That is how Auto Start Run gets a solo run without
-- waiting out a countdown for players who are not coming.
--
-- And one trap that costs a run rather than a moment: the game's own TeamsClient
-- fires "leave" on Humanoid.Jumping. Anything that jumps while standing on a
-- square drops itself out of its own queue - which is also why Unstick Me is
-- not allowed to jump in the lobby.

local lobby = { bits = nil }

function lobby.wire(bits)
	lobby.bits = bits
end

function lobby.inLobby()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	return not look.inMap()
		and remotes ~= nil
		and remotes:FindFirstChild("TeamAction") ~= nil
end

function lobby.save()
	local player = Players.LocalPlayer
	local scripts = player and player:FindFirstChild("PlayerScripts")
	local manager = scripts and scripts:FindFirstChild("ClientManager")
	local mod = manager and manager:FindFirstChild("Variables")
	if mod and mod:IsA("ModuleScript") then
		local ok, vars = pcall(require, mod)
		if ok and type(vars) == "table" and type(vars.data) == "table" then
			return vars.data
		end
	end
	return nil
end

function lobby.square(from)
	local teams = Workspace:FindFirstChild("Teams")
	if not teams then
		return nil
	end
	local best, bestAway = nil, math.huge
	for _, model in ipairs(teams:GetChildren()) do
		local ok, pivot = pcall(function()
			return model:GetPivot()
		end)
		if ok then
			local away = (pivot.Position - from).Magnitude
			if away < bestAway then
				best, bestAway = pivot.Position, away
			end
		end
	end
	return best
end

function lobby.tick()
	local bits = lobby.bits
	if bits.F.leafAutoStart ~= true or not lobby.inLobby() then
		return
	end
	local core = bits.core
	if not guard.mayDrive() then
		return
	end
	local root = core:Root()
	if not root or not core:Alive2() then
		return
	end

	if Players.LocalPlayer:GetAttribute("InTeam") ~= true then
		local where = lobby.square(root.Position)
		if where then
			core:WalkToward(where, 3, 24)
		end
		return
	end

	if not bits.due("start", 6) then
		return
	end
	local maps = { House = true, Mansion = true, GasStation = true, SpaceMap = true }
	local wantMap = maps[tostring(bits.F.leafMap)] and tostring(bits.F.leafMap) or "House"
	local ranks = { Easy = 1, Medium = 2, Hard = 3, Impossible = 4 }
	local wantDiff = ranks[tostring(bits.F.leafDifficulty)] or 1

	bits.ask("TeamAction", "setMap", wantMap)
	bits.ask("TeamAction", "setDifficulty", wantDiff)
	if bits.F.leafSolo ~= false then
		-- One person on the square and a maximum of one is a full squad, and a
		-- full squad leaves at once.
		bits.ask("TeamAction", "setMax", 1)
	else
		bits.ask("TeamAction", "confirm")
	end
	core:Notify(Module.Name, ("Starting %s on %s"):format(wantMap, tostring(bits.F.leafDifficulty or "Easy")), 5)
end

-- The upgrades you keep, which are the only thing a run is really for. These
-- are a RemoteFunction, so unlike everything in a map they answer, and "poor"
-- is the server's own word for cannot afford it.
function lobby.upgradeTick()
	local bits = lobby.bits
	if bits.F.leafAutoDiamond ~= true or not lobby.inLobby() then
		return
	end
	if not bits.due("diamond", 5) then
		return
	end
	local ok, cfg = pcall(require, ReplicatedStorage:FindFirstChild("PlayerUpgradeConfig"))
	if not ok or type(cfg) ~= "table" then
		return
	end
	local data = lobby.save()
	if not data then
		return
	end

	local order = { "BagCapacity", "WalkSpeed", "Cash", "Gems" }
	local first = tostring(bits.F.leafBuyOrder or "")
	if first ~= "" then
		local moved = { first }
		for _, key in ipairs(order) do
			if key ~= first then
				moved[#moved + 1] = key
			end
		end
		order = moved
	end

	for _, key in ipairs(order) do
		local level = (type(data.Upgrades) == "table" and tonumber(data.Upgrades[key])) or 0
		if level < (tonumber(cfg.MAX_LEVEL) or 5) then
			local answered, reply = bits.ask("UpgradeBuy", key)
			if answered and reply == "bought" then
				bits.accepted("diamond")
				bits.core:Notify(Module.Name, "Upgraded " .. key, 4)
			end
			return
		end
	end
end

function lobby.spinTick()
	local bits = lobby.bits
	if bits.F.leafAutoSpin ~= true or not lobby.inLobby() then
		return
	end
	if not bits.due("spin", 10) then
		return
	end
	local ok, cfg = pcall(require, ReplicatedStorage:FindFirstChild("ClassConfig"))
	local cost = (ok and type(cfg) == "table" and tonumber(cfg.SPIN_COST)) or 40
	local data = lobby.save()
	local diamonds = data and tonumber(data.Diamonds) or 0
	if diamonds < cost then
		return
	end
	if bits.ask("ClassSpin") then
		bits.accepted("spin")
	end
end

--------------------------------------------------------------------------------

function Module.Build(ctx)
	local core, tabGroup = ctx.core, ctx.TabGroup
	local F = core.Flags
	local LocalPlayer = Players.LocalPlayer

	----------------------------------------------------------------------------
	-- reaching the server
	----------------------------------------------------------------------------
	--
	-- One way out, and it looks up what it is talking to first. Which of
	-- FireServer and InvokeServer is right is a property of the remote and not
	-- of what you want: a RemoteFunction fired throws, and a client throwing at
	-- the server several times a second is what gets accounts removed.
	--
	-- This game splits cleanly. The lobby answers - UpgradeBuy and ClassSpin are
	-- RemoteFunctions and hand back the server's own word. A map does not: every
	-- purchase and every collect there is an event that says nothing back.
	local Remotes = ReplicatedStorage:FindFirstChild("Remotes")

	local function ask(name, ...)
		if type(name) ~= "string" then
			return false, "no such action"
		end
		local folder = Remotes
		if not folder or not folder.Parent then
			folder = ReplicatedStorage:FindFirstChild("Remotes")
			Remotes = folder
		end
		local remote = folder and folder:FindFirstChild(name)
		if not remote then
			return false, "this place has no " .. name
		end
		if remote:IsA("RemoteFunction") then
			local ok, value = pcall(function(...)
				return remote:InvokeServer(...)
			end, ...)
			journal.note(("%s %s"):format(name, ok and tostring(value) or "threw"))
			if not ok then
				return false, tostring(value)
			end
			return value ~= false, value
		end
		if remote:IsA("RemoteEvent") then
			local ok, err = pcall(function(...)
				remote:FireServer(...)
			end, ...)
			journal.note(("%s %s"):format(name, ok and "fired" or "failed"))
			if ok then
				return true
			end
			return false, tostring(err)
		end
		return false, name .. " is a " .. remote.ClassName
	end

	-- A floor under the gap between any two calls, and a ceiling per action. An
	-- impossible request asked twice a second is the one thing that reliably
	-- gets an account removed.
	local nextDue, failures, lastCall = {}, {}, 0

	local function due(key, interval)
		local now = os.clock()
		if now - lastCall < 0.25 then
			return false
		end
		if now < (nextDue[key] or 0) then
			return false
		end
		lastCall = now
		nextDue[key] = now + interval
		return true
	end

	-- Backing off is not stopping. Past a dozen in a row it stops asking at all
	-- for a while, because an action that can never succeed asked every thirty
	-- seconds is nine hundred refusals over a night.
	local function refused(key, interval)
		local count = (failures[key] or 0) + 1
		failures[key] = count
		if count >= 12 then
			nextDue[key] = os.clock() + 600
		else
			nextDue[key] = os.clock() + math.min(interval * (2 ^ count), 30)
		end
		return count
	end

	local function accepted(key)
		failures[key] = nil
		nextDue[key] = nil
	end

	local saidOnce = {}

	local function sayOnce(key, title, body)
		if saidOnce[key] then
			return
		end
		saidOnce[key] = true
		core:Notify(title, body, 7)
	end

	local bits = {
		F = F,
		core = core,
		ask = ask,
		due = due,
		refused = refused,
		accepted = accepted,
		sayOnce = sayOnce,
		player = LocalPlayer,
		window = ctx.Window,
	}
	guard.wire(bits)
	farm.wire(bits)
	shop.wire(bits)
	lobby.wire(bits)

	----------------------------------------------------------------------------
	-- the interface
	----------------------------------------------------------------------------

	local runTab = tabGroup:Tab({ Name = "Run", Image = "rbxassetid://10723407389" })
	local toolTab = tabGroup:Tab({ Name = "Tools", Image = "rbxassetid://10734886735" })
	local lobbyTab = tabGroup:Tab({ Name = "Lobby", Image = "rbxassetid://10734950309" })
	local youTab = tabGroup:Tab({ Name = "You", Image = "rbxassetid://10747373176" })

	local runLeft = runTab:Section({ Side = "Left" })
	local runRight = runTab:Section({ Side = "Right" })
	local toolLeft = toolTab:Section({ Side = "Left" })
	local toolRight = toolTab:Section({ Side = "Right" })
	local lobbyLeft = lobbyTab:Section({ Side = "Left" })
	local lobbyRight = lobbyTab:Section({ Side = "Right" })
	local youLeft = youTab:Section({ Side = "Left" })
	local youRight = youTab:Section({ Side = "Right" })

	------------------------------------------------------------------ run · left

	runLeft:Header({ Text = "Clearing" })

	local cleanToggle = runLeft:Toggle({
		Name = "Auto Clean",
		Default = false,
		Callback = function(state)
			F.autoClean = state
			if not state then
				farm.anchor = nil
				-- Switching it off has to stop the legs too. It did not once,
				-- and the character carried on walking wherever it had last
				-- been pointed with nothing running to ever stop it.
				core:SetControls(true)
			end
		end,
	}, "autoClean")
	guard.watch("autoClean", cleanToggle)

	runLeft:Dropdown({
		Name = "Pick By",
		Multi = false,
		Required = true,
		Options = { "Nearest", "Biggest Pile", "Worth Most" },
		Default = 2,
		Callback = function(value)
			F.leafPick = value
			look.scanAt = 0
		end,
	}, "leafPick")

	runLeft:Slider({
		Name = "Reach",
		Default = 30,
		Minimum = 6,
		Maximum = 30,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.leafReach = value
		end,
	}, "leafReach")

	runLeft:Toggle({
		Name = "Sell When Full",
		Default = true,
		Callback = function(state)
			F.leafSell = state
		end,
	}, "leafSell")

	runLeft:Slider({
		Name = "Sell At",
		Default = 100,
		Minimum = 40,
		Maximum = 100,
		DisplayMethod = "Percent",
		Precision = 0,
		Callback = function(value)
			F.leafSellAt = value
		end,
	}, "leafSellAt")

	----------------------------------------------------------------- run · right

	runRight:Header({ Text = "Where and how fast" })

	runRight:Slider({
		Name = "Stay Within",
		Default = 250,
		Minimum = 60,
		Maximum = 800,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.leafWander = value
			look.scanAt = 0
		end,
	}, "leafWander")

	runRight:Slider({
		Name = "Walk Speed",
		Default = 24,
		Minimum = 16,
		Maximum = 90,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.leafSpeed = value
		end,
	}, "leafSpeed")

	runRight:Dropdown({
		Name = "Travel",
		Multi = false,
		Required = true,
		Options = { "Walk", "Hop", "Teleport" },
		Default = 1,
		Callback = function(value)
			F.leafTravel = value
		end,
	}, "leafTravel")

	runRight:Toggle({
		Name = "Unstick Me",
		Default = true,
		Callback = function(state)
			F.leafUnstick = state
		end,
	}, "leafUnstick")

	----------------------------------------------------------------- tools · left

	toolLeft:Header({ Text = "Spending run cash" })


	toolLeft:Toggle({
		Name = "Auto Bag",
		Default = true,
		Callback = function(state)
			F.leafAutoBag = state
		end,
	}, "leafAutoBag")

	toolLeft:Toggle({
		Name = "Auto Buy Tools",
		Default = true,
		Callback = function(state)
			F.leafAutoTools = state
		end,
	}, "leafAutoTools")

	---------------------------------------------------------------- tools · right

	toolRight:Header({ Text = "Upgrades" })

	toolRight:Toggle({
		Name = "Auto Tool Upgrades",
		Default = true,
		Callback = function(state)
			F.leafAutoUpg = state
		end,
	}, "leafAutoUpg")

	toolRight:Dropdown({
		Name = "Upgrade Which",
		Multi = false,
		Required = true,
		Options = { "Held Tool", "Hand", "Rake", "LeafBlower" },
		Default = 1,
		Callback = function(value)
			F.leafUpgWhich = value
		end,
	}, "leafUpgWhich")

	toolRight:Toggle({
		Name = "Auto Vents",
		Default = true,
		Callback = function(state)
			F.leafAutoVent = state
		end,
	}, "leafAutoVent")

	------------------------------------------------------------------ lobby tab

	lobbyLeft:Header({ Text = "Starting a run" })

	local startToggle = lobbyLeft:Toggle({
		Name = "Auto Start Run",
		Default = false,
		Callback = function(state)
			F.leafAutoStart = state
			if not state then
				core:SetControls(true)
			end
		end,
	}, "leafAutoStart")
	guard.watch("leafAutoStart", startToggle)

	lobbyLeft:Dropdown({
		Name = "Map",
		Multi = false,
		Required = true,
		Options = { "House", "Mansion", "GasStation", "SpaceMap" },
		Default = 1,
		Callback = function(value)
			F.leafMap = value
		end,
	}, "leafMap")

	lobbyLeft:Dropdown({
		Name = "Difficulty",
		Multi = false,
		Required = true,
		Options = { "Easy", "Medium", "Hard", "Impossible" },
		Default = 1,
		Callback = function(value)
			F.leafDifficulty = value
		end,
	}, "leafDifficulty")

	lobbyLeft:Toggle({
		Name = "Solo",
		Default = true,
		Callback = function(state)
			F.leafSolo = state
		end,
	}, "leafSolo")

	lobbyRight:Header({ Text = "What you keep" })

	lobbyRight:Toggle({
		Name = "Auto Diamond Upgrades",
		Default = false,
		Callback = function(state)
			F.leafAutoDiamond = state
		end,
	}, "leafAutoDiamond")

	lobbyRight:Dropdown({
		Name = "Buy Order",
		Multi = false,
		Required = true,
		Options = { "BagCapacity", "WalkSpeed", "Cash", "Gems" },
		Default = 1,
		Callback = function(value)
			F.leafBuyOrder = value
		end,
	}, "leafBuyOrder")

	lobbyRight:Toggle({
		Name = "Auto Class Spin",
		Default = false,
		Callback = function(state)
			F.leafAutoSpin = state
		end,
	}, "leafAutoSpin")

	-------------------------------------------------------------------- you tab

	youLeft:Header({ Text = "Getting out of the way" })

	youLeft:Toggle({
		Name = "Free Cursor",
		Default = true,
		Callback = function(state)
			F.leafFreeCursor = state
		end,
	}, "leafFreeCursor")

	youLeft:Toggle({
		Name = "Hands Off While Menu Is Open",
		Default = true,
		Callback = function(state)
			F.leafHandsOff = state
			if state then
				core:SetControls(true)
			end
		end,
	}, "leafHandsOff")

	youRight:Header({ Text = "If it all goes wrong" })

	youRight:Keybind({
		Name = "Everything Off",
		Default = Enum.KeyCode.Delete,
		Callback = function()
			guard.panic(false)
		end,
	})

	youRight:Button({
		Name = "Stop Everything",
		Callback = function()
			guard.panic(false)
		end,
	})

	youRight:Toggle({
		Name = "Anti AFK",
		Default = true,
		Callback = function(state)
			F.leafAntiAfk = state
		end,
	}, "leafAntiAfk")

	----------------------------------------------------------------------------
	-- the loops
	----------------------------------------------------------------------------

	-- The cursor has to be taken back every frame, because the game writes it
	-- every frame. Anything slower and it flickers between locked and free.
	core:Connect(RunService.RenderStepped, function()
		guard.cursorTick()
	end)

	-- One pair of legs and one thing steering them.
	core:Loop("clean", 0.1, function()
		farm.tick()
	end)

	core:Loop("spend", 3, function()
		shop.bagTick()
		shop.toolTick()
		shop.upgradeTick()
		shop.ventTick()
	end)

	core:Loop("lobby", 2, function()
		lobby.tick()
		lobby.upgradeTick()
		lobby.spinTick()
	end)

	core:Loop("afk", 60, function()
		if F.leafAntiAfk == false then
			return
		end
		local vu = game:GetService("VirtualUser")
		pcall(function()
			vu:CaptureController()
			vu:ClickButton2(Vector2.new())
		end)
	end)

	-- Nothing in Build may yield: it runs while the loader is still assembling
	-- the window, and a thread that yields comes back without the capability to
	-- touch the interface. Anything that waits goes on its own thread.
	task.spawn(function()
		task.wait(1)
		seeded.apply(core)
	end)

	return {
		Tabs = {
			Run = runTab,
			Tools = toolTab,
			Lobby = lobbyTab,
			You = youTab,
		},
		Default = runTab,
		Tips = Module.Tips,
	}
end

return Module
