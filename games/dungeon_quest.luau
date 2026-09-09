--// Meridian · Dungeon Quest Reborn
--// universe 9931749389 (the lobby and every dungeon place share it, so one
--// entry in GAMES covers the whole experience and the hub survives the two
--// teleports every run makes)
--//
--// This game is not a farm you leave running in one place. A run is a journey
--// through three places: you build a lobby in the town, the server teleports
--// you into a dungeon place, you walk a corridor killing what is in it, and
--// then you teleport back. Every switch here has to know which of those three
--// it is in, and none of it may assume the character it had a second ago is
--// the one it has now.
--//
--// Everything below drives the game's own client code. The payloads were read
--// out of PlayerGui.UIS, Ui.queue.chooseDungeon and the replay button rather
--// than guessed from remote names, because three of them take arguments the
--// name does not suggest.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Module = {
	GameId = 9931749389,
	Name = "Dungeon Quest Reborn",
}

-- Hover text. One line each, for somebody who has never seen the code. No
-- mechanisms, and no number that is not one you would actually set.
Module.Tips = {
	["Auto Farm"] = "Builds a lobby, starts the dungeon, fights its way down and comes back for another. Leave it on and it keeps going.",
	["Which Dungeon"] = "Best I Can Do picks the hardest one your level actually opens, which is where the money is. Pick one by name to stay there.",
	["Difficulty"] = "Harder pays more and needs a higher level. If the one you pick is above you the game refuses the lobby and it drops to one you can enter.",
	["Hardcore"] = "One life for the whole run. Worth far more, and a mistake ends it.",
	["Private Lobby"] = "Nobody can join you uninvited. On by default so a run is yours.",
	["Replay When It Ends"] = "Goes straight into the same dungeon again instead of walking back to town. Only the person who made the lobby can.",
	["Start A Run"] = "Makes the lobby and starts it, right now.",
	["Go Back To Town"] = "Leaves the dungeon and returns to the lobby.",
	["Auto Attack"] = "Hits whatever is nearest without you clicking.",
	["Use Abilities"] = "Fires your Q and E as they come off cooldown. They hit harder than the weapon and cost nothing.",
	["Ability Slots"] = "Which of your ability keys it is allowed to press. Leave them all off and it uses whatever you have.",
	["Swing Delay"] = "A pause between swings. Zero swings as fast as the game allows.",
	["Reach"] = "How close it gets before swinging. The weapon is short, so this is nearly always small.",
	["Target"] = "Who to go for first. Weakest finishes off what is nearly dead, which thins a room faster.",
	["Back Off At"] = "The health that counts as trouble. Below it, it stops walking in and backs away instead. This is the difference between a run that ends and one that does not.",
	["Give Up After"] = "How long to spend backing off before writing the run off and going for a fresh one. Health does not come back inside a dungeon, so a run you are too hurt to finish only costs you the clock. Zero never gives up.",
	["Fight At Range"] = "Never closes to weapon distance. Slower, and a room full of them cannot reach you.",
	["Keep Distance"] = "How far away to stand while fighting at range.",
	["Equip Best Weapon"] = "Puts on the hardest hitting weapon you own that your level allows.",
	["Prefer"] = "Which number counts as hardest hitting. Your starting dagger and wand are the same size on paper and go with opposite skill points, so this is the one that decides between them.",
	["Keep Best Weapon On"] = "Checks again whenever your gear changes, so a weapon that drops mid run goes on by itself.",
	["Spend Points On"] = "Where new skill points go. Stamina is health, and health is what stops a run ending early.",
	["Spend Them Now"] = "Puts every point you have saved into the stat above.",
	["Enemy ESP"] = "Draws everything alive in the dungeon through the walls.",
	["Show Health"] = "Adds how much each one has left.",
	["Show Distance"] = "Adds how far away each one is.",
	["Fill"] = "How solid the glow on each one looks. Zero leaves just the outline.",
	["Max Distance"] = "Stops drawing anything past this far away.",
	["Anti AFK"] = "Stops Roblox idling you out of a long night.",
}

--------------------------------------------------------------------------------
-- file scope
--------------------------------------------------------------------------------
--
-- Build is ONE function against Luau's ceiling of 200 local registers. Every
-- feature past the first few lives out here on a table and is handed what it
-- needs once through a wire. ./check.sh catches the ceiling; luau-analyze does
-- not.

-- A rolling record of what the hub last said to the server, so that when
-- something stops working there is a minute of history to read rather than a
-- snapshot of the moment it broke.
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

-- Maclib does not run a control's Callback for its own declared Default, so
-- every default would sit in the interface without ever reaching the flags and
-- what actually ran would be whatever fallback the reading code happened to
-- use. Copying the declared default in once the controls exist keeps the
-- control the only place a default lives.
--
-- Toggles are in here and that is not tidiness. The comment at the top of
-- steal_an_egg.luau says Maclib fires a Toggle's callback on creation and only
-- misses Sliders and Dropdowns. On this build it misses all three: read back
-- off a live window, every slider and dropdown flag was set by this function
-- and not one toggle flag existed at all.
--
-- Which matters because of how the reading code is written. A switch read as
-- `flag ~= false` survives a missing flag by accident; one read as
-- `flag == true` does not. Auto Attack is drawn on by default and read as
-- `~= true`, so before this it was a switch that showed on and did nothing -
-- the worst kind of bug in a hub, because the person judging it is reading the
-- interface.
local seeded = {}

function seeded.apply(core)
	local flags = core.Flags
	for _, entry in ipairs(core.Controls or {}) do
		local flag = entry.flag or entry.Flag
		local kind = entry.kind or entry.Kind
		if flag and flags[flag] == nil and (kind == "Slider" or kind == "Dropdown" or kind == "Toggle") then
			local settings = entry.control and entry.control.Settings

			-- Written out rather than as `type(settings) == "table" and
			-- settings.Default or nil`, which is the same false-collapsing trap
			-- as below: a Toggle declared Default = false came out of that
			-- expression as nil and never reached the flags at all.
			local default = nil
			if type(settings) == "table" then
				default = settings.Default
			end

			-- `has` rather than testing `value ~= nil`, because a Toggle whose
			-- declared default is false is a real value and the obvious
			-- `type(default) == "boolean" and default or nil` collapses it back
			-- to nil. That mistake shipped once already and was invisible only
			-- because every switch here happens to read a missing flag as off.
			local value, has = nil, false
			if kind == "Slider" then
				value = tonumber(default)
				has = value ~= nil
			elseif kind == "Toggle" then
				if type(default) == "boolean" then
					value, has = default, true
				end
			elseif type(settings) == "table" then
				-- A multi Dropdown's Default is not an index into Options and
				-- turning one into a string here would hand a table-reader a
				-- string, so only single dropdowns are seeded.
				local options = settings.Options
				local index = tonumber(default)
				if type(options) == "table" and index and settings.Multi ~= true then
					value = options[index]
					has = value ~= nil
				end
			end
			if has then
				flags[flag] = value
				if type(settings.Callback) == "function" then
					pcall(settings.Callback, value)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- the ladder
