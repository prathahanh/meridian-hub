--// Meridian · Steal An Egg
--// universe 10563114921
--//
--// This game is the opposite of Ability Arena. There, the server trusted the
--// client and the work was finding out what it would accept. Here every action
--// already has a client-side wrapper that returns the server's own refusal
--// text, so nothing has to be inferred - but the server owns position and
--// WalkSpeed absolutely, and a purpose-built movement anti-cheat resets you to
--// base for arguing. So: no fly, no teleport, no speed write, anywhere.
--//
--// What that leaves is the thing that actually wins. Every trip to an egg
--// costs the same time for everybody, macro and script alike, because nobody
--// can travel faster than anybody else. The only variable left is which egg
--// you come back with, and the game hands us its own valuation function.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local Module = {
	GameId = 10563114921,
	Name = "Steal An Egg",
}

-- Hover text. One line each, written for somebody who has never seen the code.
-- Nothing here explains a mechanism and no number appears unless it is one you
-- would actually set.
Module.Tips = {
	["Auto Steal"] = "Walks to an egg, takes it, brings it home and puts it down. Then goes again.",
	["Pick By"] = "What makes an egg worth the walk.",
	["Stay Where You Win"] = "Settles on the best area your Speed is up to and farms there, using the recommended number on the sign at the mouth of each one. Leaves it only for an egg worth several times more.",
	["Areas"] = "Which parts of the map it is allowed to go to. Leave them all on and it goes wherever the best egg is.",
	["Worth At Least"] = "Ignores anything earning less than this. The number is money a second, the same one the game shows on a pet.",
	["Only Mutated"] = "Skips every ordinary egg, however big.",
	["How Far To Look"] = "Stops it crossing the whole map for one egg. Turn it up if you want the best on the map and do not mind the walk.",
	["Wait Before Taking"] = "A pause once it arrives, before it grabs. Zero grabs the moment it is close enough.",
	["Take It Home"] = "Carries every egg back to your base instead of leaving it where it was.",
	["Give Up After"] = "How long to spend on one egg before writing it off and picking another.",
	["Auto Place"] = "Puts a carried egg down on your base as soon as you get there.",
	["Auto Hatch"] = "Hatches every egg on your base the moment it is ready.",
	["Equip Best After Hatching"] = "A new pet is the only thing that changes which pets should be out, so it checks then. Full pen means the worst one goes.",
	["Auto Skip Growth"] = "Pays to skip the wait on eggs that are still growing. This spends money.",
	["Claim Offline Money"] = "Collects what your pets earned while you were away.",
	["Auto Collect"] = "Keeps collecting the money piling up on your base.",
	["Auto Upgrade Base"] = "Buys the next base upgrade whenever you can afford it.",
	["Auto Equip Best"] = "Keeps your best pets out, as the game ranks them.",
	["Equip Best Now"] = "Does it once, right now.",
	["Auto Sell"] = "Turns on the game's own auto sell, so junk never fills your inventory.",
	["Sell Everything"] = "Sells your whole inventory except favourites. There is no undo.",
	["Auto Treadmill"] = "Stands on the treadmill and keeps earning Speed while you are not doing anything else.",
	["Auto Upgrade Treadmill"] = "Buys the next treadmill whenever you can afford it.",
	["Treadmill For The Next Area"] = "When the next area is one sitting away on the treadmill, goes and stands on it until you can get in, then goes back to farming.",
	["Auto Rebirth"] = "Rebirths as soon as the game lets you.",
	["Rebirth Now"] = "Rebirths, right now.",
	["Claim Index"] = "Collects every index reward you have earned.",
	["Auto Free Gifts"] = "Takes the free gifts as they come up.",
	["Auto Lucky Blocks"] = "Opens lucky blocks as they are stored.",
	["Redeem Codes"] = "Tries every code the game currently has active.",
	["Egg ESP"] = "Draws every egg on the map through walls, with what it is worth.",
	["Show Worth"] = "Adds money a second to each egg, so the filter above is legible.",
	["Show Distance"] = "Adds how far away each egg is.",
	["Hide Cheap Eggs"] = "Only draws eggs worth more than your filter, so the screen is not full of Dogs.",
	["Max Distance"] = "Stops drawing eggs past this far away.",
	["Player ESP"] = "Draws every other player through walls.",
	["Anti AFK"] = "Stops the game kicking you for standing still.",
	["Auto Hop"] = "Leaves for a better server once this one has emptied out.",
	["Hop When Below"] = "How few people have to be left before it goes looking for somewhere else.",
	["Pick Server By"] = "What makes a server worth moving to.",
	["Highest Ping"] = "Servers slower than this are skipped, however full they are.",
	["Hop Now"] = "Goes to the best server it can find, right now.",
}

--------------------------------------------------------------------------------

