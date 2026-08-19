--// Meridian · Ability Arena
--// universe 10230942274 (Ability Arena, Beginner Servers, any future place)
--//
--// Everything here drives the game's own client code. No metamethod hooks and
--// no hand built remote buffers: the game ships an Adonis client that kicks on
--// tamper, and the server rejects hits it cannot see a reason for.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Module = {
	GameId = 10230942274,
	Name = "Ability Arena",
}

-- Hover text. Short on purpose, one line each.
-- Every one of these is read by somebody who has never seen the code.
--
-- The old set was written from the measurements and it showed: hitbox offsets,
-- what the server does with a packet, three numbers to two decimal places in a
-- single line. He asked for them humanised, so nothing here explains a
-- mechanism, and no number appears unless it is one you would actually set.
Module.Tips = {
	["Kill Aura"] = "Punches everyone close enough to hit, over and over, without you clicking.",
	["Reach"] = "How far the aura reaches. The slider stops where the game stops letting hits count, so every number on it works.",
	["Show Reach"] = "Draws a box around you showing exactly what a punch covers.",
	["Reach Colour"] = "The colour of that box, and how see-through it is.",
	["Target"] = "Who to go for first. Weakest finishes people off, and a kill pays five hits instead of one.",
	["Silent"] = "Never turns you. Only hits whoever you are already facing.",
	["Auto Face"] = "Turns you toward whoever you are fighting. Off leaves your view exactly where you put it.",
	["Face Speed"] = "How fast the camera swings onto someone while you are in shiftlock. Lower is a calm sweep, higher keeps up better. Out of shiftlock you turn instantly, since nothing is moving your view.",
	["Auto Dodge"] = "Goes over the top of an attack the moment someone throws one at you, then drops back down.",
	["Auto Hop"] = "Leaves for a better server once this one has emptied out.",
	["Hop When Below"] = "How few people have to be left before it goes looking for somewhere else.",
	["Pick Server By"] = "What makes a server worth moving to. More people is more to farm, lower ping is a smoother game.",
	["Highest Ping"] = "Servers slower than this are skipped, however full they are.",
	["Hop Now"] = "Goes to the best server it can find, right now.",
	["Dodge Height"] = "How far above their attack to sit. More is safer, less keeps you close enough to hit back.",
	["Ignore Star Mode"] = "Skips players glowing in star mode. Nothing can hurt them anyway.",
	["Swing Delay"] = "A pause between punches. Zero swings as fast as the game allows.",
	["Auto Skills"] = "Faces your target and uses whichever ability is ready and can actually reach them.",
	["Skill Choice"] = "Which one to use when more than one is ready. Hardest goes for the most damage.",
	["Use Dashes and Buffs"] = "Lets it use dashes and buffs too. Those hit nobody, so left on it fires them constantly at nothing.",
	["Skill Delay"] = "How long to wait between one ability and the next.",
	["Slots"] = "Which ability keys it is allowed to press.",
	["Bypass Cooldown"] = "Frees up your own ability keys. Movement abilities go through; anything that has to damage someone will not.",
	["Force Cast"] = "Fires the ability below directly, ignoring cooldown and everything else. The loudest thing on this tab.",
	["Skill"] = "Pick one of your abilities to look at.",
	["Cast"] = "Uses the ability picked above, right now.",
	["Auto Farm"] = "Goes to the nearest player and punches them until they drop.",
	["Approach"] = "How to get to them. Fly goes through walls, teleport is quickest and most obvious, walk is the quietest.",
	["Approach Speed"] = "How fast it closes the gap.",
	["Keep Distance"] = "How far away to stand while fighting. Their punch is shorter than yours, so near the top of this slider they cannot reach you back.",
	["Auto Deploy"] = "Puts you back in the arena whenever you end up in the lobby.",
	["Leave When Hurt"] = "Goes back to the lobby before you die, so the streak survives.",
	["Health Floor"] = "The health that counts as hurt.",
	["Deploy Now"] = "Takes you into the arena.",
	["Back to Lobby"] = "Leaves the arena. The game refuses while you are still in a fight.",
	["Extend Hitbox"] = "Makes your own punch reach further. Nothing automatic, you still swing yourself.",
	["Punch Reach"] = "How far that punch goes. The slider stops where the game stops letting hits count.",
	["Show Punch Reach"] = "Draws a box showing exactly what a punch covers.",
	["Punch Reach Colour"] = "The colour of that box, and how see-through it is.",
	["Ability"] = "Pick any ability your hits have unlocked. Choosing one tells you how far its best move reaches.",
	["Equip"] = "Puts on the ability picked above. It only works from the lobby, so it takes you there and back.",
	["Equip Automatically"] = "Swaps your ability on its own, between rounds.",
	["Prefer"] = "Longest Reach picks whichever ability hits from furthest away.",
	["Player"] = "Pick somebody to go after.",
	["Attack This Player"] = "Ignores everyone else and goes for the player picked above.",
	["ESP"] = "Shows players through walls, coloured by their ability.",
	["Only Deployed Players"] = "Hides everyone still standing in the lobby.",
	["Show Ability"] = "Adds the ability name to each player.",
	["Show Health"] = "Adds current health to each player.",
	["Fill"] = "How solid the outlines look.",
	["Max Distance"] = "Stops drawing names past this far away.",
	["Tracers"] = "Draws a line from you to every player, through walls.",
	["Text Size"] = "How big the names are.",
	["Fullbright"] = "Brightens the whole map and removes the shadows.",
	["Walk Speed"] = "Run faster. The game keeps trying to slow you back down, so this reapplies itself.",
	["Speed"] = "How fast you run. 16 is normal.",
	["Higher Jumps"] = "Jump further off the ground.",
	["Jump Height"] = "How high you jump. 7 is normal here.",
	["Infinite Jump"] = "Jump again in mid air, as many times as you like.",
	["Anti Void"] = "Catches you when you are about to land on something that kills you, or on nothing at all. Ordinary jumps are left alone.",
	["Fly"] = "WASD to move, space up, control down. Nothing can knock you around while it is on.",
	["Fly Speed"] = "How fast flying moves you.",
	["Anti AFK"] = "Stops the game kicking you for standing still.",
	["Stand Up"] = "Puts you back on your feet if something left you lying down.",
	["Rejoin"] = "Drops you into a fresh copy of this server.",
	["FPS Boost"] = "Drops the graphics and turns off shadows, effects and the frosted panel behind this menu. Worth about nine frames.",
	["Everything Off"] = "Panic switch. Turns off every toggle at once.",
}

