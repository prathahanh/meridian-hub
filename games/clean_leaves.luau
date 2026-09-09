--// Meridian · Clean All The Leaves
--// universe 10539411000
--//
--// Two places share this module and only one of them is the game. The lobby
--// (92637789841354) is where you pick a map, pick a difficulty and spend
--// diamonds on the upgrades you keep. Every map is a place of its own, and
--// that is where leaves, bags, dumpsters, vents and cash live. Nothing else in
--// the hub has had to do this: a switch here has to ask which of the two rooms
--// it is standing in before it does anything, and the ones that cannot work
--// where you are say so instead of failing quietly.
--//
--// The whole loop is the one Steal An Egg runs. Collect until the bag is full,
--// walk it to the dumpster, sell, spend the cash on carrying more, open the
--// next vent, and when the map is clear start the next run. Only the nouns
--// changed.
--//
--// One measured number holds the farm up, and it is the reason this file
--// exists rather than a guess: the server accepts a collect out to 32 studs
--// and SILENTLY IGNORES anything past it. Nothing comes back. CollectDenied
--// never fires. The leaf simply stays where it is. Collecting at 28.8 and 30.9
--// studs banked; 32.7, 34.2, 37.0, 38.8 and 40.5 did nothing whatsoever. A
--// farm reaching further would look perfectly healthy in its own log and bank
--// nothing all night, which is the exact shape of bug LAUNCH.md says costs a
--// night of farming.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Module = {
	GameId = 10539411000,
	Name = "Clean All The Leaves",
}

-- Hover text. One line each, written for somebody who has never seen the code.
-- No mechanisms, and no number appears unless it is one you would actually set.
Module.Tips = {
	["Auto Clean"] = "Walks to the nearest leaves, picks them up, and keeps going until the bag is full.",
	["Sell When Full"] = "Carries a full bag to the dumpster and empties it, then goes back to the leaves.",
	["Sell At"] = "How full the bag has to be before it is worth the walk. Below a hundred it leaves early, which pays when the dumpster is far.",
	["Stay Within"] = "How far it will wander from where it started. Turn it up to clear a whole zone, down to work one pile.",
	["Auto Bag"] = "Buys the next bag size the moment you can afford it. This is the upgrade that decides how much of a run is walking.",
	["Auto Rake"] = "Buys the rake once there is cash for it. The rake drags leaves into vents and pays on the spot, with no bag to fill.",
	["Auto Vents"] = "Opens the next vent as soon as it is affordable. A vent is how a zone gets cleared.",
	["Auto Start Run"] = "From the lobby, walks to a square and starts a run on its own.",
	["Map"] = "Which map to run. The later ones need the one before it cleared on Easy first.",
	["Difficulty"] = "Harder maps pay more diamonds and give you less time.",
	["Solo"] = "Starts the run with just you in it instead of waiting for a squad.",
	["Auto Diamond Upgrades"] = "Spends diamonds in the lobby on the upgrades you keep between runs.",
	["Buy Order"] = "Which lobby upgrade gets your diamonds first.",
	["Auto Class Spin"] = "Spins for a new class whenever you have the diamonds spare. Handy Man is the one worth chasing.",
}

--------------------------------------------------------------------------------
-- file scope
--------------------------------------------------------------------------------
--
-- Build is one function against Luau's ceiling of 200 local registers and this
-- game reaches it, so every feature past the first few lives out here on a
-- table and is handed what it needs once through a wire. That costs nothing
-- inside Build. ./check.sh catches the ceiling; luau-analyze does not.

-- A rolling record of the last things this said to the server, so a run that
-- goes wrong arrives with its own evidence rather than a snapshot of the moment
-- it stopped.
local journal = { keep = 40, entries = {} }