--------------------------------------------------------------------------------
--
-- The single most useful thing this game will tell you, and it tells you
-- honestly: getDungeonStats returns, per dungeon, a table keyed by difficulty
-- whose levelReq is the level that actually opens it.
--
-- Asked once for all fifteen, the answer is a straight line with no gaps:
--
--   Desert Temple    Easy 1  Medium 6  Hard 12  Insane 20  Nightmare 27
--   Winter Outpost   Easy 33 Medium 40 Hard 45  Insane 50  Nightmare 55
--   Pirate Island    Insane 60  Nightmare 65
--   King's Castle    Insane 70  Nightmare 75
--   ... every dungeon after that Insane and Nightmare only, five levels apart,
--   up to Northern Lands at Insane 180 / Nightmare 185.
--
-- Each dungeon's Nightmare is the rung directly below the next dungeon's
-- Insane, which means "the best dungeon you can enter" is a single number
-- comparison and not a matter of taste. That is what Best I Can Do runs on, and
-- it is why this is a decision the hub makes rather than a table it prints.
local ladder = { bits = nil, rows = nil, at = 0, asking = false }

-- Released on a live server, in ladder order. Gilded Skies, Oni Dungeon and
-- Krampus are in MapPlaces with released = false and IsAvailable refuses them,
-- so they are not offered.
ladder.names = {
	"Desert Temple",
	"Winter Outpost",
	"Pirate Island",
	"King's Castle",
	"The Underworld",
	"Samurai Palace",
	"The Canals",
	"Ghastly Harbor",
	"Steampunk Sewers",
	"Orbital Outpost",
	"Volcanic Chambers",
	"Aquatic Temple",
	"Enchanted Forest",
	"Northern Lands",
	"Egg Island",
}

ladder.difficulties = { "Easy", "Medium", "Hard", "Insane", "Nightmare" }

function ladder.wire(bits)
	ladder.bits = bits
end

function ladder.level()
	local bits = ladder.bits
	local player = bits and bits.player
	local stats = player and player:FindFirstChild("leaderstats")
	local level = stats and stats:FindFirstChild("Level")
	return tonumber(level and level.Value) or 1
end

