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
	["Stay Where You Win"] = "Only goes to areas your Speed is up to, using the recommended number on the sign at the mouth of each one.",
	["Areas"] = "Which parts of the map it is allowed to go to. Leave them all on and it goes wherever the best egg is.",
	["Worth At Least"] = "Ignores anything earning less than this. The number is money a second, the same one the game shows on a pet.",
	["Only Mutated"] = "Skips every ordinary egg, however big.",
	["How Far To Look"] = "Stops it crossing the whole map for one egg. Turn it up if you want the best on the map and do not mind the walk.",
	["Wait Before Taking"] = "A pause once it arrives, before it grabs. Zero grabs the moment it is close enough.",
	["Take It Home"] = "Carries every egg back to your base instead of leaving it where it was.",
	["Give Up After"] = "How long to spend on one egg before writing it off and picking another.",
	["Auto Place"] = "Puts a carried egg down on your base as soon as you get there.",
	["Auto Hatch"] = "Hatches every egg on your base the moment it is ready.",
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

	local function canHandle(areaId)
		readSigns()
		local needed = AREA_NEEDS[areaId]
		if not needed then
			-- No sign read yet is not permission. Until the world has streamed in
			-- far enough to say, the only areas worth trusting are the cheap ones,
			-- and being wrong here costs a wasted trip and a stolen egg.
			return areaNeedsCount > 0
		end
		return mySpeedPower() >= needed
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

	local function due(key, interval)
		local now = os.clock()
		if now - lastCall < SERVER_GAP then
			return false
		end
		if now < (nextDue[key] or 0) then
			return false
		end
		lastCall = now
		nextDue[key] = now + interval
		return true
	end

	local function refused(key, interval)
		local count = (failures[key] or 0) + 1
		failures[key] = count
		local ceiling = BACKOFF_MAX[key] or BACKOFF_CAP
		nextDue[key] = os.clock() + math.min(interval * (2 ^ count), ceiling)
		return count
	end

	local function accepted(key)
		failures[key] = nil
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
			local ok, reply, reason = pcall(Network.Invoke, action, ...)
			if not ok then
				return false, tostring(reply)
			end
			return reply ~= false, reason
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

		local out = {}
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
					and (F.stealOutrun == false or canHandle(record.AreaId))
				if pass then
					out[#out + 1] = {
						record = record,
						position = position,
						distance = distance,
						worth = worth,
						mutations = mutations,
					}
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
		core:SetControls(true)
		-- Whatever the last egg refused for was about that egg. Starting the next
		-- one already throttled is how a farm talks itself into standing still.
		accepted("carry")
	end

	-- Somewhere on your own base to put an egg down. The game raycasts from
	-- wherever the player is pointing; a farm has nobody pointing, so it picks
	-- its own spot and lets the server say no. Spread over the pad rather than
	-- stacked on the middle, because the server refuses a spot that is already
	-- taken and one that walks outward finds a free one in a couple of tries
	-- instead of never.
	local placeAttempt = 0

	local function placementCFrame(data)
		local pad = data.PetArea
		if not pad or not pad:IsA("BasePart") then
			return nil
		end
		placeAttempt = placeAttempt + 1
		-- A spiral, so consecutive attempts are never neighbours and a full row
		-- does not have to be walked one stud at a time.
		local turn = placeAttempt * 2.399963
		local out = math.min(placeAttempt * 1.6, math.min(pad.Size.X, pad.Size.Z) * 0.45)
		local offset = Vector3.new(math.cos(turn) * out, 0, math.sin(turn) * out)
		local world = pad.Position + offset
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
		local localCFrame = placementCFrame(data)
		if not localCFrame then
			refused("place", PLACE_INTERVAL)
			return false, "No base yet"
		end
		local ok, took, reason = pcall(EggCmds.RequestPlaceEgg, uid, localCFrame)
		if ok and took then
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

	-- Walking, and both halves of this were learned the hard way.
	--
	-- **MoveTo gives up after eight seconds.** Aiming it at a nest a thousand
	-- studs away and leaving it alone looks perfect for eight seconds and then
	-- the character simply stops, forever, because nothing ever asks again. So
	-- the order is re-issued, but at a point along the exact bearing to the real
	-- destination rather than at the destination itself, which keeps the path
	-- dead straight while staying inside what MoveTo will actually finish.
	--
	-- **And it is re-issued rarely.** The hub's own walker asks twenty times a
	-- second, which is right when chasing a player who moves; a nest has not
	-- moved in an hour, and every fresh order interrupts the humanoid's own
	-- acceleration. In a game whose entire economy is how fast you cover ground,
	-- that shuffle is the difference between a good farm and a bad one.
	local WALK_STEP = 60
	local WALK_REFRESH = 3.5

	local walkOrder = { at = 0, aim = nil }

	local function walkTo(position, standoff)
		local root, hum = core:Root(), core:Humanoid()
		if not root or not hum or hum.Health <= 0 then
			return false
		end

		local flat = Vector3.new(position.X - root.Position.X, 0, position.Z - root.Position.Z)
		local distance = flat.Magnitude
		if distance <= (standoff or 0) then
			walkOrder.aim = nil
			core:SetControls(true)
			return true
		end

		core:SetControls(false)

		local now = os.clock()
		local changed = walkOrder.aim == nil or (position - walkOrder.aim).Magnitude > 10
		if changed or now - walkOrder.at > WALK_REFRESH then
			walkOrder.at = now
			walkOrder.aim = position
			local reach = math.min(distance - (standoff or 0), WALK_STEP)
			hum:MoveTo(root.Position + flat.Unit * reach)
		end
		return false
	end

	-- Getting off the treadmill before going anywhere.
	--
	-- The treadmill sits fourteen studs from the spawn point, so a farm that has
	-- just been home is standing on it, and standing on it holds you there: the
	-- farm issued its walk orders perfectly and did not move a stud for ninety
	-- seconds. It is also the thing an AFK player is deliberately using, so the
	-- hub steps off only when it actually has somewhere to be.
	-- Only when we are actually on it.
	--
	-- The first version fired this every few seconds whenever the character had
	-- not moved, whatever the reason. It spent ninety seconds telling the server
	-- to take us off a treadmill we were seventeen studs away from, about thirty
	-- times, which is precisely the shape of thing that gets an account kicked -
	-- a request that cannot possibly succeed, repeated.
	local TREADMILL_RANGE = 12

	local function onTreadmill()
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

	local function leaveTreadmill()
		if not onTreadmill() then
			return
		end
		if due("treadmillOff", 4) then
			ask(NET.Treadmills.REQUEST_UNEQUIP)
		end
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

	local function watchForStuck()
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
			leaveTreadmill()
		end
	end

	core:Loop("steal", 0.1, function()
		if not F.autoSteal then
			if currentTarget then
				dropTarget()
			end
			stuckFrom = nil
			return
		end

		-- Anything that holds the character still gets one nudge every few
		-- seconds. On this map that is the treadmill and only the treadmill.
		watchForStuck()
		if not core:Alive2() then
			dropTarget()
			return
		end

		local held = carriedUid()
		if held then
			-- Carrying. Nothing else matters until it is down.
			currentTarget = nil
			if F.stealCarryHome == false then
				return
			end
			local data = plotData()
			if not data then
				return
			end
			local arrived = goHome()
			if not arrived then
				return
			end
			if F.basePlace == false then
				return
			end
			local placed, reason, gaveUp = tryPlace(held)
			if not placed and gaveUp then
				-- A base that is full is the one refusal the user has to do
				-- something about, and by this point it has been refused six times,
				-- so it is not bad luck.
				sayOnce("place", "Could not place it", tostring(reason))
			end
			return
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
		local ok, took, reason = pcall(EggCmds.RequestCarryAreaEgg, currentTarget.record.Uid)
		if ok and took ~= false then
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

	local function ownEggs()
		local ok, runtime = pcall(EggCmds.GetRuntimeSnapshot)
		if not ok or type(runtime) ~= "table" then
			return {}
		end
		local out = {}
		for _, slot in pairs(runtime) do
			if type(slot) == "table" then
				for _, record in pairs(slot) do
					if type(record) == "table" and record.Uid then
						out[#out + 1] = record
					end
				end
			end
		end
		return out
	end

	-- One egg per pass, not every egg every pass. A full base is twenty-odd
	-- eggs, and hatching them in one burst is twenty requests inside a frame
	-- from a client that is supposed to be pressing a button. They hatch just as
	-- fast spread out, because the growth timer is the thing that takes minutes.
	core:Loop("base", 2, function()
		if F.baseHatch and due("hatch", 2.5) then
			for _, record in ipairs(ownEggs()) do
				local ready = EggCmds.IsLocalEggReady and select(2, pcall(EggCmds.IsLocalEggReady, record.Uid))
				if ready == true then
					pcall(EggCmds.RequestHatchEgg, record.Uid)
					task.wait(0.5)
					pcall(EggCmds.RequestCompleteHatchEgg, record.Uid)
					break
				end
			end
		end

		-- Skipping costs money and the server refuses when you cannot afford it,
		-- so this is the one most likely to be refused over and over. One egg,
		-- slowly, and the gate backs it off further every time it is turned down.
		if F.baseSkip and due("skip", 4) then
			for _, record in ipairs(ownEggs()) do
				local ready = EggCmds.IsLocalEggReady and select(2, pcall(EggCmds.IsLocalEggReady, record.Uid))
				if ready ~= true then
					local ok, took = pcall(EggCmds.RequestSkipGrowth, record.Uid)
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

	local function equipBest()
		return ask(NET.Backpack.EQUIP_BEST)
	end

	core:Loop("pets", 6, function()
		if F.petsEquipBest and due("equipBest", 30) then
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
	core:Loop("speed", 5, function()
		if F.speedUpgrade and due("treadmill", 20) then
			ask(NET.Treadmills.REQUEST_UPGRADE)
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

		local held = carriedUid()
		if held then
			core.Headline = "Carrying one home"
		elseif currentTarget then
			core.Headline = ("%s · %s a second · %d studs away"):format(
				eggName(currentTarget.record),
				short(currentTarget.worth),
				math.floor(currentTarget.distance)
			)
		elseif F.autoSteal then
			core.Headline = "Looking for something worth the walk"
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