function Module.Build(ctx)
	local core, Window, tabGroup = ctx.core, ctx.Window, ctx.TabGroup
	local F = core.Flags

	-- Aiming and dodging belong to whatever is currently driving, not to one
	-- switch somewhere else. The aura, the farm and a named target are three
	-- different jobs and he wants them set separately, so each carries its own
	-- pair and these two answer for whichever one has the wheel right now.
	--
	-- Order matters: a named target beats the farm, and the farm beats the
	-- aura, which is the same order the targeting itself uses.
	local function facingOn()
		if F.silent then
			return false
		end
		if F.forceTarget then
			return F.targetFace ~= false
		end
		if F.farm then
			return F.farmFace ~= false
		end
		return F.autoFace ~= false
	end

	-- Dodging only exists while something else is flying you, so unlike facing
	-- there is no aura case. It used to be one flag on the Combat tab, which is
	-- why it kept going off for people who had never turned it on there.
	local function dodgeOn()
		if F.forceTarget then
			return F.targetDodge == true
		end
		if F.farm then
			return F.farmDodge == true
		end
		return false
	end

	-- Per run, so a tip can describe what a control is currently set to instead
	-- of repeating one option forever.
	local tips = table.clone(Module.Tips)
	tips["Target"] = function()
		local mode = F.targetMode or "Weakest"
		if mode == "Closest" then
			return "Goes for whoever is nearest, which is quickest but rarely finishes anyone."
		elseif mode == "Crosshair" then
			return "Goes for whoever you are looking at."
		end
		return "Goes for whoever is closest to dying. A kill is worth five hits."
	end

	----------------------------------------------------------------------------
	-- the game's own modules
	----------------------------------------------------------------------------

	local Files = ReplicatedStorage:WaitForChild("Files")
	local Client = Files:WaitForChild("Client")
	local Shared = Files:WaitForChild("Shared")
	local Controllers = Client:WaitForChild("Controllers")

	local CombatController = require(Controllers:WaitForChild("CombatController"))
	local CharacterController = require(Controllers:WaitForChild("CharacterController"))
	local AbilityController = require(Controllers:WaitForChild("AbilityController"))
	local DataController = require(Controllers:WaitForChild("DataController"))
	local AbilityManager = require(Shared:WaitForChild("Managers"):WaitForChild("AbilityManager"))
	local CombatUtility = require(Shared:WaitForChild("Utility"):WaitForChild("CombatUtility"))
	local CharacterUtility = require(Shared:WaitForChild("Utility"):WaitForChild("CharacterUtility"))
	local Jolt = require(Shared:WaitForChild("Components"):WaitForChild("Jolt"))

	local SetAbility = Jolt.Client("SetAbility")

	----------------------------------------------------------------------------
	-- helpers
	----------------------------------------------------------------------------

	local function deployed()
		local char = core:Character()
		return char ~= nil and char:GetAttribute("Deployed") == true
	end

	local function abilityColour(name)
		local ability = name and AbilityManager._Abilities[name]
		return ability and ability.Color or Color3.fromRGB(220, 220, 220)
	end

	-- A body that has just been moved is not somewhere worth flying to.
	--
	-- He described this exactly: target someone, they die, and while they are
	-- being put back in the arena there is a window where their position says
	-- lobby but the game still calls them deployed, so the farm crosses the map
	-- and comes straight back. Measured in a fifteen player server and it is
	-- worse than a window - one player jumped 689 studs, then 442 two seconds
	-- later, then 67 - and `Deployed` stayed true through all of it.
	--
	-- Waiting on the deploy flag settling down does not work: those same
	-- players had been deployed for nine, thirteen and twenty-nine seconds when
	-- they jumped. **The jump itself is the only honest signal**, so this
	-- watches for one and gives them a moment to arrive before anyone chases
	-- them. A hundred and twenty studs a second is the fastest anything here
	-- travels, and this is sampled twenty times a second, so six studs a tick
	-- is normal and sixty is a teleport.
	local SETTLE_JUMP = 60
	local SETTLE_WAIT = 0.75
	local settled = {}

	local function noteMovement()
		local now = os.clock()
		for _, model in ipairs(CollectionService:GetTagged("Character")) do
			local root = model:FindFirstChild("HumanoidRootPart")
			if root then
				local entry = settled[model]
				if not entry then
					settled[model] = { at = root.Position, since = now, seen = now }
				else
					-- Only compare against a reading that is actually recent.
					-- After the loop has been idle the last position is stale,
					-- and an honest walk across the arena would read as a
					-- teleport.
					if now - entry.seen < 0.4 and (root.Position - entry.at).Magnitude > SETTLE_JUMP then
						entry.since = now
					end
					entry.at, entry.seen = root.Position, now
				end
			end
		end
		for model in pairs(settled) do
			if not model.Parent then
				settled[model] = nil
			end
		end
	end

	local function inPlace(model)
		local entry = settled[model]
		return entry ~= nil and (os.clock() - entry.since) >= SETTLE_WAIT
	end

	-- Somebody who has been knocked off the map is not a target, they are a
	-- hole in the ground with a name on it.
	--
	-- A tester found this: knock the player you are hunting into the void and
	-- the farm follows them down, because their root still reports a position
	-- and the chase happily flies to it. Anti void would catch the fall and the
	-- chase would immediately fly back into it, so sometimes it saved him and
	-- sometimes he died. Three things were wrong and this is the first of them:
	-- **nothing should ever chase a position below the floor.**
	local VOID_DROP = 40

	local function overTheEdge(model)
		local theirs = model:FindFirstChild("HumanoidRootPart")
		if not theirs then
			return true
		end
		local floor = core:SafeHeight()
		if not floor then
			-- Nothing known to compare against yet, so fall back to our own
			-- height, which is at least somewhere the game let us be.
			local mine = core:Root()
			floor = mine and mine.Position.Y or nil
		end
		if not floor then
			return false
		end
		return theirs.Position.Y < floor - VOID_DROP
	end

	local function targets()
		local out = {}
		local mine = core:Character()
		for _, model in ipairs(CollectionService:GetTagged("Character")) do
			if model ~= mine and model.Parent and model:GetAttribute("Deployed") and inPlace(model) then
				if not (F.ignoreStar and model:GetAttribute("StarMode")) and not overTheEdge(model) then
					out[#out + 1] = model
				end
			end
		end
		return out
	end

	-- CharacterCanAttack wants the combo data for the swing it is being asked
	-- about. Handing it an empty table, which is what this did, either threw or
	-- came back nil, so the gate said no almost every time and the aura only
	-- ever got through on the ticks where it happened to say nothing at all.
	-- The game's own M1 builds the table first and then asks; so does this.
	local function canPunch()
		local char = core:Character()
		if not char then
			return false
		end
		local gotData, data = pcall(CombatUtility.GetComboData, char)
		if not gotData or not data then
			return false
		end
		local ok, allowed = pcall(CombatUtility.CharacterCanAttack, char, { comboData = data })
		return ok and allowed == true
	end

	local function punch()
		pcall(function()
			CombatController:UseM1()
		end)
	end

	local function unlockTable()
		local list = {}
		for name, ability in pairs(AbilityManager._Abilities) do
			if type(ability) == "table" and ability.HitsNeeded then
				list[#list + 1] = { name = name, hits = ability.HitsNeeded }
			end
		end
		table.sort(list, function(a, b)
			return a.hits < b.hits
		end)
		return list
	end

	-- The reach that actually matters in this game.
	--
	-- The M1 is capped by the server at 11.6 studs and nothing changes
	-- that. Skills are not: each one carries its own hitbox in its own
	-- definition, the server has the same definition, so a skill built to reach
	-- 40 studs reaches 40 studs and the server agrees. That is where long range
	-- lives, and it is a matter of which ability is equipped rather than
	-- anything the hub can force.
	--
	-- Measured across every ability in the game: Beam and Space Outlaw reach 40,
	-- The Hero 31, Lightning 30, Wind and Strongest Sorcerer and Vampire 28,
	-- Rock 27, down to Archer and Knight at 15 and the projectile ones at 5.
	-- One Punch reaches 800 with 100 damage, which one shots anyone in the
	-- arena, but it is a gamepass and so are Space Outlaw, Strongest Sorcerer
	-- and Heavenly.
	local function skillReach(definition)
		if not definition or not definition.HitboxSize then
			return nil
		end
		local offset = definition.HitboxOffset and math.abs(definition.HitboxOffset.Position.Z) or 0
		return offset + definition.HitboxSize.Z / 2
	end

	local function abilityReach(name)
		local ability = AbilityManager._Abilities[name]
		if type(ability) ~= "table" or type(ability.Order) ~= "table" then
			return 0, nil
		end
		local best, bestName = 0, nil
		for _, skillName in ipairs(ability.Order) do
			local skill = AbilityManager._Skills[skillName]
			local definition = skill and skill.Definition
			if definition then
				local variants = {}
				if definition.Type ~= "Variation" and type(definition.Variations) == "table" then
					for _, variant in pairs(definition.Variations) do
						variants[#variants + 1] = variant
					end
				else
					variants[1] = definition
				end
				for _, variant in ipairs(variants) do
					local reach = skillReach(variant)
					if reach and reach > best then
						best, bestName = reach, skillName
					end
				end
			end
		end
		return best, bestName
	end

	local function hits()
		local ok, value = pcall(function()
			return DataController:GetHits()
		end)
		return ok and value or 0
	end

	----------------------------------------------------------------------------
	-- tabs
	----------------------------------------------------------------------------

	local tabs = {
		Combat = tabGroup:Tab({ Name = "Combat", Image = "rbxassetid://7510979485" }),
		Farm = tabGroup:Tab({ Name = "Farm", Image = "rbxassetid://7549521656" }),
		Abilities = tabGroup:Tab({ Name = "Abilities", Image = "rbxassetid://7510980474" }),
		Visuals = tabGroup:Tab({ Name = "Visuals", Image = "rbxassetid://7541894862" }),
		Movement = tabGroup:Tab({ Name = "Movement", Image = "rbxassetid://7646573201" }),
		Player = tabGroup:Tab({ Name = "Player", Image = "rbxassetid://7549504320" }),
	}

	local combatLeft = tabs.Combat:Section({ Side = "Left" })
	local combatRight = tabs.Combat:Section({ Side = "Right" })
	local farmLeft = tabs.Farm:Section({ Side = "Left" })
	local farmRight = tabs.Farm:Section({ Side = "Right" })
	-- Under Staying Alive, because leaving a server that has emptied out is the
	-- same kind of decision as leaving the arena when you are hurt: it is about
	-- keeping the farm fed rather than about how it fights.
	local farmServer = tabs.Farm:Section({ Side = "Right" })
	local abilityLeft = tabs.Abilities:Section({ Side = "Left" })
	local abilityTest = tabs.Abilities:Section({ Side = "Right" })
	-- Third panel on the Combat tab rather than a tab of its own. Plenty of
	-- people want a wider punch and nothing else, but it still belongs to combat.
	local hitboxLeft = tabs.Combat:Section({ Side = "Right" })
	local visualLeft = tabs.Visuals:Section({ Side = "Left" })
	local visualDetail = tabs.Visuals:Section({ Side = "Right" })
	local visualRight = tabs.Visuals:Section({ Side = "Right" })
	local moveLeft = tabs.Movement:Section({ Side = "Left" })
	local moveJump = tabs.Movement:Section({ Side = "Left" })
	local moveRight = tabs.Movement:Section({ Side = "Right" })
	local moveSafety = tabs.Movement:Section({ Side = "Right" })
	local playerLeft = tabs.Player:Section({ Side = "Left" })
	local playerRight = tabs.Player:Section({ Side = "Right" })

	-- A keybind belongs under the thing it fires, not in a list somewhere else
	-- that makes you work out which toggle it meant. Maclib has no room for a
	-- key chip inside a row, so directly underneath is as close as it gets.
	core.Keybinds = core.Keybinds or {}

	local function bindTo(section, element, flag, label, default)
		local name = label .. " Key"
		-- Everything starts unbound. `default` is kept only so the suggested key
		-- is documented next to each feature.
		local bind = section:Keybind({
			Name = name,
			Callback = function()
				if F.keybinds == false or core.SuppressKeybinds then
					return
				end
				F[flag] = not F[flag]
				pcall(function()
					element:UpdateState(F[flag])
				end)
				core:Notify(Module.Name, label .. (F[flag] and " on" or " off"), 2)
			end,
			onBinded = function(key)
				core:Notify(
					Module.Name,
					("%s is now %s. Hold X over it for two seconds to clear it."):format(label, tostring(key.Name)),
					5
				)
			end,
		}, flag .. "Key")

		-- The interface layer wires the hold to clear behaviour and needs the
		-- element itself to call Unbind on.
		core.Keybinds[name] = bind
		return bind
	end

	----------------------------------------------------------------------------
	-- combat
	----------------------------------------------------------------------------

	combatLeft:Header({ Text = "Aura" })

	local auraToggle = combatLeft:Toggle({
		Name = "Kill Aura",
		Default = false,
		Callback = function(state)
			F.aura = state
		end,
	}, "aura")

	bindTo(combatLeft, auraToggle, "aura", "Kill Aura", Enum.KeyCode.Z)

	-- Measured against a live server, not assumed. See SERVER_CEILING below.
	combatLeft:Slider({
		Name = "Reach",
		Default = 11.5,
		Minimum = 5,
		Maximum = 11.5,
		DisplayMethod = "Value",
		Precision = 1,
		Callback = function(value)
			F.auraRange = value
		end,
	}, "auraRange")

	combatLeft:Toggle({
		Name = "Show Reach",
		Default = false,
		Callback = function(state)
			F.showAura = state
		end,
	}, "showAura")

	-- One control for both, because Maclib's picker carries an alpha and asking
	-- for a colour and a transparency separately would be two rows saying the
	-- same thing.
	combatLeft:Colorpicker({
		Name = "Reach Colour",
		Default = Color3.fromRGB(120, 200, 255),
		Alpha = 0.85,
		Callback = function(colour, alpha)
			F.auraColour = colour
			F.auraAlpha = alpha
		end,
	}, "auraColour")

	combatLeft:Dropdown({
		Name = "Target",
		Multi = false,
		Required = true,
		Options = { "Weakest", "Closest", "Crosshair" },
		Default = 1,
		Callback = function(value)
			F.targetMode = value
		end,
	}, "targetMode")

	combatLeft:Slider({
		Name = "Swing Delay",
		Default = 0,
		Minimum = 0,
		Maximum = 1,
		DisplayMethod = "Value",
		Precision = 2,
		Callback = function(value)
			F.swingDelay = value
		end,
	}, "swingDelay")

	combatLeft:Toggle({
		Name = "Silent",
		Default = false,
		Callback = function(state)
			F.silent = state
		end,
	}, "silent")

	combatLeft:Toggle({
		Name = "Ignore Star Mode",
		Default = true,
		Callback = function(state)
			F.ignoreStar = state
		end,
	}, "ignoreStar")

	combatLeft:Header({ Text = "Aiming" })

	-- The aura's own. The farm and Player Target each carry theirs, on their
	-- own panels, because wanting to be turned while a farm flies you is a
	-- different question from wanting it while you are playing yourself.
	combatLeft:Toggle({
		Name = "Auto Face",
		Default = true,
		Callback = function(state)
			F.autoFace = state
		end,
	}, "autoFace")

	-- One speed for all three, since it describes the camera rather than the
	-- mode: three identical sliders would be three places to look for the same
	-- number.
	combatLeft:Slider({
		Name = "Face Speed",
		Default = 420,
		Minimum = 120,
		Maximum = 900,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.faceSpeed = value
		end,
	}, "faceSpeed")

	-- Auto Dodge used to sit here. It never applied to the aura - the aura does
	-- not move you anywhere, so there is nothing to climb with - and having it
	-- on this tab meant it fired for people whose only switch on the Farm tab
	-- was the farm itself. It now lives under the two things that actually fly
	-- you around, one copy each.

	combatRight:Header({ Text = "Skills" })

	combatRight:Toggle({
		Name = "Auto Skills",
		Default = false,
		Callback = function(state)
			F.autoSkill = state
		end,
	}, "autoSkill")

	combatRight:Slider({
		Name = "Skill Delay",
		Default = 0.6,
		Minimum = 0.2,
		Maximum = 3,
		DisplayMethod = "Value",
		Precision = 1,
		Callback = function(value)
			F.skillDelay = value
		end,
	}, "skillDelay")

	combatRight:Dropdown({
		Name = "Slots",
		Multi = true,
		Required = false,
		Options = { "Q", "E", "R", "F" },
		Default = { "Q", "E", "R", "F" },
		Callback = function(value)
			F.skillSlots = value
		end,
	}, "skillSlots")

	-- Which of the skills that can reach actually gets thrown. Firing whatever
	-- sits in the first slot means a 40 stud skill goes off in someone's face
	-- while the one that would have finished them sits on cooldown.
	combatRight:Dropdown({
		Name = "Skill Choice",
		Multi = false,
		Required = true,
		Options = { "Hardest That Reaches", "Longest Reach", "Slot Order" },
		Default = 1,
		Callback = function(value)
			F.skillChoice = value
		end,
	}, "skillChoice")

	-- Dashes and buffs carry no hitbox, so nothing stops them being thrown at
	-- any range, and left alone they burn on cooldown doing nothing.
	combatRight:Toggle({
		Name = "Use Dashes and Buffs",
		Default = false,
		Callback = function(state)
			F.skillUtility = state
		end,
	}, "skillUtility")

	----------------------------------------------------------------------------
	-- farm
	----------------------------------------------------------------------------

	-- The status paragraph that used to sit here is gone, along with the ones on
	-- Abilities and Player. Tabs hold controls; the figures live on the
	-- dashboard behind the profile card, which is one place instead of four.

	farmLeft:Header({ Text = "Auto Farm" })

	-- Filled in further down, on the right hand panel. Turning the farm on
	-- reaches back to it.
	local deployToggle

	local farmToggle = farmLeft:Toggle({
		Name = "Auto Farm",
		Default = false,
		Callback = function(state)
			F.farm = state
			-- Recovery comes with the farm rather than being three more switches
			-- to find after it has already left you pinned on a rock.
			F.unstuck = state
			F.recover = state
			-- And so does getting back in. Measured: it died 22 seconds into a
			-- run and then sat in the lobby doing nothing for the rest of it,
			-- because Auto Deploy is a separate switch on the other side of the
			-- tab. Turned on, never turned off, so anyone who wants it off can
			-- still have it off.
			if state and not F.autoDeploy then
				F.autoDeploy = true
				if deployToggle then
					pcall(function()
						deployToggle:UpdateState(true)
					end)
				end
			end
		end,
	}, "farm")

	bindTo(farmLeft, farmToggle, "farm", "Auto Farm", Enum.KeyCode.X)

	farmLeft:Dropdown({
		Name = "Approach",
		Multi = false,
		Required = true,
		Options = { "Fly", "Teleport", "Walk" },
		Default = 1,
		Callback = function(value)
			F.approach = value
		end,
	}, "approach")

	farmLeft:Slider({
		Name = "Approach Speed",
		Default = 120,
		Minimum = 16,
		Maximum = 350,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.farmSpeed = value
		end,
	}, "farmSpeed")

	-- The gap the farm fights from, and the one number that decides whether it
	-- gets interrupted. Their punch reaches 8.1 studs and the server now takes
	-- ours out to 11.6, measured, so a farm sitting at 11 hits someone who is
	-- three studs short of touching it back. That was 9 while the ceiling was
	-- thought to be 10.5, which left under a stud of margin and is why it got
	-- traded with. Past 11.5 nothing lands at all, so the slider stops there.
	farmLeft:Slider({
		Name = "Keep Distance",
		Default = 11,
		Minimum = 2,
		Maximum = 11.5,
		DisplayMethod = "Value",
		Precision = 1,
		Callback = function(value)
			F.standoff = value
		end,
	}, "standoff")

	farmLeft:Toggle({
		Name = "Auto Face",
		Default = true,
		Callback = function(state)
			F.farmFace = state
		end,
	}, "farmFace")

	farmLeft:Toggle({
		Name = "Auto Dodge",
		Default = false,
		Callback = function(state)
			F.farmDodge = state
		end,
	}, "farmDodge")

	-- Shared with Player Target below it. It is a height in studs, not a
	-- preference about how to fight, so there is only ever one of it.
	farmLeft:Slider({
		Name = "Dodge Height",
		Default = 8,
		Minimum = 2,
		Maximum = 20,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.dodgeClearance = value
		end,
	}, "dodgeClearance")

	-- "When it goes wrong" is gone. Getting unstuck and redeploying when
	-- stranded are not things anyone wants to opt into after the farm has
	-- already left them pinned on a rock, so the farm turns both on itself.

	farmRight:Header({ Text = "Staying Alive" })

	deployToggle = farmRight:Toggle({
		Name = "Auto Deploy",
		Default = false,
		Callback = function(state)
			F.autoDeploy = state
		end,
	}, "autoDeploy")

	farmRight:Toggle({
		Name = "Leave When Hurt",
		Default = false,
		Callback = function(state)
			F.retreat = state
		end,
	}, "retreat")

	farmRight:Slider({
		Name = "Health Floor",
		Default = 30,
		Minimum = 5,
		Maximum = 90,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.retreatAt = value
		end,
	}, "retreatAt")

	farmRight:Divider()

	farmRight:Button({
		Name = "Deploy Now",
		Callback = function()
			task.spawn(function()
				pcall(CharacterController.Deploy)
			end)
		end,
	})

	farmRight:Button({
		Name = "Back to Lobby",
		Callback = function()
			task.spawn(function()
				pcall(CharacterController.ToLobby)
			end)
		end,
	})

	----------------------------------------------------------------------------
	-- server
	----------------------------------------------------------------------------

	-- A farm in a server with four people in it is a farm doing nothing, and
	-- this game's servers empty out steadily as rounds end. Sorted descending
	-- because that returns the hundred fullest servers: ascending returns a
	-- hundred servers with one person in them, which is the opposite of what
	-- anybody wants and is what the old Server Hop button was reading.
	--
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

	farmServer:Header({ Text = "Server" })

	farmServer:Toggle({
		Name = "Auto Hop",
		Default = false,
		Callback = function(state)
			F.autoHop = state
		end,
	}, "autoHop")

	farmServer:Slider({
		Name = "Hop When Below",
		Default = 6,
		Minimum = 2,
		Maximum = 18,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.hopBelow = value
		end,
	}, "hopBelow")

	farmServer:Dropdown({
		Name = "Pick Server By",
		Multi = false,
		Required = true,
		Options = { "Full and Fast", "Most Players", "Lowest Ping" },
		Default = 1,
		Callback = function(value)
			F.hopPick = value
		end,
	}, "hopPick")

	farmServer:Slider({
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

	farmServer:Divider()

	farmServer:Button({
		Name = "Hop Now",
		Callback = function()
			hopNow("Changing server")
		end,
	})

	-- Everyone in the server, lobby included, not everyone in the arena. A
	-- server whose population has fallen to five is a server that is finished,
	-- however many of them happen to be deployed this second.
	local quietSince = nil
	local arrived = core.ArrivedAt or os.clock()

	core:Loop("serverHop", 3, function()
		if not F.autoHop or hopping then
			quietSince = nil
			return
		end
		-- Players replicate in over the first second or two of a join, so a
		-- server you have only just arrived in always looks empty. Without this
		-- the first hop starts a chain that never stops, and every link in it
		-- costs a loading screen.
		if os.clock() - arrived < 20 then
			quietSince = nil
			return
		end
		local here = #Players:GetPlayers()
		if here >= (tonumber(F.hopBelow) or 6) then
			quietSince = nil
			return
		end
		-- Held for six seconds rather than acted on at once. A round ending
		-- does not change the population, but a handful of people leaving
		-- together at the end of one does, and they are usually replaced.
		quietSince = quietSince or os.clock()
		if os.clock() - quietSince < 6 then
			return
		end
		quietSince = nil
		hopNow(("Only %d left here"):format(here))
	end)

	----------------------------------------------------------------------------
	-- abilities
	----------------------------------------------------------------------------

	-- Every other panel in the hub opens with a header. This one did not, so it
	-- was the single untitled panel in the window.
	abilityLeft:Header({ Text = "Your Abilities" })

	local names = {}
	for _, entry in ipairs(unlockTable()) do
		names[#names + 1] = entry.name
	end
	for name, ability in pairs(AbilityManager._Abilities) do
		if type(ability) == "table" and not ability.HitsNeeded then
			names[#names + 1] = name
		end
	end

	local chosen = names[1]
	abilityLeft:Dropdown({
		Name = "Ability",
		Search = true,
		Multi = false,
		Required = true,
		Options = names,
		Default = 1,
		Callback = function(value)
			chosen = value
			local reach, skill = abilityReach(value)
			if reach > 0 then
				core:Notify(value, ("%s reaches %d studs"):format(tostring(skill), math.floor(reach)), 4)
			end
		end,
	}, "abilityChoice")

	-- This was a panel of its own on the right, holding one toggle, opposite a
	-- left panel holding one dropdown. Two near empty panels facing each other
	-- is the lopsided look he flagged, and equipping automatically belongs with
	-- equipping by hand anyway.
	abilityLeft:Toggle({
		Name = "Equip Automatically",
		Default = false,
		Callback = function(state)
			F.autoEquip = state
		end,
	}, "autoEquip")

	abilityLeft:Dropdown({
		Name = "Prefer",
		Multi = false,
		Required = true,
		Options = { "Longest Reach", "Newest Unlocked" },
		Default = 1,
		Callback = function(value)
			F.equipPrefer = value
		end,
	}, "equipPrefer")

	-- SetAbility is ignored outright while deployed. Not refused with a message,
	-- just dropped, which is why pressing Equip mid match appeared to do nothing
	-- at all. Verified both ways: deployed, asking for Wind and for Beam both
	-- left the ability on Archer; from the lobby both took immediately. So the
	-- button makes the trip itself rather than failing quietly.
	local function equipAbility(name, andRedeploy)
		if not name then
			return
		end
		task.spawn(function()
			local wasDeployed = deployed()
			if wasDeployed then
				core:Notify(Module.Name, "Changing ability needs the lobby, going there and back", 4)
				pcall(CharacterController.ToLobby)
				local until_ = os.clock() + 6
				while deployed() and os.clock() < until_ do
					task.wait(0.2)
				end
				task.wait(0.5)
			end

			SetAbility:Fire(name)

			local until_ = os.clock() + 6
			while os.clock() < until_ do
				local ok, current = pcall(function()
					return DataController:GetCurrentAbility()
				end)
				if ok and current == name then
					break
				end
				task.wait(0.3)
			end

			local reach, skill = abilityReach(name)
			core:Notify(
				Module.Name,
				reach > 0 and ("%s equipped. %s reaches %d studs."):format(name, tostring(skill), math.floor(reach))
					or (name .. " equipped"),
				4
			)

			if wasDeployed and andRedeploy ~= false then
				task.wait(0.5)
				pcall(CharacterController.Deploy)
			end
		end)
	end

	abilityLeft:Button({
		Name = "Equip",
		Callback = function()
			equipAbility(chosen)
		end,
	})


	----------------------------------------------------------------------------
	-- skill testing
	----------------------------------------------------------------------------
	--
	-- Read out of AbilityManager.StartSkill rather than guessed at. It refuses a
	-- cast unless the character is deployed, not in star mode, not mid dash,
	-- alive, off cooldown, in an allowed state, and holding enough accumulated
	-- hits. Every number shown below is the game's own, and the two bypasses
	-- each skip one named gate rather than being a vague "no cooldown" switch.

	abilityTest:Header({ Text = "Skill Testing" })

	-- A skill's real definition hides one level down unless it is already a
	-- variation, and the cooldown is keyed on CooldownName when it has one.
	local function definitionOf(skill, char)
		if type(skill) ~= "table" or type(skill.Definition) ~= "table" then
			return nil
		end
		if skill.Definition.Type ~= "Variation" and type(skill.Definition.Variations) == "table" then
			local ok, variation = pcall(function()
				return skill:GetVariation(char)
			end)
			if ok and variation then
				return skill.Definition.Variations[variation]
			end
			return nil
		end
		return skill.Definition
	end

	----------------------------------------------------------------------------
	-- going over the top of what they throw
	----------------------------------------------------------------------------

	-- Every skill in this game is a box, and a box has a height. Read off a live
	-- server: Shadow Slam and Retro Uppercut are 25 tall, Super Punch and
	-- Phychic Slam 14, Punch Barrage 9, and most of the thrown things 3. So
	-- climbing over one is a real move and a cheap one - half the height, plus
	-- however much clearance he asks for on top.
	--
	-- One exception, and it is why this checks rather than trusting the number:
	-- One Punch's One Shot Punch is a thousand studs tall. Nothing dodges that
	-- by climbing, so anything absurd is left out instead of being chased into
	-- orbit.
	local DODGE_CEILING = 60

	local function dodgeShape(model)
		local ok, ability = pcall(AbilityManager.GetAbility, model)
		if not ok or type(ability) ~= "table" or type(ability.Order) ~= "table" then
			return nil
		end
		local gotSkills, skills = pcall(AbilityManager.GetSkills, ability.Name, model)
		if not gotSkills or type(skills) ~= "table" then
			return nil
		end

		-- Which of their three it was is not knowable from outside, so this
		-- clears the tallest one they own. Being too high costs a second of
		-- farming; being too low costs the hit.
		local tallest, longest, furthest = 0, 0, 0
		for _, name in ipairs(ability.Order) do
			local definition = skills[name] and definitionOf(skills[name], model)
			local box = definition and definition.HitboxSize
			if typeof(box) == "Vector3" and box.Y > 0 and box.Y <= DODGE_CEILING then
				tallest = math.max(tallest, box.Y)
				longest = math.max(longest, (tonumber(definition.AttackTime) or 0.4) + (tonumber(definition.Endlag) or 0))
				furthest = math.max(furthest, skillReach(definition) or 0)
			end
		end
		if tallest <= 0 then
			return nil
		end
		return tallest / 2, math.clamp(longest, 0.6, 4), furthest
	end

	-- What a cast looks like from the outside, which took some finding.
	--
	-- All the obvious routes are dead ends and each was measured rather than
	-- assumed: another player's State never leaves Free, Combo or Ragdoll on
	-- this client, and their Timestamps table is empty here even while they are
	-- visibly mid skill. Forty seconds of a fifteen player server produced
	-- exactly one usable signal. **Animations replicate**, and a skill plays
	-- one.
	--
	-- Telling a skill animation from an ordinary punch is the hard half, and
	-- there is no list to look it up in: the ids live inside each skill module
	-- as strings rather than as Animation instances anywhere in the tree.
	--
	-- So it was measured. Nine hundred animation events off a thirteen player
	-- server, recorded with their lengths and then replayed against every rule
	-- worth trying. **Length separates them almost by itself**: of 902 events,
	-- 576 were between half a second and one second - that is the M1 combo, and
	-- there are several of them because a combo is several animations - while
	-- only 41 ran past a second and a half.
	--
	--   length alone, no other rule ....... 25.8 casts a player a minute
	--   plus "has not repeated in 8s" ..... 16.1, still nonsense
	--   plus "runs a second or longer" .... 6.0 a player a minute
	--
	-- Six is a believable number for two skills on ten second cooldowns. The
	-- first version of this shipped with only the repeat rule and would have
	-- dodged 359 times a minute, which is worth writing down: **the obvious
	-- discriminator was the wrong one, and one minute of recording said so.**
	--
	-- The repeat rule still earns its place on top of the length rule - it is
	-- what catches a long hit reaction or a getup that an ability plays often.
	local CAST_MIN_LENGTH = 1.0
	local REPEAT_WINDOW = 8
	local castSeen, castOrdinary = {}, {}
	local dodgeUntil, dodgeTo = 0, nil

	local function beginDodge(model)
		local mine, theirs = core:Root(), model:FindFirstChild("HumanoidRootPart")
		if not mine or not theirs then
			return
		end
		local half, hold = dodgeShape(model)
		if not half then
			return
		end
		local want = theirs.Position.Y + half + (tonumber(F.dodgeClearance) or 8)
		if mine.Position.Y >= want then
			return
		end
		dodgeTo, dodgeUntil = want, os.clock() + hold
	end

	local function watchCasts(model)
		if model == core:Character() then
			return
		end
		task.spawn(function()
			local hum = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 5)
			local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5))
			if not animator then
				return
			end
			core:Connect(animator.AnimationPlayed, function(track)
				if not dodgeOn() then
					return
				end
				-- Already over the top of something. Let it finish.
				if os.clock() < dodgeUntil then
					return
				end

				local id = track.Animation and track.Animation.AnimationId
				-- The core walk, run and jump come through as the old
				-- roblox.com asset urls; everything the game itself loads is an
				-- rbxassetid. Free filtering.
				if type(id) ~= "string" or not id:match("^rbxassetid://") then
					return
				end
				-- The line that does most of the work. A length of zero means
				-- the asset has not loaded yet rather than that it is short, so
				-- it is skipped too - the next play of it will have a length.
				if (track.Length or 0) < CAST_MIN_LENGTH then
					return
				end

				local seen = castSeen[model]
				if not seen then
					seen = {}
					castSeen[model] = seen
				end
				local ordinary = castOrdinary[model]
				if not ordinary then
					ordinary = {}
					castOrdinary[model] = ordinary
				end

				local now = os.clock()
				local before = seen[id]
				seen[id] = now
				if before and now - before < REPEAT_WINDOW then
					ordinary[id] = true
					return
				end
				if ordinary[id] then
					return
				end

				-- Only worth climbing away from someone who can actually reach
				-- you, and how far each of them reaches is knowable rather than
				-- guessable - it is the same hitbox this reads the height from.
				-- A flat forty five studs dodged for people who were never
				-- going to touch us and cost about a third of the farm.
				local theirs = model:FindFirstChild("HumanoidRootPart")
				if not theirs then
					return
				end
				local _, _, furthest = dodgeShape(model)
				if core:DistanceTo(theirs.Position) > (furthest or 20) + 12 then
					return
				end
				beginDodge(model)
			end)
		end)
	end

	for _, model in ipairs(CollectionService:GetTagged("Character")) do
		watchCasts(model)
	end
	core:Connect(CollectionService:GetInstanceAddedSignal("Character"), watchCasts)

	local function equippedSkills()
		local char = core:Character()
		local ability = char and AbilityManager.GetAbility(char)
		if not ability then
			return {}, nil, nil
		end
		local ok, skills = pcall(AbilityManager.GetSkills, ability.Name, char)
		return (ok and type(skills) == "table") and skills or {}, char, ability
	end

	-- Every registered skill in the game, read once at load. A live list that
	-- followed whatever you had equipped meant rewriting the dropdown from a
	-- loop, and this module is not allowed to touch the interface from one: the
	-- engine refuses it with "the current thread cannot access Instance", even
	-- through Maclib's own setters. Nothing here rebuilds a control after load.
	local everySkill = {}
	for name, skill in pairs(AbilityManager._Skills or {}) do
		if type(name) == "string" and type(skill) == "table" then
			everySkill[#everySkill + 1] = name
		end
	end
	table.sort(everySkill)

	local pickedSkill = nil

	-- The details arrive as a notification rather than a panel, for the same
	-- reason. It also reads better: you ask about a skill and it answers.
	local function describe(name)
		local char = core:Character()
		local skill = AbilityManager._Skills[name]
		if not skill then
			return
		end
		local definition = definitionOf(skill, char)
		if not definition then
			core:Notify(name, "Deploy to read this one, its numbers depend on your variation.", 5)
			return
		end

		local states = definition.States
		if type(states) == "table" then
			states = table.concat(states, ", ")
		end

		local lines = { ("Cooldown %s"):format(tostring(definition.Cooldown or "none")) }
		if definition.AbilityType then
			lines[#lines + 1] = ("Type %s"):format(tostring(definition.AbilityType))
		end
		if definition.MaxUsage then
			lines[#lines + 1] = ("%s uses before cooldown"):format(tostring(definition.MaxUsage))
		end
		if definition.DashLength then
			lines[#lines + 1] = ("%s studs"):format(tostring(definition.DashLength))
		end
		if definition.HitsNeeded then
			lines[#lines + 1] = ("costs %s hits"):format(tostring(definition.HitsNeeded))
		end
		if states then
			lines[#lines + 1] = ("needs %s"):format(tostring(states))
		end
		if definition.Cooldown and F.noCooldown then
			lines[#lines + 1] = "the server keeps this one too"
		end

		local description = skill.Description or definition.Description
		core:Notify(
			tostring(definition.DisplayName or definition.Name or name),
			table.concat(lines, "\n") .. (description and ("\n\n" .. description) or ""),
			7
		)
	end

	local skillPicker = abilityTest:Dropdown({
		Name = "Skill",
		Search = true,
		Multi = false,
		Required = false,
		Options = everySkill,
		Callback = function(value)
			pickedSkill = value
			describe(value)
		end,
	}, "testSkill")
	skillPicker.IgnoreConfig = true

	-- Bypass cooldown, and what it can and cannot do.
	--
	-- Cooldowns are kept in a plain Lua table on each side of the wire:
	-- CharacterUtility.GetCharacterData(char).Timestamps. The client checks its
	-- own copy, the server checks the server's, and nothing a client does
	-- reaches the server's. Feeding a forged time does not work either, because
	-- CheckTimestamp clamps anything ahead of workspace:GetServerTimeNow() back
	-- to the real clock.
	--
	-- So this frees the client and nothing else, which is worth having and is
	-- not nothing: a skill whose effect the client produces on its own - a
	-- slide, a dash, anything that only moves you - runs for real. A skill the
	-- server has to spawn or deal damage for gets the animation and no spear,
	-- which is exactly what he saw. That difference is in the tip and in the
	-- notification, because a switch that half works has to say which half.
	abilityTest:Toggle({
		Name = "Bypass Cooldown",
		Default = false,
		Callback = function(state)
			F.noCooldown = state
			if state then
				-- CheckTimestamp is what StartSkill asks before every cast, and
				-- it is also what the normal Q E R F keys go through, so this
				-- frees those too rather than only the button below.
				core:Override(CharacterUtility, "CheckTimestamp", function()
					return true
				end)
				core:Notify(
					Module.Name,
					"Your keys are free. The server keeps its own clock, so movement skills go through and anything that has to spawn or damage will not.",
					8
				)
			else
				core:Restore(CharacterUtility, "CheckTimestamp")
			end
		end,
	}, "noCooldown")

	-- Overriding the check leaves the recorded timestamps in place, so the
	-- game's own cooldown rings stay dark and the hud disagrees with the hub.
	-- Clearing the client's copy is cosmetic in exactly the same way the check
	-- is, and it keeps the two of them telling the same story.
	core:Loop("cooldownWipe", 0.25, function()
		if not F.noCooldown then
			return
		end
		local char = core:Character()
		if not char then
			return
		end
		pcall(function()
			local data = CharacterUtility.GetCharacterData(char)
			if not data or type(data.Timestamps) ~= "table" then
				return
			end
			for key in pairs(data.Timestamps) do
				if type(key) == "string" and key:sub(1, 6) == "SKILL_" then
					data.Timestamps[key] = nil
				end
			end
		end)
	end)

	abilityTest:Toggle({
		Name = "Force Cast",
		Default = false,
		Callback = function(state)
			F.forceCast = state
		end,
	}, "forceCast")

	-- Last in the panel, which is where a button and its chevron belong.
	abilityTest:Button({
		Name = "Cast",
		Callback = function()
			local char = core:Character()
			if not char or not pickedSkill then
				core:Notify(Module.Name, "Pick a skill first", 3)
				return
			end

			-- Force cast goes straight to the definition's own Start, which is
			-- the last thing StartSkill does once every gate has passed, so it
			-- skips all of them: cooldown, state, hit cost, and the requirement
			-- that the skill belong to the ability you are actually holding.
			if F.forceCast then
				local definition = definitionOf(AbilityManager._Skills[pickedSkill], char)
				if not definition or type(definition.Start) ~= "function" then
					core:Notify(Module.Name, "That skill has no Start to call", 4)
					return
				end
				task.spawn(definition.Start, definition, char)
				core:Notify(Module.Name, "Forced " .. tostring(pickedSkill), 3)
				return
			end

			-- The polite path only works for a skill your equipped ability owns,
			-- because that is the table StartSkill looks in.
			local skills = equippedSkills()
			if not skills[pickedSkill] then
				core:Notify(Module.Name, tostring(pickedSkill) .. " is not on your ability. Use force cast.", 5)
				return
			end

			local ok, fired = pcall(AbilityManager.StartSkill, char, pickedSkill)
			core:Notify(
				Module.Name,
				(ok and fired) and ("Cast " .. tostring(pickedSkill))
					or ("The game refused " .. tostring(pickedSkill)),
				3
			)
		end,
	})

	----------------------------------------------------------------------------
	-- hitbox, on its own because plenty of people want this and nothing else
	----------------------------------------------------------------------------

	hitboxLeft:Header({ Text = "Hitbox Extender" })

	local hitboxToggle = hitboxLeft:Toggle({
		Name = "Extend Hitbox",
		Default = false,
		Callback = function(state)
			F.hitbox = state
		end,
	}, "hitbox")

	bindTo(hitboxLeft, hitboxToggle, "hitbox", "Extend Hitbox", Enum.KeyCode.H)

	-- 8.5 rather than 8, because the game's own punch already reaches 8.1 and
	-- anything at or below that does nothing at all. A slider whose first
	-- third is dead is a slider that lies.
	hitboxLeft:Slider({
		Name = "Punch Reach",
		Default = 11.5,
		Minimum = 8.5,
		Maximum = 11.5,
		DisplayMethod = "Value",
		Precision = 1,
		Callback = function(value)
			F.hitboxReach = value
		end,
	}, "hitboxReach")

	hitboxLeft:Toggle({
		Name = "Show Punch Reach",
		Default = false,
		Callback = function(state)
			F.showHitbox = state
		end,
	}, "showHitbox")

	hitboxLeft:Colorpicker({
		Name = "Punch Reach Colour",
		Default = Color3.fromRGB(255, 170, 120),
		Alpha = 0.85,
		Callback = function(colour, alpha)
			F.hitboxColour = colour
			F.hitboxAlpha = alpha
		end,
	}, "hitboxColour")


	----------------------------------------------------------------------------
	-- visuals
	----------------------------------------------------------------------------

	visualLeft:Header({ Text = "Players" })

	local espToggle = visualLeft:Toggle({
		Name = "ESP",
		Default = false,
		Callback = function(state)
			F.esp = state
		end,
	}, "esp")

	bindTo(visualLeft, espToggle, "esp", "ESP", Enum.KeyCode.C)

	visualLeft:Toggle({
		Name = "Only Deployed Players",
		Default = true,
		Callback = function(state)
			F.espDeployedOnly = state
		end,
	}, "espDeployedOnly")

	visualLeft:Toggle({
		Name = "Show Ability",
		Default = true,
		Callback = function(state)
			F.espAbility = state
		end,
	}, "espAbility")

	visualLeft:Toggle({
		Name = "Show Health",
		Default = false,
		Callback = function(state)
			F.espHealth = state
		end,
	}, "espHealth")

	visualLeft:Toggle({
		Name = "Tracers",
		Default = false,
		Callback = function(state)
			F.espTracers = state
		end,
	}, "espTracers")

	visualDetail:Header({ Text = "Appearance" })

	-- Whole numbers, not a nought to one range shown as a percentage. Typing 35
	-- into that box was read as 35, clamped to the maximum of 1, and came back
	-- as 100 percent.
	visualDetail:Slider({
		Name = "Fill",
		Default = 35,
		Minimum = 0,
		Maximum = 100,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.espFill = value / 100
		end,
	}, "espFill")

	visualDetail:Slider({
		Name = "Text Size",
		Default = 17,
		Minimum = 12,
		Maximum = 28,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.espTextSize = value
		end,
	}, "espTextSize")

	visualDetail:Slider({
		Name = "Max Distance",
		Default = 1200,
		Minimum = 100,
		Maximum = 4000,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.espDistance = value
		end,
	}, "espDistance")

	visualRight:Header({ Text = "World" })

	visualRight:Toggle({
		Name = "Fullbright",
		Default = false,
		Callback = function(state)
			F.fullbright = state
		end,
	}, "fullbright")

	visualRight:Toggle({
		Name = "FPS Boost",
		Default = false,
		Callback = function(state)
			F.fpsBoost = state
		end,
	}, "fpsBoost")

	----------------------------------------------------------------------------
	-- movement
	----------------------------------------------------------------------------

	moveLeft:Header({ Text = "Ground" })

	local speedToggle = moveLeft:Toggle({
		Name = "Walk Speed",
		Default = false,
		Callback = function(state)
			F.speed = state
		end,
	}, "speed")

	bindTo(moveLeft, speedToggle, "speed", "Walk Speed", Enum.KeyCode.B)

	moveLeft:Slider({
		Name = "Speed",
		Default = 28,
		Minimum = 16,
		Maximum = 200,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.speedAmount = value
		end,
	}, "speedAmount")

	-- Its own panel rather than one stray toggle at the bottom of Ground, which
	-- left Movement as three panels and a hole.
	moveJump:Header({ Text = "Jump" })

	local jumpToggle = moveJump:Toggle({
		Name = "Higher Jumps",
		Default = false,
		Callback = function(state)
			F.jump = state
		end,
	}, "jump")

	bindTo(moveJump, jumpToggle, "jump", "Higher Jumps", Enum.KeyCode.J)

	-- Studs of height, because this game runs on JumpHeight rather than
	-- JumpPower and its normal is 7.2. A slider in JumpPower units would have
	-- read 50 for a jump the character could not make.
	moveJump:Slider({
		Name = "Jump Height",
		Default = 16,
		Minimum = 7,
		Maximum = 80,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.jumpAmount = value
		end,
	}, "jumpAmount")

	moveJump:Toggle({
		Name = "Infinite Jump",
		Default = false,
		Callback = function(state)
			F.infJump = state
		end,
	}, "infJump")

	moveRight:Header({ Text = "Air" })

	local flyToggle = moveRight:Toggle({
		Name = "Fly",
		Default = false,
		Callback = function(state)
			F.fly = state
		end,
	}, "fly")

	bindTo(moveRight, flyToggle, "fly", "Fly", Enum.KeyCode.V)

	moveSafety:Header({ Text = "Safety" })

	moveSafety:Toggle({
		Name = "Anti Void",
		Default = false,
		Callback = function(state)
			F.antiVoid = state
		end,
	}, "antiVoid")

	moveSafety:Button({
		Name = "Stand Up",
		Callback = function()
			local hum = core:Humanoid()
			if hum then
				hum.PlatformStand = false
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
			core:SetControls(true)
		end,
	})

	moveRight:Slider({
		Name = "Fly Speed",
		Default = 90,
		Minimum = 20,
		Maximum = 400,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.flySpeed = value
		end,
	}, "flySpeed")

	----------------------------------------------------------------------------
	-- player
	----------------------------------------------------------------------------

	playerLeft:Header({ Text = "Session" })

	playerLeft:Toggle({
		Name = "Anti AFK",
		Default = false,
		Callback = function(state)
			F.antiAfk = state
		end,
	}, "antiAfk")

	-- Ahead of the two buttons, because a button and its chevron belong at the
	-- end of a panel and everything that is not one belongs above them.
	playerLeft:Keybind({
		Name = "Everything Off",
		Default = Enum.KeyCode.Delete,
		Callback = function()
			for flag, element in pairs({
				aura = auraToggle,
				farm = farmToggle,
				esp = espToggle,
				fly = flyToggle,
				speed = speedToggle,
			}) do
				F[flag] = false
				pcall(function()
					element:UpdateState(false)
				end)
			end
			core:Notify(Module.Name, "Everything Off", 3)
		end,
	}, "panicKey")

	playerLeft:Button({
		Name = "Rejoin",
		Callback = function()
			pcall(function()
				TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
			end)
		end,
	})

	-- Server Hop used to sit here, taking the first server with a free seat off
	-- a listing sorted emptiest first, which reliably landed you somewhere with
	-- one person in it. It is now Hop Now on the Farm tab's Server panel, next
	-- to the settings that decide where it goes. Rejoin stays, because putting
	-- you back where you already are is a different thing to want.

	-- Not a list of who is here. It is one target and how to go and get them,
	-- which is the farm pointed at a person instead of at whoever is nearest,
	-- so it carries the same three controls the farm does.
	playerRight:Header({ Text = "Player Target" })

	local playerList = playerRight:Dropdown({
		Name = "Player",
		Search = true,
		Multi = false,
		Required = false,
		Options = { "Nobody" },
		Default = 1,
		Callback = function(value)
			F.watchPlayer = value
		end,
	}, "watchPlayer")
	playerList.IgnoreConfig = true

	local huntToggle = playerRight:Toggle({
		Name = "Attack This Player",
		Default = false,
		Callback = function(state)
			F.forceTarget = state
			-- Same as the farm: getting unstuck is not something anyone wants
			-- to go and find after they are already pinned on a rock.
			if state then
				F.unstuck = true
				F.recover = true
			end
		end,
	}, "forceTarget")

	bindTo(playerRight, huntToggle, "forceTarget", "Attack This Player", Enum.KeyCode.G)

	-- Its own settings rather than the farm's. Chasing one person is a
	-- different job from clearing a server and rarely wants the same speed.
	playerRight:Dropdown({
		Name = "Approach",
		Multi = false,
		Required = true,
		Options = { "Fly", "Teleport", "Walk" },
		Default = 1,
		Callback = function(value)
			F.targetApproach = value
		end,
	}, "targetApproach")

	playerRight:Slider({
		Name = "Approach Speed",
		Default = 120,
		Minimum = 16,
		Maximum = 350,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.targetSpeed = value
		end,
	}, "targetSpeed")

	playerRight:Slider({
		Name = "Keep Distance",
		Default = 11,
		Minimum = 2,
		Maximum = 11.5,
		DisplayMethod = "Value",
		Precision = 1,
		Callback = function(value)
			F.targetStandoff = value
		end,
	}, "targetStandoff")

	playerRight:Toggle({
		Name = "Auto Face",
		Default = true,
		Callback = function(state)
			F.targetFace = state
		end,
	}, "targetFace")

	-- Dodge Height is on the Farm tab. Both of these use it.
	playerRight:Toggle({
		Name = "Auto Dodge",
		Default = false,
		Callback = function(state)
			F.targetDodge = state
		end,
	}, "targetDodge")

	-- Someone leaving is not the same as someone standing in the lobby, and the
	-- combat loop could only tell you the second. It repeated "not in the arena
	-- right now" every eight seconds while the person it was waiting for had
	-- closed the game, so this says the true thing once and stops chasing.
	core:Connect(Players.PlayerRemoving, function(player)
		if type(F.watchPlayer) ~= "string" or player.Name ~= F.watchPlayer then
			return
		end
		core:Notify(Module.Name, player.DisplayName .. " left the server", 5)
		core.Watched = nil
		if F.forceTarget then
			F.forceTarget = false
			pcall(function()
				huntToggle:UpdateState(false)
			end)
		end
	end)

	----------------------------------------------------------------------------
	-- behaviour
	----------------------------------------------------------------------------

	-- Maclib does not call a control's callback for its own default, so without
	-- this every flag would read nil until the control was touched and a toggle
	-- drawn as on would behave as off.
	for flag, value in pairs({
		aura = false,
		auraRange = 11.5,
		showAura = false,
		auraColour = Color3.fromRGB(120, 200, 255),
		auraAlpha = 0.85,
		targetMode = "Weakest",
		swingDelay = 0,
		silent = false,
		ignoreStar = true,
		autoFace = true,
		faceSpeed = 420,
		dodgeClearance = 8,
		autoSkill = false,
		skillDelay = 0.6,
		skillChoice = "Hardest That Reaches",
		skillUtility = false,
		noCooldown = false,
		forceCast = false,
		farm = false,
		approach = "Fly",
		farmSpeed = 120,
		standoff = 11,
		farmFace = true,
		farmDodge = false,
		unstuck = false,
		recover = false,
		hitbox = false,
		hitboxReach = 11.5,
		showHitbox = false,
		hitboxColour = Color3.fromRGB(255, 170, 120),
		hitboxAlpha = 0.85,
		forceTarget = false,
		targetApproach = "Fly",
		targetSpeed = 120,
		targetStandoff = 11,
		targetFace = true,
		targetDodge = false,
		autoDeploy = false,
		retreat = false,
		retreatAt = 30,
		autoHop = false,
		hopBelow = 6,
		hopPick = "Full and Fast",
		hopPing = 250,
		autoEquip = false,
		equipPrefer = "Longest Reach",
		esp = false,
		espDeployedOnly = true,
		espAbility = true,
		espHealth = false,
		espFill = 0.35,
		espDistance = 1200,
		espTextSize = 17,
		espTracers = false,
		fullbright = false,
		fpsBoost = false,
		speed = false,
		speedAmount = 28,
		jump = false,
		jumpAmount = 16,
		infJump = false,
		antiVoid = false,
		fly = false,
		flySpeed = 90,
		antiAfk = false,
	}) do
		if F[flag] == nil then
			F[flag] = value
		end
	end

	-- Reach, in studs, and it means studs.
	--
	-- Read out of CombatController._SetM1Closure. The hit test does not put a
	-- box on you at all: it puts a box of HitboxSize halved around the TARGET's
	-- root, and tests that against a fixed probe of half extents 2 x 3 x 1
	-- sitting at HitboxOffset in front of you. So the distance a punch actually
	-- covers along an axis is the probe's half extent on that axis plus half of
	-- HitboxSize, and handing the slider straight to HitboxSize made every
	-- number on this tab a lie: Reach 16 built a 36 stud box and landed at
	-- about 23, and Hitbox size 30 landed at about 20.
	--
	-- Both are turned into studs here instead. The offset is zeroed at the same
	-- time so the box sits on the character rather than 4.1 studs in front of
	-- it, which is what makes one number mean the same in every direction.
	local PROBE = Vector3.new(2, 3, 1)

	-- What the game's own punch covers, in those same studs, and it is 8.1 and
	-- not 7.1. The box is 5 x 6 x 6 sitting 4.1 in front, so the front face is
	-- at 3 + 4.1 = 7.1 - but the sliders are centre to centre, and the probe
	-- adds its own half extent of 1 on that axis. 7.1 here quietly let Punch
	-- reach 8 build a box smaller than the one the game gives you for nothing.
	local GAME_REACH = 8.1

	-- And the number that matters more than any of it.
	--
	-- Hit detection is client side: the client picks who was hit and sends
	-- their ids. The open question was whether the server checked. It does.
	-- Measured 18 Aug against a live server, flying in on a stationary target
	-- and swinging with the client reach set to 60 so the client always found
	-- them, recording the distance at the instant of each swing:
	--
	--   17.2 refused   13.3 refused   11.6 refused
	--   15.2 refused   13.3 refused   11.6 refused
	--    9.9 ACCEPTED   8.9 ACCEPTED   8.8 ACCEPTED   6.7 ACCEPTED
	--
	-- A second run agreed: 11.9 and 11.8 refused, 10.4 10.1 and 8.0 accepted.
	--
	-- Then it was measured properly, standing still, no teleport anywhere in the
	-- swing, three swings a step, against a live server:
	--
	--    9.0  3 of 3      11.5  3 of 3      11.7  0 of 3      11.9  0 of 3
	--   10.5  2 of 2      11.6  3 of 3      11.8  0 of 3      12.0  0 of 3
	--
	-- The wall is between 11.6 and 11.7 studs root to root, and it is a wall, not
	-- a fade: either every swing lands or none of them do. So the cap is 11.5,
	-- a hair under it, and every number on every reach slider is a stud that
	-- really connects. The game's own swing reaches 8.1, so this is a bit under
	-- half again as far, taken without moving an inch.
	--
	-- Nothing raises it. Ten attacks are written up in MERIDIAN-NEXT.md, and the
	-- one that works only works by moving the character, which is the bypass
	-- below and is off by default for exactly that reason. The last honest hope
	-- is IncreasedMaxDistance, a field the game carries into every combo and no
	-- ability fills in. If an update ever fills it, this number moves.
	local SERVER_CEILING = 11.5

	local function boxForReach(studs)
		return Vector3.new(
			math.max((studs - PROBE.X) * 2, 1),
			math.max((studs - PROBE.Y) * 2, 1),
			math.max((studs - PROBE.Z) * 2, 1)
		)
	end

	-- The farm needs to swing from further out than it stands, or it walks into
	-- the enemy's own reach to punch and gets interrupted for its trouble.
	local function wantedReach()
		local reach = 0
		if F.hitbox then
			reach = F.hitboxReach or 10
		end
		if F.aura or F.farm then
			reach = math.max(reach, F.auraRange or 10)
		end
		if F.farm then
			-- Enough to cover where the farm chooses to stand, and no further.
			reach = math.max(reach, (F.standoff or 9) + 1)
		end
		if F.forceTarget then
			reach = math.max(reach, (F.targetStandoff or 11) + 1)
		end
		reach = math.min(reach, SERVER_CEILING)
		if reach <= GAME_REACH then
			return nil
		end
		return reach
	end

	-- GetComboData hands back a fresh copy every call, so writing to that copy
	-- changes this swing and nothing else. It applies to every punch including
	-- the ones thrown by hand.
	local originalGetComboData = CombatUtility.GetComboData
	core:Override(CombatUtility, "GetComboData", function(...)
		local data = originalGetComboData(...)
		local reach = wantedReach()
		if data and reach then
			data.HitboxSize = boxForReach(reach)
			data.HitboxOffset = CFrame.new()
		end
		return data
	end)

	-- Seeing the box is the only way to tell a number that means studs from one
	-- that does not, which is exactly the complaint that produced all of the
	-- above. One box per feature rather than one for their maximum, so it is
	-- always clear which slider is being moved.
	local auraView = core:BoxView("MeridianAuraReach")
	local hitboxView = core:BoxView("MeridianPunchReach")

	local function drawReach(view, on, reach, colour, alpha, root)
		if not on or not root or not reach then
			view:Hide()
			return
		end
		view:Show(root.CFrame, Vector3.one * reach * 2, colour or Color3.fromRGB(255, 255, 255), alpha or 0.85)
	end

	core:Connect(RunService.Heartbeat, function()
		local root = core:Root()
		drawReach(
			auraView,
			F.showAura and (F.aura or F.farm),
			math.min(F.farm and math.max(F.auraRange or 10, (F.standoff or 9) + 1) or (F.auraRange or 10), SERVER_CEILING),
			F.auraColour,
			F.auraAlpha,
			root
		)
		drawReach(hitboxView, F.showHitbox and F.hitbox, F.hitboxReach, F.hitboxColour, F.hitboxAlpha, root)
	end)


	local currentTarget = nil
	local lastSwing = 0

	-- The combat loop runs twenty times a second, so anything it wants to tell
	-- you has to be rationed or it becomes a wall of notifications.
	local said = {}

	local function sayOnce(key, text)
		if os.clock() - (said[key] or 0) < 8 then
			return
		end
		said[key] = os.clock()
		core:Notify(Module.Name, text, 4)
	end

	-- Target locking. A kill pays five hits and a punch pays one, so the whole
	-- point is finishing someone. Re-picking twenty times a second meant the
	-- aura kept walking away from people at low health to hit whoever had just
	-- stepped closer, and almost nobody died. The lock holds until the target
	-- dies, escapes, or stops losing health, which is the only honest sign that
	-- they cannot be reached.
	local lockedHealth, lockedProgressAt = nil, 0

	local function lockStillGood()
		if not currentTarget or not currentTarget.Parent then
			return false
		end

		local hum = currentTarget:FindFirstChildOfClass("Humanoid")
		local root = currentTarget:FindFirstChild("HumanoidRootPart")
		if not hum or not root or hum.Health <= 0 then
			return false
		end
		if not currentTarget:GetAttribute("Deployed") then
			return false
		end
		-- Being carried back into the arena. Let go rather than following them
		-- to the lobby and back.
		if not inPlace(currentTarget) then
			return false
		end
		if F.ignoreStar and currentTarget:GetAttribute("StarMode") then
			return false
		end

		-- How far a target may drift before the lock is dropped. The bypass
		-- reaches much further than the aura does, so the leash has to know
		-- about it or a locked target is let go the moment it steps out of
		-- punching distance.
		local leash = (F.farm or F.forceTarget) and 500 or (F.auraRange or 10)
		if core:DistanceTo(root.Position) > leash then
			return false
		end

		if lockedHealth == nil or hum.Health < lockedHealth then
			lockedHealth = hum.Health
			lockedProgressAt = os.clock()
		end

		return os.clock() - lockedProgressAt <= 5
	end

	core:Loop("combat", 0.05, function()
		-- Before anything else, and before any of the returns below, because
		-- the jump detector is only meaningful if it is sampled at a steady
		-- rate.
		noteMovement()

		if not core:Alive2() or not deployed() then
			currentTarget = nil
			return
		end

		if not (F.aura or F.farm or F.forceTarget) then
			currentTarget = nil
			return
		end

		-- One named player beats everything else, for when somebody has decided
		-- to make your afternoon their business.
		--
		-- This used to fall through to normal targeting whenever the chosen
		-- player was not currently punchable, which meant "attack this player"
		-- quietly went and attacked somebody else instead. It now holds: if the
		-- named player is not there, nothing is targeted, and it says why once
		-- rather than every twentieth of a second.
		if F.forceTarget then
			local name = F.watchPlayer
			if type(name) ~= "string" or name == "Nobody" then
				currentTarget = nil
				sayOnce("noPick", "Pick a player on the Player tab first")
				return
			end

			local player = Players:FindFirstChild(name)
			local theirs = player and player.Character
			local root = theirs and theirs:FindFirstChild("HumanoidRootPart")
			local hum = theirs and theirs:FindFirstChildOfClass("Humanoid")

			if not root or not hum or hum.Health <= 0 then
				currentTarget = nil
				sayOnce("gone", name .. " is not in the arena right now")
				return
			end
			if not theirs:GetAttribute("Deployed") then
				currentTarget = nil
				sayOnce("lobby", name .. " is standing in the lobby")
				return
			end
			if overTheEdge(theirs) then
				currentTarget = nil
				sayOnce("void", name .. " went off the map, not following them down")
				return
			end
			if not inPlace(theirs) then
				currentTarget = nil
				return
			end

			currentTarget = theirs
		elseif not lockStillGood() then
			local range = F.farm and math.huge or (F.auraRange or 10)
			currentTarget = core:PickTarget(targets(), {
				mode = F.targetMode or "Weakest",
				range = range,
				-- Anything that has to travel there should care how far it is.
				distanceWeight = (F.farm or F.forceTarget) and 0.45 or nil,
			})
			local hum = currentTarget and currentTarget:FindFirstChildOfClass("Humanoid")
			lockedHealth = hum and hum.Health or nil
			lockedProgressAt = os.clock()
		end

		local root = currentTarget and currentTarget:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end

		local distance = core:DistanceTo(root.Position)

		-- What the punch actually covers this tick, which is what decides when
		-- to swing. It used to swing at auraRange while the box reached further,
		-- so the two numbers disagreed and neither was the one on screen.
		local reach = F.auraRange or 10

		-- Chasing is the farm's job and it is also what Attack This Player
		-- means, so both go through here. The Player tab keeps its own three
		-- settings, and they win while it is hunting somebody by name.
		local hunting = F.forceTarget and true or false
		local standoff, mode, speed
		if hunting then
			standoff, mode, speed = F.targetStandoff or 11, F.targetApproach or "Fly", F.targetSpeed or 120
		else
			standoff, mode, speed = F.standoff or 9, F.approach or "Fly", F.farmSpeed or 70
		end

		if F.farm or hunting then
			reach = math.max(reach, standoff + 1)
		end
		reach = math.min(reach, SERVER_CEILING)

		-- Face whoever it is fighting, the whole time it is fighting them.
		--
		-- This was cut back to almost nothing last round because turning his
		-- view twenty times a second while he was playing was unbearable, and
		-- because an extended punch box is centred and symmetric so facing
		-- changes nothing mechanically. Both still true. But while the farm is
		-- on, the farm is already flying him around, and a character that
		-- punches sideways at people looks broken to everyone watching.
		--
		-- So: face continuously while something else is driving, and leave him
		-- alone when he is driving himself.
		--
		-- That last part is no longer true and it was a bug he found. The aura
		-- was excluded from facing entirely, on the grounds that an extended
		-- punch box is centred and symmetric so facing changes nothing
		-- mechanically. It still changes nothing mechanically. It looks wrong,
		-- which is the part that mattered, and the camera is smooth now, so the
		-- reason for holding it back is gone. All three modes face, each behind
		-- its own switch.
		if facingOn() then
			core:LockFacing(function()
				local live = currentTarget
				if not live or not live.Parent then
					return nil
				end
				local at = live:FindFirstChild("HumanoidRootPart")
				return at and at.Position or nil
			end, 0.4)
		end

		-- So getting unstuck moves at the pace of the run rather than at a
		-- fixed crawl.
		core.ApproachSpeed = speed

		-- Over the top of whatever they just threw. This wins over the approach
		-- while it lasts and always flies, whichever approach is set: walking
		-- cannot go up, and a blink that lands mid climb puts you back in the
		-- box you were leaving.
		if dodgeOn() and os.clock() < dodgeUntil and dodgeTo then
			core:FlyToward(Vector3.new(root.Position.X, dodgeTo, root.Position.Z), standoff, math.max(speed, 90))
			return
		end

		if F.farm or hunting then
			if mode == "Walk" then
				core:WalkToward(root.Position, standoff, speed)
			elseif mode == "Teleport" then
				-- Bit by bit while they are far, one hop onto the standoff once
				-- a single step covers the rest, and then the punch below
				-- fires. It used to jump the whole way in one go for anything
				-- inside a hundred studs, which is the part he was describing.
				--
				-- The step is the studs a second Approach Speed asks for,
				-- divided by the twenty times a second this loop runs, so the
				-- slider means the same thing whichever approach is picked.
				core:BlinkTo(root.Position, standoff, math.max(speed / 20, 4))
			else
				core:FlyToward(root.Position, standoff, speed)
			end
		end

		if os.clock() - lastSwing < (F.swingDelay or 0) then
			return
		end

		if distance <= reach and canPunch() then
			lastSwing = os.clock()
			-- The facing lock above covers every mode now, including the aura,
			-- so the fifth of a second this used to grab at the moment of each
			-- swing is gone. It was also the bug: it only ran while the punch
			-- box was the game's own, and turning the aura on extends the box,
			-- so the aura never faced anybody.
			punch()
		end
	end)

	local sessionStart = os.clock()
	local sessionFrom = nil

	-- Table writes only. This module may not touch the interface, so the numbers
	-- are left here and the dashboard reads them.
	core:Loop("farmStatus", 1, function()
		local owned = hits()
		if not sessionFrom then
			sessionFrom = owned
		end

		local gained = owned - sessionFrom
		local minutes = (os.clock() - sessionStart) / 60
		local perHour = minutes > 0.2 and math.floor(gained / minutes * 60) or 0

		core.Stats = {
			Hits = gained,
			Rate = perHour,
			Total = owned,
		}
		core.Headline = (F.farm or F.aura) and gained > 0 and ("%d hits · %d an hour"):format(gained, perHour)
			or nil
	end)

	-- Only fires when the farm has genuinely been unable to close on anyone for
	-- a long stretch. Combat knocks you around constantly, so the threshold is
	-- deliberately generous and any real progress resets it.
	local chaseSince, closestSeen = nil, nil

	core:Loop("recover", 1, function()
		if not F.recover or not F.farm or not deployed() or not core:Alive2() then
			chaseSince, closestSeen = nil, nil
			return
		end
		local root = currentTarget and currentTarget:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end

		local distance = core:DistanceTo(root.Position)
		if distance <= math.max(F.auraRange or 10, (F.standoff or 9) + 1) then
			chaseSince, closestSeen = nil, nil
			return
		end
		if not closestSeen or distance < closestSeen - 5 then
			closestSeen = distance
			chaseSince = os.clock()
			return
		end
		chaseSince = chaseSince or os.clock()

		if os.clock() - chaseSince > 20 then
			chaseSince, closestSeen = nil, nil
			core:Notify(Module.Name, "Could not reach anyone, deploying again", 3)
			task.spawn(function()
				pcall(CharacterController.ToLobby)
				task.wait(1.5)
				pcall(CharacterController.Deploy)
			end)
		end
	end)

	-- Auto skills, rebuilt.
	--
	-- What it did before was walk the four slots in order, press each one and
	-- wait, whether or not anything was in front of you, whether or not the
	-- skill was off cooldown, and without ever turning to face anyone. Most of
	-- what it fired went into empty air behind the character.
	--
	-- Now: one skill per pass, only when there is a target, only when that
	-- skill's own clock says it is ready, and always facing them first. The
	-- ready check goes through the game's own CheckTimestamp, captured here
	-- before Bypass cooldown can replace it, so it stays honest even while the
	-- bypass is on.
	-- Which approach is in charge right now. The Player tab keeps its own.
	local function approachMode()
		if F.forceTarget and not F.farm then
			return F.targetApproach or "Fly"
		end
		return F.approach or "Fly"
	end

	local realCheckTimestamp = CharacterUtility.CheckTimestamp
	local nextSkillAt = 0
	local slotOrder = { "Q", "E", "R", "F" }

	local function skillReady(char, skill)
		local definition = definitionOf(skill, char)
		if not definition then
			return false
		end
		local name = definition.CooldownName or skill.Name
		local ok, ready = pcall(realCheckTimestamp, char, "SKILL_" .. tostring(name), nil, nil, definition.PersistentCooldown)
		return ok and ready == true
	end

	core:Loop("skills", 0.1, function()
		if not F.autoSkill or not deployed() or not core:Alive2() then
			return
		end
		if os.clock() < nextSkillAt then
			return
		end

		local char = core:Character()
		local ability = char and AbilityManager.GetAbility(char)
		if not ability or type(ability.Order) ~= "table" then
			return
		end

		-- Something to aim at. Without this it threw every skill it had at the
		-- horizon the moment it came off cooldown.
		local target = currentTarget
		if not target or not target.Parent then
			target = core:PickTarget(targets(), {
			mode = F.targetMode or "Weakest",
			range = 120,
			distanceWeight = (F.farm or F.forceTarget) and 0.45 or nil,
		})
		end
		local root = target and target:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end

		local skills = AbilityManager.GetSkills(ability.Name, char)
		if type(skills) ~= "table" then
			return
		end

		local distance = core:DistanceTo(root.Position)
		local wanted = F.skillSlots

		-- Gather everything that could go off right now, then choose, rather
		-- than firing whatever happens to sit in the first slot.
		local ready = {}
		for index, name in ipairs(ability.Order) do
			local letter = slotOrder[index]
			local allowed = type(wanted) ~= "table" or wanted[letter] == true
			local skill = allowed and skills[name] or nil
			if skill then
				local definition = definitionOf(skill, char)

				-- Each skill knows how far it goes. Throwing a 15 stud one at
				-- somebody 60 studs away burned its whole cooldown on nothing,
				-- which is most of why this felt like the worst thing on the
				-- tab. No hitbox at all means a dash or a buff: it reaches
				-- anything, which is exactly why it needs its own switch.
				local reach = skillReach(definition)
				local utility = reach == nil
				local inRange = utility or distance <= reach + 2

				if inRange and (not utility or F.skillUtility) and skillReady(char, skill) then
					ready[#ready + 1] = {
						index = index,
						name = name,
						reach = reach,
						utility = utility,
						damage = (definition and tonumber(definition.Damage)) or 0,
						-- How long the cast actually runs, which is how long
						-- the aim has to stay on them. Big Beam is 1.18 of
						-- attack and 0.9 of endlag; Trinity Burst is 0.43 and
						-- 1. Anything without the fields gets a short default.
						hold = ((definition and tonumber(definition.AttackTime)) or 0.4)
							+ ((definition and tonumber(definition.Endlag)) or 0),
					}
				end
			end
		end

		if #ready == 0 then
			return
		end

		local choice = F.skillChoice or "Hardest That Reaches"
		local pick = ready[1]
		if choice == "Hardest That Reaches" then
			for _, entry in ipairs(ready) do
				if entry.damage > pick.damage
					or (entry.damage == pick.damage and (entry.reach or 0) > (pick.reach or 0))
				then
					pick = entry
				end
			end
		elseif choice == "Longest Reach" then
			for _, entry in ipairs(ready) do
				if (entry.reach or 0) > (pick.reach or 0) then
					pick = entry
				end
			end
		end

		if facingOn() then
			-- Lock, do not snap. The lock follows them for as long as the
			-- animation runs, so a two second cast still ends up pointing at
			-- whoever it started on, and it releases the moment the cast is
			-- over instead of holding his view hostage.
			--
			-- It is the same target the aura and the farm are already on, so
			-- the three of them never pull in different directions.
			core:LockFacing(function()
				local live = currentTarget or target
				if not live or not live.Parent then
					return nil
				end
				local at = live:FindFirstChild("HumanoidRootPart")
				return at and at.Position or nil
			end, pick.hold + 0.2)

			-- Wait for the turn to arrive rather than for a fixed number of
			-- frames, then let it replicate: the server reads the root's
			-- rotation when it resolves the skill, not when the key is pressed.
			local settle = os.clock() + 0.3
			while os.clock() < settle and not core:FacingWithin(root.Position) do
				task.wait()
			end
			task.wait(0.06)
		end
		pcall(function()
			AbilityController:UseAbility(pick.index)
		end)
		nextSkillAt = os.clock() + (F.skillDelay or 0.6)
	end)

	core:Loop("deploy", 1.5, function()
		local char = core:Character()
		if not char or not core:Alive2() or char:GetAttribute("StarMode") then
			return
		end

		if F.retreat and char:GetAttribute("Deployed") then
			local hum = core:Humanoid()
			if hum and hum.Health <= (F.retreatAt or 30) then
				pcall(CharacterController.ToLobby)
				return
			end
		end

		if F.autoDeploy and not char:GetAttribute("Deployed") then
			local hum = core:Humanoid()
			if F.retreat and hum and hum.Health <= (F.retreatAt or 30) then
				return
			end
			pcall(CharacterController.Deploy)
		end
	end)

	-- Only ever from the lobby, because that is the only place the server
	-- listens. It fires between rounds on its own, which is exactly when you
	-- would change ability by hand anyway.
	core:Loop("equip", 4, function()
		if not F.autoEquip or deployed() then
			return
		end

		local owned = hits()
		local byReach = (F.equipPrefer or "Longest Reach") == "Longest Reach"
		local best, bestScore = nil, -1

		for _, entry in ipairs(unlockTable()) do
			if owned >= entry.hits then
				local score = byReach and abilityReach(entry.name) or entry.hits
				if score > bestScore then
					best, bestScore = entry.name, score
				end
			end
		end

		local ok, current = pcall(function()
			return DataController:GetCurrentAbility()
		end)
		if best and ok and current ~= best then
			SetAbility:Fire(best)
			local reach, skill = abilityReach(best)
			core:Notify(
				Module.Name,
				reach > 0 and ("Equipped %s, %s reaches %d studs"):format(best, tostring(skill), math.floor(reach))
					or ("Equipped " .. best),
				4
			)
		end
	end)

	core:Loop("stats", 1, function()
		local owned = hits()
		local nextName, nextHits = nil, nil
		for _, entry in ipairs(unlockTable()) do
			if entry.hits > owned then
				nextName, nextHits = entry.name, entry.hits
				break
			end
		end

		local ok, replica = pcall(function()
			return DataController:GetReplica()
		end)
		local kills, deaths = 0, 0
		if ok and replica then
			kills = replica.Data.Kills or 0
			deaths = replica.Data.Deaths or 0
		end

		local currentOk, current = pcall(function()
			return DataController:GetCurrentAbility()
		end)

		local carried = core.Stats or {}
		carried.Total = owned
		carried.Kills = kills
		carried.Deaths = deaths
		carried.Holding = currentOk and tostring(current) or "unknown"
		carried.NextUnlock = nextName
		carried.NextIn = nextName and (nextHits - owned) or nil
		core.Stats = carried
	end)

	-- Rebuilding this list every few seconds wiped whatever was selected, which
	-- is why picking someone to attack quietly jumped to another name. Only
	-- rebuild when the roster has actually changed, and put the selection back.
	local rosterKey = nil

	core:Loop("playerList", 3, function()
		local options = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= Players.LocalPlayer then
				options[#options + 1] = player.Name
			end
		end
		table.sort(options)
		if #options == 0 then
			options = { "Nobody" }
		end

		local key = table.concat(options, "|")
		if key == rosterKey then
			return
		end
		rosterKey = key

		local keep = F.watchPlayer
		pcall(function()
			playerList:ClearOptions()
			playerList:InsertOptions(options)
			if type(keep) == "string" and table.find(options, keep) then
				playerList:UpdateSelection(keep)
				F.watchPlayer = keep
			end
		end)
	end)

	core:Loop("watched", 1, function()
		local name = F.watchPlayer
		if type(name) ~= "string" or name == "Nobody" then
			core.Watched = nil
			return
		end
		local player = Players:FindFirstChild(name)
		local char = player and player.Character
		if not char then
			core.Watched = { Name = name, Away = true }
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		core.Watched = {
			Name = player.DisplayName,
			Holding = char:GetAttribute("AbilityName") or "unknown",
			Health = hum and math.floor(hum.Health) or 0,
			Distance = char:FindFirstChild("HumanoidRootPart")
					and math.floor(core:DistanceTo(char.HumanoidRootPart.Position))
				or 0,
		}
	end)

	----------------------------------------------------------------------------
	-- world and session
	----------------------------------------------------------------------------

	local lighting = {
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		FogEnd = Lighting.FogEnd,
		GlobalShadows = Lighting.GlobalShadows,
		Ambient = Lighting.Ambient,
	}
	core:Track(function()
		for key, value in pairs(lighting) do
			pcall(function()
				Lighting[key] = value
			end)
		end
	end)

	core:Loop("world", 1, function()
		if F.fullbright then
			Lighting.Brightness = 3
			Lighting.ClockTime = 14
			Lighting.FogEnd = 100000
			Lighting.GlobalShadows = false
			Lighting.Ambient = Color3.fromRGB(178, 178, 178)
		elseif Lighting.Brightness ~= lighting.Brightness then
			for key, value in pairs(lighting) do
				pcall(function()
					Lighting[key] = value
				end)
			end
		end
	end)

	-- Everything here was measured in a fourteen player server, alternating
	-- each switch on and off three times so a server that gets busier midway
	-- cannot be read as a result. Per frame, at about 20ms a frame:
	--
	--   quality level 1 ............ 1.88ms   the one that actually matters
	--   shadows and post effects ... 0.68ms
	--   the menu's frosted panel ... 0.42ms
	--   particles, trails, beams ... nothing, and there are 35,047 of them
	--
	-- The particle result is worth keeping written down, because turning them
	-- all off is the obvious move and it buys nothing: almost none of them are
	-- emitting at any given moment, and Roblox does not pay for an idle emitter.
	--
	-- What it adds up to is about 3ms, which at fifty frames a second is fifty
	-- to about fifty-nine. The rest of a bad frame in this game is the game.
	local boosted = false
	local restore = nil

	core:Loop("fps", 2, function()
		if F.fpsBoost and not boosted then
			boosted = true
			restore = { shadows = Lighting.GlobalShadows, effects = {}, blur = nil }

			-- Descendants, not children: this game keeps some of its post
			-- effects one level down and the old version walked straight past
			-- them. It also never turned them back on, so the first time anyone
			-- used this the game stayed flat until they rejoined.
			for _, effect in ipairs(Lighting:GetDescendants()) do
				if effect:IsA("PostEffect") then
					restore.effects[effect] = effect.Enabled
					effect.Enabled = false
				end
			end
			Lighting.GlobalShadows = false

			pcall(function()
				settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
			end)
			pcall(function()
				restore.blur = Window:GetAcrylicBlurState()
				Window:SetAcrylicBlurState(false)
			end)
		elseif not F.fpsBoost and boosted then
			boosted = false
			pcall(function()
				settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
			end)
			if restore then
				for effect, was in pairs(restore.effects) do
					pcall(function()
						effect.Enabled = was
					end)
				end
				pcall(function()
					Lighting.GlobalShadows = restore.shadows
				end)
				if restore.blur then
					pcall(function()
						Window:SetAcrylicBlurState(true)
					end)
				end
				restore = nil
			end
		end
	end)

	-- Anti AFK. Disabling the Idled connections is quieter than pretending to
	-- click, and it means no auto clicker running in the background.
	task.spawn(function()
		local ok = pcall(function()
			for _, connection in ipairs(getconnections(Players.LocalPlayer.Idled)) do
				connection:Disable()
			end
		end)
		if not ok then
			core:Connect(Players.LocalPlayer.Idled, function()
				if not F.antiAfk then
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

	core:StartESP({
		flag = "esp",
		interval = 0.2,
		list = function()
			local out = {}
			local mine = core:Character()
			for _, model in ipairs(CollectionService:GetTagged("Character")) do
				if model ~= mine and model.Parent then
					if not F.espDeployedOnly or model:GetAttribute("Deployed") then
						out[#out + 1] = model
					end
				end
			end
			return out
		end,
		maxDistance = function()
			return F.espDistance or 1200
		end,
		fill = function()
			return F.espFill or 0.35
		end,
		textSize = function()
			return F.espTextSize or 17
		end,
		colour = function(model)
			return abilityColour(model:GetAttribute("AbilityName"))
		end,
		label = function(model, distance)
			local player = Players:GetPlayerFromCharacter(model)
			local text = player and player.DisplayName or model.Name
			if F.espAbility then
				local ability = model:GetAttribute("AbilityName")
				if ability then
					text ..= "  " .. ability
				end
			end
			if F.espHealth then
				local hum = model:FindFirstChildOfClass("Humanoid")
				if hum then
					text ..= ("  %d hp"):format(hum.Health)
				end
			end
			return ("%s  %dm"):format(text, distance)
		end,
	})

	core:StartControlWatcher()
	core:StartUnstuck()
	core:StartInfiniteJump()
	core:StartSpeed(function()
		local wanted = core.DefaultWalkSpeed or 16
		if F.speed then
			wanted = math.max(wanted, F.speedAmount or 28)
		end
		-- Only Walk. Flying and teleporting do not read WalkSpeed at all, so
		-- raising it for them was a hundred and twenty stud a second sprint
		-- visible to everyone in the server, bought for nothing. And it is the
		-- braked figure, not the slider, or MoveTo overshoots the standoff.
		if (F.farm or F.forceTarget) and approachMode() == "Walk" then
			wanted = math.max(wanted, core.WalkWant or 20)
		end
		return wanted
	end)
	core:StartJump(function()
		if not F.jump then
			return nil
		end
		return F.jumpAmount or 80
	end)
	core:StartFly(function()
		return F.flySpeed or 60
	end)
	-- What kills you here is the KillBricks folder, not a height. Everything
	-- under it is fatal on contact and the pair of slabs at the bottom of the
	-- map are what the void actually is, so "am I going to land on one of those"
	-- is the whole question.
	-- Two folders, not one, and the one that matters is the one that was
	-- missed. What is actually at the bottom of the void is `Border`: a pair of
	-- 1459 by 1552 slabs whose tops sit at about Y -5, CanTouch with CanCollide
	-- off, which is what a kill trigger looks like. `KillBricks` is the out of
	-- bounds regions around the edges. Checking only KillBricks meant a real
	-- fall landed on a Border slab, was read as ordinary ground, and he died on
	-- it, which is exactly what he described.
	local FATAL = { "Border", "KillBricks" }

	core:StartAntiVoid({
		deadly = function(instance)
			for _, name in ipairs(FATAL) do
				local folder = workspace:FindFirstChild(name)
				if folder and instance:IsDescendantOf(folder) then
					return true
				end
			end
			return false
		end,
	})

	return {
		Tabs = tabs,
		Default = tabs.Combat,
		Tips = tips,
	}
end

return Module
