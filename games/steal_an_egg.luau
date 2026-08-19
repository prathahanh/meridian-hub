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
	local EggToolDisplay = require(Client:WaitForChild("Eggs"):WaitForChild("EggToolDisplay"))

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
	local function carriedUid()
		local character = core:Character()
		for _, holder in ipairs({ character, LocalPlayer:FindFirstChildOfClass("Backpack") }) do
			if holder then
				for _, item in ipairs(holder:GetChildren()) do
					if item:IsA("Tool") then
						local ok, uid = pcall(EggToolDisplay.GetToolUid, item)
						if ok and uid then
							return uid, item
						end
					end
				end
			end
		end
		return nil
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

	local function tryPlace(uid)
		local data = plotData()
		if not data or not data.CenterPoint then
			return false, "No base yet"
		end
		local localCFrame = placementCFrame(data)
		if not localCFrame then
			return false, "No base yet"
		end
		local ok, accepted, reason = pcall(EggCmds.RequestPlaceEgg, uid, localCFrame)
		if not ok then
			return false, tostring(accepted)
		end
		if accepted then
			placeAttempt = 0
			stats.placed = stats.placed + 1
			return true
		end
		return false, reason
	end

	-- Carrying an egg home. Everything about this is deliberately ordinary
	-- walking: this game resets you to your base for a 60 stud jump, and the
	-- one thing worse than a slow farm is a farm that keeps getting sent home
	-- empty handed.
	local function goHome()
		local data = plotData()
		local target = data and data.RespawnPointCFrame
		if not target then
			return false
		end
		return core:WalkToward(target.Position, 10, tonumber(F.stealSpeed) or 200)
	end

	core:Loop("steal", 0.1, function()
		if not F.autoSteal then
			if currentTarget then
				dropTarget()
			end
			return
		end
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
			local placed, reason = tryPlace(held)
			if not placed and reason then
				-- The pad filling up is the one refusal worth saying out loud,
				-- because it is the one the user has to do something about.
				sayOnce("place", "Could not place", tostring(reason))
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
		end

		local position = eggPosition(currentTarget.record) or currentTarget.position
		local arrived = core:WalkToward(position, STEAL_REACH, tonumber(F.stealSpeed) or 200)
		if not arrived then
			return
		end

		if os.clock() < nextAttempt then
			return
		end
		nextAttempt = os.clock() + (tonumber(F.stealDelay) or 0.2)

		-- The wrapper raises rather than returning false when the server says
		-- no, and the message it raises is the server's own wording, so this is
		-- the one place in the hub where an error is the useful reply.
		local ok, err = pcall(EggCmds.RequestCarryAreaEgg, currentTarget.record.Uid)
		if ok then
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

		local message = tostring(err)
		if message:find("Enter the gameplay area") then
			-- Standing at the edge of an area is a different refusal from
			-- standing too far from the egg, and walking closer fixes it, so it
			-- is worth one more step rather than a new target.
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

	core:Loop("base", 2, function()
		if F.baseHatch then
			for _, record in ipairs(ownEggs()) do
				local ready = EggCmds.IsLocalEggReady and select(2, pcall(EggCmds.IsLocalEggReady, record.Uid))
				if ready == true then
					pcall(EggCmds.RequestHatchEgg, record.Uid)
					task.wait(0.35)
					pcall(EggCmds.RequestCompleteHatchEgg, record.Uid)
				end
			end
		end

		if F.baseSkip then
			for _, record in ipairs(ownEggs()) do
				local ready = EggCmds.IsLocalEggReady and select(2, pcall(EggCmds.IsLocalEggReady, record.Uid))
				if ready ~= true then
					pcall(EggCmds.RequestSkipGrowth, record.Uid)
				end
			end
		end

		if F.baseUpgrade then
			pcall(Network.Invoke, NET.Plots.REQUEST_BASE_UPGRADE)
		end
	end)

	core:Loop("offline", 10, function()
		if F.baseOffline then
			pcall(Network.Invoke, NET.OfflineAssets.REQUEST_REDEEM)
		end
	end)

	----------------------------------------------------------------------------
	-- pets
	----------------------------------------------------------------------------

	local function equipBest()
		return pcall(Network.Invoke, NET.Backpack.EQUIP_BEST)
	end

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
	core:Loop("speed", 5, function()
		if F.speedUpgrade then
			pcall(Network.Invoke, NET.Treadmills.REQUEST_UPGRADE)
		end
	end)

	----------------------------------------------------------------------------
	-- progress
	----------------------------------------------------------------------------

	core:Loop("progress", 8, function()
		if F.progIndex then
			pcall(Network.Invoke, NET.Index.REQUEST_CLAIM_ALL)
		end
		if F.progGifts then
			pcall(Network.Invoke, NET.FreeGifts.REQUEST_CLAIM)
		end
		if F.progLucky then
			pcall(Network.Invoke, NET.LuckyBlock.REQUEST_STORED_BLOCK_OPEN_CLAIM)
		end
		if F.progRebirth then
			pcall(Network.Invoke, NET.Rebirth.REQUEST_REBIRTH)
			pcall(Network.Invoke, NET.Rebirth.REQUEST_REBIRTH_COMMIT)
		end
	end)

	----------------------------------------------------------------------------
	-- the interface
	----------------------------------------------------------------------------

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
	stealLeft:Paragraph({
		Header = "About walking",
		Body = "This game will not let anyone move faster than anyone else, so the farm walks. Your Speed stat is the only thing that changes that, and the Progress tab grows it.",
	})

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
			equipBest()
		end,
	})

	--------------------------------------------------------------- pets · right

	petsRight:Header({ Text = "Selling" })

	petsRight:Toggle({
		Name = "Auto Sell",
		Default = false,
		Callback = function(state)
			F.petsAutoSell = state
			pcall(Network.Invoke, NET.Backpack.SET_AUTO_SELL_STATE, state)
		end,
	}, "petsAutoSell")

	petsRight:Button({
		Name = "Sell Everything",
		Callback = function()
			pcall(Network.Invoke, NET.AssetInventory.SELL_ALL_ASSETS)
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
			pcall(Network.Invoke, NET.Rebirth.REQUEST_REBIRTH)
			pcall(Network.Invoke, NET.Rebirth.REQUEST_REBIRTH_COMMIT)
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
	-- nest is not, and the snapshot already knows where every egg is to the
	-- stud. So this draws from the same ranked list the farm reads: whatever
	-- the label says is the best egg is the one the farm is about to walk to,
	-- because there is only one list.
	--
	-- Colour is the rank, not the rarity. Rarity is what the game already shows
	-- you on the nest; what it does not show you is that this Pterodactyl is
	-- worth twenty times the one behind you because of its size.
	local espHolder = nil
	local espMarks = {}

	local function espColour(worth, best)
		if best <= 0 then
			return Color3.fromRGB(235, 235, 235)
		end
		local part = math.clamp(worth / best, 0, 1) ^ 0.4
		return Color3.fromRGB(150, 150, 150):Lerp(Color3.fromRGB(120, 255, 190), part)
	end

	local function clearEggEsp()
		for uid, mark in pairs(espMarks) do
			pcall(function()
				mark.anchor:Destroy()
			end)
			espMarks[uid] = nil
		end
	end

	core:Loop("eggEsp", 0.3, function()
		if not F.eggEsp then
			if next(espMarks) then
				clearEggEsp()
			end
			return
		end

		if not espHolder or not espHolder.Parent then
			espHolder = Instance.new("Folder")
			espHolder.Name = "\0MeridianEggs"
			espHolder.Parent = Workspace
			core:Track(espHolder)
		end

		local ranked = rankedEggs()
		local range = tonumber(F.eggEspRange) or 2500
		local floor = F.eggEspFilter ~= false and (tonumber(F.stealFloor) or 0) or 0
		local best = ranked[1] and ranked[1].worth or 0

		local wanted = {}
		for index, egg in ipairs(ranked) do
			if egg.distance <= range and egg.worth >= floor and index <= 60 then
				local uid = egg.record.Uid
				wanted[uid] = true
				local mark = espMarks[uid]
				if not mark then
					local anchor = Instance.new("Part")
					anchor.Size = Vector3.new(0.05, 0.05, 0.05)
					anchor.Transparency = 1
					anchor.Anchored = true
					anchor.CanCollide = false
					anchor.CanQuery = false
					anchor.CanTouch = false
					anchor.Parent = espHolder

					local billboard = Instance.new("BillboardGui")
					billboard.Size = UDim2.fromOffset(230, 34)
					billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
					billboard.AlwaysOnTop = true
					billboard.Adornee = anchor
					billboard.Parent = anchor

					local label = Instance.new("TextLabel")
					label.BackgroundTransparency = 1
					label.Size = UDim2.fromScale(1, 1)
					label.Font = Enum.Font.GothamMedium
					label.TextSize = 15
					label.TextStrokeTransparency = 0.4
					label.Parent = billboard

					mark = { anchor = anchor, label = label }
					espMarks[uid] = mark
				end

				mark.anchor.Position = egg.position

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
				mark.label.Text = text
				mark.label.TextColor3 = espColour(egg.worth, best)
			end
		end

		for uid, mark in pairs(espMarks) do
			if not wanted[uid] then
				pcall(function()
					mark.anchor:Destroy()
				end)
				espMarks[uid] = nil
			end
		end
	end)

	----------------------------------------------------------------------------
	-- anti afk
	----------------------------------------------------------------------------

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

	refreshSnapshot()

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