function journal.note(what)
	local list = journal.entries
	list[#list + 1] = { at = os.clock(), what = what }
	while #list > journal.keep do
		table.remove(list, 1)
	end
end

function journal.text()
	local now, lines = os.clock(), {}
	for _, entry in ipairs(journal.entries) do
		lines[#lines + 1] = ("%5.1fs ago  %s"):format(now - entry.at, entry.what)
	end
	return table.concat(lines, "\n")
end

-- Maclib does not fire ANY control's callback for its own declared default, and
-- that includes Toggles. This was watched happening rather than reasoned about:
-- Auto Bag, Auto Rake, Auto Vents and Sell When Full all ship Default = true,
-- all three drew as on, and all four flags read nil for a hundred and eight
-- seconds of live farming while cash climbed past the price of a bag upgrade
-- and nothing bought it. A switch drawn as on that behaves as off is the worst
-- kind of bug in a hub, because the person judging it is reading the interface.
--
-- The reference module seeds only Sliders and Dropdowns, which is why this had
-- to be found again here. Rather than keep two values in step by hand, the
-- declared default is copied into the flag once the tabs exist, and the
-- control's own callback is then run so that what happens is the behaviour
-- being restored rather than a value being copied.
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
			-- declaring Default = false ends up unseeded. It reads the same as
			-- off today only because every test in this file asks `== true`.
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
-- the map half
--------------------------------------------------------------------------------

-- Measured, not chosen. See the header: past this the server ignores a collect
-- without a word. The farm asks for a little less than the true ceiling,
-- because the leaf and the character both move between the frame that picked
-- the target and the frame that sends it.
local REACH = 30

local farm = {
	bits = nil,
	near = {},
	scanAt = 0,
	nextGrab = 0,
	sim = nil,
	simAt = 0,
	anchor = nil,
}

function farm.wire(bits)
	farm.bits = bits
end

-- The game's own client wrapper, which is why this module never has to guess at
-- a payload. LeafSim stamps each leaf with the epoch the server handed out and
-- fires CollectLeaf itself, so collecting is its collectMany and never a remote
-- call written here.
--
-- It only exists in a map place, so a nil answer is also how the rest of this
-- file knows it is standing in the lobby.
function farm.module()
	if farm.sim then
		return farm.sim
	end
	if os.clock() - farm.simAt < 2 then
		return nil
	end
	farm.simAt = os.clock()
	local player = Players.LocalPlayer
	local scripts = player and player:FindFirstChild("PlayerScripts")
	local mod = scripts and scripts:FindFirstChild("LeafSim")
	if not mod or not mod:IsA("ModuleScript") then
		return nil
	end
	local ok, value = pcall(require, mod)
	if ok and type(value) == "table" and type(value.collectMany) == "function" then
		farm.sim = value
		return value
	end
	return nil
end

function farm.inMap()
	return farm.module() ~= nil
end

-- What the bag is doing, straight off the attributes the game keeps on the
-- player. Nothing here is asked of the server.
function farm.bag()
	local player = Players.LocalPlayer
	local held = tonumber(player:GetAttribute("Leaves")) or 0
	local cap = tonumber(player:GetAttribute("LeafCapacity")) or 25
	local endless = player:GetAttribute("InfiniteBag") == true
		or player:GetAttribute("OwnsInfiniteBag") == true
	return held, cap, endless
end

-- How many leaves one grab may take, and how long until the next is allowed.
-- Both are upgrades, so both are read from the game rather than fixed: Hold is
-- how many extra come with the one you reached for, Dexterity is the cooldown
-- in seconds.
function farm.grabSize(sim)
	local ok, extra = pcall(sim.upgEffect, "Hand", "Hold")
	return 1 + (ok and tonumber(extra) or 0)
end

function farm.cooldown(sim)
	local ok, seconds = pcall(sim.upgEffect, "Hand", "Dexterity")
	return ok and tonumber(seconds) or 0.5
end

-- The leaves worth walking to, refreshed on a timer rather than every tick.
--
-- A map holds upwards of thirteen thousand leaf parts and the farm ticks ten
-- times a second, so scanning the folder every tick is a hundred and thirty
-- thousand distance tests a second for an answer that barely moves. Once a
-- second is plenty: leaves do not run away.
function farm.scan(sim, root)
	if os.clock() - farm.scanAt < 1 then
		return farm.near
	end
	farm.scanAt = os.clock()

	local wander = tonumber(farm.bits.F.leafWander) or 250
	local anchor = farm.anchor or root.Position
	local found = {}
	for _, part in ipairs(sim.folder:GetChildren()) do
		if part:IsA("BasePart") and (part.Position - anchor).Magnitude <= wander then
			found[#found + 1] = { part = part, d = (part.Position - root.Position).Magnitude }
		end
	end
	table.sort(found, function(a, b)
		return a.d < b.d
	end)
	-- Only the front of the list is ever used, and holding thirteen thousand
	-- entries alive between ticks shows up as frame time rather than as a bug.
	while #found > 80 do
		table.remove(found)
	end
	farm.near = found
	return found
end

function farm.dumpster(from)
	local map = Workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Dumpsters")
	if not folder then
		return nil
	end
	local best, bestAway = nil, math.huge
	for _, model in ipairs(folder:GetChildren()) do
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

-- One step of the trip home. Returns true while it still wants the legs.
function farm.sell()
	local bits = farm.bits
	local root = bits.core:Root()
	if not root then
		return false
	end
	local where = farm.dumpster(root.Position)
	if not where then
		bits.sayOnce("dump", "No dumpster here", "Nothing on this map takes a full bag, so selling is off.")
		return false
	end
	if not bits.core:WalkToward(where, 10, 60) then
		return true
	end
	if not bits.due("empty", 1.5) then
		return true
	end
	local ok, why = bits.ask("EmptyBackpack")
	if ok then
		bits.accepted("empty")
	else
		bits.refused("empty", 1.5)
		bits.sayOnce("empty", "Could not empty the bag", tostring(why))
	end
	return true
end

-- One step per call, never two, and every step behind a gate.
function farm.tick()
	local bits = farm.bits
	if not bits or bits.F.autoClean ~= true then
		return false
	end
	local sim = farm.module()
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
	if not farm.anchor then
		farm.anchor = root.Position
	end

	-- Full bag first. Nothing else matters until it is empty again, and the game
	-- says how full it is rather than it being counted here.
	local held, cap, endless = farm.bag()
	local at = (tonumber(bits.F.leafSellAt) or 100) / 100
	if not endless and bits.F.leafSell ~= false and held >= math.max(1, math.floor(cap * at)) then
		return farm.sell()
	end

	local list = farm.scan(sim, root)
	local target = list[1]
	if not target or not target.part.Parent then
		farm.near = {}
		return false
	end

	-- Walk in until the collect is inside the measured ceiling. The standoff is
	-- well short of it, so arriving is never a photo finish.
	if (target.part.Position - root.Position).Magnitude > REACH * 0.6 then
		core:WalkToward(target.part.Position, REACH * 0.4, 70)
		return true
	end

	if os.clock() < farm.nextGrab then
		return true
	end

	-- Everything already in range, nearest first, up to what the bag will take
	-- and what one grab is allowed to hold.
	local room = endless and 40 or math.max(0, cap - held)
	if room <= 0 then
		return true
	end
	local batch, want = {}, math.min(farm.grabSize(sim), room)
	for _, entry in ipairs(list) do
		if #batch >= want then
			break
		end
		if entry.part.Parent == sim.folder
			and (entry.part.Position - root.Position).Magnitude <= REACH
		then
			batch[#batch + 1] = entry.part
		end
	end
	if #batch == 0 then
		return true
	end

	local ok = pcall(sim.collectMany, batch)
	journal.note(("collect %d %s"):format(#batch, ok and "ok" or "threw"))
	farm.nextGrab = os.clock() + math.max(farm.cooldown(sim), 0.1)
	-- The list is stale the moment a grab lands, and reusing it is how a farm
	-- ends up reaching for leaves that are already in its own bag.
	farm.scanAt = 0
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

-- The bag, which is the upgrade a run is shaped by: every level is fewer walks
-- to the dumpster and more of the run spent actually clearing.
function shop.bagTick()
	local bits = shop.bits
	if bits.F.leafAutoBag ~= true or not farm.inMap() then
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
	bits.core:Notify("Meridian", "Bought a bigger bag", 4)
end

-- The rake, which is the other half of how this game is actually played: it
-- drags leaves into a vent and pays on the spot, with no bag to fill and no
-- walk to make.
function shop.rakeTick()
	local bits = shop.bits
	if bits.F.leafAutoRake ~= true or not farm.inMap() then
		return
	end
	if Players.LocalPlayer:GetAttribute("OwnsRake") == true then
		return
	end
	local ok, cfg = pcall(require, ReplicatedStorage:FindFirstChild("UpgradeConfig"))
	local entry = ok and type(cfg) == "table" and cfg.shop and cfg.shop.Rake
	local price = entry and tonumber(entry.cash)
	if not price or shop.cash() < price then
		return
	end
	if not shop.worthAsking("rake") or not bits.due("rake", 6) then
		return
	end
	shop.spend("rake", "BuyToolCash", "Rake")
	bits.core:Notify("Meridian", "Bought the rake", 5)
end

-- Vents are how a zone gets cleared, so an unopened one is the thing standing
-- between this run and the next map.
function shop.ventTick()
	local bits = shop.bits
	if bits.F.leafAutoVent ~= true or not farm.inMap() then
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
-- square drops itself out of its own queue.

local lobby = { bits = nil }

function lobby.wire(bits)
	lobby.bits = bits
end

function lobby.inLobby()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	return not farm.inMap()
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
	local root = core:Root()
	if not root or not core:Alive2() then
		return
	end

	if Players.LocalPlayer:GetAttribute("InTeam") ~= true then
		local where = lobby.square(root.Position)
		if where then
			core:WalkToward(where, 3, 40)
		end
		return
	end

	-- On a square. Settle the choices before asking for the run: they are
	-- separate events and the last one the server reads is the one that counts.
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
	core:Notify("Meridian", ("Starting %s on %s"):format(wantMap, tostring(bits.F.leafDifficulty or "Easy")), 5)
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
				bits.core:Notify("Meridian", "Upgraded " .. key, 4)
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
	-- purchase and every collect there is an event that says nothing.
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

	farm.wire({
		F = F,
		core = core,
		ask = ask,
		due = due,
		refused = refused,
		accepted = accepted,
		sayOnce = sayOnce,
		player = LocalPlayer,
	})
	shop.wire(farm.bits)
	lobby.wire(farm.bits)

	----------------------------------------------------------------------------
	-- the interface
	----------------------------------------------------------------------------

	local runTab = tabGroup:Tab({ Name = "Run", Image = "rbxassetid://10723407389" })
	local cashTab = tabGroup:Tab({ Name = "Upgrades", Image = "rbxassetid://10734886735" })
	local lobbyTab = tabGroup:Tab({ Name = "Lobby", Image = "rbxassetid://10734950309" })

	local runLeft = runTab:Section({ Side = "Left" })
	local runRight = runTab:Section({ Side = "Right" })
	local cashLeft = cashTab:Section({ Side = "Left" })
	local lobbyLeft = lobbyTab:Section({ Side = "Left" })
	local lobbyRight = lobbyTab:Section({ Side = "Right" })

	------------------------------------------------------------------ run · left

	runLeft:Header({ Text = "Clearing" })

	runLeft:Toggle({
		Name = "Auto Clean",
		Default = false,
		Callback = function(state)
			F.autoClean = state
			if not state then
				farm.anchor = nil
				core:SetControls(true)
			end
		end,
	}, "autoClean")

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

	runRight:Header({ Text = "Where" })

	runRight:Slider({
		Name = "Stay Within",
		Default = 250,
		Minimum = 60,
		Maximum = 600,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.leafWander = value
			farm.scanAt = 0
		end,
	}, "leafWander")

	--------------------------------------------------------------- upgrades tab

	cashLeft:Header({ Text = "Spending the run's cash" })

	cashLeft:Toggle({
		Name = "Auto Bag",
		Default = true,
		Callback = function(state)
			F.leafAutoBag = state
		end,
	}, "leafAutoBag")

	cashLeft:Toggle({
		Name = "Auto Rake",
		Default = true,
		Callback = function(state)
			F.leafAutoRake = state
		end,
	}, "leafAutoRake")

	cashLeft:Toggle({
		Name = "Auto Vents",
		Default = true,
		Callback = function(state)
			F.leafAutoVent = state
		end,
	}, "leafAutoVent")

	------------------------------------------------------------------ lobby tab

	lobbyLeft:Header({ Text = "Starting a run" })

	lobbyLeft:Toggle({
		Name = "Auto Start Run",
		Default = false,
		Callback = function(state)
			F.leafAutoStart = state
		end,
	}, "leafAutoStart")

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

	----------------------------------------------------------------------------
	-- the loops
	----------------------------------------------------------------------------

	core:Loop("clean", 0.1, function()
		farm.tick()
	end)

	core:Loop("spend", 3, function()
		shop.bagTick()
		shop.rakeTick()
		shop.ventTick()
	end)

	core:Loop("lobby", 2, function()
		lobby.tick()
		lobby.upgradeTick()
		lobby.spinTick()
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
			Upgrades = cashTab,
			Lobby = lobbyTab,
		},
		Default = runTab,
		Tips = Module.Tips,
	}
end

return Module
