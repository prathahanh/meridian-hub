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
	["Only If You Can Get Away"] = "Waits for the guard to be somewhere else instead of taking an egg and losing it a second later. Uses the game's own escape maths against where the guard is standing right now, so it knows before it grabs.",
	["Eggs A Minute"] = "A hard ceiling on how often an egg can be taken, whatever else says it is fine. The walk usually takes longer than this anyway, so it only bites when something has gone wrong.",
	["Walk Like A Keyboard"] = "WASD only has eight directions, so that is all a desktop player ever moves in. This snaps to the same eight instead of walking at any angle it likes. Whether this game cares is a guess, so it is off until the kick log says otherwise.",
	["New Species First"] = "Goes for anything missing from your index before anything else, wherever it is. That reward is paid once, it is usually worth more than a night of farming, and there is no second chance at a first hatch.",
	["Claim Everything"] = "Asks for every index reward you have earned, right now.",
	["Equip Best Bat"] = "Puts on the bat from the best area you have finished the index for.",
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
	["Skip If Longer Than"] = "Only pays to skip an egg with more than this left to grow. Growth runs from ten seconds to a full day here, and it is the day-long ones that hold your base hostage overnight.",
	["Claim Offline Money"] = "Collects what your pets earned while you were away.",
	["Auto Collect"] = "Keeps collecting the money piling up on your base.",
	["Auto Upgrade Base"] = "Buys the next base upgrade whenever you can afford it.",
	["Auto Equip Best"] = "Keeps your best pets out, as the game ranks them.",
	["Equip Best Now"] = "Does it once, right now.",
	["Auto Sell"] = "Sells pets as they hatch, up to the rarity you pick. Favourites are never sold. Leave this on overnight or the pen fills, hatching stops, and the farm has nowhere to plant.",
	["Sell Everything"] = "Sells your whole inventory except favourites. There is no undo.",
	["Sell Up To"] = "Everything at this rarity and below gets sold. Uncommon keeps anything Rare or better.",
	["Auto Fuse Runts"] = "Fuses three of the same species when they are small enough that it pays. Three pets become one egg, so it only wins on runts: at ordinary size you get back well under half of what you put in.",
	["Only Fuse Below"] = "The size a pet has to be under before it is worth fusing. 0.66 is where the maths turns; above it you lose earnings every time.",
	["Auto Treadmill"] = "Stands on the treadmill and keeps earning Speed while you are not doing anything else.",
	["Auto Upgrade Treadmill"] = "Buys the next treadmill whenever you can afford it.",
	["Treadmill When Eggs Are Poor"] = "When nothing on the map would move the needle, stands on the treadmill instead of walking fifteen hundred studs for an egg worth a rounding error.",
	["Worth The Walk"] = "How much an egg has to add to what you already earn before it is worth the trip. A species you have never hatched always is, whatever it earns.",
	["Treadmill For The Next Area"] = "When the next area is one sitting away on the treadmill, goes and stands on it until you can get in, then goes back to farming.",
	["Auto Rebirth"] = "Rebirths as soon as the game lets you.",
	["Rebirth Now"] = "Rebirths, right now.",
	["Claim Index"] = "Collects every index reward you have earned, including the limited egg one.",
	["Claim Group Reward"] = "Takes the reward for being in the group, if you are in it.",
	["Auto Free Gifts"] = "Takes the free gifts as they come up.",
	["Auto Lucky Blocks"] = "Opens lucky blocks as they are stored.",
	["Redeem Codes"] = "Tries every code the game currently has active.",
	["Egg ESP"] = "Draws every egg on the map through walls, with what it is worth.",
	["Colour By"] = "Worth shades from grey to green against the best egg on the map. Rarity uses the game's own colours. Index paints anything you have never hatched gold and everything else grey.",
	["Mark New Species"] = "Puts NEW in front of any egg whose species is missing from your index. Those are worth more than anything else on the map.",
	["Show Index Reward"] = "Adds the Speed you get for hatching that species for the first time.",
	["Only New Species"] = "Hides every egg you have already got in the index.",
	["Show Rarity"] = "Adds Common, Rare, Mythic and so on to each egg.",
	["Show Area"] = "Adds which area the egg is sitting in.",
	["Tracers"] = "Draws a line from the bottom of your screen to every egg being shown.",
	["How Many At Once"] = "How many eggs to draw. Fewer is easier to read when the map is full.",
	["Text Size"] = "How big the egg names are.",
	["Fill"] = "How solid the glow on each egg looks. Zero leaves just the outline.",
	["Show Worth"] = "Adds money a second to each egg, so the filter above is legible.",
	["Show Distance"] = "Adds how far away each egg is.",
	["Hide Cheap Eggs"] = "Only draws eggs worth more than your filter, so the screen is not full of Dogs.",
	["Max Distance"] = "Stops drawing eggs past this far away.",
	["Player ESP"] = "Draws every other player through walls.",
	["Anti AFK"] = "Stops Roblox idling you out, and stops the game bouncing you out and back every eighteen minutes. Turn it off and you get the normal AFK behaviour, which is worth trying if a night keeps ending early.",
	["Auto Hop"] = "Leaves for a better server once this one has emptied out.",
	["Hop When Below"] = "How few people have to be left before it goes looking for somewhere else.",
	["Pick Server By"] = "What makes a server worth moving to.",
	["Highest Ping"] = "Servers slower than this are skipped, however full they are.",
	["Hop Now"] = "Goes to the best server it can find, right now.",
}

--------------------------------------------------------------------------------

-- A rolling record of the last things the farm said to the server.
--
-- Three kicks in and the log still could not answer the only question that
-- matters, because a snapshot of the moment of the kick says nothing about the
-- minute before it. Two of the three happened with every switch off and the
-- character standing still, which rules out the farm's behaviour and leaves
-- what it had been saying to the server. So every request goes in a ring buffer
-- with the time since it happened, and the kick log prints the lot.
--
-- It lives out here rather than inside Build because Build is one function and
-- that function is at Luau's ceiling of 200 local registers: one more local in
-- there and the whole module stops compiling.
local journal = { keep = 60, entries = {} }