-- Fifteen round trips, so it happens once on a background thread and is kept.
-- The answer only moves when the game updates.
function ladder.refresh()
	local bits = ladder.bits
	if not bits or ladder.asking then
		return
	end
	ladder.asking = true
	task.spawn(function()
		local rows = {}
		for _, name in ipairs(ladder.names) do
			local ok, stats = pcall(function()
				return bits.remotes().getDungeonStats:InvokeServer(name)
			end)
			if ok and type(stats) == "table" then
				local row = {}
				for _, difficulty in ipairs(ladder.difficulties) do
					local entry = stats[difficulty]
					if type(entry) == "table" and tonumber(entry.levelReq) then
						row[difficulty] = tonumber(entry.levelReq)
					end
				end
				rows[name] = row
			end
			task.wait(0.35)
		end
		if next(rows) then
			ladder.rows = rows
			ladder.at = os.clock()
			journal.note("read the level ladder for " .. tostring(#ladder.names) .. " dungeons")
		end
		ladder.asking = false
	end)
end

-- The hardest rung this level actually opens, as dungeon plus difficulty.
-- Returns nil while the ladder has not been read yet, and the caller falls back
-- to what the controls say rather than guessing.
function ladder.best()
	local rows = ladder.rows
	if not rows then
		return nil
	end
	local level = ladder.level()
	local bestName, bestDifficulty, bestReq = nil, nil, -1
	for _, name in ipairs(ladder.names) do
		local row = rows[name]
		if row then
			for _, difficulty in ipairs(ladder.difficulties) do
				local req = row[difficulty]
				-- Egg Island sits at level 1 on both rungs and is an event
				-- dungeon, so it never wins the comparison on merit. It stays
				-- selectable by name.
				if req and req <= level and req > bestReq and name ~= "Egg Island" then
					bestName, bestDifficulty, bestReq = name, difficulty, req
				end
			end
		end
	end
	if not bestName then
		return nil
	end
	return bestName, bestDifficulty, bestReq
end

-- What a named dungeon needs, so a difficulty the player picked by hand can be
-- dropped to one they can actually enter instead of being refused all night.
function ladder.allowed(name, difficulty)
	local rows = ladder.rows
	local row = rows and rows[name]
	if not row then
		return difficulty
	end
	local level = ladder.level()
	if row[difficulty] and row[difficulty] <= level then
		return difficulty
	end
	local fallback = nil
	for _, candidate in ipairs(ladder.difficulties) do
		local req = row[candidate]
		if req and req <= level then
			fallback = candidate
		end
	end
	return fallback
end

--------------------------------------------------------------------------------
-- fighting
--------------------------------------------------------------------------------
--
-- Two ways to hit something, and both were read out of PlayerGui.UIS rather
-- than inferred, because both take a step that the remote name does not
-- suggest.
--
-- The weapon is an Accessory on the character carrying a child called Weapon
-- and a RemoteEvent of its own. Firing that remote alone is half the job: the
-- game also fires remotes.weaponUsed, and the pair is what the server counts.
--
-- An ability is a Tool in the Backpack carrying an abilitySlot. The game fires
-- the Tool's own localEvent, which is a client side BindableEvent that plays
-- the animation and fires the ability's own remote, and THEN fires
-- remotes.abilityUsed with the slot and the Tool. Firing abilityUsed by itself
-- skips the game's own client half.
--
-- Both refuse while Character.busyCasting is true, and the weapon also refuses
-- while the player's peaceful value is true, which is how the game says "you
-- are standing in a town".
local fight = { bits = nil, lastSwing = 0, retreating = false, retreatingSince = 0 }

function fight.wire(bits)
	fight.bits = bits
end

-- Everything alive in the dungeon.
--
-- Not workspace.enemies. That folder exists, is the obvious place to look, and
-- stayed empty for a whole run while the character was being beaten to death by
-- twenty of them. They live under each room instead, in workspace.dungeon.<room>
-- .enemyFolder, which is also why they appear a room at a time as you walk.
function fight.enemies()
	local out = {}
	local dungeon = Workspace:FindFirstChild("dungeon")
	if not dungeon then
		return out
	end
	for _, room in ipairs(dungeon:GetChildren()) do
		local folder = room:FindFirstChild("enemyFolder")
		if folder then
			for _, model in ipairs(folder:GetChildren()) do
				if model:IsA("Model") then
					local humanoid = model:FindFirstChildOfClass("Humanoid")
					local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
					if humanoid and root and humanoid.Health > 0 then
						out[#out + 1] = { model = model, humanoid = humanoid, root = root }
					end
				end
			end
		end
	end
	return out
end

function fight.pick(from)
	local bits = fight.bits
	local mode = (bits and bits.F.dqTarget) or "Nearest"
	local best, bestScore = nil, math.huge
	for _, entry in ipairs(fight.enemies()) do
		local distance = (entry.root.Position - from).Magnitude
		local score = distance
		if mode == "Weakest" then
			score = entry.humanoid.Health + distance * 0.05
		end
		if score < bestScore then
			best, bestScore = entry, score
		end
	end
	return best
end

function fight.ability(slot)
	local bits = fight.bits
	local player = bits and bits.player
	if not player then
		return nil
	end
	local backpack = player:FindFirstChild("Backpack")
	for _, tool in ipairs(backpack and backpack:GetChildren() or {}) do
		local marker = tool:FindFirstChild("abilitySlot")
		if marker and marker.Value == slot then
			return tool
		end
	end
	return nil
end

-- On cooldown is asked of the Backpack and the character both, because the Tool
-- moves between them while it is being used.
function fight.onCooldown(slot)
	local bits = fight.bits
	local player = bits and bits.player
	if not player then
		return true
	end
	local places = { player:FindFirstChild("Backpack"), player.Character }
	for _, place in ipairs(places) do
		for _, tool in ipairs(place and place:GetChildren() or {}) do
			local marker = tool:FindFirstChild("abilitySlot")
			if marker and marker.Value == slot then
				local cooldown = tool:FindFirstChild("cooldown")
				if cooldown and cooldown.Value > 0 then
					return true
				end
			end
		end
	end
	return false
end

function fight.busy()
	local bits = fight.bits
	local character = bits and bits.player and bits.player.Character
	local flag = character and character:FindFirstChild("busyCasting")
	return flag ~= nil and flag.Value == true
end

function fight.cast(slot)
	local bits = fight.bits
	if not bits or fight.busy() or fight.onCooldown(slot) then
		return false
	end
	local tool = fight.ability(slot)
	if not tool then
		return false
	end
	local event = tool:FindFirstChild("localEvent")
	if not event then
		return false
	end
	local ok = pcall(function()
		event:Fire()
	end)
	if not ok then
		return false
	end
	bits.fire("abilityUsed", slot, tool)
	journal.note("cast " .. slot .. " " .. tool.Name)
	return true
end

function fight.weapon()
	local bits = fight.bits
	local character = bits and bits.player and bits.player.Character
	for _, child in ipairs(character and character:GetChildren() or {}) do
		if child:IsA("Accessory") and child:FindFirstChild("Weapon") then
			return child
		end
	end
	return nil
end

function fight.swing()
	local bits = fight.bits
	if not bits or fight.busy() then
		return false
	end
	local peaceful = bits.player:FindFirstChild("peaceful")
	if peaceful and peaceful.Value == true then
		return false
	end
	local accessory = fight.weapon()
	if not accessory then
		return false
	end
	local remote = accessory:FindFirstChildOfClass("RemoteEvent")
	if not remote then
		return false
	end
	local ok = pcall(function()
		remote:FireServer()
	end)
	if not ok then
		return false
	end
	bits.fire("weaponUsed")
	return true
end

-- One step per call, and it says whether it took the legs, because the run loop
-- and this share one character and only one of them may be steering.
--
-- The order here is the whole feature. Walking at a room and swinging is what a
-- level one does once: measured on Desert Temple Easy it killed five Sand
-- Peasants in eighteen seconds and then died, because twenty of them hit back
-- and nothing was watching the health bar. So health is read first, and below
-- the floor the only thing this does is walk away.
function fight.tick()
	local bits = fight.bits
	if not bits then
		return false
	end
	local F = bits.F
	if F.dqAutoAttack ~= true then
		return false
	end
	local character = bits.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		fight.retreating = false
		return false
	end

	local target = fight.pick(root.Position)
	if not target then
		fight.retreating = false
		return false
	end

	local distance = (target.root.Position - root.Position).Magnitude
	local share = humanoid.MaxHealth > 0 and (humanoid.Health / humanoid.MaxHealth * 100) or 100
	local floor = tonumber(F.dqBackOffAt) or 45

	-- Hysteresis, so a character sitting exactly on the line does not spend the
	-- run twitching between advancing and retreating.
	-- Hysteresis, so a character sitting exactly on the line does not spend the
	-- run twitching between advancing and retreating.
	--
	-- Watched: this alone is a trap. Health does not come back inside a dungeon.
	-- The first version dropped to 21 of 100, retreated, and then stood at
	-- x=-99 saying "Backing off" for as long as anyone watched, because nothing
	-- could ever push it back over the line again. It had killed twelve of
	-- twenty and it was never going to kill the thirteenth. So the clock below
	-- is not a nicety: without it Auto Farm stalls for the rest of the timer
	-- every time it gets hurt, which is every run.
	if fight.retreating and share > floor + 15 then
		fight.retreating = false
	elseif not fight.retreating and share <= floor then
		fight.retreating = true
		fight.retreatingSince = os.clock()
		journal.note(("backing off at %d%% health"):format(math.floor(share)))
	end

	if fight.retreating then
		local away = root.Position - target.root.Position
		if away.Magnitude > 0.1 then
			bits.steer(Vector3.new(away.X, 0, away.Z).Unit)
		end
		-- Still worth throwing whatever is off cooldown while retreating: it
		-- costs nothing and the thing chasing is in front of you.
		if F.dqUseAbilities ~= false and distance <= 34 then
			for _, slot in ipairs(fight.slots()) do
				if fight.cast(slot) then
					break
				end
			end
		end
		return true
	end

	local ranged = F.dqRanged == true
	local keep = tonumber(F.dqKeepDistance) or 26
	local reach = tonumber(F.dqReach) or 10
	local want = ranged and keep or reach

	if distance > want then
		local toward = target.root.Position - root.Position
		bits.steer(Vector3.new(toward.X, 0, toward.Z).Unit)
	else
		bits.steer(nil)
		-- Face it anyway. The server decides where a fireball goes from the
		-- character's own facing, so a cast thrown without turning first goes
		-- past whatever you meant to hit.
		bits.face(target.root.Position)
	end

	if F.dqUseAbilities ~= false and distance <= 34 then
		for _, slot in ipairs(fight.slots()) do
			if fight.cast(slot) then
				break
			end
		end
	end

	if not ranged and distance <= reach + 2 then
		local delay = tonumber(F.dqSwingDelay) or 0
		if os.clock() - fight.lastSwing >= delay then
			if fight.swing() then
				fight.lastSwing = os.clock()
			end
		end
	end
	return true
end

function fight.slots()
	local bits = fight.bits
	local chosen = bits and bits.F.dqSlots
	local out = {}
	if type(chosen) == "table" then
		for slot, on in pairs(chosen) do
			if on then
				out[#out + 1] = slot
			end
		end
		table.sort(out)
		if #out > 0 then
			return out
		end
	end
	-- Nothing chosen means every slot. Asking for one you do not own costs
	-- nothing, because fight.ability simply finds no Tool for it.
	return { "q", "e", "q2", "e2" }
end

--------------------------------------------------------------------------------
-- the run
--------------------------------------------------------------------------------
--
-- Three places, one loop. PlaceManager.GetPlaceName() answers "Lobby" in town
-- and "Level" inside a dungeon, and it is the game's own answer rather than a
-- list of place ids to keep in step with it.
--
-- Watched end to end on a live client: createLobby returns true and a Folder
-- named after you appears under workspace.games.inLobby; startDungeon answers
-- with clearGuisOnTeleport carrying the dungeon name and a five second
-- countdown, and then the teleport happens; changeStartValue starts the run and
-- the server announces it to everyone in the dungeon.
local runner = { bits = nil, phase = "idle", since = 0, startedAt = 0 }

function runner.wire(bits)
	runner.bits = bits
end

function runner.where()
	local bits = runner.bits
	local ok, name = pcall(function()
		return bits.PlaceManager.GetPlaceName()
	end)
	return ok and name or nil
end

function runner.mine()
	local bits = runner.bits
	local games = Workspace:FindFirstChild("games")
	local inLobby = games and games:FindFirstChild("inLobby")
	return inLobby and inLobby:FindFirstChild(bits.player.Name) or nil
end

function runner.choice()
	local bits = runner.bits
	local F = bits.F
	local name = F.dqDungeon
	local difficulty = F.dqDifficulty or "Easy"
	if name == nil or name == "Best I Can Do" then
		local bestName, bestDifficulty = ladder.best()
		if bestName then
			return bestName, bestDifficulty
		end
		return "Desert Temple", "Easy"
	end
	return name, ladder.allowed(name, difficulty) or "Easy"
end

function runner.state()
	local started = Workspace:FindFirstChild("dungeonStarted")
	local progress = Workspace:FindFirstChild("dungeonProgress")
	local dungeon = Workspace:FindFirstChild("dungeon")
	local bossRoom = dungeon and dungeon:FindFirstChild("bossRoom")
	local finished = bossRoom and bossRoom:FindFirstChild("dungeonFinished")
	return {
		started = started ~= nil and started.Value == true,
		progress = progress and progress.Value or "",
		finished = finished ~= nil and finished.Value == true,
		timeLeft = tonumber(Workspace:FindFirstChild("timeLeft") and Workspace.timeLeft.Value) or 0,
	}
end

function runner.alive()
	local bits = runner.bits
	local character = bits.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- The payload the game's own replay button sends, rebuilt the same way it
-- builds it: the dungeon values off workspace plus every ValueBase under
-- workspace.dungeon and its bossRoom. Sending a bare call instead is the kind
-- of guess that this file exists to avoid.
function runner.replayPayload()
	local data = {}
	for _, key in ipairs({ "dungeonName", "dungeonProgress", "dungeonStarted" }) do
		local value = Workspace:FindFirstChild(key)
		if value and value:IsA("ValueBase") then
			data[key] = value.Value
		end
	end
	local hardcore = Workspace:FindFirstChild("hardcore")
	if hardcore and hardcore:IsA("BoolValue") then
		data.hardcore = hardcore.Value
		data.isHardcore = hardcore.Value
	end
	local dungeon = Workspace:FindFirstChild("dungeon")
	if dungeon then
		for _, child in ipairs(dungeon:GetChildren()) do
			if child:IsA("ValueBase") then
				data[child.Name] = child.Value
			end
		end
		local bossRoom = dungeon:FindFirstChild("bossRoom")
		for _, child in ipairs(bossRoom and bossRoom:GetChildren() or {}) do
			if child:IsA("ValueBase") then
				data[child.Name] = child.Value
			end
		end
	end
	return data
end

function runner.town()
	local bits = runner.bits
	local F = bits.F
	if runner.mine() then
		if bits.due("start", 6) then
			bits.fire("startDungeon")
			journal.note("startDungeon")
			runner.phase = "starting"
		end
		return
	end
	if not bits.due("lobby", 8) then
		return
	end
	local name, difficulty = runner.choice()
	local ok, made = bits.invoke(
		"createLobby",
		name,
		difficulty,
		1,
		F.dqHardcore == true,
		F.dqPrivate ~= false,
		false
	)
	journal.note(("createLobby %s %s -> %s"):format(tostring(name), tostring(difficulty), tostring(made)))
	if ok and made == true then
		bits.accepted("lobby")
		runner.phase = "lobby"
		bits.notify(("Lobby up: %s on %s"):format(tostring(name), tostring(difficulty)))
	else
		bits.refused("lobby", 8)
	end
end

function runner.level()
	local bits = runner.bits
	local F = bits.F
	local state = runner.state()

	if state.finished then
		runner.phase = "finished"
		if F.dqReplay ~= false then
			if bits.due("replay", 10) then
				bits.fire("replayDungeon", runner.replayPayload())
				journal.note("replayDungeon")
			end
		elseif bits.due("home", 10) then
			bits.fire("ReturnToLobbyEvent")
			journal.note("ReturnToLobbyEvent")
		end
		return
	end

	if not state.started then
		runner.phase = "waiting"
		if bits.due("begin", 5) then
			bits.fire("changeStartValue")
			journal.note("changeStartValue")
		end
		return
	end

	runner.phase = "running"

	-- Dead, solo, with the clock still going. Nothing revives you and the run
	-- carries on without you, so there is no reason to stand there for the rest
	-- of the timer: go back and start another.
	if not runner.alive() then
		runner.phase = "dead"
		if bits.due("home", 12) then
			bits.fire("ReturnToLobbyEvent")
			journal.note("died, ReturnToLobbyEvent")
		end
		return
	end

	-- A run that cannot be finished is worth leaving. Health does not come back
	-- in here, so once the retreat has been going this long it is going to keep
	-- going until the timer runs out, and the character that walks out of the
	-- lobby next time starts at full.
	if fight.retreating then
		local patience = tonumber(F.dqGiveUpAfter) or 45
		if patience > 0 and os.clock() - fight.retreatingSince > patience then
			runner.phase = "giving up"
			if bits.due("home", 12) then
				bits.steer(nil)
				bits.fire("ReturnToLobbyEvent")
				journal.note("hurt and going nowhere, leaving for a fresh run")
				bits.notify("Too hurt to finish. Starting a fresh run.")
			end
			return
		end
	end

	if not fight.tick() then
		-- Nothing to fight and nothing to run from: the corridor runs along
		-- negative X in every dungeon place seen so far, so walking that way is
		-- what finds the next room.
		bits.steer(Vector3.new(-1, 0, 0))
	end
end

function runner.tick()
	local bits = runner.bits
	if not bits or bits.F.dqAutoFarm ~= true then
		return
	end
	local where = runner.where()
	if where == "Lobby" then
		bits.steer(nil)
		runner.town()
	elseif where == "Level" then
		runner.level()
	end
end

--------------------------------------------------------------------------------
-- gear
--------------------------------------------------------------------------------
--
-- equipItem takes an item type and the number off the inventory key, not the
-- UniqueItemID, and the third argument is only for abilities. Watched: with
-- nothing equipped there is no Accessory carrying a Weapon on the character at
-- all, so the swing has nothing to fire and does nothing quietly.
-- equipItem("weapon", 1) answered true and the Bronze Dagger appeared, with its
-- own RemoteEvent named swing, and it was still on after dying and respawning.
local gear = { bits = nil, at = 0, cache = nil }

function gear.wire(bits)
	gear.bits = bits
end

function gear.inventory()
	local bits = gear.bits
	if gear.cache and os.clock() - gear.at < 20 then
		return gear.cache
	end
	local ok, invy = bits.invoke("reloadInvy")
	if ok and type(invy) == "table" then
		gear.cache = invy
		gear.at = os.clock()
	end
	return gear.cache
end

function gear.forget()
	gear.cache = nil
	gear.at = 0
end

-- The number on the end of an inventory key, which is what equipItem wants.
function gear.number(key)
	return tonumber(tostring(key):match("_(%d+)$"))
end

function gear.bestWeapon()
	local invy = gear.inventory()
	local weapons = invy and invy.weapons
	if type(weapons) ~= "table" then
		return nil
	end
	local level = ladder.level()
	local prefer = gear.bits and gear.bits.F.dqPrefer or "Whichever Is Higher"

	-- The larger of the two stats on its own is not enough, and the starting
	-- gear proves it: the Bronze Dagger is 6 physical and 1 spell, the Starter
	-- Wand is 1 physical and 6 spell, so by the larger number they tie exactly
	-- and which one goes on is whichever pairs happened to come out of the table
	-- first. They are not interchangeable - this game spends skill points into
	-- physicalPower and spellPower as two separate ladders - so which stat
	-- counts is the player's decision and not something to guess.
	local function score(item)
		local physical = tonumber(item.physicalDamage) or 0
		local spell = tonumber(item.spellPower) or 0
		if prefer == "Physical" then
			return physical
		elseif prefer == "Spell" then
			return spell
		end
		return math.max(physical, spell)
	end

	local bestKey, bestScore, bestName, alreadyOn = nil, -1, nil, false
	for key, item in pairs(weapons) do
		if type(item) == "table" then
			local req = tonumber(item.levelReq) or 1
			local value = score(item)
			-- Strictly greater, so a tie leaves whatever is already on alone
			-- rather than swapping back and forth between two equal weapons
			-- every time the loop comes round.
			if req <= level and value > bestScore then
				bestKey, bestScore, bestName = key, value, item.name
				alreadyOn = item.equipped == true
			end
		end
	end
	-- A tie that the equipped weapon is part of is not worth a swap.
	if bestKey and not alreadyOn then
		for key, item in pairs(weapons) do
			if type(item) == "table" and item.equipped == true and score(item) >= bestScore then
				return nil
			end
		end
	end
	if not bestKey then
		return nil
	end
	return gear.number(bestKey), bestName, bestScore, alreadyOn
end

function gear.equipBest(force)
	local bits = gear.bits
	if not bits then
		return false
	end
	if not force and not bits.due("equip", 25) then
		return false
	end
	local number, name, score, alreadyOn = gear.bestWeapon()
	if not number or alreadyOn then
		return false
	end
	local ok, done = bits.invoke("equipItem", "weapon", number)
	journal.note(("equipItem weapon %d (%s) -> %s"):format(number, tostring(name), tostring(done)))
	if ok and done ~= false then
		gear.forget()
		bits.notify(("Put on the %s, %d damage"):format(tostring(name), math.floor(score or 0)))
		bits.accepted("equip")
		return true
	end
	bits.refused("equip", 25)
	return false
end

function gear.tick()
	local bits = gear.bits
	if not bits or bits.F.dqKeepBest ~= true then
		return
	end
	gear.equipBest(false)
end

-- The three stats the game accepts, spelled the way its own inventory spells
-- them. Anything else and the server throws.
gear.stats = {
	["Physical Power"] = "physicalPower",
	["Spell Power"] = "spellPower",
	["Stamina"] = "stamina",
}

function gear.spend(amount)
	local bits = gear.bits
	if not bits then
		return false
	end
	local label = bits.F.dqSpendOn or "Stamina"
	local key = gear.stats[label]
	if not key then
		return false
	end
	if not bits.due("points", 5) then
		return false
	end
	bits.fire("spendSkillPoint", key, amount or 1)
	journal.note(("spendSkillPoint %s %d"):format(key, amount or 1))
	bits.notify(("Put %d into %s"):format(amount or 1, label))
	return true
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

	local Utility = ReplicatedStorage:WaitForChild("Utility")
	local PlaceManager = require(Utility:WaitForChild("PlaceManager"))

	----------------------------------------------------------------------------
	-- reaching the server
	----------------------------------------------------------------------------
	--
	-- One way out, and it looks up what it is talking to first. This game keeps
	-- 190 remotes in one flat folder and the split is not guessable from the
	-- names: createLobby, joinDungeon, equipItem and reloadInvy are
	-- RemoteFunctions, while startDungeon, changeStartValue, replayDungeon and
	-- spendSkillPoint are RemoteEvents. Firing a RemoteFunction throws, and a
	-- client throwing at the server on a timer is the thing that gets accounts
	-- removed.
	local folder = ReplicatedStorage:FindFirstChild("remotes")

	local function remotes()
		if not folder or not folder.Parent then
			folder = ReplicatedStorage:FindFirstChild("remotes")
		end
		return folder
	end

	local function lookup(name)
		local where = remotes()
		return where and where:FindFirstChild(name) or nil
	end

	local function fire(name, ...)
		local remote = lookup(name)
		if not remote then
			journal.note("no remote " .. tostring(name))
			return false
		end
		if not remote:IsA("RemoteEvent") then
			journal.note(tostring(name) .. " is a " .. remote.ClassName .. ", not fired")
			return false
		end
		local ok, err = pcall(function(...)
			remote:FireServer(...)
		end, ...)
		if not ok then
			journal.note(("%s failed: %s"):format(name, tostring(err)))
		end
		return ok
	end

	-- Nothing on a loop may wait on the server. An InvokeServer that never comes
	-- back would stop the run loop where it stands, so a request goes out on its
	-- own thread with a deadline and "no answer" is a perfectly good answer here
	-- because every action is behind a gate that will try again.
	local function invoke(name, ...)
		local remote = lookup(name)
		if not remote then
			journal.note("no remote " .. tostring(name))
			return false, nil
		end
		if not remote:IsA("RemoteFunction") then
			journal.note(tostring(name) .. " is a " .. remote.ClassName .. ", not invoked")
			return false, nil
		end
		local args = table.pack(...)
		local state = { done = false }
		task.spawn(function()
			local ok, value = pcall(function()
				return remote:InvokeServer(table.unpack(args, 1, args.n))
			end)
			state.ok, state.value, state.done = ok, value, true
		end)
		local deadline = os.clock() + 4
		while not state.done and os.clock() < deadline do
			task.wait()
		end
		if not state.done then
			journal.note(name .. ": the server did not answer")
			return false, nil
		end
		if not state.ok then
			journal.note(("%s errored: %s"):format(name, tostring(state.value)))
			return false, nil
		end
		return true, state.value
	end

	-- A gate every repeated request goes through, with a doubling wait after a
	-- refusal and a long park once something has clearly never been going to
	-- work. An impossible request asked twice a second is the one thing that
	-- reliably removes an account.
	local nextDue, failures, parked = {}, {}, {}
	local lastCall = 0

	local function due(key, interval)
		local now = os.clock()
		if now - lastCall < 0.4 then
			return false
		end
		if now < (nextDue[key] or 0) then
			return false
		end
		lastCall = now
		nextDue[key] = now + interval
		return true
	end

	local function accepted(key)
		failures[key] = nil
		parked[key] = nil
	end

	local function refused(key, interval)
		local count = (failures[key] or 0) + 1
		failures[key] = count
		if count >= 10 then
			local rounds = (parked[key] or 0) + 1
			parked[key] = rounds
			nextDue[key] = os.clock() + math.min(300 * (2 ^ (rounds - 1)), 14400)
			if rounds <= 2 then
				warn(("[Meridian] %s refused %d times, leaving it alone for a while"):format(key, count))
			end
			return
		end
		nextDue[key] = os.clock() + math.min(interval * (2 ^ count), 60)
	end

	----------------------------------------------------------------------------
	-- the legs
	----------------------------------------------------------------------------
	--
	-- Humanoid:Move on a render step, not MoveTo. The control module writes over
	-- MoveTo every frame, and steering is also the only thing that keeps working
	-- when the character is replaced, which happens on every death and every
	-- teleport in this game.
	local steer = { direction = nil }

	local function setSteer(direction)
		steer.direction = direction
	end

	local function face(position)
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local flat = Vector3.new(position.X, root.Position.Y, position.Z)
		if (flat - root.Position).Magnitude < 0.5 then
			return
		end
		pcall(function()
			root.CFrame = CFrame.lookAt(root.Position, flat)
		end)
	end

	core:Connect(RunService.RenderStepped, function()
		local direction = steer.direction
		if not direction then
			return
		end
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid:Move(direction, false)
		end
	end)

	local function notify(text)
		core:Notify(Module.Name, text, 5)
	end

	local bits = {
		F = F,
		core = core,
		player = LocalPlayer,
		PlaceManager = PlaceManager,
		remotes = remotes,
		fire = fire,
		invoke = invoke,
		due = due,
		accepted = accepted,
		refused = refused,
		steer = setSteer,
		face = face,
		notify = notify,
	}

	ladder.wire(bits)
	fight.wire(bits)
	runner.wire(bits)
	gear.wire(bits)

	----------------------------------------------------------------------------
	-- loops, registered before a single tab exists
	----------------------------------------------------------------------------
	--
	-- Maclib yields while it builds elements, and a thread that has yielded
	-- spawns children that cannot touch an Instance at all. A loop created after
	-- the tabs therefore runs forever without drawing anything. Registering
	-- first is the fix, and it is load bearing.

	core:Loop("run", 0.3, function()
		runner.tick()
	end)

	core:Loop("gear", 5, function()
		gear.tick()
	end)

	core:Loop("stats", 1, function()
		local state = runner.state()
		local carried = core.Stats or {}
		carried.Level = ladder.level()
		carried.Where = runner.where() or "?"
		carried.Left = state.timeLeft > 0 and (("%d:%02d"):format(math.floor(state.timeLeft / 60), state.timeLeft % 60)) or "-"
		local alive = #fight.enemies()
		carried.Enemies = alive
		core.Stats = carried

		if F.dqAutoFarm ~= true then
			core.Headline = nil
		elseif runner.phase == "dead" then
			core.Headline = "Died. Going back for another."
		elseif runner.phase == "giving up" then
			core.Headline = "Too hurt to finish. Going back for a fresh one."
		elseif runner.phase == "finished" then
			core.Headline = "Finished. " .. (F.dqReplay ~= false and "Going again." or "Heading back.")
		elseif runner.where() == "Lobby" then
			local name, difficulty = runner.choice()
			core.Headline = ("Setting up %s on %s"):format(tostring(name), tostring(difficulty))
		elseif fight.retreating then
			core.Headline = "Backing off"
		elseif alive > 0 then
			core.Headline = ("Fighting · %d left"):format(alive)
		else
			core.Headline = "Looking for the next room"
		end
	end)

	core.Journal = journal

	-- Off the build thread, deliberately. Fifteen InvokeServer round trips yield,
	-- and nothing in Build may yield: Build runs part way through the loader
	-- assembling the window, and a thread that yields comes back without the
	-- capability to touch the interface.
	task.spawn(function()
		task.wait(2)
		ladder.refresh()
	end)

	-- A character that has just been replaced has no weapon on it yet, and the
	-- inventory the hub remembers is about the old one.
	core:Connect(LocalPlayer.CharacterAdded, function()
		gear.forget()
		fight.retreating = false
		setSteer(nil)
	end)

	----------------------------------------------------------------------------
	-- the interface, last on purpose
	----------------------------------------------------------------------------

	local dungeonTab = tabGroup:Tab({ Name = "Dungeon", Image = "rbxassetid://10723407389" })
	local fightTab = tabGroup:Tab({ Name = "Fight", Image = "rbxassetid://7510979485" })
	local gearTab = tabGroup:Tab({ Name = "Gear", Image = "rbxassetid://10723415903" })
	local visualsTab = tabGroup:Tab({ Name = "Visuals", Image = "rbxassetid://10734898355" })
	local playerTab = tabGroup:Tab({ Name = "Player", Image = "rbxassetid://10747373176" })

	local dungeonLeft = dungeonTab:Section({ Side = "Left" })
	local dungeonRight = dungeonTab:Section({ Side = "Right" })
	local fightLeft = fightTab:Section({ Side = "Left" })
	local fightRight = fightTab:Section({ Side = "Right" })
	local gearLeft = gearTab:Section({ Side = "Left" })
	local visualsLeft = visualsTab:Section({ Side = "Left" })
	local playerLeft = playerTab:Section({ Side = "Left" })

	------------------------------------------------------------- dungeon · left

	dungeonLeft:Header({ Text = "Run" })

	dungeonLeft:Toggle({
		Name = "Auto Farm",
		Default = false,
		Callback = function(state)
			F.dqAutoFarm = state
			if not state then
				setSteer(nil)
			end
		end,
	}, "dqAutoFarm")

	local dungeonOptions = { "Best I Can Do" }
	for _, name in ipairs(ladder.names) do
		dungeonOptions[#dungeonOptions + 1] = name
	end

	dungeonLeft:Dropdown({
		Name = "Which Dungeon",
		Multi = false,
		Required = true,
		Options = dungeonOptions,
		Default = 1,
		Callback = function(value)
			F.dqDungeon = value
		end,
	}, "dqDungeon")

	dungeonLeft:Dropdown({
		Name = "Difficulty",
		Multi = false,
		Required = true,
		Options = ladder.difficulties,
		Default = 1,
		Callback = function(value)
			F.dqDifficulty = value
		end,
	}, "dqDifficulty")

	dungeonLeft:Toggle({
		Name = "Hardcore",
		Default = false,
		Callback = function(state)
			F.dqHardcore = state
		end,
	}, "dqHardcore")

	dungeonLeft:Toggle({
		Name = "Private Lobby",
		Default = true,
		Callback = function(state)
			F.dqPrivate = state
		end,
	}, "dqPrivate")

	dungeonLeft:Toggle({
		Name = "Replay When It Ends",
		Default = true,
		Callback = function(state)
			F.dqReplay = state
		end,
	}, "dqReplay")

	------------------------------------------------------------ dungeon · right

	dungeonRight:Header({ Text = "Right Now" })

	dungeonRight:Button({
		Name = "Start A Run",
		Callback = function()
			task.spawn(function()
				local name, difficulty = runner.choice()
				if runner.where() ~= "Lobby" then
					notify("You are already in a dungeon")
					return
				end
				local ok, made = invoke("createLobby", name, difficulty, 1, F.dqHardcore == true, F.dqPrivate ~= false, false)
				if not ok or made ~= true then
					notify("The game refused that lobby")
					return
				end
				task.wait(1)
				fire("startDungeon")
				notify(("Starting %s on %s"):format(tostring(name), tostring(difficulty)))
			end)
		end,
	})

	dungeonRight:Button({
		Name = "Go Back To Town",
		Callback = function()
			setSteer(nil)
			fire("ReturnToLobbyEvent")
		end,
	})

	--------------------------------------------------------------- fight · left

	fightLeft:Header({ Text = "Attacking" })

	fightLeft:Toggle({
		Name = "Auto Attack",
		Default = true,
		Callback = function(state)
			F.dqAutoAttack = state
		end,
	}, "dqAutoAttack")

	fightLeft:Toggle({
		Name = "Use Abilities",
		Default = true,
		Callback = function(state)
			F.dqUseAbilities = state
		end,
	}, "dqUseAbilities")

	-- No Default on a multi dropdown. seeded.apply turns a Default index into
	-- options[index], which for a multi control is a string where the reading
	-- code wants a table: the control would have shown "q" selected while the
	-- farm fired both slots, which is the worst kind of bug in a hub because the
	-- person judging it is reading the interface.
	fightLeft:Dropdown({
		Name = "Ability Slots",
		Multi = true,
		Required = false,
		Options = { "q", "e", "q2", "e2" },
		Callback = function(value)
			F.dqSlots = value
		end,
	}, "dqSlots")

	fightLeft:Dropdown({
		Name = "Target",
		Multi = false,
		Required = true,
		Options = { "Nearest", "Weakest" },
		Default = 1,
		Callback = function(value)
			F.dqTarget = value
		end,
	}, "dqTarget")

	fightLeft:Slider({
		Name = "Swing Delay",
		Default = 0,
		Minimum = 0,
		Maximum = 1.5,
		DisplayMethod = "Value",
		Precision = 1,
		Callback = function(value)
			F.dqSwingDelay = value
		end,
	}, "dqSwingDelay")

	fightLeft:Slider({
		Name = "Reach",
		Default = 10,
		Minimum = 5,
		Maximum = 18,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.dqReach = value
		end,
	}, "dqReach")

	-------------------------------------------------------------- fight · right

	fightRight:Header({ Text = "Staying Alive" })

	fightRight:Slider({
		Name = "Back Off At",
		Default = 45,
		Minimum = 0,
		Maximum = 90,
		DisplayMethod = "Percent",
		Precision = 0,
		Callback = function(value)
			F.dqBackOffAt = value
		end,
	}, "dqBackOffAt")

	fightRight:Slider({
		Name = "Give Up After",
		Default = 45,
		Minimum = 0,
		Maximum = 180,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.dqGiveUpAfter = value
		end,
	}, "dqGiveUpAfter")

	fightRight:Toggle({
		Name = "Fight At Range",
		Default = false,
		Callback = function(state)
			F.dqRanged = state
		end,
	}, "dqRanged")

	fightRight:Slider({
		Name = "Keep Distance",
		Default = 26,
		Minimum = 12,
		Maximum = 34,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.dqKeepDistance = value
		end,
	}, "dqKeepDistance")

	---------------------------------------------------------------- gear · left

	gearLeft:Header({ Text = "Gear" })

	gearLeft:Button({
		Name = "Equip Best Weapon",
		Callback = function()
			task.spawn(function()
				if not gear.equipBest(true) then
					notify("Nothing better to put on")
				end
			end)
		end,
	})

	gearLeft:Dropdown({
		Name = "Prefer",
		Multi = false,
		Required = true,
		Options = { "Whichever Is Higher", "Physical", "Spell" },
		Default = 1,
		Callback = function(value)
			F.dqPrefer = value
		end,
	}, "dqPrefer")

	gearLeft:Toggle({
		Name = "Keep Best Weapon On",
		Default = false,
		Callback = function(state)
			F.dqKeepBest = state
		end,
	}, "dqKeepBest")

	gearLeft:Divider()

	gearLeft:Dropdown({
		Name = "Spend Points On",
		Multi = false,
		Required = true,
		Options = { "Stamina", "Physical Power", "Spell Power" },
		Default = 1,
		Callback = function(value)
			F.dqSpendOn = value
		end,
	}, "dqSpendOn")

	gearLeft:Button({
		Name = "Spend Them Now",
		Callback = function()
			task.spawn(function()
				gear.spend(1)
			end)
		end,
	})

	------------------------------------------------------------- visuals · left

	visualsLeft:Header({ Text = "Enemies" })

	visualsLeft:Toggle({
		Name = "Enemy ESP",
		Default = false,
		Callback = function(state)
			F.dqEsp = state
		end,
	}, "dqEsp")

	visualsLeft:Toggle({
		Name = "Show Health",
		Default = true,
		Callback = function(state)
			F.dqEspHealth = state
		end,
	}, "dqEspHealth")

	visualsLeft:Toggle({
		Name = "Show Distance",
		Default = true,
		Callback = function(state)
			F.dqEspRange = state
		end,
	}, "dqEspRange")

	-- No tracers control. core:StartESP has no tracer of its own, and a switch
	-- that cannot work is worse than a missing one.
	visualsLeft:Slider({
		Name = "Fill",
		Default = 0.2,
		Minimum = 0,
		Maximum = 1,
		DisplayMethod = "Value",
		Precision = 2,
		Callback = function(value)
			F.dqEspFill = value
		end,
	}, "dqEspFill")

	visualsLeft:Slider({
		Name = "Max Distance",
		Default = 900,
		Minimum = 100,
		Maximum = 2000,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.dqEspDistance = value
		end,
	}, "dqEspDistance")

	core:StartESP({
		flag = "dqEsp",
		interval = 0.3,
		fill = function()
			return tonumber(F.dqEspFill) or 0.2
		end,
		maxDistance = function()
			return tonumber(F.dqEspDistance) or 900
		end,
		list = function()
			local out = {}
			for _, entry in ipairs(fight.enemies()) do
				out[#out + 1] = entry.model
			end
			return out
		end,
		label = function(model, distance)
			local bits = { model.Name }
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if F.dqEspHealth ~= false and humanoid then
				bits[#bits + 1] = ("%d hp"):format(math.floor(humanoid.Health))
			end
			if F.dqEspRange ~= false and distance then
				bits[#bits + 1] = ("%d studs"):format(math.floor(distance))
			end
			return table.concat(bits, " · ")
		end,
	})

	-------------------------------------------------------------- player · left

	playerLeft:Header({ Text = "Session" })

	playerLeft:Toggle({
		Name = "Anti AFK",
		Default = true,
		Callback = function(state)
			F.dqAntiAfk = state
		end,
	}, "dqAntiAfk")

	do
		local ok, connection = pcall(function()
			return LocalPlayer.Idled
		end)
		if ok and connection then
			core:Connect(LocalPlayer.Idled, function()
				if F.dqAntiAfk == false then
					return
				end
				local vu = game:GetService("VirtualUser")
				pcall(function()
					vu:CaptureController()
					vu:ClickButton2(Vector2.new())
				end)
				journal.note("anti afk nudge")
			end)
		end
	end

	-- Every slider and dropdown default, copied into the flags now that the
	-- controls exist. Nothing here yields, which Build may not do.
	seeded.apply(core)

	return {
		Tabs = {
			Dungeon = dungeonTab,
			Fight = fightTab,
			Gear = gearTab,
			Visuals = visualsTab,
			Player = playerTab,
		},
		Default = dungeonTab,
		Tips = Module.Tips,
	}
end

return Module