function Module.Build(ctx)
	local core, tabGroup = ctx.core, ctx.TabGroup
	local F = core.Flags

	local LocalPlayer = Players.LocalPlayer

	----------------------------------------------------------------------------
	-- the game's own modules
	----------------------------------------------------------------------------

	local Library = ReplicatedStorage:WaitForChild("Library")
	local Client = Library:WaitForChild("Client")
	local Directory = ReplicatedStorage:WaitForChild("Directory")

	local EggCmds = require(Client:WaitForChild("EggCmds"))
	local PlotCmds = require(Client:WaitForChild("PlotCmds"))
	local Network = require(Client:WaitForChild("Network"))

	local Constants = require(Library:WaitForChild("Globals"):WaitForChild("Constants"))
	local NET = Constants.NETWORK_MAP

	local AssetGen = require(Library:WaitForChild("Util"):WaitForChild("AssetGenerationUtil"))
	local Assets = require(Directory:WaitForChild("Assets"))
	local Areas = require(Directory:WaitForChild("Areas"))

	----------------------------------------------------------------------------
	-- what an egg is worth
	----------------------------------------------------------------------------

	-- The whole reason to use this over anything else, and it is four lines,
	-- because the game already computes it and we are allowed to ask.
	--
	-- `GetBaseRateMutationOnly` is the game's own valuation: earning rate for
	-- the pet, multiplied by size (scale^1.85 up to 5, flattening after) and by
	-- whatever mutations it rolled, with rebirth and gamepasses left out so two
	-- eggs compare the same way for everybody.
	--
	-- Measured on one live server: the best egg on the map was worth 184,366 a
	-- second and the worst was worth 2. Every script that grabs the nearest egg
	-- is playing a lottery across that range on every single trip, and the walk
	-- costs the same either way.
	local worthCache = {}

	local function eggWorth(record)
		if not record or not record.AssetCategory then
			return 0
		end
		local key = record.Uid
		local hit = key and worthCache[key]
		if hit then
			return hit
		end
		local ok, rate = pcall(AssetGen.GetBaseRateMutationOnly, {
			Category = record.AssetCategory,
			Scale = record.AssetScale,
			Mutations = record.Mutations,
		})
		if not ok or type(rate) ~= "number" then
			return 0
		end
		if key then
			worthCache[key] = rate
		end
		return rate
	end

	local function mutationList(record)
		local out = {}
		for name in pairs(record.Mutations or {}) do
			out[#out + 1] = tostring(name)
		end
		if record.BaseMutation and record.BaseMutation ~= "" then
			table.insert(out, 1, tostring(record.BaseMutation))
		end
		return out
	end

	local function eggName(record)
		local config = record.AssetCategory and Assets.Directory[record.AssetCategory]
		return (config and config.DisplayName) or record.AssetCategory or "Egg"
	end

	-- Money, the way the game writes it, so a filter reads like the number on a
	-- pet rather than like a row from a spreadsheet.
	local function short(n)
		n = tonumber(n) or 0
		local units = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
		for _, unit in ipairs(units) do
			if n >= unit[1] then
				local scaled = n / unit[1]
				local text = scaled < 10 and ("%.1f"):format(scaled) or ("%d"):format(scaled)
				return text:gsub("%.0$", "") .. unit[2]
			end
		end
		return ("%d"):format(n)
	end

	----------------------------------------------------------------------------
	-- where things are
	----------------------------------------------------------------------------

	local AREA_NAMES = {}
	for name in pairs(Areas.Directory) do
		AREA_NAMES[#AREA_NAMES + 1] = name
	end
	table.sort(AREA_NAMES)

	----------------------------------------------------------------------------
	-- where you are actually allowed to be
	----------------------------------------------------------------------------

	-- The game already answers this and puts the answer on a sign at the mouth
	-- of every area: "recommended 700K". That number is Speed Power, the stat on
	-- your screen, and it is the only honest gate.
	--
	--   Forest 11 · Lake 900 · Desert 10K · Jungle 40K · Snow 170K
	--   Volcano 700K · Abyss Ocean 2.5M · Prehistoric 17M · Cosmic 700M
	--
	-- The first version of this compared your WalkSpeed against the guard's
	-- WalkSpeed instead, which is a different scale and got Volcano wrong: it
	-- called an area shut that he clears comfortably. Read the sign.
	local AREA_MODELS = "GuardAreas"

	local function parseSpeed(text)
		if type(text) ~= "string" then
			return nil
		end
		local number, suffix = text:match("([%d%.]+)%s*([KMBT]?)")
		local value = tonumber(number)
		if not value then
			return nil
		end
		local scale = { K = 1e3, M = 1e6, B = 1e9, T = 1e12 }
		return value * (scale[suffix] or 1)
	end

	-- Read on demand rather than once at build, and that matters. The hub loads
	-- before the world has finished streaming in, so reading the signs up front
	-- found nothing, every area came back allowed, and the farm walked straight
	-- into Prehistoric with a tenth of the Speed it wants. It keeps trying until
	-- it has all nine.
	local AREA_NEEDS = {}
	local areaNeedsCount = 0

	local function readSigns()
		if areaNeedsCount >= 9 then
			return
		end
		local objects = Workspace:FindFirstChild("__OBJECTS")
		local areasFolder = objects and objects:FindFirstChild("Areas")
		local guardAreas = areasFolder and areasFolder:FindFirstChild(AREA_MODELS)
		for _, model in ipairs(guardAreas and guardAreas:GetChildren() or {}) do
			if AREA_NEEDS[model.Name] == nil then
				local sign = model:FindFirstChild("RequiredSpeedSign")
				for _, label in ipairs(sign and sign:GetDescendants() or {}) do
					if label:IsA("TextLabel") and label.Name == "Speed" then
						local needed = parseSpeed(label.Text)
						if needed then
							AREA_NEEDS[model.Name] = needed
							areaNeedsCount = areaNeedsCount + 1
						end
						break
					end
				end
			end
		end
	end

	local SpeedPower = require(Client:WaitForChild("SpeedPowerProjection"))

	-- The way in, and the reason a farm can stand two studs from an egg for
	-- twenty seconds without taking it.
	--
	-- Areas are fenced. Walking at an egg's coordinates from outside puts you
	-- against the fence, close enough for the distance check to read two studs
	-- and still outside, so every request comes back "Enter the gameplay area
	-- first" and nothing ever changes. Each area model carries a Bounds pad and
	-- a ClosestExitPoint, which is also the way in, so the approach goes through
	-- the door before it goes to the egg.
	local function areaModel(areaId)
		local objects = Workspace:FindFirstChild("__OBJECTS")
		local areasFolder = objects and objects:FindFirstChild("Areas")
		local guardAreas = areasFolder and areasFolder:FindFirstChild(AREA_MODELS)
		return guardAreas and guardAreas:FindFirstChild(areaId) or nil
	end

	local function insideArea(areaId, position)
		local model = areaModel(areaId)
		local bounds = model and model:FindFirstChild("Bounds")
		if not bounds or not bounds:IsA("BasePart") then
			return true
		end
		local relative = bounds.CFrame:PointToObjectSpace(position)
		local half = bounds.Size / 2
		return math.abs(relative.X) <= half.X and math.abs(relative.Z) <= half.Z
	end

	-- A point a little way inside the fence rather than on it, so arriving does
	-- not leave you straddling the line.
	local function areaEntrance(areaId)
		local model = areaModel(areaId)
		if not model then
			return nil
		end
		local door = model:FindFirstChild("ClosestExitPoint")
		local bounds = model:FindFirstChild("Bounds")
		if not door or not door:IsA("BasePart") then
			return bounds and bounds:IsA("BasePart") and bounds.Position or nil
		end
		if bounds and bounds:IsA("BasePart") then
			local inward = (bounds.Position - door.Position)
			if inward.Magnitude > 1 then
				return door.Position + inward.Unit * 14
			end
		end
		return door.Position
	end

	local function mySpeedPower()
		local ok, value = pcall(SpeedPower.GetSpeedPower)
		return (ok and tonumber(value)) or 0
	end

	-- Which areas to farm, in order, best first.
	--
	-- This is a different question from which egg is best, and answering the
	-- wrong one is what he caught: it walked past Volcano to take an egg out of
	-- Snow, because that one Snow egg happened to be worth more than anything
	-- Volcano had spawned that minute. Wrong trade. The walk costs the same
	-- either way, Volcano's eggs are worth far more on average, and a farm
	-- running all night lives on the average, not on one lucky spawn.
	--
	-- The sign is both the gate and the ranking. 11, 900, 10K, 40K, 170K, 900K,
	-- 2.5M, 17M, 700M: the order of the numbers is the order of the areas, so
	-- the highest sign we pass is where we belong.
	local function areasByTier()
		readSigns()
		local power = mySpeedPower()
		local out = {}
		for id, needed in pairs(AREA_NEEDS) do
			if needed <= power then
				out[#out + 1] = { id = id, needed = needed }
			end
		end
		table.sort(out, function(a, b)
			return a.needed > b.needed
		end)
		return out
	end

	local function eggPosition(record)
		local cframe = record.BoundsCFrame or record.BottomCFrame
		return cframe and cframe.Position or nil
	end

	local function myPosition()
		local root = core:Root()
		return root and root.Position or nil
	end

	local function plotData()
		local ok, data = pcall(PlotCmds.GetPlotData)
		return ok and data or nil
	end

	-- A starter egg is addressed by a compound key rather than a plain uid, and
	-- asking for one the ordinary way comes back "Egg not found". They are also
	-- the cheapest things on the map, so the farm has no reason to want one.
	local function isStarterEgg(record)
		return type(record.Uid) == "string" and record.Uid:find("FirstAreaEgg") ~= nil
	end

	-- What we are carrying, if anything. The tool is the truth: the server put
	-- it in our hands, so it cannot disagree with itself the way a local flag
	-- can after a refusal we misread.
	----------------------------------------------------------------------------
	-- talking to the server
	----------------------------------------------------------------------------

	-- Nothing in this module calls the server except through here, and that is
	-- not tidiness. The first version retried a refused placement on every tick
	-- of a loop that runs ten times a second, which is six hundred identical
	-- requests a minute from one client, and it got the account kicked for
	-- cheating inside a minute. **A refusal retried immediately is the loudest
	-- thing a script can do**, far louder than the farm walking around.
	--
	-- So: a floor under the gap between any two calls at all, a per-action
	-- interval on top of that, and a doubling wait after each refusal.
	local SERVER_GAP = 0.45
	local BACKOFF_CAP = 30

	-- The ceiling is per action, and that is not a detail. Carrying backed off to
	-- thirty seconds after a handful of refusals and nothing cleared the count,
	-- so the farm stood next to an egg it was perfectly able to take and asked
	-- once a minute. A slow action can afford to wait. The one the farm is built
	-- around cannot.
	local BACKOFF_MAX = { carry = 4 }

	local lastCall = 0
	local nextDue = {}
	local failures = {}

	-- The actions that spend money, which the gate has to treat differently.
	local BUYING = { treadmill = true, upgrade = true, skip = true, trail = true }

	-- What is in the bank right now, so a purchase that was refused is not asked
	-- again until there is more money than there was when it said no. Cheaper
	-- and more honest than knowing every price in the game, and it means a farm
	-- that cannot afford the next treadmill asks about it once and then not
	-- again until it has actually earned something.
	local function money()
		local stats = LocalPlayer:FindFirstChild("leaderstats")
		local cash = stats and stats:FindFirstChild("Money")
		return tonumber(cash and cash.Value) or 0
	end

	local refusedAt = {}

	local function due(key, interval)
		local now = os.clock()
		if now - lastCall < SERVER_GAP then
			return false
		end
		if now < (nextDue[key] or 0) then
			return false
		end
		if BUYING[key] and refusedAt[key] and money() <= refusedAt[key] then
			return false
		end
		lastCall = now
		nextDue[key] = now + interval
		return true
	end

	-- Backing off is not the same as stopping, and for something meant to run all
	-- night the difference is the whole game.
	--
	-- Doubling the wait and capping it at thirty seconds means an action that
	-- can never succeed settles into asking once every thirty seconds - which is
	-- a hundred and twenty an hour, nine hundred and sixty overnight, all of them
	-- refused. That is the exact shape this game kicks for, delivered slowly. So
	-- past a dozen refusals in a row it stops asking at all for ten minutes, and
	-- the next thing that succeeds clears the count.
	local GIVE_UP_AFTER = 12
	local GIVE_UP_FOR = 600
	local parked = {}

	-- Anything that costs money is a special case, and getting it wrong cost an
	-- account ten minutes of bouncing between servers.
	--
	-- Auto Upgrade Treadmill asked to buy the next rung every twenty seconds. He
	-- could not afford it - the one above Golden is three billion - so that was
	-- twelve refusals in four minutes, which is exactly the shape this game
	-- kicks for. Money does not arrive in twenty seconds. A refused purchase is
	-- worth trying again in five minutes and not before, and three in a row is
	-- enough to stop asking until something changes.
	local BUYING_AFTER = 3
	local BUYING_WAIT = 300

	local function refused(key, interval)
		local count = (failures[key] or 0) + 1
		failures[key] = count
		if BUYING[key] then
			refusedAt[key] = money()
			if count >= BUYING_AFTER then
				nextDue[key] = os.clock() + GIVE_UP_FOR
				if not parked[key] then
					parked[key] = true
					warn(("[Meridian] cannot afford %s, leaving it alone for a while"):format(key))
				end
			else
				nextDue[key] = os.clock() + BUYING_WAIT
			end
			return count
		end
		if count >= GIVE_UP_AFTER then
			nextDue[key] = os.clock() + GIVE_UP_FOR
			if not parked[key] then
				parked[key] = true
				warn(("[Meridian] %s has been refused %d times, leaving it alone for a while"):format(key, count))
			end
			return count
		end
		local ceiling = BACKOFF_MAX[key] or BACKOFF_CAP
		nextDue[key] = os.clock() + math.min(interval * (2 ^ count), ceiling)
		return count
	end

	local function accepted(key)
		failures[key] = nil
		parked[key] = nil
		refusedAt[key] = nil
		nextDue[key] = nil
	end

	-- One way to reach the server, and it looks up what it is talking to first.
	--
	-- Network.Fire calls FireServer and Network.Invoke calls InvokeServer, and
	-- which one is right is a property of the remote, not of what you are trying
	-- to do. Treadmills: RequestUnequip is a RemoteFunction; firing it threw
	-- "FireServer is not a valid member of RemoteFunction" on every attempt, and
	-- a client throwing that at the server several times a second is what got
	-- this account kicked three times.
	--
	-- Worse, four of the names in NETWORK_MAP have no remote in the folder at
	-- all. Reaching for one of those is the documented way to poison this game's
	-- network layer: it creates a BindableEvent under the Network folder, the
	-- name caches in the wrong slot, and every later Invoke on any name comes
	-- back as an Instance instead of the server's reply, until the client
	-- rejoins.
	--
	-- So nothing is called by name alone. Find the remote, use the method it
	-- actually is, and if it is not there, do nothing and say so.
	local NetworkFolder = ReplicatedStorage:FindFirstChild("Network")

	-- Nothing in the farm tick may wait on the server, and this is not theory.
	--
	-- Treadmills.REQUEST_UNEQUIP proved it. Called from the tick while the
	-- character was anchored to a treadmill, InvokeServer never came back. The
	-- farm stopped where it stood with its legs still running on the spot, the
	-- headline said "Planting it" for four minutes, and every later call queued
	-- behind the one that was never going to answer. A loop that ticks ten times
	-- a second cannot be the thread that waits for a reply that may not come.
	--
	-- So a request goes out on its own thread with a deadline. The tick gets the
	-- answer if one arrives in time and "no answer" if not, which is a perfectly
	-- good answer here because every action is on a gate that will try again.
	local ANSWER_WITHIN = 2.5

	local function answerWithin(fn, ...)
		local args = table.pack(...)
		local state = { done = false }
		task.spawn(function()
			local ok, value, reason = pcall(fn, table.unpack(args, 1, args.n))
			state.ok, state.value, state.reason, state.done = ok, value, reason, true
		end)
		local deadline = os.clock() + ANSWER_WITHIN
		while not state.done and os.clock() < deadline do
			task.wait()
		end
		if not state.done then
			return false, "the server did not answer"
		end
		if not state.ok then
			return false, tostring(state.value)
		end
		return state.value ~= false, state.reason
	end

	local function ask(action, ...)
		if type(action) ~= "string" then
			return false, "no such action"
		end
		local folder = NetworkFolder
		if not folder or not folder.Parent then
			folder = ReplicatedStorage:FindFirstChild("Network")
			NetworkFolder = folder
		end
		local remote = folder and folder:FindFirstChild(action)
		if not remote then
			return false, "this game has no " .. action
		end
		if remote:IsA("RemoteFunction") then
			return answerWithin(Network.Invoke, action, ...)
		end
		if remote:IsA("RemoteEvent") then
			local ok, err = pcall(Network.Fire, action, ...)
			if ok then
				return true
			end
			return false, tostring(err)
		end
		return false, action .. " is a " .. remote.ClassName
	end

	----------------------------------------------------------------------------
	-- the snapshot
	----------------------------------------------------------------------------

	-- Kept fresh by the game's own signals rather than by asking every tick.
	-- Asking is a round trip and the game already tells us when anything moves.
	local snapshot = { Records = {} }

	local function refreshSnapshot()
		local ok, result = pcall(EggCmds.RequestAreaEggSnapshot)
		if ok and type(result) == "table" and type(result.Records) == "table" then
			snapshot = result
			return true
		end
		return false
	end

	local function cachedSnapshot()
		local ok, result = pcall(EggCmds.GetAreaEggSnapshot)
		if ok and type(result) == "table" and type(result.Records) == "table" then
			snapshot = result
		end
		return snapshot
	end

	for _, signalName in ipairs({ "AreaEggSnapshotUpdated", "AreaEggUpdated", "AreaEggRemoved" }) do
		local signal = EggCmds[signalName]
		if type(signal) == "table" and signal.Connect then
			core:Connect(signal, function()
				cachedSnapshot()
			end)
		end
	end

	-- Carrying is a signal, not a tool, and getting this wrong is what made the
	-- farm look broken.
	--
	-- An area egg you pick up never becomes a Tool in your backpack. The server
	-- fires AreaEggCarryStateChanged with { IsCarrying, Uid, SpeedMultiplier }
	-- and the game renders you holding it. The game's own module for this is
	-- called CarryRunBackEffects, which is the loop in one word.
	--
	-- The first version looked for a Tool with a uid on it. Hatched pets are
	-- Tools with uids, so a full backpack read as "carrying" forever and the
	-- farm never went for another egg; filtering those out left it recognising
	-- nothing at all, so it never went home either and just kept hunting with an
	-- egg in its hands. Both symptoms, one wrong question.
	local carrying = { active = false, uid = nil, slowedTo = 1 }

	do
		local signal = EggCmds.AreaEggCarryStateChanged
		if type(signal) == "table" and signal.Connect then
			core:Connect(signal, function(state)
				if type(state) ~= "table" then
					return
				end
				carrying.active = state.IsCarrying == true
				carrying.uid = carrying.active and state.Uid or nil
				carrying.slowedTo = tonumber(state.SpeedMultiplier) or 1
			end)
		end
	end

	local function carriedUid()
		if carrying.active and carrying.uid then
			return carrying.uid
		end
		-- The signal only fires on a change, so a hub loaded while already
		-- holding one has never heard it. The snapshot knows.
		for _, record in ipairs(cachedSnapshot().Records) do
			if record.State == "Carried" and tostring(record.CarrierUserId or record.OwnerUserId or "") == tostring(LocalPlayer.UserId) then
				return record.Uid
			end
		end
		return nil
	end

	----------------------------------------------------------------------------
	-- choosing
	----------------------------------------------------------------------------

	-- Everything the farm knows about the map, ranked, once per tick. Kept as
	-- one function so the ESP and the farm cannot ever disagree about which egg
	-- is the good one - they read the same list.
	-- Which area the farm settled on, so the interface can say so rather than
	-- leaving him to work it out from where the character is standing.
	local chosenArea = nil

	-- How much better a lower area has to be before the farm moves to it.
	local ESCAPE_MULTIPLE = 3

	local function rankedEggs()
		local me = myPosition()
		if not me then
			return {}
		end

		local allowed = F.stealAreas
		local allowedSet = nil
		if type(allowed) == "table" and #allowed > 0 and #allowed < #AREA_NAMES then
			allowedSet = {}
			for _, name in ipairs(allowed) do
				allowedSet[name] = true
			end
		end

		local floor = tonumber(F.stealFloor) or 0
		local reach = tonumber(F.stealRange) or 4000
		local mode = F.stealPick or "Most Valuable"
		local mutatedOnly = F.stealMutated == true

		-- Everything takeable, bucketed by area, so the area can be chosen before
		-- the egg is.
		local byArea = {}
		for _, record in ipairs(cachedSnapshot().Records) do
			local position = eggPosition(record)
			if position and record.State == "Slot" and not isStarterEgg(record) then
				local distance = (position - me).Magnitude
				local worth = eggWorth(record)
				local mutations = mutationList(record)
				local pass = distance <= reach
					and worth >= floor
					and (not allowedSet or allowedSet[record.AreaId])
					and (not mutatedOnly or #mutations > 0)
				if pass then
					local bucket = byArea[record.AreaId]
					if not bucket then
						bucket = {}
						byArea[record.AreaId] = bucket
					end
					bucket[#bucket + 1] = {
						record = record,
						position = position,
						distance = distance,
						worth = worth,
						mutations = mutations,
					}
				end
			end
		end

		-- Settle the area first. The best area we can get out of, and if it has
		-- nothing worth taking this minute, the next one down rather than
		-- standing still. Only when the gate is switched off does it go back to
		-- ranking every egg on the map against every other, which is the thing
		-- that sent it to Snow.
		local out = {}
		if F.stealOutrun == false then
			for _, bucket in pairs(byArea) do
				table.move(bucket, 1, #bucket, #out + 1, out)
			end
		else
			local tiers = areasByTier()
			local home, homeBest = nil, 0
			for _, area in ipairs(tiers) do
				local bucket = byArea[area.id]
				if bucket and #bucket > 0 then
					home = bucket
					chosenArea = area.id
					for _, egg in ipairs(bucket) do
						if egg.worth > homeBest then
							homeBest = egg.worth
						end
					end
					break
				end
			end
			out = home or {}

			-- The top area is home, and it stays home even on a thin minute.
			-- But when it has been picked clean and something several times
			-- better is sitting in an area below, the walk is the same walk and
			-- the trade goes the other way. Several times, not slightly: one
			-- lucky Snow egg beating one Volcano egg is not a reason to move
			-- house, which is the thing he caught it doing.
			if home then
				for _, area in ipairs(tiers) do
					if area.id ~= chosenArea then
						for _, egg in ipairs(byArea[area.id] or {}) do
							if egg.worth > homeBest * ESCAPE_MULTIPLE then
								out = byArea[area.id]
								chosenArea = area.id
								homeBest = egg.worth
							end
						end
					end
				end
			end
		end

		-- Three honest answers to "which one", not one dressed three ways.
		--
		-- Most Valuable ignores the walk entirely and is right when you are
		-- farming unattended. Nearest is what every other script does and is
		-- here so the difference is visible. Best Nearby is the one worth
		-- defaulting to: worth per second of walking, which is the only
		-- question that has a correct answer when both cost you time.
		if mode == "Nearest" then
			table.sort(out, function(a, b)
				return a.distance < b.distance
			end)
		elseif mode == "Best Nearby" then
			-- Studs, not seconds, because we do not know the walk speed the
			-- server will give us and the ordering is the same either way. The
			-- 40 keeps an egg three studs away from dividing by nothing and
			-- winning on a rounding error.
			table.sort(out, function(a, b)
				return a.worth / (a.distance + 40) > b.worth / (b.distance + 40)
			end)
		else
			table.sort(out, function(a, b)
				if a.worth ~= b.worth then
					return a.worth > b.worth
				end
				return a.distance < b.distance
			end)
		end

		return out
	end

	----------------------------------------------------------------------------
	-- the farm
	----------------------------------------------------------------------------

	-- Measured, by walking in on one egg and asking at every step: refused at
	-- 21.1 studs and accepted at 15.4. So the wall is somewhere between, and
	-- closing to 12 leaves room for the server disagreeing with us about where
	-- we are standing.
	local STEAL_REACH = 12

	local stats = {
		taken = 0,
		placed = 0,
		earned = 0,
		started = os.clock(),
	}

	-- Assigned by the walker further down, which is defined after this.
	local clearRoute
	local stopWalking

	local currentTarget = nil
	local targetSince = 0
	local nextAttempt = 0
	local lastSaid = {}

	local function sayOnce(key, title, body)
		if os.clock() - (lastSaid[key] or 0) < 8 then
			return
		end
		lastSaid[key] = os.clock()
		core:Notify(title, body, 4)
	end

	local function dropTarget()
		currentTarget = nil
		clearRoute()
		-- Whatever the last egg refused for was about that egg. Starting the next
		-- one already throttled is how a farm talks itself into standing still.
		accepted("carry")
	end

	-- The egg you carried home is not the egg you plant, and that one sentence
	-- is why nothing was ever planted.
	--
	-- An area egg in transit is a carry state: a uid on a signal, no Tool
	-- anywhere. The moment you cross into your own plot the server claims it,
	-- and *then* it becomes a Tool with ItemType "AssetEgg" and a UID attribute
	-- of its own - a different uid from the area egg's. Placement wants that
	-- one. Passing the area uid gets a polite refusal forever.
	--
	-- Measured: carry uid FirstAreaEgg_699240826_5957263_Volcano:Slot_004,
	-- tool uid 236f63e8eedc402ea0a4584c916490ce, and the second one placed.
	local function heldEggTool()
		local character = LocalPlayer.Character
		local pack = LocalPlayer:FindFirstChild("Backpack")
		for _, place in ipairs({ character, pack }) do
			for _, item in ipairs(place and place:GetChildren() or {}) do
				if item:IsA("Tool") and item:GetAttribute("ItemType") == "AssetEgg" then
					local uid = item:GetAttribute("UID")
					if type(uid) == "string" then
						return uid, item
					end
				end
			end
		end
		return nil
	end

	-- Somewhere on your own base to put it down. The game raycasts from wherever
	-- the player is pointing; a farm has nobody pointing, so it picks its own
	-- spot. Under your own feet first, because you are standing on the pad and
	-- that spot is reachable by definition; then a spiral outward, because the
	-- server refuses a spot that is already taken and walking outward finds a
	-- free one in a couple of tries instead of never.
	local placeAttempt = 0

	local function placementCFrame(data)
		local pad = data.PetArea
		if not pad or not pad:IsA("BasePart") then
			return nil
		end
		local half = pad.Size / 2
		local root = core:Root()
		local base = pad.Position
		if root then
			local relative = pad.CFrame:PointToObjectSpace(root.Position)
			base = pad.CFrame:PointToWorldSpace(Vector3.new(
				math.clamp(relative.X, -half.X * 0.85, half.X * 0.85),
				0,
				math.clamp(relative.Z, -half.Z * 0.85, half.Z * 0.85)
			))
		end
		local world = base
		if placeAttempt > 0 then
			-- A spiral, so consecutive attempts are never neighbours and a full
			-- row does not have to be walked one stud at a time.
			local turn = placeAttempt * 2.399963
			local out = math.min(placeAttempt * 2.4, math.min(half.X, half.Z) * 0.9)
			world = base + Vector3.new(math.cos(turn) * out, 0, math.sin(turn) * out)
			local relative = pad.CFrame:PointToObjectSpace(world)
			world = pad.CFrame:PointToWorldSpace(Vector3.new(
				math.clamp(relative.X, -half.X * 0.9, half.X * 0.9),
				0,
				math.clamp(relative.Z, -half.Z * 0.9, half.Z * 0.9)
			))
		end
		placeAttempt = placeAttempt + 1
		return data.CenterPoint.CFrame:ToObjectSpace(CFrame.new(world))
	end

	-- Six refusals in a row is a base that is full or an egg the game will not
	-- take, not a spot that was unlucky. Past that it stops asking rather than
	-- asking louder.
	local PLACE_INTERVAL = 1.2
	local PLACE_GIVE_UP = 6

	local function tryPlace(uid)
		if not due("place", PLACE_INTERVAL) then
			return false
		end
		local data = plotData()
		if not data or not data.CenterPoint then
			refused("place", PLACE_INTERVAL)
			return false, "No base yet"
		end
		-- The server only takes it from someone standing on their own plot, and
		-- refusing to ask from outside is cheaper than being told.
		local root = core:Root()
		local here = root and PlotCmds.IsWorldPositionWithinLocalPlotBounds(root.Position)
		if not here then
			return false, "Not home yet"
		end
		local localCFrame = placementCFrame(data)
		if not localCFrame then
			refused("place", PLACE_INTERVAL)
			return false, "No base yet"
		end
		local took, reason = answerWithin(EggCmds.RequestPlaceEgg, uid, localCFrame)
		local ok = true
		if took then
			accepted("place")
			placeAttempt = 0
			stats.placed = stats.placed + 1
			return true
		end
		local count = refused("place", PLACE_INTERVAL)
		if count >= PLACE_GIVE_UP then
			return false, tostring(ok and reason or took), true
		end
		return false
	end

	-- Walking, which turned out to be the hard part of this whole module.
	--
	-- Three things had to be true at once and each one broke it alone.
	--
	-- **It has to path, not aim.** The base is walled off from the areas. A
	-- straight line at an egg seven hundred studs away puts the character into
	-- that wall, where it stands with a MoveTo target nine studs ahead and
	-- covers no ground at all. That is the "walks for a bit and then stops"
	-- and no amount of re-aiming fixes it, because the aim was never wrong.
	--
	-- **MoveTo gives up after eight seconds**, so a distant target is never
	-- reached even in open ground.
	--
	-- **And it steers rather than re-targeting.** Thirty-four waypoints over a
	-- hundred studs would mean a fresh order every few studs, and each one
	-- interrupts the humanoid's own acceleration. It aims at the waypoint about
	-- fifty studs along instead, which follows the same route at a run.
	local PathfindingService = game:GetService("PathfindingService")

	local WAYPOINT_REACHED = 8
	local ROUTE_MOVED = 25
	local ROUTE_RETRY = 2
	local ROUTE_LOST = 60

	local route = { goal = nil, points = nil, index = 1, busy = false, failedAt = 0 }

	function clearRoute()
		route.goal, route.points, route.index = nil, nil, 1
	end

	-- ComputeAsync yields, and the farm loop must never yield, so the path is
	-- worked out on its own thread and the loop just reads whatever is ready.
	local function planRoute(goal)
		if route.busy or os.clock() - route.failedAt < ROUTE_RETRY then
			return
		end
		route.busy = true
		task.spawn(function()
			local root = core:Root()
			if root then
				local path = PathfindingService:CreatePath({
					AgentRadius = 3,
					AgentHeight = 6,
					AgentCanJump = true,
					AgentMaxSlope = 60,
				})
				local ok = pcall(function()
					path:ComputeAsync(root.Position, goal)
				end)
				if ok and path.Status == Enum.PathStatus.Success then
					route.goal = goal
					route.points = path:GetWaypoints()
					-- The first waypoint is where we already are.
					route.index = math.min(2, #route.points)
				else
					clearRoute()
					route.failedAt = os.clock()
				end
			end
			route.busy = false
		end)
	end

	local function flatDistance(a, b)
		return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
	end

	-- How far along the path to aim, which is the thing that decides whether the
	-- character follows the route or leans on a wall next to it.
	--
	-- Aiming fifty studs ahead regardless is what parked it against
	-- "COLLISIONS.GUARD NO COLLIDE.WALL RIGHT" for a whole minute with a valid
	-- three hundred waypoint path to Volcano in hand and MoveDirection pointing
	-- east. On a route that turns, the point fifty studs along is *through* the
	-- corner, and steering at a point through a wall walks into the wall.
	--
	-- The fifty was inherited from the MoveTo version, where each new target was
	-- an order that interrupted the humanoid's acceleration and so had to be
	-- given rarely. Steering does not issue orders, it sets a direction per
	-- frame, and changing that costs nothing. So aim as far ahead as can
	-- actually be seen, and no further.
	local WALK_LOOKAHEAD_STEPS = 10
	local sightParams = RaycastParams.new()
	sightParams.FilterType = Enum.RaycastFilterType.Exclude
	sightParams.IgnoreWater = true

	local function canSee(from, to)
		local character = LocalPlayer.Character
		sightParams.FilterDescendantsInstances = character and { character } or {}
		local eye = from + Vector3.new(0, 2, 0)
		local aim = Vector3.new(to.X, from.Y + 2, to.Z)
		local reach = aim - eye
		if reach.Magnitude < 0.5 then
			return true
		end
		return Workspace:Raycast(eye, reach, sightParams) == nil
	end

	local function lookAhead(from)
		local points = route.points
		if not points then
			return nil
		end

		-- Move to whichever waypoint ahead is nearest, rather than stepping one
		-- at a time. At a hundred and twenty studs a second a tenth of a second
		-- covers twelve studs and the waypoints are four apart, so stepping one
		-- at a time leaves the aim pointing at something already behind us.
		local nearest, nearestAt = route.index, math.huge
		for i = route.index, math.min(route.index + 16, #points) do
			local distance = flatDistance(points[i].Position, from)
			if distance < nearestAt then
				nearest, nearestAt = i, distance
			end
		end
		-- A long way from every waypoint means the route is about a journey we
		-- are no longer on: shoved by a guard, knocked off a ledge, teleported.
		-- Throw it away rather than steering back to a path that has stopped
		-- being the shortest way anywhere.
		if nearestAt > ROUTE_LOST then
			clearRoute()
			return nil
		end
		route.index = nearest
		if nearestAt <= WAYPOINT_REACHED and route.index < #points then
			route.index = route.index + 1
		end

		local pick = route.index
		for i = route.index + 1, math.min(route.index + WALK_LOOKAHEAD_STEPS, #points) do
			if not canSee(from, points[i].Position) then
				break
			end
			pick = i
		end
		return points[pick], points[route.index]
	end

	-- And the movement itself is Humanoid:Move on a render step, not MoveTo.
	--
	-- The game's ControlModule binds to RenderStep at Input priority and calls
	-- Humanoid:Move every frame with whatever the keyboard says, which is zero
	-- when nobody is holding a key. That cancels any MoveTo instantly, so the
	-- character stood still with a perfectly good target nine studs ahead.
	--
	-- Disabling the control module works when you can reach it, and often you
	-- cannot: PlayerScripts is missing outright for a while after a rejoin, and
	-- "PlayerScripts is not a valid member of Player" is not something a farm
	-- should depend on not happening. So instead of switching their steering
	-- off, this runs one step later in the same frame and steers itself. Same
	-- call they make, same frame, ours last.
	local steer = { direction = nil }

	function stopWalking()
		steer.direction = nil
		local hum = core:Humanoid()
		if hum then
			pcall(function()
				hum:Move(Vector3.zero, false)
			end)
		end
	end

	core:Track(function()
		steer.direction = nil
		pcall(function()
			RunService:UnbindFromRenderStep("MeridianSteer")
		end)
	end)

	pcall(function()
		RunService:BindToRenderStep("MeridianSteer", Enum.RenderPriority.Input.Value + 5, function()
			local hum = core:Humanoid()
			if not hum or hum.Health <= 0 then
				return
			end
			if steer.direction then
				hum:Move(steer.direction, false)
			end
		end)
	end)

	local function walkTo(goal, standoff)
		local root, hum = core:Root(), core:Humanoid()
		if not root or not hum or hum.Health <= 0 then
			steer.direction = nil
			return false
		end

		if flatDistance(goal, root.Position) <= (standoff or 0) then
			clearRoute()
			steer.direction = nil
			return true
		end

		if not route.goal or (goal - route.goal).Magnitude > ROUTE_MOVED then
			planRoute(goal)
		end

		local aim, next_ = lookAhead(root.Position)
		local target = aim and aim.Position or goal

		-- Jump waypoints have to be acted on as they come up, or the character
		-- runs at a ledge and stops there.
		if next_ and next_.Action == Enum.PathWaypointAction.Jump then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end

		local flat = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
		if flat.Magnitude < 0.5 then
			steer.direction = nil
			return false
		end
		steer.direction = flat.Unit
		return false
	end

	-- Only when we are actually on it.
	--
	-- The first version fired this every few seconds whenever the character had
	-- not moved, whatever the reason. It spent ninety seconds telling the server
	-- to take us off a treadmill we were seventeen studs away from, about thirty
	-- times, which is precisely the shape of thing that gets an account kicked -
	-- a request that cannot possibly succeed, repeated.
	-- Standing near a treadmill is not standing on one, and that difference got
	-- the account kicked again.
	--
	-- The proximity guess said "on it" for anything within twelve studs of
	-- TreadmillBottom, and the pet pad is inside that circle. So the moment the
	-- farm walked home to plant an egg and stood still to do it, the stuck
	-- watcher decided it was stuck on the treadmill and asked the server to take
	-- it off, every four seconds, for as long as it stood there. An impossible
	-- request on repeat, which is the one thing this game reliably kicks for.
	--
	-- The server says so itself: ActiveTreadmillChanged fires with the treadmill
	-- you are on, or with nothing when you get off. Ask the game, not the map.
	local treadmill = { active = nil }

	do
		local ok, signal = pcall(Network.Fired, NET.Treadmills.ACTIVE_TREADMILL_EVENT)
		if ok and type(signal) == "table" and signal.Connect then
			core:Connect(signal, function(which)
				treadmill.active = which ~= nil
			end)
		end
	end

	local TREADMILL_RANGE = 12

	local function nearTreadmill()
		local root = core:Root()
		local data = plotData()
		local folder = data and data.PlotFolder
		if not root or not folder then
			return false
		end
		local bottom = folder:FindFirstChild("TreadmillBottom", true)
		if not bottom or not bottom:IsA("BasePart") then
			return false
		end
		return (bottom.Position - root.Position).Magnitude <= TREADMILL_RANGE
	end

	local function onTreadmill()
		if treadmill.active ~= nil then
			return treadmill.active
		end
		-- The event has never fired, which is what a hub loaded while already
		-- standing on one looks like. Proximity is all there is until it does,
		-- and being wrong once is survivable where being wrong forever is not.
		return nearTreadmill()
	end

	-- Standing on the treadmill instead of farming, and when a night is better
	-- spent that way.
	--
	-- "Try to understand if you are at a level where you need better money, so
	-- you are going to spend as much time on the treadmill as possible." The
	-- treadmill pays Speed Power, Speed Power is the gate on every area, and the
	-- areas are where the money is. Volcano wants 900K and Abyss Ocean wants
	-- 2.5M, and an Abyss egg is worth a tier more than a Volcano one for as long
	-- as it lives.
	--
	-- Measured on a Golden treadmill: about four thousand Speed Power a second
	-- standing on it, against about fourteen hundred while farming - walking
	-- pays Speed too, so the farm is never standing still on this. Three times
	-- faster, and no eggs. Which makes the answer: grind only when it buys the
	-- next area, and only when the next area is close enough to reach in a
	-- sitting rather than over a night.
	--
	-- The rate is measured rather than assumed, because it multiplies by eighty
	-- across the treadmill ladder and the number below is one rung of it.
	local TREADMILL_RATE = 4000
	local TREADMILL_PATIENCE = 900

	local rate = { estimate = TREADMILL_RATE, at = 0, power = nil }

	local function watchTreadmillRate(power)
		if not treadmill.active then
			rate.at, rate.power = 0, nil
			return
		end
		local now = os.clock()
		if not rate.power then
			rate.at, rate.power = now, power
			return
		end
		local span = now - rate.at
		if span < 15 then
			return
		end
		local seen = (power - rate.power) / span
		rate.at, rate.power = now, power
		if seen > 1 then
			-- Slowly, so one unlucky window does not talk it out of a rung it
			-- has actually bought.
			rate.estimate = rate.estimate * 0.7 + seen * 0.3
		end
	end

	-- The next sign above us, and how long the treadmill would take to reach it.
	local function nextAreaGap()
		readSigns()
		local power = mySpeedPower()
		local need, id = nil, nil
		for area, sign in pairs(AREA_NEEDS) do
			if sign > power and (not need or sign < need) then
				need, id = sign, area
			end
		end
		if not need then
			return nil
		end
		return need - power, id, need
	end

	local function worthGrinding()
		local gap, area = nextAreaGap()
		if not gap then
			return false
		end
		return gap / math.max(rate.estimate, 1) <= TREADMILL_PATIENCE, area, gap
	end

	local function treadmillSpot()
		local data = plotData()
		local folder = data and data.PlotFolder
		local bottom = folder and folder:FindFirstChild("TreadmillBottom", true)
		return bottom and bottom:IsA("BasePart") and bottom.Position or nil
	end

	-- Getting off, which matters more than it sounds: a treadmill anchors the
	-- root part, so a farm that steps on one on the way out of its own base and
	-- cannot get off again is a farm that has finished for the night. The path
	-- out of the base runs straight over it.
	--
	-- The remote is the first try and it is the one that hung. The second try is
	-- the game's own route: it binds UserInputService.JumpRequest and calls the
	-- same remote from there with its own in-flight guard, so running those
	-- handlers is a player pressing space rather than us racing the game on one
	-- RemoteFunction. Real's firesignal is a silent no-op, but getconnections
	-- hands back the functions themselves, and native input is no use here
	-- because it needs the window focused and an unattended farm's window is not.
	local UserInputService = game:GetService("UserInputService")

	local function jumpOff()
		local list = getconnections and getconnections(UserInputService.JumpRequest)
		if type(list) ~= "table" or #list == 0 then
			return false
		end
		for _, connection in ipairs(list) do
			local handler = connection.Function
			if type(handler) == "function" then
				-- Spawned, because the game's own handler invokes the server and
				-- we are not going to wait on it either.
				task.spawn(function()
					pcall(handler)
				end)
			end
		end
		return true
	end

	local function leaveTreadmill()
		if not onTreadmill() then
			return false
		end
		if not due("treadmillOff", 4) then
			return false
		end
		local ok = ask(NET.Treadmills.REQUEST_UNEQUIP)
		if ok then
			treadmill.active = false
			accepted("treadmillOff")
			return true
		end
		local count = refused("treadmillOff", 4)
		if count >= 2 then
			jumpOff()
		end
		return false
	end

	-- Home is the pet pad, not the spawn point, and the difference is the whole
	-- of a complaint.
	--
	-- RespawnPointCFrame sits about fourteen studs from the treadmill and fifty
	-- from the pad. Walking there meant arriving on the treadmill every single
	-- trip - which pulls you into treadmill mode and is exactly what an AFK
	-- player does not want happening to them - while still being nowhere near
	-- the place an egg can actually be put down. Go where the egg is going.
	local homeSpot = nil

	local function homeTarget()
		local data = plotData()
		local pad = data and data.PetArea
		if not pad or not pad:IsA("BasePart") then
			return data and data.RespawnPointCFrame and data.RespawnPointCFrame.Position or nil
		end
		-- The near edge rather than the middle, so arriving does not mean
		-- crossing the whole pad and walking over eggs that are already down.
		local root = core:Root()
		if not root then
			return pad.Position
		end
		local toward = pad.CFrame:PointToObjectSpace(root.Position)
		local half = pad.Size / 2
		local x = math.clamp(toward.X, -half.X * 0.6, half.X * 0.6)
		local z = math.clamp(toward.Z, -half.Z * 0.6, half.Z * 0.6)
		homeSpot = pad.CFrame:PointToWorldSpace(Vector3.new(x, 0, z))
		return homeSpot
	end

	local function goHome()
		local target = homeTarget()
		if not target then
			return false
		end
		return walkTo(target, 6)
	end

	-- If an order has been standing for a few seconds and the character has not
	-- covered any ground, something is holding it: the treadmill, almost always.
	local stuckFrom, stuckAt = nil, nil

	-- Standing still on purpose is not being stuck, and the treadmill is the one
	-- place where the two look identical.
	local grinding = false

	local function watchForStuck()
		if grinding then
			stuckFrom = nil
			return
		end
		local root = core:Root()
		if not root then
			return
		end
		local now = os.clock()
		if not stuckFrom or (root.Position - stuckFrom).Magnitude > 12 then
			stuckFrom, stuckAt = root.Position, now
			return
		end
		if now - stuckAt > 3 then
			stuckAt = now
			if not leaveTreadmill() then
				-- Not the treadmill, so it is the path: a route computed from
				-- somewhere we are no longer standing, or one that runs into
				-- something that has since moved. Throw it away and let the next
				-- tick work out a new one. Asking the server about it would be
				-- asking the wrong party.
				clearRoute()
				-- And jump, because a good half of these are a lip an inch high
				-- that the humanoid will not walk up and will hop over without
				-- being asked twice.
				local hum = core:Humanoid()
				if hum then
					pcall(function()
						hum:ChangeState(Enum.HumanoidStateType.Jumping)
					end)
				end
			end
		end
	end

	core:Loop("steal", 0.1, function()
		if not F.autoSteal then
			if currentTarget then
				dropTarget()
			end
			stuckFrom = nil
			-- Switching the farm off has to stop the legs too. It did not, and the
			-- character carried on walking wherever it had last been pointed, with
			-- nothing running to ever stop it.
			stopWalking()
			return
		end

		-- Anything that holds the character still gets one nudge every few
		-- seconds. On this map that is the treadmill and only the treadmill.
		watchForStuck()
		if not core:Alive2() then
			dropTarget()
			return
		end

		-- A trip has three states, not two, and the third one is the one that was
		-- missing: an egg that is already yours and is still in your hands.
		--
		--   carrying  - an area egg in transit, walk it home
		--   holding   - claimed on arrival, now a Tool, walk to the pad and plant
		--   neither   - go find one
		--
		-- Holding is checked first. Crossing into the plot ends the carry and
		-- starts the hold in the same instant, and a farm that only knows about
		-- carrying reads that as "trip over" and walks straight back out with
		-- the egg still in its hands. Which is exactly what he watched happen.
		local eggUid, eggTool = heldEggTool()
		if eggUid then
			currentTarget = nil
			if F.basePlace == false then
				return
			end
			-- On the pad, not merely inside the fence. The plot is big and the
			-- pad is the part of it an egg can go on.
			if not goHome() then
				return
			end
			local hum = core:Humanoid()
			if eggTool and eggTool.Parent ~= LocalPlayer.Character and hum then
				pcall(function()
					hum:EquipTool(eggTool)
				end)
			end
			local placed, reason, gaveUp = tryPlace(eggUid)
			if placed then
				stopWalking()
			elseif gaveUp then
				-- A base that is full is the one refusal the user has to do
				-- something about, and by this point it has been refused six times,
				-- so it is not bad luck.
				sayOnce("place", "Could not plant it", tostring(reason))
			end
			return
		end

		local held = carriedUid()
		if held then
			-- Carrying. Nothing else matters until it is home.
			currentTarget = nil
			if F.stealCarryHome == false then
				return
			end
			if not plotData() then
				return
			end
			goHome()
			return
		end

		-- Hands empty, so the question is what the next hour is worth more spent
		-- on. Almost always eggs. Occasionally the treadmill, when the next area
		-- is one sitting away and a whole tier of egg is on the other side of it.
		if F.speedGrind ~= false then
			local grind, area, gap = worthGrinding()
			if grind then
				local spot = treadmillSpot()
				if spot then
					if not grinding then
						grinding = true
						currentTarget = nil
						core:Notify(
							"Meridian",
							("Riding the treadmill for %s, %s of Speed to go"):format(tostring(area), short(gap)),
							6
						)
					end
					if walkTo(spot, 3) then
						stopWalking()
					end
					return
				end
			end
		end

		if grinding then
			grinding = false
			-- Off it deliberately, or the farm walks its next trip at treadmill
			-- pace, which is no pace at all.
			leaveTreadmill()
		end

		-- Not carrying, so find something worth walking to.
		if currentTarget then
			local fresh = EggCmds.GetAreaEggRecord and select(2, pcall(EggCmds.GetAreaEggRecord, currentTarget.record.Uid))
			if type(fresh) == "table" and fresh.State ~= "Slot" then
				-- Somebody else got there first.
				dropTarget()
				return
			end
			if os.clock() - targetSince > (tonumber(F.stealGiveUp) or 25) then
				sayOnce("giveup", "Gave up", ("Could not reach the %s"):format(eggName(currentTarget.record)))
				dropTarget()
				return
			end
		end

		if not currentTarget then
			local best = rankedEggs()[1]
			if not best then
				return
			end
			currentTarget = best
			targetSince = os.clock()
			nextAttempt = 0
			accepted("carry")
		end

		local position = eggPosition(currentTarget.record) or currentTarget.position
		local me = myPosition()
		local areaId = currentTarget.record.AreaId

		-- Through the door first. Nothing about the egg matters until we are on
		-- the right side of the fence.
		if me and not insideArea(areaId, me) then
			local door = areaEntrance(areaId)
			if door then
				walkTo(door, 6)
				return
			end
		end

		local arrived = walkTo(position, STEAL_REACH)
		if not arrived then
			return
		end

		if os.clock() < nextAttempt then
			return
		end
		if not due("carry", math.max(tonumber(F.stealDelay) or 0.2, 0.5)) then
			return
		end
		nextAttempt = os.clock() + (tonumber(F.stealDelay) or 0.2)

		-- The wrapper raises rather than returning false when the server says
		-- no, and the message it raises is the server's own wording, so this is
		-- the one place in the hub where an error is the useful reply.
		-- It refuses two different ways depending on why. Out of reach comes back
		-- as a plain false with a reason; some others are raised. Treating pcall
		-- succeeding as the egg being taken counted every refusal as a win, which
		-- is why the farm reported nothing and stood still.
		local took, reason = answerWithin(EggCmds.RequestCarryAreaEgg, currentTarget.record.Uid)
		local ok = true
		if took then
			accepted("carry")
			stats.taken = stats.taken + 1
			stats.earned = stats.earned + currentTarget.worth
			core:Notify(
				"Took " .. eggName(currentTarget.record),
				("%s a second%s"):format(
					short(currentTarget.worth),
					#currentTarget.mutations > 0 and (" · " .. table.concat(currentTarget.mutations, ", ")) or ""
				),
				3
			)
			dropTarget()
			return
		end

		local message = tostring(ok and reason or took)
		if message:find("Enter the gameplay area") then
			-- Refused because we are outside the fence, which the approach above
			-- is meant to have prevented. Back off rather than asking again on
			-- the next tick, and give up on this one if it keeps happening.
			if refused("carry", 1) >= 4 then
				dropTarget()
			end
			return
		end

		-- Starter area eggs are addressed by a compound key and come back "Egg
		-- not found" when asked for the ordinary way. They are also the cheapest
		-- things on the map, so there is nothing to gain by solving it.
		if message:find("Egg not found") then
			dropTarget()
			return
		end
		sayOnce("refuse", "Could not take it", message:gsub("^.-:%d+:%s*", ""))
		dropTarget()
	end)

	----------------------------------------------------------------------------
	-- base
	----------------------------------------------------------------------------

	-- Your own eggs, and only yours.
	--
	-- The first version read GetRuntimeSnapshot, which is every player's eggs
	-- keyed by owner, and then looked for a Uid field on each entry. There is no
	-- Uid field: the uid is the key. So it returned an empty list every time and
	-- auto hatch has never once hatched anything. GetOwnerRuntimeRecords asks
	-- the question that was meant.
	local function ownEggs()
		local ok, records = pcall(EggCmds.GetOwnerRuntimeRecords, LocalPlayer.UserId)
		if not ok or type(records) ~= "table" then
			return {}
		end
		local out = {}
		for uid, record in pairs(records) do
			if type(uid) == "string" and type(record) == "table" then
				out[#out + 1] = { uid = uid, record = record }
			end
		end
		return out
	end

	-- "If it beats what you have, keep it. No space, so throw out the worst and
	-- plant the better one." The game does exactly that on one button, and its
	-- own idea of better is the one the pen actually pays out on, so there is
	-- nothing to reimplement. It debounces at five seconds on the server, so
	-- asking faster than that only earns a refusal.
	local function equipBest()
		if not due("equipBest", 8) then
			return
		end
		local ok = ask(NET.Backpack.EQUIP_BEST)
		if ok then
			accepted("equipBest")
		else
			refused("equipBest", 8)
		end
	end

	-- One egg per pass, not every egg every pass. A full base is twenty-odd
	-- eggs, and hatching them in one burst is twenty requests inside a frame
	-- from a client that is supposed to be pressing a button. They hatch just as
	-- fast spread out, because the growth timer is the thing that takes minutes.
	core:Loop("base", 2, function()
		if F.baseHatch and due("hatch", 2.5) then
			for _, egg in ipairs(ownEggs()) do
				local ready = EggCmds.IsLocalEggReady and select(2, pcall(EggCmds.IsLocalEggReady, egg.uid))
				if ready == true then
					local ok, hatched = pcall(EggCmds.RequestHatchEgg, egg.uid)
					if ok and hatched ~= false then
						task.wait(0.5)
						pcall(EggCmds.RequestCompleteHatchEgg, egg.uid)
						stats.hatched = (stats.hatched or 0) + 1
						-- A new pet is the only moment the answer to "what should
						-- be out in the pen" can have changed.
						if F.baseBest ~= false then
							equipBest()
						end
					end
					break
				end
			end
		end

		-- Skipping costs money and the server refuses when you cannot afford it,
		-- so this is the one most likely to be refused over and over. One egg,
		-- slowly, and the gate backs it off further every time it is turned down.
		if F.baseSkip and due("skip", 4) then
			for _, egg in ipairs(ownEggs()) do
				local ready = EggCmds.IsLocalEggReady and select(2, pcall(EggCmds.IsLocalEggReady, egg.uid))
				if ready ~= true then
					local ok, took = pcall(EggCmds.RequestSkipGrowth, egg.uid)
					if ok and took ~= false then
						accepted("skip")
					else
						refused("skip", 4)
					end
					break
				end
			end
		end

		if F.baseUpgrade and due("upgrade", 20) then
			ask(NET.Plots.REQUEST_BASE_UPGRADE)
		end
	end)

	core:Loop("offline", 10, function()
		if F.baseOffline and due("offline", 90) then
			ask(NET.OfflineAssets.REQUEST_REDEEM)
		end
	end)

	----------------------------------------------------------------------------
	-- pets
	----------------------------------------------------------------------------

	core:Loop("pets", 6, function()
		if F.petsEquipBest then
			equipBest()
		end
	end)

	----------------------------------------------------------------------------
	-- speed
	----------------------------------------------------------------------------

	-- The only movement lever in this game that is real. WalkSpeed is server
	-- owned and derived from the Speed leaderstat, so writing WalkSpeed does
	-- nothing at all, and growing Speed makes you faster *and* widens what the
	-- movement anti-cheat will accept. A developed account already walks at
	-- around 98, six times the default, entirely legitimately.
	-- Upgrading the treadmill is the largest single lever in the game and it is
	-- one call. The ladder runs x2 free, x5 for 15K, x12 for 250K, x30 for 5M,
	-- x80 for 120M, x100 for 3B, and on up to x2000. Each step multiplies how
	-- fast Speed grows, Speed is the gate on every area, and the areas are where
	-- the money is. Buying it the minute it is affordable is never wrong.
	--
	-- It is also the easiest way to spend all night asking for something you
	-- cannot afford, so a refusal counts as a refusal and the gate backs it off.
	core:Loop("speed", 5, function()
		watchTreadmillRate(mySpeedPower())
		if F.speedUpgrade and due("treadmill", 20) then
			if ask(NET.Treadmills.REQUEST_UPGRADE) then
				accepted("treadmill")
				core:Notify("Meridian", "Bought the next treadmill", 4)
			else
				refused("treadmill", 20)
			end
		end
	end)

	----------------------------------------------------------------------------
	-- progress
	----------------------------------------------------------------------------

	core:Loop("progress", 8, function()
		if F.progIndex and due("index", 60) then
			ask(NET.Index.REQUEST_CLAIM_ALL)
		end
		if F.progGifts and due("gifts", 60) then
			ask(NET.FreeGifts.REQUEST_CLAIM)
		end
		if F.progLucky and due("lucky", 45) then
			ask(NET.LuckyBlock.REQUEST_STORED_BLOCK_OPEN_CLAIM)
		end
		if F.progRebirth and due("rebirth", 60) then
			ask(NET.Rebirth.REQUEST_REBIRTH)
			task.wait(0.5)
			ask(NET.Rebirth.REQUEST_REBIRTH_COMMIT)
		end
	end)

	----------------------------------------------------------------------------
	-- moving server
	----------------------------------------------------------------------------

	-- Lifted whole from Ability Arena, deliberately unchanged. It is the same
	-- job in both games and a second copy that drifted would be worse than a
	-- shared one that did not.
	-- `ping` on this listing is what the server reports for the people already
	-- in it, not what ours would be. It is a good enough proxy - a server whose
	-- players are all on 300 is a server on the other side of the world - but it
	-- is not a promise, which is why the control is a ceiling rather than a
	-- target.
	local SERVER_LIST = "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100"
	local hopping = false

	local function bestServer()
		local ok, body = pcall(function()
			return game:HttpGet(SERVER_LIST:format(game.PlaceId))
		end)
		if not ok then
			return nil, "Could not read the server list"
		end

		local read, decoded = pcall(function()
			return HttpService:JSONDecode(body)
		end)
		if not read or type(decoded) ~= "table" then
			return nil, "The server list came back unreadable"
		end

		local mode = F.hopPick or "Full and Fast"
		local ceiling = tonumber(F.hopPing) or 250
		local best, bestScore, tooSlow = nil, -math.huge, 0

		for _, server in ipairs(decoded.data or {}) do
			local seats = tonumber(server.maxPlayers) or 0
			local playing = tonumber(server.playing) or 0
			if playing < seats and server.id ~= game.JobId then
				local ping = tonumber(server.ping) or 0
				if ping > ceiling then
					tooSlow += 1
				else
					local score
					if mode == "Most Players" then
						score = playing
					elseif mode == "Lowest Ping" then
						score = -ping
					else
						-- How full it is against how slow it is. Full counts for
						-- a hundred, so a quarter of the ping puts a 60 ms
						-- server four fifths full ahead of a 200 ms one that is
						-- completely full.
						score = (playing / math.max(seats, 1)) * 100 - ping / 4
					end
					if score > bestScore then
						best, bestScore = server, score
					end
				end
			end
		end

		if not best then
			if tooSlow > 0 then
				return nil, ("Every server with room was slower than %d ms"):format(ceiling)
			end
			return nil, "No other server had room"
		end
		return best
	end

	local function hopNow(why)
		if hopping then
			return
		end
		hopping = true
		task.spawn(function()
			local server, trouble = bestServer()
			if not server then
				core:Notify(Module.Name, trouble or "Nowhere to move to", 4)
				hopping = false
				return
			end
			core:Notify(
				Module.Name,
				("%s. Moving to a %d of %d server on %d ms"):format(
					why or "Changing server",
					tonumber(server.playing) or 0,
					tonumber(server.maxPlayers) or 0,
					math.floor(tonumber(server.ping) or 0)
				),
				5
			)
			-- Long enough for that to be readable before the screen goes.
			task.wait(1.2)
			-- Queue the hub to load itself again on the other side. A teleport
			-- ends the script that started it, so without this the farm arrives
			-- somewhere busier with nothing running.
			if type(core.QueueRelaunch) == "function" then
				core.QueueRelaunch()
			end
			local sent = pcall(function()
				TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, Players.LocalPlayer)
			end)
			if not sent then
				core:Notify(Module.Name, "The game refused the move", 4)
			end
			-- A teleport that is accepted takes several seconds to happen. This
			-- stops the loop below firing another one into the gap.
			task.wait(10)
			hopping = false
		end)
	end


	local quietSince = nil
	local arrived = core.ArrivedAt or os.clock()

	core:Loop("serverHop", 3, function()
		if not F.autoHop or hopping then
			quietSince = nil
			return
		end
		-- Players replicate in over the first second or two of a join, so a
		-- server you have only just arrived in always looks empty. Without this
		-- the first hop starts a chain that never stops.
		if os.clock() - arrived < 20 then
			quietSince = nil
			return
		end
		local here = #Players:GetPlayers()
		if here >= (tonumber(F.hopBelow) or 4) then
			quietSince = nil
			return
		end
		quietSince = quietSince or os.clock()
		if os.clock() - quietSince < 6 then
			return
		end
		quietSince = nil
		hopNow(("Only %d left here"):format(here))
	end)

	----------------------------------------------------------------------------
	-- egg ESP
	----------------------------------------------------------------------------

	-- The hub's own ESP wants models with humanoids in them, which an egg in a
	-- nest is not. This draws from the same ranked list the farm reads, so
	-- whatever the label says is the best egg is the one the farm is about to
	-- walk to. There is only one list and it cannot disagree with itself.
	--
	-- Colour is the rank, not the rarity. Rarity is already on the nest; what
	-- the game does not show you is that this Pterodactyl is worth twenty times
	-- the one behind you because of its size.
	--
	-- Every egg is a real model, `Workspace.AreaEggSlotsClient.<uid>`, so this
	-- adorns to those rather than parking parts of its own in the world. The
	-- first attempt did the latter and they silently never appeared: something
	-- in this game sweeps instances it did not put in Workspace, and a folder
	-- parented there is gone before the next frame without an error.
	--
	-- **The whole pool is built here and never grows.** A loop thread is
	-- resumed by the engine after it waits, and a resumed thread cannot call
	-- Instance.new at all - it fails with "the current thread cannot access
	-- Instance" every tick, forever, and the ESP silently draws nothing. So the
	-- billboards are made once, on the build thread, and the loop only ever
	-- points them at things. It is also simply better: no allocation twice a
	-- second and nothing for the collector to chase.
	local EGG_MODELS = "AreaEggSlotsClient"
	local ESP_POOL = 60

	-- PlayerGui rather than the hidden container the rest of the hub lives in,
	-- and this was measured rather than chosen. A loop thread here can write to
	-- the world all day - the farm walks, and that is Instance writes on the
	-- character - but it cannot write to anything inside gethui(), which needs a
	-- capability the thread does not have. Every tick warned "the current thread
	-- cannot access Instance" and the ESP drew nothing at all while the farm ran
	-- perfectly, in the same module, from the same kind of loop.
	local espHolder = Instance.new("Folder")
	espHolder.Name = "MeridianEggs"
	espHolder.Parent = LocalPlayer:WaitForChild("PlayerGui")
	core:Track(espHolder)

	local espPool = {}
	for _ = 1, ESP_POOL do
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(240, 34)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
		billboard.AlwaysOnTop = true
		billboard.Enabled = false
		billboard.Parent = espHolder

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 15
		label.TextStrokeTransparency = 0.4
		label.Parent = billboard

		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 0.85
		highlight.OutlineTransparency = 0.2
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Enabled = false
		highlight.Parent = espHolder

		espPool[#espPool + 1] = { billboard = billboard, label = label, highlight = highlight }
	end

	local function espColour(worth, best)
		if best <= 0 then
			return Color3.fromRGB(235, 235, 235)
		end
		-- A root rather than a straight ratio, because one Cosmic egg on the map
		-- makes every other worth a fraction of a percent of it, and a linear
		-- ramp would paint everything else the same grey.
		local part = math.clamp(worth / best, 0, 1) ^ 0.4
		return Color3.fromRGB(150, 150, 150):Lerp(Color3.fromRGB(120, 255, 190), part)
	end

	local function hideFrom(index)
		for slot = index, ESP_POOL do
			local mark = espPool[slot]
			if not mark.billboard.Enabled and not mark.highlight.Enabled then
				break
			end
			mark.billboard.Enabled = false
			mark.highlight.Enabled = false
			mark.billboard.Adornee = nil
			mark.highlight.Adornee = nil
		end
	end

	core:Loop("eggEsp", 0.3, function()
		if not F.eggEsp then
			hideFrom(1)
			return
		end

		local models = Workspace:FindFirstChild(EGG_MODELS)
		if not models then
			hideFrom(1)
			return
		end

		local ranked = rankedEggs()
		local range = tonumber(F.eggEspRange) or 2500
		local floor = F.eggEspFilter ~= false and (tonumber(F.stealFloor) or 0) or 0
		local best = ranked[1] and ranked[1].worth or 0

		local slot = 0
		for _, egg in ipairs(ranked) do
			if slot >= ESP_POOL then
				break
			end
			if egg.distance <= range and egg.worth >= floor then
				local model = models:FindFirstChild(egg.record.Uid)
				local anchor = model
					and (model.PrimaryPart or model:FindFirstChild("Hitbox") or model:FindFirstChildWhichIsA("BasePart"))
				if anchor then
					slot = slot + 1
					local mark = espPool[slot]

					local text = eggName(egg.record)
					if F.eggEspWorth ~= false then
						text = text .. " · " .. short(egg.worth)
					end
					if #egg.mutations > 0 then
						text = text .. " · " .. table.concat(egg.mutations, ", ")
					end
					if F.eggEspDistance then
						text = text .. " · " .. math.floor(egg.distance)
					end

					local colour = espColour(egg.worth, best)
					mark.label.Text = text
					mark.label.TextColor3 = colour
					mark.highlight.FillColor = colour
					mark.highlight.OutlineColor = colour
					mark.billboard.Adornee = anchor
					mark.highlight.Adornee = model
					mark.billboard.Enabled = true
					mark.highlight.Enabled = true
				end
			end
		end

		hideFrom(slot + 1)
	end)

	----------------------------------------------------------------------------
	-- anti afk
	----------------------------------------------------------------------------

	-- Everyone in the world except you. In this game the people who matter are
	-- the ones walking toward your base, so nobody is filtered out by state the
	-- way the arena filtered out the lobby.
	core:StartESP({
		flag = "playerEsp",
		interval = 0.3,
		list = function()
			local out = {}
			for _, player in ipairs(Players:GetPlayers()) do
				if player ~= LocalPlayer and player.Character then
					out[#out + 1] = player.Character
				end
			end
			return out
		end,
		maxDistance = function()
			return tonumber(F.eggEspRange) or 2500
		end,
		fill = function()
			return tonumber(F.playerEspFill) or 0.25
		end,
		colour = function()
			return Color3.fromRGB(235, 235, 235)
		end,
		label = function(model, distance)
			return ("%s · %d"):format(model.Name, math.floor(distance))
		end,
	})

	core:Connect(LocalPlayer.Idled, function()
		if F.antiAfk == false then
			return
		end
		local VirtualUser = game:GetService("VirtualUser")
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)

	----------------------------------------------------------------------------
	-- what the dashboard shows
	----------------------------------------------------------------------------

	-- The dashboard reads fixed keys off core.Stats, and core.Headline is the
	-- one line it shows above them. A game module never touches the interface
	-- itself, so this is the whole of what it publishes.
	core:Loop("stats", 1, function()
		local minutes = math.max((os.clock() - stats.started) / 60, 1 / 60)
		local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
		local perSecond = leaderstats and leaderstats:FindFirstChild("Money/s")

		local carried = core.Stats or {}
		carried.Hits = stats.taken
		carried.Rate = math.floor(stats.taken / minutes * 60)
		carried.Total = stats.placed
		carried.Holding = perSecond and (short(perSecond.Value) .. " a second") or "nothing yet"
		core.Stats = carried

		local eggUid = heldEggTool()
		local held = carriedUid()
		if eggUid then
			core.Headline = "Planting it"
		elseif held then
			core.Headline = "Carrying one home"
		elseif currentTarget then
			core.Headline = ("%s · %s a second · %d studs away"):format(
				eggName(currentTarget.record),
				short(currentTarget.worth),
				math.floor(currentTarget.distance)
			)
		elseif grinding then
			local _, area, gap = worthGrinding()
			core.Headline = area
				and ("Treadmill · %s of Speed to %s"):format(short(gap or 0), area)
				or "On the treadmill"
		elseif F.autoSteal then
			core.Headline = chosenArea
				and ("Farming %s · nothing worth taking yet"):format(chosenArea)
				or "Looking for something worth the walk"
		else
			core.Headline = nil
		end
	end)

	----------------------------------------------------------------------------
	-- the interface, and it is last on purpose
	----------------------------------------------------------------------------
	--
	-- Every loop above this line is registered before a single tab exists, and
	-- that ordering is load bearing.
	--
	-- Maclib yields while it builds elements, and a thread that has yielded
	-- spawns children that cannot touch an Instance at all. Loops created after
	-- the tabs therefore run forever without ever drawing anything, warning
	-- "the current thread cannot access Instance" on every tick. The farm worked
	-- and the ESP did not, in the same module, for exactly this reason.
	--
	-- setthreadidentity does not fix it, because capability is not identity.
	-- Registering first is the fix.

	local stealTab = tabGroup:Tab({ Name = "Steal", Image = "rbxassetid://10723407389" })
	local baseTab = tabGroup:Tab({ Name = "Base", Image = "rbxassetid://10734886735" })
	local petsTab = tabGroup:Tab({ Name = "Pets", Image = "rbxassetid://10723415903" })
	local progressTab = tabGroup:Tab({ Name = "Progress", Image = "rbxassetid://10734950309" })
	local visualsTab = tabGroup:Tab({ Name = "Visuals", Image = "rbxassetid://10734898355" })
	local playerTab = tabGroup:Tab({ Name = "Player", Image = "rbxassetid://10747373176" })

	local stealLeft = stealTab:Section({ Side = "Left" })
	local stealRight = stealTab:Section({ Side = "Right" })
	local baseLeft = baseTab:Section({ Side = "Left" })
	local baseRight = baseTab:Section({ Side = "Right" })
	local petsLeft = petsTab:Section({ Side = "Left" })
	local petsRight = petsTab:Section({ Side = "Right" })
	local progLeft = progressTab:Section({ Side = "Left" })
	local progRight = progressTab:Section({ Side = "Right" })
	local visualsLeft = visualsTab:Section({ Side = "Left" })
	local visualsRight = visualsTab:Section({ Side = "Right" })
	local playerLeft = playerTab:Section({ Side = "Left" })
	local playerRight = playerTab:Section({ Side = "Right" })

	--------------------------------------------------------------- steal · left

	stealLeft:Header({ Text = "Farm" })

	stealLeft:Toggle({
		Name = "Auto Steal",
		Default = false,
		Callback = function(state)
			F.autoSteal = state
			if not state then
				dropTarget()
			end
		end,
	}, "autoSteal")

	stealLeft:Toggle({
		Name = "Take It Home",
		Default = true,
		Callback = function(state)
			F.stealCarryHome = state
		end,
	}, "stealCarryHome")

	stealLeft:Slider({
		Name = "Wait Before Taking",
		Default = 0.2,
		Minimum = 0,
		Maximum = 3,
		DisplayMethod = "Value",
		Precision = 1,
		Callback = function(value)
			F.stealDelay = value
		end,
	}, "stealDelay")

	stealLeft:Slider({
		Name = "Give Up After",
		Default = 25,
		Minimum = 8,
		Maximum = 90,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.stealGiveUp = value
		end,
	}, "stealGiveUp")

	stealLeft:Divider()

	-- Deliberately not a slider you can push past what the game gives you. In
	-- this game the server owns WalkSpeed outright, so a hub that offered a
	-- speed number would be selling something it cannot deliver.


	-------------------------------------------------------------- steal · right

	stealRight:Header({ Text = "Which Egg" })

	stealRight:Dropdown({
		Name = "Pick By",
		Multi = false,
		Required = true,
		Options = { "Best Nearby", "Most Valuable", "Nearest" },
		Default = 1,
		Callback = function(value)
			F.stealPick = value
		end,
	}, "stealPick")

	stealRight:Toggle({
		Name = "Stay Where You Win",
		Default = true,
		Callback = function(state)
			F.stealOutrun = state
		end,
	}, "stealOutrun")

	stealRight:Dropdown({
		Name = "Areas",
		Multi = true,
		Required = false,
		Search = true,
		Options = AREA_NAMES,
		Callback = function(value)
			local list = {}
			if type(value) == "table" then
				for name, on in pairs(value) do
					if on == true then
						list[#list + 1] = name
					elseif type(on) == "string" then
						list[#list + 1] = on
					end
				end
			end
			F.stealAreas = list
		end,
	}, "stealAreas")

	stealRight:Slider({
		Name = "How Far To Look",
		Default = 4000,
		Minimum = 250,
		Maximum = 6000,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.stealRange = value
		end,
	}, "stealRange")

	-- A slider is the wrong control for this. What an egg earns runs from 2 a
	-- second to over a billion, so a linear slider spends its first ninety-nine
	-- percent inside the range nobody cares about, and a slider whose first
	-- third does nothing is a slider that lies. Named steps say what they mean.
	local WORTH_STEPS = {
		["Anything"] = 0,
		["1K A Second"] = 1e3,
		["10K A Second"] = 1e4,
		["100K A Second"] = 1e5,
		["1M A Second"] = 1e6,
		["10M A Second"] = 1e7,
		["100M A Second"] = 1e8,
	}

	stealRight:Dropdown({
		Name = "Worth At Least",
		Multi = false,
		Required = true,
		Options = {
			"Anything",
			"1K A Second",
			"10K A Second",
			"100K A Second",
			"1M A Second",
			"10M A Second",
			"100M A Second",
		},
		Default = 1,
		Callback = function(value)
			F.stealFloorName = value
			F.stealFloor = WORTH_STEPS[value] or 0
		end,
	}, "stealFloorName")

	stealRight:Toggle({
		Name = "Only Mutated",
		Default = false,
		Callback = function(state)
			F.stealMutated = state
		end,
	}, "stealMutated")

	---------------------------------------------------------------- base · left

	baseLeft:Header({ Text = "Your Base" })

	baseLeft:Toggle({
		Name = "Auto Place",
		Default = true,
		Callback = function(state)
			F.basePlace = state
		end,
	}, "basePlace")

	baseLeft:Toggle({
		Name = "Auto Hatch",
		Default = false,
		Callback = function(state)
			F.baseHatch = state
		end,
	}, "baseHatch")

	baseLeft:Toggle({
		Name = "Equip Best After Hatching",
		Default = true,
		Callback = function(state)
			F.baseBest = state
		end,
	}, "baseBest")

	baseLeft:Toggle({
		Name = "Auto Skip Growth",
		Default = false,
		Callback = function(state)
			F.baseSkip = state
		end,
	}, "baseSkip")

	--------------------------------------------------------------- base · right

	baseRight:Header({ Text = "Money" })

	baseRight:Toggle({
		Name = "Claim Offline Money",
		Default = false,
		Callback = function(state)
			F.baseOffline = state
		end,
	}, "baseOffline")

	baseRight:Toggle({
		Name = "Auto Upgrade Base",
		Default = false,
		Callback = function(state)
			F.baseUpgrade = state
		end,
	}, "baseUpgrade")

	---------------------------------------------------------------- pets · left

	petsLeft:Header({ Text = "Equipped" })

	petsLeft:Toggle({
		Name = "Auto Equip Best",
		Default = false,
		Callback = function(state)
			F.petsEquipBest = state
		end,
	}, "petsEquipBest")

	petsLeft:Button({
		Name = "Equip Best Now",
		Callback = function()
			task.spawn(equipBest)
		end,
	})

	--------------------------------------------------------------- pets · right

	petsRight:Header({ Text = "Selling" })

	petsRight:Toggle({
		Name = "Auto Sell",
		Default = false,
		Callback = function(state)
			F.petsAutoSell = state
			-- Spawned, like every other call out of a control. Network.Invoke is a
			-- round trip, and a callback that yields blocks the interface thread that
			-- called it.
			task.spawn(function()
				ask(NET.Backpack.SET_AUTO_SELL_STATE, state)
			end)
		end,
	}, "petsAutoSell")

	petsRight:Button({
		Name = "Sell Everything",
		Callback = function()
			task.spawn(function()
				ask(NET.AssetInventory.SELL_ALL_ASSETS)
			end)
		end,
	})

	------------------------------------------------------------ progress · left

	progLeft:Header({ Text = "Speed" })

	progLeft:Toggle({
		Name = "Auto Upgrade Treadmill",
		Default = false,
		Callback = function(state)
			F.speedUpgrade = state
		end,
	}, "speedUpgrade")

	progLeft:Toggle({
		Name = "Treadmill For The Next Area",
		Default = true,
		Callback = function(state)
			F.speedGrind = state
		end,
	}, "speedGrind")

	progLeft:Divider()

	progLeft:Header({ Text = "Rebirth" })

	progLeft:Toggle({
		Name = "Auto Rebirth",
		Default = false,
		Callback = function(state)
			F.progRebirth = state
		end,
	}, "progRebirth")

	progLeft:Button({
		Name = "Rebirth Now",
		Callback = function()
			task.spawn(function()
				ask(NET.Rebirth.REQUEST_REBIRTH)
				ask(NET.Rebirth.REQUEST_REBIRTH_COMMIT)
			end)
		end,
	})

	----------------------------------------------------------- progress · right

	progRight:Header({ Text = "Free Things" })

	progRight:Toggle({
		Name = "Claim Index",
		Default = false,
		Callback = function(state)
			F.progIndex = state
		end,
	}, "progIndex")

	progRight:Toggle({
		Name = "Auto Free Gifts",
		Default = false,
		Callback = function(state)
			F.progGifts = state
		end,
	}, "progGifts")

	progRight:Toggle({
		Name = "Auto Lucky Blocks",
		Default = false,
		Callback = function(state)
			F.progLucky = state
		end,
	}, "progLucky")

	------------------------------------------------------------- visuals · left

	visualsLeft:Header({ Text = "Eggs" })

	visualsLeft:Toggle({
		Name = "Egg ESP",
		Default = false,
		Callback = function(state)
			F.eggEsp = state
		end,
	}, "eggEsp")

	visualsLeft:Toggle({
		Name = "Show Worth",
		Default = true,
		Callback = function(state)
			F.eggEspWorth = state
		end,
	}, "eggEspWorth")

	visualsLeft:Toggle({
		Name = "Show Distance",
		Default = false,
		Callback = function(state)
			F.eggEspDistance = state
		end,
	}, "eggEspDistance")

	visualsLeft:Toggle({
		Name = "Hide Cheap Eggs",
		Default = true,
		Callback = function(state)
			F.eggEspFilter = state
		end,
	}, "eggEspFilter")

	visualsLeft:Slider({
		Name = "Max Distance",
		Default = 2500,
		Minimum = 200,
		Maximum = 6000,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.eggEspRange = value
		end,
	}, "eggEspRange")

	------------------------------------------------------------ visuals · right

	visualsRight:Header({ Text = "Players" })

	visualsRight:Toggle({
		Name = "Player ESP",
		Default = false,
		Callback = function(state)
			F.playerEsp = state
		end,
	}, "playerEsp")

	visualsRight:Slider({
		Name = "Fill",
		Default = 0.25,
		Minimum = 0,
		Maximum = 1,
		DisplayMethod = "Percent",
		Precision = 2,
		Callback = function(value)
			F.playerEspFill = value
		end,
	}, "playerEspFill")

	-------------------------------------------------------------- player · left

	playerLeft:Header({ Text = "Session" })

	playerLeft:Toggle({
		Name = "Anti AFK",
		Default = true,
		Callback = function(state)
			F.antiAfk = state
		end,
	}, "antiAfk")

	------------------------------------------------------------- player · right

	playerRight:Header({ Text = "Server" })

	playerRight:Toggle({
		Name = "Auto Hop",
		Default = false,
		Callback = function(state)
			F.autoHop = state
		end,
	}, "autoHop")

	playerRight:Slider({
		Name = "Hop When Below",
		Default = 4,
		Minimum = 1,
		Maximum = 12,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.hopBelow = value
		end,
	}, "hopBelow")

	playerRight:Dropdown({
		Name = "Pick Server By",
		Multi = false,
		Required = true,
		Options = { "Full and Fast", "Most Players", "Lowest Ping" },
		Default = 1,
		Callback = function(value)
			F.hopPick = value
		end,
	}, "hopPick")

	playerRight:Slider({
		Name = "Highest Ping",
		Default = 250,
		Minimum = 50,
		Maximum = 400,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.hopPing = value
		end,
	}, "hopPing")


	-- Off the build thread, deliberately, and this is not a style choice.
	--
	-- RequestAreaEggSnapshot is a RemoteFunction round trip, so it yields, and a
	-- thread that yields is resumed by the engine without the capability to touch
	-- the interface. Build is called part way through the loader putting the
	-- window together, so yielding here killed the next line of main.luau with
	-- "the current thread cannot access Instance" and left the loading bar frozen
	-- at ninety-two percent. **Nothing in Build may yield.** The game's own
	-- signals fill the cache in anyway; this only shortens the wait for the first
	-- one.
	task.spawn(refreshSnapshot)

	-- main.luau selects the default tab itself, after the chrome is on. Doing it
	-- from in here runs the tab transition before the window is finished and
	-- Maclib's tween throws, so the module says which tab it wants and lets the
	-- loader pick the moment.
	return {
		Tabs = {
			Steal = stealTab,
			Base = baseTab,
			Pets = petsTab,
			Progress = progressTab,
			Visuals = visualsTab,
			Player = playerTab,
		},
		Default = stealTab,
		Tips = Module.Tips,
	}
end

return Module