function journal.note(what)
	local list = journal.entries
	list[#list + 1] = { at = os.clock(), what = what }
	if #list > journal.keep then
		table.remove(list, 1)
	end
end

function journal.text()
	local list = journal.entries
	if #list == 0 then
		return "(nothing recorded)"
	end
	local now = os.clock()
	local out = {}
	for _, entry in ipairs(list) do
		out[#out + 1] = ("-%.1fs %s"):format(now - entry.at, entry.what)
	end
	return table.concat(out, " ; ")
end

function Module.Build(ctx)
	journal.entries = {}
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
	local Save = require(Client:WaitForChild("Save"))
	local Network = require(Client:WaitForChild("Network"))

	local Constants = require(Library:WaitForChild("Globals"):WaitForChild("Constants"))
	local NET = Constants.NETWORK_MAP

	local AssetGen = require(Library:WaitForChild("Util"):WaitForChild("AssetGenerationUtil"))
	local Assets = require(Directory:WaitForChild("Assets"))
	local Areas = require(Directory:WaitForChild("Areas"))
	local Guards = require(Directory:WaitForChild("Guards"))

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
	-- The index, which turns out to be the largest number in this game.
	--
	-- Every asset carries an IndexSpeedReward, paid once, the first time you
	-- ever hatch that species. He has 42 of the 84 and the 42 he is missing add
	-- up to 40,586,150 Speed Power against the 11.5M he has now - roughly four
	-- times everything he owns, and the only route past Prehistoric at 17M.
	--
	-- Which means the best egg on the map is usually not the most valuable one.
	-- It is one whose species he has never hatched.
	local AssetDirectory = Assets.Directory or Assets

	-- Held for a couple of seconds rather than asked for every egg on every
	-- tick. Forty eggs three times a second is a lot of times to ask the same
	-- question of a table that changes when you hatch something.
	local indexCache = { at = 0, map = nil }

	local function indexMap()
		local now = os.clock()
		if indexCache.map and now - indexCache.at < 3 then
			return indexCache.map
		end
		local ok, data = pcall(Save.Get)
		if ok and type(data) == "table" and type(data.Index) == "table" then
			indexCache.map = data.Index
			indexCache.at = now
		end
		return indexCache.map
	end

	local function indexHas(category)
		local map = indexMap()
		if not map then
			-- Not knowing is not the same as not having it, and treating unknown
			-- as new would send the farm chasing everything on the map.
			return true
		end
		return map[category] == true
	end

	local function indexReward(category)
		local asset = category and AssetDirectory[category]
		return (type(asset) == "table" and tonumber(asset.IndexSpeedReward)) or 0
	end

	-- Where the index actually stands, area by area.
	--
	-- Each area carries a DropTable of the species that spawn in it and an
	-- IndexBatGearId, so finishing an area's drop table is what hands you that
	-- area's bat. That makes the areas the right grouping and not the rarities,
	-- which was the first guess.
	local AreaDirectory = Areas.Directory or Areas

	local function indexProgress()
		local map = indexMap() or {}
		local out = {}
		for id, area in pairs(AreaDirectory) do
			if type(area) == "table" and type(area.DropTable) == "table" then
				local row = { got = 0, total = 0, owed = 0, missing = {}, bat = area.IndexBatGearId }
				for _, entry in ipairs(area.DropTable) do
					local name = entry[1]
					row.total = row.total + 1
					if map[name] then
						row.got = row.got + 1
					else
						row.missing[#row.missing + 1] = name
						row.owed = row.owed + indexReward(name)
					end
				end
				out[id] = row
			end
		end
		return out
	end

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

	-- Whether we would actually get out with it, which is a different question
	-- from whether we are fast enough for the area.
	--
	-- The sign at the mouth answers the second one and the farm has been obeying
	-- it. But it kept taking eggs with the guard standing right there, losing
	-- them a second later, and taking another: twelve grabs in three minutes on
	-- the run that got the account kicked, six of them dropped. No person plays
	-- like that. A person waits for the guard to wander off.
	--
	-- So this runs the game's own escape model against where the guard is
	-- standing right now. He sleeps for the waking duration after you take one,
	-- you carry at about nine tenths speed, and after that it is a plain
	-- pursuit: if he is faster than you, he closes the head start at the
	-- difference, and the only question is whether the fence arrives first.
	local GuardConfig = Guards.Directory or Guards
	local WAKING = 0.63
	do
		local ok, policy = pcall(require, ReplicatedStorage.Library.Modules.GuardAreas.GuardChasePolicy)
		if ok and type(policy) == "table" and type(policy.GetWakingDuration) == "function" then
			local fine, value = pcall(policy.GetWakingDuration)
			if fine and tonumber(value) then
				WAKING = value
			end
		end
	end

	-- Not a constant, a starting guess. The server sends the real number with
	-- every carry as SpeedMultiplier and the handler below overwrites this with
	-- it, because guessing here is how you take an egg you cannot get away with:
	-- at 62 walkspeed against a Desert guard that also walks 62, the difference
	-- between 0.9 and whatever it really is decides the whole trip.
	local CARRY_SLOWDOWN = 0.9
	-- Arrive with room to spare rather than by a stride. A photo finish is a
	-- lost egg most of the time, because the guard does not run in a straight
	-- line and neither do we.
	local ESCAPE_MARGIN = 1.3

	local function guardPart(areaId)
		local model = areaModel(areaId)
		local guard = model and model:FindFirstChild("Guard")
		if not guard then
			return nil
		end
		return guard.PrimaryPart
			or guard:FindFirstChild("HumanoidRootPart")
			or guard:FindFirstChildWhichIsA("BasePart")
	end

	local function willEscape(areaId, from)
		if F.stealEscape == false then
			return true
		end
		local model = areaModel(areaId)
		local door = model and model:FindFirstChild("ClosestExitPoint")
		local guard = guardPart(areaId)
		if not door or not guard then
			-- No door or no guard rendered yet is not a reason to stand still.
			return true
		end

		local config = GuardConfig[areaId]
		local guardSpeed = tonumber(type(config) == "table" and config.WalkSpeed) or 60
		local hitDistance = tonumber(type(config) == "table" and config.HitDistance) or 4

		local hum = core:Humanoid()
		local mySpeed = (hum and hum.WalkSpeed or 16) * CARRY_SLOWDOWN
		if mySpeed <= 1 then
			return false
		end

		local exit = Vector3.new(door.Position.X, from.Y, door.Position.Z)
		local away = exit - from
		local run = away.Magnitude
		if run < 1 then
			return true
		end
		local exitTime = run / mySpeed
		if exitTime <= WAKING then
			-- Out of the fence before he has opened his eyes.
			return true
		end

		local toGuard = Vector3.new(guard.Position.X, from.Y, guard.Position.Z)
		local lead = (from - toGuard):Dot(away.Unit) + mySpeed * WAKING
		if lead <= hitDistance then
			return false
		end
		if mySpeed >= guardSpeed then
			return true
		end
		local closeIn = (lead - hitDistance) / (guardSpeed - mySpeed)
		return (WAKING + closeIn) > exitTime * ESCAPE_MARGIN
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

	-- A purchase sent on a RemoteEvent gets no answer, so there is no refusal to
	-- count and nothing to back off from. Base upgrades were fired every twenty
	-- seconds forever on that basis. Record what was in the bank instead: it
	-- will not be asked again until there is more than there was, which covers
	-- both "could not afford it" and "bought it, and the next one costs more".
	local function spent(key, interval)
		refusedAt[key] = money()
		nextDue[key] = os.clock() + interval
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

	-- A rolling record of the last things the farm did.
	--
	-- Three kicks in and the log still could not answer the only question that
	-- matters, because a snapshot of the moment of the kick says nothing about
	-- the minute before it. Two of the three happened with every switch off and
	-- the character standing still, which rules out the farm's behaviour and
	-- leaves what it had been saying to the server. So every request goes in a
	-- ring buffer with the time since it happened, and the kick log prints the
	-- lot. The next kick arrives with its own evidence attached.
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
			local ok, reason = answerWithin(Network.Invoke, action, ...)
			journal.note(("%s %s"):format(action, ok and "ok" or ("refused: " .. tostring(reason))))
			return ok, reason
		end
		if remote:IsA("RemoteEvent") then
			local ok, err = pcall(Network.Fire, action, ...)
			journal.note(("%s %s"):format(action, ok and "fired" or ("failed: " .. tostring(err))))
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
	local selling = {
		RANK = {
			Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5,
			Mythic = 6, Cosmic = 7, Secret = 8, Eternal = 9, Divine = 10,
		},
	}

	local carrying = { active = false, uid = nil, slowedTo = 1, area = nil }

	-- Losing an egg is the observable that matters, and until now nothing
	-- counted it.
	--
	-- The run that got the account kicked was twelve grabs and six losses: the
	-- farm stood in the guard's reach taking, being hit, and taking again. The
	-- guard check ahead of the grab should stop most of that, but a rule that is
	-- sometimes wrong needs something behind it, and this is the honest signal.
	-- Three in five minutes means whatever the prediction thinks, it is losing,
	-- so it goes home and earns Speed for a while instead. Which is both safer
	-- and what a person would do after being caught three times.
	-- The three numbers live on the table rather than beside it, because Build
	-- is at Luau's 200-register ceiling and three constants is three registers
	-- that a whole feature needed more. See MERIDIAN-DESIGN.
	local losses = { at = {}, cooling = 0, window = 300, limit = 3, cooldown = 240, byArea = {} }

	-- How often a trip out of an area actually ends with the egg at home.
	losses.seen = function(areaId, gotHome)
		if type(areaId) ~= "string" then
			return
		end
		local row = losses.byArea[areaId]
		if not row then
			row = { home = 0, lost = 0 }
			losses.byArea[areaId] = row
		end
		if gotHome then
			row.home = row.home + 1
		else
			row.lost = row.lost + 1
		end
	end

	-- The odds of getting an egg out of an area, as a number between 0 and 1.
	--
	-- The sign at the mouth of an area says what Speed gets you in. It says
	-- nothing about what gets you out, and those are different questions: at 62
	-- walkspeed against a Desert guard that also walks 62 he lost three in a
	-- row, twice, out of an area the sign said he was ready for. A rich area you
	-- cannot leave is worth nothing at all.
	--
	-- Two sources. The prior is physics - your carrying speed against the
	-- guard's, which is knowable before you ever go there and is what stops the
	-- farm learning the hard way in an area that will hurt. The correction is
	-- what actually happened, because the prior knows nothing about the shape of
	-- the room, where the door is, or how many players are on the server
	-- slapping eggs out of your hands. Observation takes over as trips
	-- accumulate, and never entirely, so a run of bad luck cannot write an area
	-- off forever.
	losses.odds = function(areaId)
		local config = GuardConfig[areaId]
		local guard = tonumber(type(config) == "table" and config.WalkSpeed) or 60
		local hum = core:Humanoid()
		local mine = (hum and hum.WalkSpeed or 16) * CARRY_SLOWDOWN
		local ratio = mine / math.max(guard, 1)
		-- Level pegging is a coin toss; 15% either way settles it.
		local prior = math.clamp((ratio - 0.85) / 0.3, 0.05, 1)

		local row = losses.byArea[areaId]
		if not row then
			return prior
		end
		local trips = row.home + row.lost
		if trips < 3 then
			return prior
		end
		local weight = math.min(trips / 10, 0.8)
		return prior * (1 - weight) + (row.home / trips) * weight
	end

	-- Filled in further down, once there is something to ask about a Tool and
	-- somewhere to count it. The signal has to be connected here, before the
	-- interface exists, or the connection never gets made at all.
	local onCarryEnded = nil

	local function noteLoss()
		local now = os.clock()
		local kept = {}
		for _, when in ipairs(losses.at) do
			if now - when < losses.window then
				kept[#kept + 1] = when
			end
		end
		kept[#kept + 1] = now
		losses.at = kept
		if #kept >= losses.limit then
			losses.at = {}
			losses.cooling = now + losses.cooldown
			core:Notify("Meridian", "Lost three in a row. Earning Speed for a bit instead.", 6)
		end
	end

	local function beingCareful()
		return os.clock() < losses.cooling
	end

	do
		local signal = EggCmds.AreaEggCarryStateChanged
		if type(signal) == "table" and signal.Connect then
			core:Connect(signal, function(state)
				if type(state) ~= "table" then
					return
				end
				local was = carrying.active
				local endedUid = carrying.uid
				local endedArea = carrying.area
				carrying.active = state.IsCarrying == true
				carrying.uid = carrying.active and state.Uid or nil
				carrying.slowedTo = tonumber(state.SpeedMultiplier) or 1

				-- The server's own number for how much an egg slows you. Only
				-- while actually carrying: it comes back as 1 when the carry
				-- ends and that would quietly undo the measurement.
				if carrying.active and carrying.slowedTo > 0 and carrying.slowedTo < 1 then
					CARRY_SLOWDOWN = carrying.slowedTo
				end

				-- Carrying stopped. Either it was claimed, which is a Tool
				-- appearing a moment later, or a guard took it off us. Give the
				-- claim a moment to show up before calling it a loss.
				if was and not carrying.active and onCarryEnded then
					onCarryEnded(endedUid, endedArea)
				end
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

	-- The search that decides which egg matters, and it is not free: every record
	-- on the map, a worth lookup, a mutation list, an index lookup, a distance
	-- and two sorts. It used to run twice on every tick of a ten hertz loop plus
	-- once for the ESP, which is twenty-three full passes a second to answer a
	-- question whose answer changes when an egg spawns.
	local rankCache = { at = 0, list = nil }

	local function rankedEggsUncached()
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
					local category = record.AssetCategory
					local fresh = not indexHas(category)
					bucket[#bucket + 1] = {
						record = record,
						position = position,
						distance = distance,
						worth = worth,
						mutations = mutations,
						fresh = fresh,
						reward = fresh and indexReward(category) or 0,
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

			-- Worth times the odds of getting it home, not the highest sign.
			-- The old rule took the richest area it was allowed into and stayed
			-- there, which is how it spent an afternoon feeding Desert guards.
			-- An area where nothing survives the walk scores zero however good
			-- the eggs look sitting on the ground.
			local bestScore = 0
			for _, area in ipairs(tiers) do
				local bucket = byArea[area.id]
				if bucket and #bucket > 0 then
					local top = 0
					for _, egg in ipairs(bucket) do
						if egg.worth > top then
							top = egg.worth
						end
					end
					local score = top * losses.odds(area.id)
					if score > bestScore then
						bestScore = score
						home = bucket
						homeBest = top
						chosenArea = area.id
					end
				end
			end
			out = home or {}

			-- The top area is home, and it stays home even on a thin minute.
			-- But when it has been picked clean and something several times
			-- better is sitting in an area below, the walk is the same walk and
			-- the trade goes the other way. Several times, not slightly: one
			-- lucky Snow egg beating one Volcano egg is not a reason to move
			-- house, which is the thing he caught it doing.
			--
			-- A species never hatched is the other reason to leave, and it does
			-- not have to beat anything: the index reward is paid once, it is
			-- worth more than a night of farming, and there is no second chance
			-- at a first hatch. The biggest one on the map wins, wherever it is.
			if home then
				local away, awayReward = nil, 0
				for _, area in ipairs(tiers) do
					for _, egg in ipairs(byArea[area.id] or {}) do
						if egg.fresh and egg.reward > awayReward then
							away, awayReward = area.id, egg.reward
						end
					end
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
				if away and F.stealFresh ~= false and away ~= chosenArea then
					out = byArea[away]
					chosenArea = away
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
		-- A species you have never hatched jumps the queue, in every mode, because
		-- the reward for it is paid once and never again. Within the new ones it
		-- is still worth going for the bigger reward first.
		local prefer = F.stealFresh ~= false

		if prefer then
			local fresh, rest = {}, {}
			for _, egg in ipairs(out) do
				if egg.fresh then
					fresh[#fresh + 1] = egg
				else
					rest[#rest + 1] = egg
				end
			end
			if #fresh > 0 then
				table.sort(fresh, function(a, b)
					if a.reward ~= b.reward then
						return a.reward > b.reward
					end
					return a.distance < b.distance
				end)
				-- Everything already indexed still gets ranked the usual way and
				-- kept behind them, so the farm never runs out of work.
				out = fresh
				table.move(rest, 1, #rest, #fresh + 1, out)
				return out
			end
		end

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

	local function rankedEggs()
		local now = os.clock()
		if rankCache.list and now - rankCache.at < 0.25 then
			return rankCache.list
		end
		rankCache.list = rankedEggsUncached()
		rankCache.at = now
		return rankCache.list
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
	local lastCarryAt = 0
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
	-- Every egg you own that is not in the ground yet.
	--
	-- The save carries an EggInventory keyed by uid, and an entry with a
	-- Placement is one already on the pad. He had eleven without one against two
	-- with - an evening of carrying, sitting in a bag earning nothing - because
	-- the farm only ever planted what was in its hands on the walk home.
	-- Anything that arrived another way, or was there before the hub loaded, or
	-- that a kick interrupted mid-trip, stayed in the bag for good.
	--
	-- RequestEquipTool takes one out of the bag from anywhere on the map, so
	-- there is no walk to add. Only the placing needs you standing on the plot.
	local function looseEggs()
		local ok, data = pcall(Save.Get)
		if not ok or type(data) ~= "table" or type(data.EggInventory) ~= "table" then
			return {}
		end
		local out = {}
		for uid, record in pairs(data.EggInventory) do
			if type(uid) == "string" and type(record) == "table" and record.Placement == nil then
				out[#out + 1] = uid
			end
		end
		return out
	end

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

	-- Now that there is a Tool to look for, the carry-ended signal above can
	-- tell a claim from a guard taking it off us.
	onCarryEnded = function(uid, area)
		task.delay(1.2, function()
			local root = core:Root()
			local home = root and PlotCmds.IsWorldPositionWithinLocalPlotBounds(root.Position)
			if home or heldEggTool() then
				losses.seen(area, true)
				return
			end
			stats.lost = (stats.lost or 0) + 1

			-- Why, not just that. The game records a DropReason on the egg and
			-- they are not the same problem: GuardHit says the escape check was
			-- wrong and trying again soon is how the account got kicked, while
			-- PlayerSlap is another player on a busy server and no amount of
			-- waiting fixes it. Counting them together sends the farm to the
			-- treadmill for four minutes over something it could not have
			-- avoided and could not have prevented by stopping.
			local reason = "unknown"
			if uid and EggCmds.GetAreaEggRecord then
				local ok, record = pcall(EggCmds.GetAreaEggRecord, uid)
				if ok and type(record) == "table" and record.DropReason then
					reason = tostring(record.DropReason)
				end
			end
			journal.note("lost " .. reason)

			losses.seen(area, false)

			if reason == "PlayerSlap" then
				sayOnce("slapped", "Someone slapped it out of your hands", "Not the guards, so not backing off")
				return
			end
			noteLoss()
		end)
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
		journal.note(("PlaceEgg %s"):format(took and "ok" or ("refused: " .. tostring(reason))))
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

	local function treadmillSpot()
		local data = plotData()
		local folder = data and data.PlotFolder
		local bottom = folder and folder:FindFirstChild("TreadmillBottom", true)
		return bottom and bottom:IsA("BasePart") and bottom.Position or nil
	end

	-- Standing still on purpose is not being stuck, and the treadmill is the one
	-- place where the two look identical.
	local grinding = false
	local grindReason = nil

	-- Walk around the treadmill rather than over it.
	--
	-- The way out of the base runs straight across it and stepping on one
	-- anchors the character, so the farm stopped dead, got itself off a second
	-- later, took two steps and stood on it again. He noticed it every single
	-- time he came back. Getting off it quickly was treating the symptom.
	--
	-- This is the ordinary steering answer: while we are not deliberately
	-- riding it, anything in front of us and near the line gets pushed around
	-- rather than walked through, harder the closer it is to dead ahead.
	local TREADMILL_CLEAR = 20

	-- Walking the way a keyboard walks.
	--
	-- WASD has eight combinations, so a desktop player's MoveDirection is always
	-- one of eight directions relative to the camera. Ours is any angle at all,
	-- held perfectly steady, for hours. Whether this game looks at that is a
	-- guess - the kick message is generic and the check is server side - but it
	-- is the cleanest difference there is between us and a person, and snapping
	-- to the eight costs a 22 degree error that a path correction absorbs
	-- immediately.
	--
	-- Off by default, because it is a guess. The kick log is what will settle
	-- it: leave it on for a night, leave it off for a night, compare.
	local function likeAKeyboard(direction)
		if F.stealHuman ~= true then
			return direction
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return direction
		end
		local look = camera.CFrame.LookVector
		local ahead = Vector3.new(look.X, 0, look.Z)
		if ahead.Magnitude < 0.01 then
			return direction
		end
		ahead = ahead.Unit
		local right = Vector3.new(-ahead.Z, 0, ahead.X)
		-- sin(22.5 degrees), which is where one key stops and two begin.
		local EDGE = 0.3827
		local forward = direction:Dot(ahead)
		local across = direction:Dot(right)
		local f = (forward > EDGE and 1) or (forward < -EDGE and -1) or 0
		local r = (across > EDGE and 1) or (across < -EDGE and -1) or 0
		if f == 0 and r == 0 then
			return direction
		end
		local out = ahead * f + right * r
		return out.Magnitude > 0.01 and out.Unit or direction
	end

	local function dodgeTreadmill(from, direction)
		if grinding then
			return direction
		end
		local spot = treadmillSpot()
		if not spot then
			return direction
		end
		local toward = Vector3.new(spot.X - from.X, 0, spot.Z - from.Z)
		local range = toward.Magnitude
		if range < 0.1 or range > TREADMILL_CLEAR * 3 then
			return direction
		end
		if toward.Unit:Dot(direction) <= 0.2 then
			-- Behind us or off to the side. Nothing to walk into.
			return direction
		end
		local side = toward - direction * toward:Dot(direction)
		local off = side.Magnitude
		if off > TREADMILL_CLEAR then
			return direction
		end
		local push = off < 0.1 and Vector3.new(-direction.Z, 0, direction.X) or -side.Unit
		local strength = math.clamp((TREADMILL_CLEAR - off) / TREADMILL_CLEAR, 0, 1) * 1.7
		local out = direction + push * strength
		return out.Magnitude > 0.01 and out.Unit or direction
	end

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
		steer.direction = likeAKeyboard(dodgeTreadmill(root.Position, flat.Unit))
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

	-- The screen on the treadmill plays video the whole time you are on it, which
	-- costs frames and is the last thing anyone leaving a farm running overnight
	-- wants playing. The game has a Stop of its own, so getting on it stops the
	-- video once and leaves it alone after that.
	local VideoController = nil
	do
		local ok, module = pcall(function()
			return require(Client:WaitForChild("TreadmillVideoController", 5))
		end)
		VideoController = ok and type(module) == "table" and module or nil
	end

	local function hushTheScreen()
		if not VideoController or type(VideoController.Stop) ~= "function" then
			return
		end
		pcall(VideoController.Stop)
	end

	do
		local ok, signal = pcall(Network.Fired, NET.Treadmills.ACTIVE_TREADMILL_EVENT)
		if ok and type(signal) == "table" and signal.Connect then
			core:Connect(signal, function(which)
				local on = which ~= nil
				if on and not treadmill.active then
					hushTheScreen()
				end
				treadmill.active = on
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
	local TREADMILL_PATIENCE = 1800

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

	-- What you earn right now, which is the only sensible yardstick for whether
	-- an egg is worth walking to.
	local function moneyRate()
		local stats = LocalPlayer:FindFirstChild("leaderstats")
		local per = stats and stats:FindFirstChild("Money/s")
		return tonumber(per and per.Value) or 0
	end

	-- Is anything on the map worth the trip, or is the treadmill a better use of
	-- the next few minutes?
	--
	-- He watched it walk fifteen hundred studs for an egg worth 191 a second
	-- while earning twenty-one million a second, and said what anyone would:
	-- that is not going to do anything. He is right. An egg that adds a rounding
	-- error to what you already make is not worth the walk, and the treadmill
	-- pays the same four thousand Speed a second whatever the map looks like.
	--
	-- A species never hatched is always worth it, whatever it earns, because
	-- that reward is paid once and there is no second chance at it.
	local function worthTheTrip(egg, times)
		if not egg then
			return false
		end
		if egg.fresh then
			return true
		end
		local share = (tonumber(F.stealShare) or 2) / 100 * (times or 1)
		local earning = moneyRate()
		if earning <= 0 or share <= 0 then
			return true
		end
		return egg.worth >= earning * share
	end

	-- Two reasons to be standing on it, and the second one is the one he asked
	-- for: the next area is a sitting away, or there is nothing out there worth
	-- the walk.
	local function worthGrinding(best)
		local gap, area = nextAreaGap()
		-- Three eggs lost in five minutes means the escape prediction is wrong
		-- about something, and the answer to that is not to try a fourth time.
		if beingCareful() then
			return true, "lost three, letting the guards settle", area, gap
		end
		-- An area you can already walk into and have never finished is worth
		-- more than the next door along.
		--
		-- On a fresh account the old rule ground forever. Ten Speed, no pets, no
		-- money: it walked to the treadmill, unlocked Lake, did not so much as
		-- glance at it, and set off for Desert eight thousand Speed away. Half
		-- an hour in it would still have had nothing - no eggs, no income, an
		-- empty index - because a gap that big divided by the treadmill's rate
		-- still came in under half an hour of patience, and patience was the
		-- only thing the rule asked about.
		--
		-- What it should have asked is whether there is anything left in the
		-- room. Every species is an index entry, and an index entry is Speed you
		-- keep and a bat, on top of the egg's own earnings. Grinding past a room
		-- you have not emptied is buying a door you do not need yet.
		--
		-- The locals here are free: this is its own closure, and it is Build's
		-- register frame that is full, not this one.
		local unfinished = nil
		if best then
			local power = mySpeedPower()
			for id, row in pairs(indexProgress()) do
				local need = AREA_NEEDS[id]
				if need and need <= power and row.got < row.total then
					unfinished = id
					break
				end
			end
		end
		if gap and not unfinished and gap / math.max(rate.estimate, 1) <= TREADMILL_PATIENCE then
			return true, ("%s of Speed to %s"):format(short(gap), area), area, gap
		end
		if F.speedIdle ~= false then
			-- Hysteresis, because the map changes every few seconds and a farm
			-- that walks out, turns round, and walks out again gets nothing done
			-- and looks worse than either choice. Once it is on the treadmill it
			-- wants twice the reason to leave.
			local enough = worthTheTrip(best)
			if grinding then
				enough = enough and worthTheTrip(best, 2)
			end
			if not enough then
				return true, "nothing out there worth the walk", area, gap
			end
		end
		return false, nil, area, gap
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

	-- Getting on, which nothing ever did.
	--
	-- The farm walked to the treadmill, stopped, and reported "On the treadmill"
	-- for as long as you left it there, gaining nothing. The pad is an invisible
	-- marker: no collision, no prompt, a thousandth of a stud thick and three
	-- below the floor you stand on. So the obvious reading - step on it and the
	-- server notices - looked right and was wrong. Measured on a fresh account:
	-- six seconds standing on it gained nothing, ten seconds walking on the spot
	-- gained nothing, and one REQUEST_EQUIP_STATIC took ten Speed to forty-two
	-- in five seconds. Mounting is a request, and until it is made a night on
	-- the treadmill is a night of standing still.
	function treadmill.mount()
		if onTreadmill() then
			return true
		end
		if not nearTreadmill() then
			return false
		end
		if not due("treadmillOn", 3) then
			return false
		end
		local ok, reason = ask(NET.Treadmills.REQUEST_EQUIP_STATIC)
		if ok then
			-- The event corrects this a moment later either way; believing it
			-- now is what stops a second request going out on the next tick.
			treadmill.active = true
			accepted("treadmillOn")
			return true
		end
		if refused("treadmillOn", 3) == 1 then
			sayOnce("mount", "Could not get on the treadmill", tostring(reason or "the server said no"))
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

	----------------------------------------------------------------------------
	-- the fuse machine
	----------------------------------------------------------------------------

	-- Three pets of one species in, one egg of that species out, and a fee of
	-- three minutes of what those three were earning. He said his pets got worse
	-- and he was right: it is a losing trade nearly everywhere, and the reason is
	-- a single exponent. A pet earns as scale^1.85, so turning three into one
	-- needs the survivor 81% bigger than the inputs just to break even.
	--
	-- Rolling the game's own RollFusedAssetScale twenty thousand times per input
	-- size: three ordinary pets hand back 58% of the earning power that went in,
	-- and beat the trade one time in ten. It gets worse the better the pets are,
	-- because the tilt toward bigger tiers never catches the s^1.85 you threw
	-- away - three scale-4 pets keep a fifth. Worst of all, the fee reads the
	-- inputs' mutations and triples for them while the output rolls its own, so
	-- three mutated pets cost treble and come back plain.
	--
	-- There is exactly one place it wins. Below about 0.66 the roll drags a runt
	-- back toward an ordinary pet, and three runts are worth so little that
	-- nearly anything beats them. So this fuses runts and refuses everything
	-- else. Every other hub will ship "Auto Fuse" and quietly cost people money
	-- three pets at a time.
	--
	-- One table rather than a dozen locals, because Build is one function sitting
	-- on Luau's ceiling of 200 registers and a whole feature will not fit.
	local fuse = { crossover = 0.656, spot = nil, said = false }

	function fuse.machine()
		if fuse.spot then
			return fuse.spot
		end
		local objects = Workspace:FindFirstChild("__OBJECTS")
		local machines = objects and objects:FindFirstChild("Machines")
		local model = machines and machines:FindFirstChild("FuseMachine")
		local part = model and (model.PrimaryPart
			or model:FindFirstChild("Overhead")
			or model:FindFirstChildWhichIsA("BasePart"))
		fuse.spot = part and part.Position or nil
		return fuse.spot
	end

	-- Three of one species, all under the line, none favourited, none already in
	-- a machine. Smallest first, and of the species that qualify, the one whose
	-- three are smallest - that is where the roll has the most room to help.
	function fuse.pick()
		local limit = tonumber(F.petsFuseBelow) or fuse.crossover
		local ok, data = pcall(Save.Get)
		if not ok or type(data) ~= "table" or type(data.Inventory) ~= "table" then
			return nil
		end
		local bySpecies = {}
		for uid, item in pairs(data.Inventory) do
			if type(uid) == "string" and type(item) == "table"
				and item.IsFavorite ~= true and item.InFuse ~= true
				and (tonumber(item.Scale) or 1) < limit
			then
				local list = bySpecies[item.Category]
				if not list then
					list = {}
					bySpecies[item.Category] = list
				end
				list[#list + 1] = { uid = uid, scale = tonumber(item.Scale) or 1 }
			end
		end
		local best, bestMean = nil, math.huge
		for species, list in pairs(bySpecies) do
			if #list >= 3 then
				table.sort(list, function(a, b)
					return a.scale < b.scale
				end)
				local mean = (list[1].scale + list[2].scale + list[3].scale) / 3
				if mean < bestMean then
					bestMean = mean
					best = {
						species = species,
						uids = { list[1].uid, list[2].uid, list[3].uid },
						mean = mean,
					}
				end
			end
		end
		return best
	end

	-- How many are in the machine right now, and whether they are ours to touch.
	function fuse.loaded(data)
		local n = 0
		for i = 1, 3 do
			local uid = data.FusionSlots and data.FusionSlots[i]
			if uid and data.Inventory and data.Inventory[uid] then
				n = n + 1
			end
		end
		return n
	end

	-- One step per call, never two, and every step behind a gate. The machine is
	-- a RemoteFunction on every route and the one lesson this game has taught
	-- repeatedly is that an impossible request asked twice a second is what gets
	-- you removed.
	function fuse.tick()
		if F.petsFuse ~= true then
			return false
		end
		local ok, data = pcall(Save.Get)
		if not ok or type(data) ~= "table" then
			return false
		end

		-- Something finished: take it before anything else.
		if data.FusionReward ~= nil or data.FusionEggReward == true then
			if due("fuseClaim", 5) and ask(NET.FuseMachine.COMPLETE_REVEAL) then
				accepted("fuseClaim")
				core:Notify("Meridian", "Took the fused egg", 4)
			end
			return true
		end

		-- Running. Nothing to do but let it.
		if data.FusionLocked == true then
			return true
		end

		local held = fuse.loaded(data)

		-- Loaded and idle: start it.
		if held >= 3 then
			if not due("fuseStart", 6) then
				return true
			end
			local started, why = ask(NET.FuseMachine.START_FUSE)
			if started then
				accepted("fuseStart")
				core:Notify("Meridian", "Fusing three runts", 4)
			elseif refused("fuseStart", 6) == 1 then
				sayOnce("fuse", "Could not start the fuse", tostring(why or "the server said no"))
			end
			return true
		end

		local batch = fuse.pick()
		if not batch then
			return false
		end

		-- The machine is a fixed thing across the lobby and the requests may or
		-- may not care how far away we are. Walking there is what a player does
		-- and it costs one trip, where being wrong about it costs a refusal
		-- repeated forever.
		local where = fuse.machine()
		if not where then
			return false
		end
		if not walkTo(where, 12) then
			return true
		end
		stopWalking()

		if not due("fuseInsert", 1.5) then
			return true
		end
		local uid = batch.uids[held + 1]
		if not uid then
			return true
		end
		local inserted, why = ask(NET.FuseMachine.INSERT_MOB, uid)
		if inserted then
			accepted("fuseInsert")
		elseif refused("fuseInsert", 1.5) == 1 then
			sayOnce("fuseIn", "Could not load the fuse machine", tostring(why or "the server said no"))
		end
		return true
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
				--
				-- Not while anchored, though. A treadmill anchors the root part,
				-- and a character jumping on the spot while the server has it
				-- pinned is not something a player can do, which is exactly the
				-- sort of thing a character integrity check is watching for.
				local feet = core:Root()
				local hum = core:Humanoid()
				if hum and feet and not feet.Anchored then
					pcall(function()
						hum:ChangeState(Enum.HumanoidStateType.Jumping)
					end)
				end
			end
		end
	end

	-- The server watches the character and says so when it disagrees.
	--
	-- ClientCharacter carries IntegrityViolation, CorrectionStarted and an
	-- IntegrityHeartbeat, which means this game keeps its own model of where you
	-- should be and how fast you got there. Nothing in the client calls those,
	-- so they are the server talking to us, and they are the closest thing to a
	-- warning shot before a kick.
	--
	-- So when one arrives: stop moving, stand still for a few seconds, and say
	-- so on screen. A farm that freezes for five seconds has lost five seconds.
	-- A farm that carries on has lost the account for the evening.
	local flagged = { until_ = 0, count = 0 }

	local function warned(what)
		flagged.until_ = os.clock() + 6
		flagged.count = flagged.count + 1
		stopWalking()
		clearRoute()
		warn(("[Meridian] the server flagged the character (%s), standing still for a moment"):format(what))
		if flagged.count <= 3 or flagged.count % 10 == 0 then
			core:Notify("Meridian", ("Server said %s. Waiting a moment."):format(what), 5)
		end
	end

	for name, label in pairs({
		INTEGRITY_VIOLATION = "the character moved wrong",
		CORRECTION_STARTED = "it is correcting the character",
	}) do
		local action = NET.ClientCharacter and NET.ClientCharacter[name]
		if action then
			local ok, signal = pcall(Network.Fired, action)
			if ok and type(signal) == "table" and signal.Connect then
				core:Connect(signal, function()
					warned(label)
				end)
			end
		end
	end

	-- Write down what the game says when it kicks us, because it says why and
	-- nobody is ever watching at the moment it happens.
	--
	-- The kick message lands in Roblox's own error prompt, which survives just
	-- long enough to read and then the client rejoins and the console is gone
	-- with it. So it goes to a file, with what the farm was doing at the time.
	-- After a night of this the file answers a question we have been guessing
	-- at: whether it is the requests or the character.
	local KICK_LOG = "Meridian/kicks.txt"

	-- What the farm was doing, in enough detail to be worth reading later.
	--
	-- The first version wrote "doing: nothing" and that told us nothing at all.
	-- The kick message itself is generic - "removed for cheating, CODE BAC-6517"
	-- - and the code is server side, so the only way to work out what set it off
	-- is a record of what was happening each time. Every switch that was on,
	-- how much had been taken and how recently, where the character was and how
	-- fast: one of those columns will be the same on every line.
	local function whatWasHappening()
		local bits = {}
		bits[#bits + 1] = "doing=" .. tostring(core.Headline or "idle")
		bits[#bits + 1] = ("took=%d planted=%d in %dm"):format(
			stats.taken, stats.placed, math.floor((os.clock() - stats.started) / 60))
		local root, hum = core:Root(), core:Humanoid()
		if root then
			bits[#bits + 1] = ("at=%d,%d"):format(root.Position.X, root.Position.Z)
			bits[#bits + 1] = "anchored=" .. tostring(root.Anchored)
		end
		if hum then
			bits[#bits + 1] = ("ws=%d moving=%s"):format(hum.WalkSpeed, tostring(hum.MoveDirection.Magnitude > 0.1))
		end
		bits[#bits + 1] = "area=" .. tostring(chosenArea or "none")
		bits[#bits + 1] = "grinding=" .. tostring(grinding)
		bits[#bits + 1] = "onTreadmill=" .. tostring(treadmill.active)
		bits[#bits + 1] = "flagged=" .. tostring(flagged.count)
		local switches = {}
		for _, control in ipairs(core.Controls or {}) do
			if control.flag and core.Flags[control.flag] == true then
				switches[#switches + 1] = control.flag
			end
		end
		table.sort(switches)
		bits[#bits + 1] = "on=" .. table.concat(switches, ",")
		bits[#bits + 1] = "last=" .. journal.text()
		return table.concat(bits, " | ")
	end

	local function noteKick(reason)
		local newline = string.char(10)
		local line = ("%s | %s | %s"):format(
			os.date("%Y-%m-%d %H:%M:%S"),
			tostring(reason):gsub("%s+", " "),
			whatWasHappening()
		) .. newline
		warn("[Meridian] kicked: " .. line)
		pcall(function()
			local existing = ""
			if isfile and isfile(KICK_LOG) then
				existing = readfile(KICK_LOG)
			end
			writefile(KICK_LOG, existing .. line)
		end)
	end

	do
		local ok, coreGui = pcall(function()
			return game:GetService("CoreGui")
		end)
		if ok and coreGui then
			core:Connect(coreGui.DescendantAdded, function(thing)
				if not thing:IsA("TextLabel") then
					return
				end
				local prompt = thing:FindFirstAncestor("ErrorPrompt")
					or thing:FindFirstAncestor("ErrorTitleFrame")
					or thing:FindFirstAncestor("promptOverlay")
				if not prompt then
					return
				end
				task.delay(0.35, function()
					local text = thing.Text
					if type(text) == "string" and #text > 8 then
						noteKick(text)
					end
				end)
			end)
		end
	end

	core:Loop("steal", 0.1, function()
		if os.clock() < flagged.until_ then
			-- Being told off is the one time standing still is the right answer.
			stopWalking()
			return
		end

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
		local bagged = eggUid and 0 or #looseEggs()

		-- A base with no room is the one refusal that does not go away on its
		-- own, and until now it ended the night. Six attempts, a line in the
		-- notifications nobody is awake to read, and then the farm stood at the
		-- pad holding an egg and retrying forever: no eggs, no Speed, no money
		-- until morning. Ten minutes on the treadmill is worth something, and
		-- the parking expires by itself, so it goes back and tries again.
		if (eggUid or bagged > 0) and parked["place"] and os.clock() < (nextDue["place"] or 0) then
			local spot = treadmillSpot()
			if spot then
				if not grinding then
					grinding = true
					currentTarget = nil
					core:Notify("Meridian", "Base is full. Earning Speed until there is room.", 6)
				end
				grindReason = "base is full, nowhere to plant"
				if walkTo(spot, 3) then
					stopWalking()
				end
				treadmill.mount()
				return
			end
		end

		if eggUid or bagged > 0 then
			currentTarget = nil
			if F.basePlace == false then
				return
			end
			-- On the pad, not merely inside the fence. The plot is big and the
			-- pad is the part of it an egg can go on.
			if not goHome() then
				return
			end

			-- Standing on the pad with nothing in hand and eggs in the bag. Take
			-- one out. This is where the eleven he had been carrying home all
			-- evening finally go in the ground.
			if not eggUid and due("unbag", 1.5) then
				local waiting = looseEggs()
				local first = waiting[1]
				if first then
					local took = answerWithin(EggCmds.RequestEquipTool, first)
					journal.note(("EquipTool %s"):format(took and "ok" or "refused"))
					if took then
						accepted("unbag")
						eggUid = first
					else
						refused("unbag", 1.5)
					end
				end
			end
			if not eggUid then
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
		-- Clearing the runts out, before deciding between eggs and the treadmill.
		-- It shares one pair of legs with the farm, so it cannot have a loop of
		-- its own: two callers of walkTo pulling in different directions is the
		-- farm leaning on a wall again. It runs here, where the hands are empty,
		-- and it says whether it is busy.
		if fuse.tick() then
			return
		end

		if F.speedGrind ~= false then
			local grind, why = worthGrinding(rankedEggs()[1])
			if grind then
				local spot = treadmillSpot()
				if spot then
					if not grinding then
						grinding = true
						currentTarget = nil
						core:Notify("Meridian", "On the treadmill · " .. tostring(why), 6)
					end
					grindReason = why
					if walkTo(spot, 3) then
						stopWalking()
					end
					-- Gated on being near it, so this is a no-op for the whole
					-- walk over and one request once it arrives.
					treadmill.mount()
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

		-- Standing next to it is not the same as being able to get away with it.
		-- Wait for the guard to be somewhere else rather than taking it and
		-- losing it, which is both the difference between six eggs and twelve
		-- grabs and the difference between farming and looking like a script.
		if me and not willEscape(areaId, me) then
			-- Wait by the door rather than standing over the egg. Standing still
			-- inside a guard's reach is how you get hit without even taking
			-- anything, it is not what a person does, and from the door the run
			-- out is already half made.
			local door = areaEntrance(areaId)
			if door then
				walkTo(door, 8)
			else
				stopWalking()
			end
			if os.clock() - targetSince > 20 then
				sayOnce("guard", "Waiting on a guard", ("%s is standing over it"):format(tostring(areaId)))
				dropTarget()
			end
			return
		end

		-- A ceiling on how often an egg can be taken at all, whatever else says
		-- it is fine. Twelve in three minutes is what a kick looks like from the
		-- outside; a person doing well gets one every twenty or thirty seconds,
		-- and the walk takes longer than that anyway, so this only ever bites
		-- when something has gone wrong.
		local perMinute = math.clamp(tonumber(F.stealCeiling) or 5, 1, 30)
		local window = 60 / perMinute
		if os.clock() - lastCarryAt < window then
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
		journal.note(("CarryAreaEgg %s %s"):format(tostring(chosenArea), took and "ok" or ("refused: " .. tostring(reason))))
		if took then
			-- Tagged here rather than in the carry-state handler, which is built
			-- before chosenArea exists and would have read a nil global.
			carrying.area = chosenArea
		end
		local ok = true
		if took then
			accepted("carry")
			lastCarryAt = os.clock()
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
		--
		-- It used to skip anything that was not ready, which paid to hurry along
		-- an egg with eight seconds left. Growth times in this game run from ten
		-- seconds to a full day, and the whole point of skipping is the long
		-- ones: a twenty-four hour egg planted at midnight holds its patch of
		-- the base until tomorrow evening, and enough of those is a base with no
		-- room, which is how a night ends. So it skips what is actually in the
		-- way and lets the short ones cook.
		if F.baseSkip and due("skip", 4) then
			local floor = (tonumber(F.baseSkipOver) or 5) * 60
			local now = workspace:GetServerTimeNow()
			local saved = select(2, pcall(Save.Get))
			local bank = type(saved) == "table" and saved.EggInventory or nil
			for _, egg in ipairs(ownEggs()) do
				local ready = EggCmds.IsLocalEggReady and select(2, pcall(EggCmds.IsLocalEggReady, egg.uid))
				local left = 0
				local held = bank and bank[egg.uid]
				local where = type(held) == "table" and held.Placement or nil
				if type(where) == "table" then
					left = (tonumber(where.PlacedAt) or 0) + (tonumber(where.GrowthDuration) or 0) - now
				end
				if ready ~= true and left > floor then
					local ok, took = pcall(EggCmds.RequestSkipGrowth, egg.uid)
					journal.note(("SkipGrowth %dm %s"):format(left / 60, took ~= false and "ok" or "refused"))
					if ok and took ~= false then
						accepted("skip")
					else
						refused("skip", 4)
					end
					break
				end
			end
		end

		if F.baseUpgrade and due("upgrade", 120) then
			ask(NET.Plots.REQUEST_BASE_UPGRADE)
			spent("upgrade", 120)
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

	-- Everything the game will hand over for nothing, asked for on a gate.
	--
	-- These used to fire every minute whether or not there was anything to
	-- collect, which over a night is several hundred refusals for each - the
	-- shape that gets an account kicked, delivered slowly. A refusal now counts
	-- as one, so the backoff doubles and the breaker parks it, and the moment
	-- something is actually claimable it goes back to working.
	--
	-- Four of the names in the network map have no remote behind them in this
	-- game: free gifts, lucky blocks, rebirth and codes. ask() looks the remote
	-- up before calling and returns quietly, so the switches can stay on screen
	-- without costing anything.
	local FREE = {
		{ flag = "progIndex", key = "index", every = 120, action = NET.Index.REQUEST_CLAIM_ALL },
		{ flag = "progIndex", key = "indexEgg", every = 180, action = NET.Index.REQUEST_CLAIM_LIMITED_EGG_REWARD },
		{ flag = "progGroup", key = "group", every = 300, action = NET.GroupReward.CLAIM_REWARD },
		{ flag = "progGifts", key = "gifts", every = 120, action = NET.FreeGifts.REQUEST_CLAIM },
		{ flag = "progLucky", key = "lucky", every = 90, action = NET.LuckyBlock.REQUEST_STORED_BLOCK_OPEN_CLAIM },
	}

	core:Loop("progress", 8, function()
		for _, claim in ipairs(FREE) do
			if F[claim.flag] ~= false and due(claim.key, claim.every) then
				if ask(claim.action) then
					accepted(claim.key)
				else
					refused(claim.key, claim.every)
				end
			end
		end
		if F.progRebirth and due("rebirth", 120) then
			if ask(NET.Rebirth.REQUEST_REBIRTH) then
				task.wait(0.5)
				ask(NET.Rebirth.REQUEST_REBIRTH_COMMIT)
				accepted("rebirth")
			else
				refused("rebirth", 120)
			end
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
		billboard.Size = UDim2.fromOffset(300, 36)
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
		label.RichText = true
		label.Parent = billboard

		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 0.85
		highlight.OutlineTransparency = 0.2
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Enabled = false
		highlight.Parent = espHolder

		-- Drawn in the world rather than on the screen, which is the whole
		-- difference between these and the ones he called slow and snappy.
		--
		-- A Drawing line is a 2D overlay: it starts at the same place on screen
		-- however you are looking, it has to be re-projected every time the
		-- camera moves, and re-projecting it three times a second - which is how
		-- often the egg list is rebuilt - is a line that jumps rather than
		-- follows. A CylinderHandleAdornment is real geometry. It runs from your
		-- root to the egg, turns with the world on its own, and AlwaysOnTop
		-- still draws it through walls. It is the same thing Ability Arena uses,
		-- which is the one he said looks right.
		local tracer = Instance.new("CylinderHandleAdornment")
		tracer.Radius = 0.06
		tracer.AlwaysOnTop = true
		tracer.ZIndex = 0
		tracer.Transparency = 0.35
		tracer.Visible = false
		tracer.Parent = espHolder

		espPool[#espPool + 1] = {
			billboard = billboard,
			label = label,
			highlight = highlight,
			tracer = tracer,
			target = nil,
			colour = nil,
		}
	end

	-- Every frame, not three times a second. The list of which eggs matter is
	-- rebuilt slowly because that is a search; where the line has to be drawn
	-- changes every time the camera moves, which is sixty times faster.
	core:Connect(RunService.Heartbeat, function()
		local myRoot = core:Root()
		local on = F.eggEsp and F.eggEspTracers == true and myRoot ~= nil
		for _, mark in ipairs(espPool) do
			local target = on and mark.target or nil
			if target and target.Parent then
				local relative = myRoot.CFrame:PointToObjectSpace(target.Position)
				local length = relative.Magnitude
				if length > 0.5 then
					mark.tracer.Adornee = myRoot
					mark.tracer.Height = length
					mark.tracer.CFrame = CFrame.lookAt(Vector3.zero, relative) * CFrame.new(0, 0, -length / 2)
					mark.tracer.Color3 = mark.colour or Color3.fromRGB(255, 255, 255)
					mark.tracer.Visible = true
				else
					mark.tracer.Visible = false
				end
			elseif mark.tracer.Visible then
				mark.tracer.Visible = false
				mark.tracer.Adornee = nil
			end
		end
	end)

	local NEW_COLOUR = Color3.fromRGB(255, 214, 92)

	local function worthColour(worth, best)
		if best <= 0 then
			return Color3.fromRGB(235, 235, 235)
		end
		-- A root rather than a straight ratio, because one Cosmic egg on the map
		-- makes every other worth a fraction of a percent of it, and a linear
		-- ramp would paint everything else the same grey.
		local part = math.clamp(worth / best, 0, 1) ^ 0.4
		return Color3.fromRGB(150, 150, 150):Lerp(Color3.fromRGB(120, 255, 190), part)
	end

	-- The game's own rarity colour for the species, which is the one he already
	-- reads everywhere else in the game.
	local function rarityOf(category)
		local asset = category and AssetDirectory[category]
		local rarity = type(asset) == "table" and asset.Rarity or nil
		if type(rarity) ~= "table" then
			return nil, nil
		end
		return rarity.Color, rarity.DisplayName
	end

	local function espColour(egg, best)
		local mode = F.eggEspColour or "Worth"
		if mode == "Index" then
			return egg.fresh and NEW_COLOUR or Color3.fromRGB(140, 150, 160)
		end
		if mode == "Rarity" then
			local colour = rarityOf(egg.record.AssetCategory)
			if colour then
				return colour
			end
		end
		return worthColour(egg.worth, best)
	end

	local function hideFrom(index)
		for slot = index, ESP_POOL do
			local mark = espPool[slot]
			if not mark.billboard.Enabled and not mark.highlight.Enabled and not mark.target then
				break
			end
			mark.billboard.Enabled = false
			mark.highlight.Enabled = false
			mark.billboard.Adornee = nil
			mark.highlight.Adornee = nil
			mark.target = nil
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
		local best = 0
		for _, egg in ipairs(ranked) do
			if egg.worth > best then
				best = egg.worth
			end
		end

		local most = math.clamp(tonumber(F.eggEspMax) or ESP_POOL, 1, ESP_POOL)
		local size = math.clamp(tonumber(F.eggEspSize) or 15, 10, 30)
		local fill = math.clamp((tonumber(F.eggEspFill) or 15) / 100, 0, 1)
		local tracers = F.eggEspTracers == true
		local onlyNew = F.eggEspOnlyNew == true

		local slot = 0
		for _, egg in ipairs(ranked) do
			if slot >= most then
				break
			end
			local wanted = egg.distance <= range
				and egg.worth >= floor
				and (not onlyNew or egg.fresh)
			if wanted then
				local model = models:FindFirstChild(egg.record.Uid)
				local anchor = model
					and (model.PrimaryPart or model:FindFirstChild("Hitbox") or model:FindFirstChildWhichIsA("BasePart"))
				if anchor then
					slot = slot + 1
					local mark = espPool[slot]

					local text = eggName(egg.record)
					if egg.fresh and F.eggEspNewTag ~= false then
						-- The one thing on this screen worth interrupting a farm
						-- for, so it is said first and in its own colour.
						text = ("<font color=\"#FFD65C\">NEW</font> %s"):format(text)
					end
					if F.eggEspWorth ~= false then
						text = text .. " · " .. short(egg.worth)
					end
					if F.eggEspRarity then
						local _, rarity = rarityOf(egg.record.AssetCategory)
						if rarity then
							text = text .. " · " .. rarity
						end
					end
					if F.eggEspArea then
						text = text .. " · " .. tostring(egg.record.AreaId)
					end
					if egg.fresh and F.eggEspReward and egg.reward > 0 then
						text = text .. " · +" .. short(egg.reward) .. " Speed"
					end
					if #egg.mutations > 0 then
						text = text .. " · " .. table.concat(egg.mutations, ", ")
					end
					if F.eggEspDistance then
						text = text .. " · " .. math.floor(egg.distance)
					end

					local colour = espColour(egg, best)
					mark.label.Text = text
					mark.label.TextColor3 = colour
					mark.label.TextSize = size
					mark.highlight.FillColor = colour
					mark.highlight.OutlineColor = colour
					mark.highlight.FillTransparency = 1 - fill
					mark.billboard.Adornee = anchor
					mark.highlight.Adornee = model
					mark.billboard.Enabled = true
					mark.highlight.Enabled = true

					-- The tracer itself is drawn on Heartbeat above; all this has
					-- to do is say where and what colour.
					mark.target = tracers and anchor or nil
					mark.colour = colour
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

	-- Anti AFK, and it now does what the switch says.
	--
	-- Disabling the Idled connections is quieter than pretending to click:
	-- VirtualUser is a CoreScript API and a normal script reaching for it every
	-- twenty minutes all night is a loud thing to be doing. But the disable ran
	-- at load and ignored the flag entirely, so the toggle controlled nothing.
	--
	-- What it switches off matters more than it looks. The game's own AntiAFK
	-- hangs off the same signal: sixty seconds idle and it reports you AFK to
	-- the server, eighteen minutes and it calls
	-- `TeleportService:Teleport(game.PlaceId)` to bounce you out and back.
	-- Killing every Idled connection stops the bounce, which is the difference
	-- between one long night and twenty-six rejoins, but it also stops the AFK
	-- report the server would otherwise get from an unattended player.
	--
	-- Two kicks so far have landed with the hub loaded and every switch off, and
	-- this ran anyway, so it is one of the very few things that was true both
	-- times. Now it obeys the flag, which makes the overnight run an experiment
	-- that can be run twice instead of a single guess.
	core.SetAntiAfk = function(on)
		return pcall(function()
			for _, connection in ipairs(getconnections(LocalPlayer.Idled)) do
				if on then
					connection:Disable()
				else
					connection:Enable()
				end
			end
		end)
	end

	task.spawn(function()
		if F.antiAfk == false then
			return
		end
		local ok = core.SetAntiAfk(true)
		if not ok then
			-- No getconnections, so fall back to looking like a keypress.
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
	-- what the dashboard shows
	----------------------------------------------------------------------------

	-- The dashboard reads fixed keys off core.Stats, and core.Headline is the
	-- one line it shows above them. A game module never touches the interface
	-- itself, so this is the whole of what it publishes.
	-- Published so the journal and the per-area record can be read while it is
	-- running, rather than only after a kick has already written them to a file.
	-- The overnight run is eight hours long and the console buffer does not
	-- survive a rejoin, so this is the only way to ask what happened.
	core.Journal = journal
	core.Losses = losses

	core:Loop("stats", 1, function()
		local minutes = math.max((os.clock() - stats.started) / 60, 1 / 60)
		local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
		local perSecond = leaderstats and leaderstats:FindFirstChild("Money/s")

		local carried = core.Stats or {}
		carried.Hits = stats.taken
		carried.Rate = math.floor(stats.taken / minutes * 60)
		carried.Total = stats.placed
		carried.Lost = stats.lost or 0
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
			core.Headline = "Treadmill · " .. tostring(grindReason or "earning Speed")
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
	local indexPanel = progressTab:Section({ Side = "Left" })
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
		Name = "Only If You Can Get Away",
		Default = true,
		Callback = function(state)
			F.stealEscape = state
		end,
	}, "stealEscape")

	stealRight:Slider({
		Name = "Eggs A Minute",
		Default = 5,
		Minimum = 1,
		Maximum = 30,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.stealCeiling = value
		end,
	}, "stealCeiling")

	stealRight:Toggle({
		Name = "Walk Like A Keyboard",
		Default = false,
		Callback = function(state)
			F.stealHuman = state
		end,
	}, "stealHuman")

	stealRight:Toggle({
		Name = "New Species First",
		Default = true,
		Callback = function(state)
			F.stealFresh = state
		end,
	}, "stealFresh")

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

	baseLeft:Slider({
		Name = "Skip If Longer Than",
		Default = 5,
		Minimum = 0,
		Maximum = 120,
		Precision = 0,
		Suffix = " min",
		Callback = function(value)
			F.baseSkipOver = value
		end,
	}, "baseSkipOver")

	--------------------------------------------------------------- base · right

	baseRight:Header({ Text = "Money" })

	baseRight:Toggle({
		Name = "Claim Offline Money",
		Default = true,
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

	-- Auto Sell has never sold anything, and this is why: SetAutoSellState does
	-- not take a boolean, it takes a map of rarity name to true, and the hub was
	-- sending it `true`. The server took the call, found nothing it recognised,
	-- and set nothing. Ten rarities, Common through Divine, numbered 1 to 10.
	--
	-- It matters more than it looks. A night unattended fills the pen, a full
	-- pen stops eggs hatching, and eggs that cannot hatch stop the plot ever
	-- having room, which stops planting, which strands the farm at the pad
	-- holding an egg it cannot put down. Selling the bottom of the ladder is
	-- what keeps a night moving.
	selling.push = function()
		local map = {}
		if F.petsAutoSell then
			local limit = selling.RANK[F.petsSellUpTo or "Uncommon"] or 2
			for name, rank in pairs(selling.RANK) do
				if rank <= limit then
					map[name] = true
				end
			end
		end
		ask(NET.Backpack.SET_AUTO_SELL_STATE, map)
	end

	petsRight:Toggle({
		Name = "Auto Sell",
		Default = false,
		Callback = function(state)
			F.petsAutoSell = state
			-- Spawned, like every other call out of a control. Network.Invoke is a
			-- round trip, and a callback that yields blocks the interface thread that
			-- called it.
			task.spawn(selling.push)
		end,
	}, "petsAutoSell")

	petsRight:Dropdown({
		Name = "Sell Up To",
		Multi = false,
		Required = true,
		Options = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" },
		Default = 2,
		Callback = function(value)
			F.petsSellUpTo = value
			task.spawn(selling.push)
		end,
	}, "petsSellUpTo")

	petsRight:Button({
		Name = "Sell Everything",
		Callback = function()
			task.spawn(function()
				ask(NET.AssetInventory.SELL_ALL_ASSETS)
			end)
		end,
	})

	------------------------------------------------------------- pets · fusing

	petsRight:Header({ Text = "Fusing" })

	petsRight:Toggle({
		Name = "Auto Fuse Runts",
		Default = false,
		Callback = function(state)
			F.petsFuse = state
		end,
	}, "petsFuse")

	petsRight:Slider({
		Name = "Only Fuse Below",
		Default = 0.65,
		Minimum = 0.1,
		Maximum = 1.5,
		Precision = 2,
		Callback = function(value)
			F.petsFuseBelow = value
		end,
	}, "petsFuseBelow")

	-- On the table, not a local: Build has no registers left. See MERIDIAN-DESIGN.
	fuse.label = petsRight:Label({ Text = "Nothing worth fusing" })

	core:Loop("fuseLabel", 5, function()
		local batch = fuse.pick()
		if not batch then
			fuse.label:UpdateName("Nothing worth fusing")
			return
		end
		fuse.label:UpdateName(("3 %s · %.2f average"):format(tostring(batch.species), batch.mean))
	end)

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

	progLeft:Toggle({
		Name = "Treadmill When Eggs Are Poor",
		Default = true,
		Callback = function(state)
			F.speedIdle = state
		end,
	}, "speedIdle")

	progLeft:Slider({
		Name = "Worth The Walk",
		Default = 2,
		Minimum = 0,
		Maximum = 25,
		DisplayMethod = "Percent",
		Precision = 0,
		Callback = function(value)
			F.stealShare = value
		end,
	}, "stealShare")

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
		Default = true,
		Callback = function(state)
			F.progIndex = state
		end,
	}, "progIndex")

	progRight:Toggle({
		Name = "Auto Free Gifts",
		Default = true,
		Callback = function(state)
			F.progGifts = state
		end,
	}, "progGifts")

	progRight:Toggle({
		Name = "Claim Group Reward",
		Default = true,
		Callback = function(state)
			F.progGroup = state
		end,
	}, "progGroup")

	progRight:Toggle({
		Name = "Auto Lucky Blocks",
		Default = true,
		Callback = function(state)
			F.progLucky = state
		end,
	}, "progLucky")

	--------------------------------------------------------------- the index
	--
	-- The largest number in this game, and the one nobody looks at.
	--
	-- Every species pays an IndexSpeedReward the first time you ever hatch it,
	-- once, and completing an area's whole drop table hands you that area's bat.
	-- He has 42 of the 84 and the 42 he is missing are worth 40,586,150 Speed
	-- Power against the 11.5M he has - four times everything he owns, and the
	-- only route past Prehistoric at 17M.
	--
	-- Which is why this is a panel and not a line: knowing you are one species
	-- from the Desert Bat is worth more than any toggle on this tab.
	indexPanel:Header({ Text = "Index" })

	local indexTotal = indexPanel:Label({ Text = "Index · counting" })

	local AREA_ORDER = {}
	for id, area in pairs(AreaDirectory) do
		if type(area) == "table" and type(area.DropTable) == "table" then
			AREA_ORDER[#AREA_ORDER + 1] = {
				id = id,
				tier = tonumber(area.Rarity and area.Rarity.RarityNumber) or 0,
			}
		end
	end
	table.sort(AREA_ORDER, function(a, b)
		return a.tier < b.tier
	end)

	local indexRows = {}
	for _, area in ipairs(AREA_ORDER) do
		indexRows[area.id] = indexPanel:Label({ Text = area.id .. " · counting" })
	end

	indexPanel:Button({
		Name = "Claim Everything",
		Callback = function()
			task.spawn(function()
				ask(NET.Index.REQUEST_CLAIM_ALL)
				task.wait(0.6)
				ask(NET.Index.REQUEST_CLAIM_LIMITED_EGG_REWARD)
				core:Notify("Meridian", "Asked for every index reward", 4)
			end)
		end,
	})

	indexPanel:Toggle({
		Name = "Equip Best Bat",
		Default = true,
		Callback = function(state)
			F.indexBat = state
		end,
	}, "indexBat")

	core:Loop("index", 6, function()
		local progress = indexProgress()
		local got, total, owed = 0, 0, 0
		local closest, closestLeft = nil, math.huge

		for _, area in ipairs(AREA_ORDER) do
			local row = progress[area.id]
			local label = indexRows[area.id]
			if row and label then
				got = got + row.got
				total = total + row.total
				owed = owed + row.owed
				local left = row.total - row.got
				if left > 0 and left < closestLeft then
					closest, closestLeft = area.id, left
				end
				local text
				if left == 0 then
					text = ("%s · done · %s"):format(area.id, tostring(row.bat))
				elseif left <= 3 then
					text = ("%s · %d of %d · needs %s"):format(
						area.id, row.got, row.total, table.concat(row.missing, ", "))
				else
					text = ("%s · %d of %d · %s Speed left here"):format(
						area.id, row.got, row.total, short(row.owed))
				end
				label:UpdateName(text)
			end
		end

		local headline
		if closest then
			headline = ("Index · %d of %d · %s Speed on the table · closest is %s, %d to go"):format(
				got, total, short(owed), closest, closestLeft)
		else
			headline = ("Index · %d of %d · every area done"):format(got, total)
		end
		indexTotal:UpdateName(headline)

		-- The bat from the best area you have finished. Nothing to do until one
		-- of them is finished, which is the whole point of the panel above.
		if F.indexBat ~= false and due("bat", 45) then
			local best = nil
			for _, area in ipairs(AREA_ORDER) do
				local row = progress[area.id]
				if row and row.got >= row.total then
					best = area.id
				end
			end
			if best then
				if ask(NET.Index.REQUEST_EQUIP_AREA_BAT, best) then
					accepted("bat")
				else
					refused("bat", 45)
				end
			end
		end
	end)

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

	visualsLeft:Divider()

	visualsLeft:Dropdown({
		Name = "Colour By",
		Multi = false,
		Required = true,
		Options = { "Worth", "Rarity", "Index" },
		Default = 1,
		Callback = function(value)
			F.eggEspColour = value
		end,
	}, "eggEspColour")

	visualsLeft:Toggle({
		Name = "Mark New Species",
		Default = true,
		Callback = function(state)
			F.eggEspNewTag = state
		end,
	}, "eggEspNewTag")

	visualsLeft:Toggle({
		Name = "Show Index Reward",
		Default = true,
		Callback = function(state)
			F.eggEspReward = state
		end,
	}, "eggEspReward")

	visualsLeft:Toggle({
		Name = "Only New Species",
		Default = false,
		Callback = function(state)
			F.eggEspOnlyNew = state
		end,
	}, "eggEspOnlyNew")

	visualsLeft:Toggle({
		Name = "Show Rarity",
		Default = false,
		Callback = function(state)
			F.eggEspRarity = state
		end,
	}, "eggEspRarity")

	visualsLeft:Toggle({
		Name = "Show Area",
		Default = false,
		Callback = function(state)
			F.eggEspArea = state
		end,
	}, "eggEspArea")

	visualsLeft:Toggle({
		Name = "Tracers",
		Default = false,
		Callback = function(state)
			F.eggEspTracers = state
		end,
	}, "eggEspTracers")

	visualsLeft:Slider({
		Name = "How Many At Once",
		Default = 60,
		Minimum = 1,
		Maximum = 60,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.eggEspMax = value
		end,
	}, "eggEspMax")

	visualsLeft:Slider({
		Name = "Text Size",
		Default = 15,
		Minimum = 10,
		Maximum = 30,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.eggEspSize = value
		end,
	}, "eggEspSize")

	visualsLeft:Slider({
		Name = "Fill",
		Default = 15,
		Minimum = 0,
		Maximum = 100,
		DisplayMethod = "Percent",
		Precision = 0,
		Callback = function(value)
			F.eggEspFill = value
		end,
	}, "eggEspFill")

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
			task.spawn(function()
				if type(core.SetAntiAfk) == "function" then
					core.SetAntiAfk(state)
				end
			end)
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
