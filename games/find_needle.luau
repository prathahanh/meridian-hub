--// Meridian · Search For The Needle
--// universe 10756011174
--//
--// Three places, not one. The lobby at 77108422251420 is a farm with a gem
--// shop and a party pad; the game itself is FARMHOUSE at 108628039999641 and
--// BASEMENT at 83445806734780, reached by standing on a pad until it counts
--// down. Meridian keys on GameId, so this module loads in all three and has to
--// ask which one it is in before it offers anything.
--//
--// What makes this game worth a hub is the same thing that made Steal An Egg
--// worth one: the game hands us its own valuation function and it is cheap to
--// ask. `Config.isRainbow(hayId)` is a pure hash of the strand's id - no
--// server call, no guessing - and a rainbow strand is worth ten times an
--// ordinary one for exactly the same 0.55s cooldown.
--//
--// Watched on a live server, and this is the whole argument for the module: a
--// bag of 25 strands with three rainbow in it sold for $0.52. The same bag with
--// none in it sells for $0.25. Three strands out of twenty-five doubled the
--// trip, and every farm that grabs whatever is nearest walks past them.
--//
--// The pile holds 13000 rendered strands of which six were rainbow, so they are
--// not something you stumble into - they are something you look up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Module = {
	GameId = 10756011174,
	Name = "Search For The Needle",
}

-- Hover text. One line each, written for somebody who has never seen the code.
-- Nothing here explains a mechanism and no number appears unless it is one you
-- would actually set.
Module.Tips = {
	["Auto Collect"] = "Works the pile on its own: takes hay, carries it to the cow when the bag is full, and goes back for more.",
	["Rainbow Hay First"] = "Takes a rainbow strand ahead of anything else in reach. One is worth ten ordinary strands and costs the same moment to pick, so this is free money.",
	["Walk For Rainbow"] = "How far it will go out of its way for a rainbow strand. Zero means it only takes the ones it was already standing next to.",
	["Spread Out"] = "Moves round the pile instead of hollowing out one side. The needle is buried somewhere under it and only digging near it counts.",
	["Sell When Full"] = "Carries the bag to the cow the moment it will not hold any more. Off means it keeps working and stops earning.",
	["Buy Upgrades"] = "Spends the money it earns on the thing that pays for itself soonest, and leaves the rest alone.",
	["Spend On"] = "Which ladder it is allowed to climb. Everything lets it choose between them on payback.",
	["Pays Back Within"] = "How long an upgrade has to earn its price back before it is worth buying. Seconds. Turn it up and it will buy things that only pay off on a long round.",
	["Keep In Reserve"] = "Money it will not spend, so there is always something left for the thing you want to buy yourself.",
	["Highlight The Needle"] = "Outlines the needle once the game has told you where it is. Nothing can point at it before that, because the server does not say.",
	["Tracer To The Needle"] = "Draws a line from you to the needle while it is showing.",
	["Go And Get It"] = "Walks to the needle the moment it shows, takes it, and carries it to the farmer.",
	["Announce The Reveal"] = "Says so when the needle turns up, which is easy to miss while you are looking at the pile.",
}

--------------------------------------------------------------------------------
-- file scope
--------------------------------------------------------------------------------
--
-- Build is ONE function against Luau's ceiling of 200 local registers, and
-- steal_an_egg.luau reached it. Everything past the plumbing lives out here on
-- a table and is handed what it needs once, through a wire.
--
-- ./check.sh games/find_needle.luau catches the ceiling. luau-analyze does not.

local LOBBY_PLACE = 77108422251420

-- The pile, and the only interesting question about it.
local pile = { bits = nil, rainbow = {}, cursor = 1, scanned = nil, folder = nil }

function pile.wire(bits)
	pile.bits = bits
end

-- Where the hay is, asked the way the game asks it.
--
-- The pile is 13000 parts. The game's own grab code uses GetPartBoundsInRadius
-- against an OverlapParams filtered to the hay folder rather than walking the
-- children, and so does this: at three picks a second, a 13000 iteration scan
-- per pick is forty thousand attribute reads a second for an answer that only
-- needs the strands within arm's reach.
function pile.nearby(from, radius)
	local bits = pile.bits
	if not bits or not bits.overlap then
		return {}
	end
	local folder = pile.hayFolder()
	if not folder then
		return {}
	end
	bits.overlap.FilterDescendantsInstances = { folder }
	return Workspace:GetPartBoundsInRadius(from, radius, bits.overlap)
end

function pile.hayFolder()
	local folder = pile.folder
	if folder and folder.Parent then
		return folder
	end
	folder = Workspace:FindFirstChild("HaystackClient")
	pile.folder = folder
	return folder
end

-- The rainbow strands, found a slice at a time.
--
-- Six of thirteen thousand were rainbow on the server this was written against,
-- so a full scan finds almost nothing almost all of the time and there is no
-- reason to pay for it in one frame. A twentieth of the folder per tick keeps
-- the list within a few seconds of the truth and costs nothing measurable.
function pile.sweep()
	local bits = pile.bits
	local folder = pile.hayFolder()
	if not bits or not folder then
		pile.rainbow = {}
		return
	end
	local children = folder:GetChildren()
	local count = #children
	if count == 0 then
		pile.rainbow = {}
		return
	end
	if pile.scanned ~= folder then
		pile.scanned, pile.cursor, pile.rainbow = folder, 1, {}
	end
	local slice = math.max(400, count // 20)
	local last = math.min(pile.cursor + slice - 1, count)
	local found = pile.pending or {}
	for index = pile.cursor, last do
		local part = children[index]
		local id = part and part.Parent and part:GetAttribute("HayId")
		if id and bits.isRainbow(id) then
			found[#found + 1] = part
		end
	end
	if last >= count then
		-- Swapped in whole rather than appended to, so the list is never half a
		-- sweep old at one end and current at the other.
		pile.rainbow, pile.pending, pile.cursor = found, nil, 1
	else
		pile.pending, pile.cursor = found, last + 1
	end
end

-- The best strand to take next, which is the whole point.
--
-- Rainbow first inside arm's reach, because ten times the money for the same
-- cooldown is not a close call. Beyond reach it is a walk, and a walk is only
-- worth it if the strand is close enough that the detour costs less than the
-- nine hundredths of a dollar it is worth.
function pile.pick(from, reach, walkFor)
	local bits = pile.bits
	if not bits then
		return nil, nil
	end
	local best, bestScore = nil, -math.huge
	for _, part in ipairs(pile.nearby(from, reach)) do
		local id = part:GetAttribute("HayId")
		if id then
			local distance = (part.Position - from).Magnitude
			local score = (bits.isRainbow(id) and 1e6 or 0) - distance
			if score > bestScore then
				best, bestScore = part, score
			end
		end
	end
	if best and bits.isRainbow(best:GetAttribute("HayId")) then
		return best, "rainbow"
	end
	-- Nothing golden in reach. Is one close enough to be worth the walk?
	if walkFor and walkFor > 0 then
		local target, targetDistance = nil, math.huge
		for _, part in ipairs(pile.rainbow) do
			if part.Parent then
				local distance = (part.Position - from).Magnitude
				if distance > reach and distance <= walkFor and distance < targetDistance then
					target, targetDistance = part, distance
				end
			end
		end
		if target then
			return target, "walk"
		end
	end
	return best, best and "near" or nil
end

--------------------------------------------------------------------------------

-- What to buy next, and this is the part that is easy to get wrong.
--
-- Three ladders, one wallet, and the cheapest thing is not the best thing.
-- Measured against the game's own tables, at the base pick cooldown of 0.55s
-- and the 45 studs between the pile and the cow:
--
--   bag 25, bare hands   1.27 hay a second
--   bag 50               1.49
--   bag 100              1.64
--   bag 250              1.74   (the ceiling is 1.82, the pick rate itself)
--   bag 25 + pitchfork   3.20
--   bag 100 + pitchfork   7.60
--
-- So capacity buys less and less, the pitchfork buys a great deal, and the two
-- multiply. Capacity level 2 costs $1 and gains 0.22 hay a second; the
-- pitchfork costs $8 and gains 1.93. Their paybacks are 455 and 414 seconds -
-- close enough that neither is obviously first, which is exactly why this
-- compares them on payback rather than on price.
--
-- Steal An Egg learned this the expensive way: three ladders with no order
-- between them meant whichever timer came round first spent everything, and a
-- billion-dollar base upgrade sat unbought for hours behind a treadmill.
local ladder = { bits = nil }

function ladder.wire(bits)
	ladder.bits = bits
end

-- Hay a second for a given bag size and seconds-per-pick, including the walk.
function ladder.rate(capacity, perPick, perSwing)
	local trip = 6
	local seconds = capacity * (perSwing or perPick) + trip
	if seconds <= 0 then
		return 0
	end
	return capacity / seconds
end

function ladder.state()
	local bits = ladder.bits
	if not bits then
		return nil
	end
	local ok, state = pcall(function()
		return bits.remotes.GetUpgradeState:InvokeServer()
	end)
	if not ok or type(state) ~= "table" then
		return nil
	end
	return state
end

-- The affordable thing with the best payback, or nothing.
--
-- `ceiling` is what stops this being cheapest-first wearing a suit. At bag 100
-- the next bag upgrade costs $5 and buys 0.05 hay a second, which is a payback
-- of ten thousand seconds; the pitchfork costs $8 and buys 5.96, which is a
-- hundred and thirty-four. Buying the cheap one first is not just worse value,
-- it takes the money that was five bags away from the good one.
--
-- Steal An Egg paid for this: three ladders with no order between them, and
-- whichever timer came round first spent everything.
function ladder.best(cash, allow, ceiling)
	local bits = ladder.bits
	if not bits or type(cash) ~= "number" then
		return nil
	end
	ceiling = tonumber(ceiling) or 600
	local player = bits.player
	local Config = bits.Config
	local capacity = tonumber(player:GetAttribute("HayCapacity")) or 25
	local perPick = tonumber(player:GetAttribute("HayPickCooldown")) or Config.PICK_COOLDOWN
	local forked = player:GetAttribute("PitchforkOwned") == true
		or player:GetAttribute("PermanentPitchforkOwned") == true
	local scoop = tonumber(player:GetAttribute("PitchforkScoop")) or 12
	local swing = tonumber(player:GetAttribute("PitchforkCooldown")) or Config.PITCHFORK_COOLDOWN

	-- What we earn now, in hay a second.
	local nowPer = forked and (swing / math.max(scoop, 1)) or perPick
	local now = ladder.rate(capacity, nowPer)

	local best, saving = nil, nil
	local function offer(kind, id, label, cost, after)
		cost = tonumber(cost)
		if not cost or after <= now then
			return
		end
		-- Payback in seconds: what it costs, over what it adds. Hay is a cent,
		-- so a gain of one hay a second is a cent a second.
		local payback = cost / ((after - now) * Config.HAY_VALUE)
		if payback > ceiling then
			return
		end
		local want = { kind = kind, id = id, label = label, cost = cost, payback = payback }
		if cost > cash then
			-- Worth having but not yet affordable. Remembered so the caller can
			-- say it is saving rather than say nothing at all.
			if not saving or payback < saving.payback then
				saving = want
			end
			return
		end
		if not best or payback < best.payback then
			best = want
		end
	end

	if allow ~= "Pitchfork Only" then
		local level = tonumber(player:GetAttribute("HayUpgradeCapacity")) or 1
		local step = Config.UPGRADE_TRACKS.Capacity.Levels[level + 1]
		if step and tonumber(step.Capacity) then
			offer("upgrade", "Capacity", ("Bag %d"):format(step.Capacity), step.Cost,
				ladder.rate(step.Capacity, nowPer))
		end
	end

	if allow ~= "Bag Only" then
		if not forked then
			-- The tool itself, before any of its own ladder exists.
			offer("item", "Pitchfork", "Pitchfork", 8,
				ladder.rate(capacity, swing / math.max(scoop, 1)))
		else
			local level = tonumber(player:GetAttribute("HayUpgradePitchfork")) or 1
			local step = Config.UPGRADE_TRACKS.Pitchfork.Levels[level + 1]
			if step and tonumber(step.Scoop) then
				offer("upgrade", "Pitchfork", ("Sweep %d"):format(step.Scoop), step.Cost,
					ladder.rate(capacity, swing / step.Scoop))
			end
			local cool = tonumber(player:GetAttribute("HayUpgradePitchforkCooldown")) or 1
			local faster = Config.UPGRADE_TRACKS.PitchforkCooldown.Levels[cool + 1]
			if faster and tonumber(faster.Cooldown) then
				offer("upgrade", "PitchforkCooldown", "Faster swing", faster.Cost,
					ladder.rate(capacity, faster.Cooldown / math.max(scoop, 1)))
			end
		end
	end

	-- Saving beats spending when the thing being saved for is much better. Bag
	-- 150 at ten thousand seconds and the pitchfork at a hundred and thirty-four
	-- are not close, and taking the affordable one delays the good one.
	if saving and best and saving.payback * 4 < best.payback then
		return nil, saving
	end
	return best, saving
end

function ladder.buy(want)
	local bits = ladder.bits
	if not bits or not want then
		return false
	end
	-- BuyUpgrade takes the track name and BuyShopItem takes the item id. Read off
	-- the game's own shop buttons, which carry ShopSessionTrack for one and
	-- ShopItemId for the other, and are not interchangeable.
	if want.kind == "upgrade" then
		return bits.ask("BuyUpgrade", want.id)
	end
	return bits.ask("BuyShopItem", want.id)
end

--------------------------------------------------------------------------------

-- The needle.
--
-- It is buried, and the server does not say where until it decides to. The only
-- honest thing a hub can do is light it up the moment the game admits it exists,
-- and say plainly that nothing can point at it before then.
--
-- Two ways in, both read off the game's own client:
--
--   * a part carrying the `IsNeedleObjective` attribute, which is what the
--     game's own pickup code checks and what `PickHay:FireServer("Objective")`
--     claims
--   * `NeedleTargetChanged`, which fires with the needle's hay id and nothing
--     else, and the same id turns up as `needleHayId` in the GetHayState
--     snapshot for anyone who joined after the reveal
--
-- The attribute is preferred because it needs no remote and cannot go stale.
local needle = { bits = nil, hayId = nil, part = nil, said = false }

function needle.wire(bits)
	needle.bits = bits
end

function needle.forget()
	needle.hayId, needle.part, needle.said = nil, nil, false
end

-- The part the needle is in, if the game is showing one.
function needle.find()
	local bits = needle.bits
	if not bits then
		return nil
	end
	if needle.part and needle.part.Parent then
		return needle.part
	end
	needle.part = nil

	local folder = pile.hayFolder()
	local hidden = Workspace:FindFirstChild("HiddenNeedleClient")
	for _, where in ipairs({ hidden, folder }) do
		for _, part in ipairs(where and where:GetChildren() or {}) do
			if part:IsA("BasePart") then
				if part:GetAttribute("IsNeedleObjective") then
					needle.part = part
					return part
				end
				if needle.hayId and part:GetAttribute("HayId") == needle.hayId then
					needle.part = part
					return part
				end
			end
		end
	end
	return nil
end

-- Whether the server has revealed it, asked of the save rather than guessed.
function needle.revealed()
	local bits = needle.bits
	if not bits then
		return false
	end
	if needle.hayId or needle.part then
		return true
	end
	local ok, state = pcall(function()
		return bits.remotes.GetHayState:InvokeServer()
	end)
	if ok and type(state) == "table" then
		if state.needleClaimed == true then
			return false
		end
		local id = tonumber(state.needleHayId)
		if id then
			needle.hayId = id
			return true
		end
		return state.needleRevealed == true
	end
	return false
end

function needle.tick()
	local bits = needle.bits
	if not bits then
		return
	end
	local F = bits.F
	local showing = F.needleHighlight == true and bits.inRound()
	local part = showing and needle.find() or nil

	bits.mark.Adornee = part
	bits.mark.Enabled = part ~= nil

	if part and not needle.said then
		needle.said = true
		if F.needleAnnounce ~= false then
			bits.core:Notify(Module.Name, "The needle is showing. It is outlined now.", 6)
		end
	elseif not part then
		needle.said = false
	end

	if part and F.needleFetch == true and bits.due("needleFetch", 0.4) then
		local root = bits.core:Root()
		if root then
			local distance = (part.Position - root.Position).Magnitude
			if distance > 6 then
				bits.core:WalkToward(part.Position, 5, 20)
			elseif bits.due("needleTake", 1.2) then
				-- The game's own claim call. "Objective" rather than a hay id,
				-- copied from the call site in NeedleHaystackClient.
				bits.ask("PickHay", "Objective")
			end
		end
	end
end

--------------------------------------------------------------------------------

-- The loop.
local farm = { bits = nil, spot = 1, herePicks = 0, held = 0, bags = 0, picks = 0, rainbow = 0 }

function farm.wire(bits)
	farm.bits = bits
end

function farm.spots()
	local bits = farm.bits
	if not bits then
		return {}
	end
	if farm.ring then
		return farm.ring
	end
	local Config = bits.Config
	local ring = {}
	for index = 0, 7 do
		local angle = index * math.pi / 4
		ring[#ring + 1] = Config.PILE_CENTER
			+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * (Config.PILE_RADIUS + 2)
	end
	farm.ring = ring
	return ring
end

function farm.sellPart()
	local bits = farm.bits
	if not bits then
		return nil
	end
	if farm.hole and farm.hole.Parent then
		return farm.hole
	end
	for _, part in ipairs(CollectionService:GetTagged(bits.Config.SELL_PART_NAME)) do
		if part:IsA("BasePart") and part:IsDescendantOf(Workspace) then
			farm.hole = part
			return part
		end
	end
	return nil
end

-- One step per call, never two, and every step behind a gate.
function farm.tick()
	local bits = farm.bits
	if not bits or bits.F.autoCollect ~= true then
		return
	end
	if not bits.inRound() then
		-- The lobby has no pile. Say so once rather than sit there looking broken.
		if bits.due("lobbySaid", 30) then
			bits.core:Notify(Module.Name, "Nothing to farm in the lobby. Stand on a pad to start a round.", 6)
		end
		return
	end
	local root = bits.core:Root()
	if not root or not bits.core:Alive2() then
		return
	end

	local player = bits.player
	local capacity = tonumber(player:GetAttribute("HayCapacity")) or 25
	local held = tonumber(player:GetAttribute("HayHeld")) or 0
	local infinite = player:GetAttribute("InfiniteBagOwned") == true
		or player:GetAttribute("PermanentInfiniteBagOwned") == true

	if held >= capacity and not infinite then
		farm.sell(root)
		return
	end

	local reach = bits.Config.INTERACT_DISTANCE

	-- Move on when this spot has had its share, and keep moving until we arrive.
	--
	-- Advancing the spot on its own does nothing, which is how the first version
	-- of this behaved: there was still hay within twenty studs, so the next tick
	-- picked it, wander was never reached, and the farm stood at one point of the
	-- ring for fifty-five seconds and eighty-five picks. Watched. The needle only
	-- reveals for picks near wherever it is buried, so a farm that hollows out one
	-- side is a farm that never finds it.
	if farm.moving then
		if farm.wander(root) then
			farm.moving = false
		end
		return
	end

	local walkFor = bits.F.rainbowFirst == false and 0 or (tonumber(bits.F.rainbowWalk) or 0)
	local part, why = pile.pick(root.Position, reach, walkFor)

	if not part then
		farm.moving = true
		return
	end

	-- A strand worth walking for is walked to, not fired at from across the pile.
	if why == "walk" then
		local distance = (part.Position - root.Position).Magnitude
		if distance > reach - 2 then
			bits.core:WalkToward(part.Position, reach - 4, 20)
			return
		end
	end

	local cooldown = tonumber(player:GetAttribute("HayPickCooldown")) or bits.Config.PICK_COOLDOWN
	if not bits.due("pick", cooldown + 0.05) then
		return
	end

	local id = part:GetAttribute("HayId")
	local wasRainbow = bits.isRainbow(id)
	farm.held = held
	-- The payload the game's own code sends. The second argument is the extra
	-- strands a wider grab picks up, and it is empty until HayGrabCount is above
	-- one, so it is built the way getGrabCandidates builds it or not at all.
	bits.ask("PickHay", id, farm.candidates(part, root))
	farm.picks = farm.picks + 1
	farm.herePicks = farm.herePicks + 1
	if wasRainbow then
		farm.rainbow = farm.rainbow + 1
	end

	-- Eighteen picks near the needle is what the server wants before it reveals
	-- it, and this gives each point of the ring more than that before moving on.
	if bits.F.farmSpread ~= false and farm.herePicks >= 24 then
		farm.herePicks = 0
		farm.spot = farm.spot % 8 + 1
		farm.moving = true
	end
end

-- The extra ids a wider grab takes with it, built the way the game builds them.
function farm.candidates(part, root)
	local bits = farm.bits
	local player = bits.player
	local count = tonumber(player:GetAttribute("HayGrabCount")) or 1
	local radius = tonumber(player:GetAttribute("HayGrabRadius")) or 0
	if count <= 1 or radius <= 0 then
		return {}
	end
	local rows = {}
	for _, other in ipairs(pile.nearby(part.Position, radius)) do
		local id = other:GetAttribute("HayId")
		if id and other ~= part then
			rows[#rows + 1] = { id = id, distance = (other.Position - part.Position).Magnitude }
		end
	end
	table.sort(rows, function(a, b)
		if a.distance == b.distance then
			return a.id < b.id
		end
		return a.distance < b.distance
	end)
	local out = {}
	for index = 1, math.min(count - 1, #rows) do
		out[#out + 1] = rows[index].id
	end
	return out
end

function farm.sell(root)
	local bits = farm.bits
	if bits.F.sellWhenFull == false then
		return
	end
	local hole = farm.sellPart()
	if not hole then
		if bits.due("noHole", 20) then
			bits.core:Notify(Module.Name, "Cannot find the cow's hole in this map.", 5)
		end
		return
	end
	local distance = (hole.Position - root.Position).Magnitude
	if distance > bits.Config.SELL_INTERACT_DISTANCE - 4 then
		bits.core:WalkToward(hole.Position, 8, 20)
		return
	end
	if not bits.due("sell", 1.5) then
		return
	end
	-- No arguments at all, and no aim either. The client gates this on the camera
	-- pointing into the hole, but SellHay carries nothing, so the server can only
	-- be checking distance - watched paying out in full with the camera facing
	-- the other way.
	bits.ask("SellHay")
	farm.bags = farm.bags + 1
	farm.spend()
end

function farm.spend()
	local bits = farm.bits
	if bits.F.autoBuy ~= true or not bits.due("spend", 3) then
		return
	end
	local state = ladder.state()
	local cash = state and tonumber(state.cash)
	if not cash then
		return
	end
	local reserve = tonumber(bits.F.buyReserve) or 0
	local want, saving = ladder.best(cash - reserve, bits.F.buyAllow, bits.F.buyPayback)
	if not want then
		-- Say what it is holding out for, once, rather than look idle while the
		-- money piles up.
		if saving and farm.savingFor ~= saving.id then
			farm.savingFor = saving.id
			bits.core:Notify(Module.Name,
				("Saving for the %s, $%.2f"):format(saving.label, saving.cost), 5)
		end
		return
	end
	farm.savingFor = nil
	if ladder.buy(want) then
		bits.core:Notify(Module.Name,
			("%s, $%.2f, pays for itself in %d seconds"):format(want.label, want.cost, want.payback), 5)
	end
end

-- Walk to the spot we are headed for. True once we are standing on it.
function farm.wander(root)
	local bits = farm.bits
	local ring = farm.spots()
	local where = ring[farm.spot]
	if not where then
		return true
	end
	local flat = Vector3.new(where.X - root.Position.X, 0, where.Z - root.Position.Z)
	if flat.Magnitude <= 6 then
		farm.herePicks = 0
		return true
	end
	-- Give up on a spot we cannot get to rather than lean on it for good. The
	-- pile is fenced in places and one point of the ring can be behind geometry.
	if bits.due("wanderGiveUp", 12) then
		if farm.stuckAt and (farm.stuckAt - root.Position).Magnitude < 4 then
			farm.spot = farm.spot % #ring + 1
			farm.herePicks = 0
			farm.stuckAt = nil
			return true
		end
		farm.stuckAt = root.Position
	end
	bits.core:WalkToward(where, 5, 20)
	return false
end

--------------------------------------------------------------------------------

-- Every declared default, copied into the flags once the controls exist.
--
-- Maclib does not call an element's Callback for its own Default, so a declared
-- default never reaches the flag table and a control drawn as on behaves as off.
--
-- Toggles are in here and not just sliders and dropdowns, which is not what the
-- template says, and the template is wrong. Read off the live hub with all
-- sixteen controls built: core.Flags held rainbowWalk, buyReserve and buyAllow
-- and nothing else at all. Six toggles declaring Default = true were absent, so
-- Highlight The Needle drew as on while `F.needleHighlight == true` was false
-- and the highlight could never appear. That is the same bug as the Pick By
-- dropdown in Steal An Egg - a switch lying about what it does - and it is only
-- ever found by reading the flags during a live run.
local seeded = {}

function seeded.apply(core)
	local flags = core.Flags
	for _, entry in ipairs(core.Controls or {}) do
		local flag = entry.flag or entry.Flag
		local kind = entry.kind or entry.Kind
		local settings = entry.control and entry.control.Settings
		if flag and flags[flag] == nil and type(settings) == "table" then
			local default = settings.Default
			local value = nil
			if kind == "Slider" then
				value = tonumber(default)
			elseif kind == "Toggle" then
				value = default == true
			elseif kind == "Dropdown" then
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

function Module.Build(ctx)
	local core, tabGroup = ctx.core, ctx.TabGroup
	local F = core.Flags
	local LocalPlayer = Players.LocalPlayer

	----------------------------------------------------------------------------
	-- reaching the server
	----------------------------------------------------------------------------
	--
	-- One way out, and it looks up what it is talking to first.
	--
	-- This game keeps its whole round in one folder of plainly named remotes,
	-- which is the opposite of the network map in Steal An Egg: there are no
	-- names here without a remote behind them. That is worth not taking for
	-- granted, so the folder is still asked rather than assumed, and a missing
	-- remote comes back as a refusal rather than an error.
	local Remotes = ReplicatedStorage:FindFirstChild("NeedleHaystack")

	local function folder()
		if Remotes and Remotes.Parent then
			return Remotes
		end
		Remotes = ReplicatedStorage:FindFirstChild("NeedleHaystack")
		return Remotes
	end

	local function ask(name, ...)
		local where = folder()
		local remote = where and where:FindFirstChild(name)
		if not remote then
			return false, "this game has no " .. tostring(name)
		end
		if remote:IsA("RemoteFunction") then
			local ok, value = pcall(function(...)
				return remote:InvokeServer(...)
			end, ...)
			if not ok then
				return false, tostring(value)
			end
			return value ~= false, value
		end
		if remote:IsA("RemoteEvent") then
			local ok, err = pcall(function(...)
				remote:FireServer(...)
			end, ...)
			if ok then
				return true
			end
			return false, tostring(err)
		end
		return false, name .. " is a " .. remote.ClassName
	end

	-- A gate every repeated request goes through. An impossible request asked
	-- twice a second is the one thing that reliably removes an account, and this
	-- game hands out a cooldown of its own - HayPickCooldown - which is the
	-- number the picking gate uses rather than one of ours.
	local nextDue = {}

	local function due(key, interval)
		local now = os.clock()
		if now < (nextDue[key] or 0) then
			return false
		end
		nextDue[key] = now + interval
		return true
	end

	----------------------------------------------------------------------------
	-- the game's own modules
	----------------------------------------------------------------------------
	--
	-- Config is where the whole game is written down, including the two numbers
	-- this module is built on: HAY_VALUE and RAINBOW_VALUE_MULTIPLIER.
	--
	-- It only exists in a gameplay place. In the lobby there is no NeedleHaystack
	-- folder at all, so this cannot be a WaitForChild - the loader would sit on
	-- it forever and the window would never finish.
	local inRound = game.PlaceId ~= LOBBY_PLACE
	local Config = nil
	if Remotes then
		local configModule = Remotes:FindFirstChild("Config")
		if configModule then
			local ok, loaded = pcall(require, configModule)
			Config = ok and loaded or nil
		end
	end

	-- Enough of Config to keep every reader honest when we are in the lobby and
	-- there is nothing to read. Same names, same meanings, so no call site has
	-- to know which one it got.
	Config = Config or {
		HAY_VALUE = 0.01,
		RAINBOW_VALUE_MULTIPLIER = 10,
		RAINBOW_CHANCE = 0.0025,
		PLACEMENT_SEED = 8242026,
		PICK_COOLDOWN = 0.55,
		PITCHFORK_COOLDOWN = 0.85,
		INTERACT_DISTANCE = 20,
		SELL_INTERACT_DISTANCE = 20,
		SELL_PART_NAME = "SellPart",
		PILE_CENTER = Vector3.new(-199.184, 2.1, 30.241),
		PILE_RADIUS = 17,
		UPGRADE_TRACKS = { Capacity = { Levels = {} }, Pitchfork = { Levels = {} },
			PitchforkCooldown = { Levels = {} } },
	}

	-- The game's own valuation, and the reason this module exists.
	--
	-- isRainbow is a pure hash of the strand's id: no server call, no state, the
	-- same answer on every client. Which means a farm can know that this strand
	-- is worth ten of the one next to it before it reaches for either.
	local isRainbow = Config.isRainbow
	if type(isRainbow) ~= "function" then
		-- The same hash, in case Config could not be reached. Copied from the
		-- game's own function rather than invented, so the two cannot disagree.
		isRainbow = function(id)
			if type(id) ~= "number" then
				return false
			end
			local value = math.sin(id * 7.31413 + Config.PLACEMENT_SEED * 0.00037 + 1913.77) * 24634.6345
			return value - math.floor(value) < Config.RAINBOW_CHANCE
		end
	end

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.MaxParts = 400

	----------------------------------------------------------------------------
	-- what the needle is drawn with
	----------------------------------------------------------------------------
	--
	-- Made once, here, on the build thread. A loop thread is resumed by the
	-- engine and a resumed thread cannot call Instance.new at all: it fails with
	-- "the current thread cannot access Instance" every tick, forever, and the
	-- highlight silently draws nothing. Steal An Egg's ESP was built twice before
	-- that was understood.
	--
	-- PlayerGui rather than gethui(), for the same reason measured there: a loop
	-- thread can write to the world all day but cannot write to anything inside
	-- gethui().
	local holder = Instance.new("Folder")
	holder.Name = "MeridianNeedle"
	holder.Parent = LocalPlayer:WaitForChild("PlayerGui")
	core:Track(holder)

	local mark = Instance.new("Highlight")
	mark.FillColor = Color3.fromRGB(120, 235, 255)
	mark.OutlineColor = Color3.fromRGB(235, 250, 255)
	mark.FillTransparency = 0.45
	mark.OutlineTransparency = 0
	mark.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	mark.Enabled = false
	mark.Parent = holder

	-- Drawn in the world rather than on the screen. A Drawing line is a 2D
	-- overlay that has to be re-projected every time the camera moves; a
	-- CylinderHandleAdornment is real geometry that turns with the world on its
	-- own and still draws through walls. It is what Ability Arena uses and what
	-- he said looks right.
	local tracer = Instance.new("CylinderHandleAdornment")
	tracer.Radius = 0.07
	tracer.AlwaysOnTop = true
	tracer.ZIndex = 0
	tracer.Transparency = 0.3
	tracer.Color3 = Color3.fromRGB(120, 235, 255)
	tracer.Visible = false
	tracer.Parent = holder

	----------------------------------------------------------------------------

	local bits = {
		F = F,
		core = core,
		ask = ask,
		due = due,
		player = LocalPlayer,
		Config = Config,
		isRainbow = isRainbow,
		overlap = overlap,
		mark = mark,
		remotes = {
			GetHayState = Remotes and Remotes:FindFirstChild("GetHayState"),
			GetUpgradeState = Remotes and Remotes:FindFirstChild("GetUpgradeState"),
		},
		inRound = function()
			return game.PlaceId ~= LOBBY_PLACE
		end,
	}
	pile.wire(bits)
	ladder.wire(bits)
	needle.wire(bits)
	farm.wire(bits)

	-- What the server says about the needle, taken the moment it says it.
	if Remotes then
		local told = Remotes:FindFirstChild("NeedleTargetChanged")
		if told then
			core:Connect(told.OnClientEvent, function(id)
				needle.hayId = tonumber(id)
				needle.part = nil
			end)
		end
		for _, name in ipairs({ "NeedleFound", "NeedleHandIn", "NeedleRoundCompleted" }) do
			local done = Remotes:FindFirstChild(name)
			if done then
				core:Connect(done.OnClientEvent, function()
					needle.forget()
				end)
			end
		end
	end

	----------------------------------------------------------------------------
	-- the interface
	----------------------------------------------------------------------------

	local farmTab = tabGroup:Tab({ Name = "Farm", Image = "rbxassetid://10723407389" })
	local needleTab = tabGroup:Tab({ Name = "Needle", Image = "rbxassetid://10734898355" })

	local hayLeft = farmTab:Section({ Side = "Left" })
	local moneyRight = farmTab:Section({ Side = "Right" })
	local needleLeft = needleTab:Section({ Side = "Left" })

	----------------------------------------------------------------- farm · left

	hayLeft:Header({ Text = "Hay" })

	hayLeft:Toggle({
		Name = "Auto Collect",
		Default = false,
		Callback = function(state)
			F.autoCollect = state
		end,
	}, "autoCollect")

	hayLeft:Toggle({
		Name = "Rainbow Hay First",
		Default = true,
		Callback = function(state)
			F.rainbowFirst = state
		end,
	}, "rainbowFirst")

	hayLeft:Slider({
		Name = "Walk For Rainbow",
		Default = 22,
		Minimum = 0,
		Maximum = 60,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.rainbowWalk = value
		end,
	}, "rainbowWalk")

	hayLeft:Toggle({
		Name = "Spread Out",
		Default = true,
		Callback = function(state)
			F.farmSpread = state
		end,
	}, "farmSpread")

	---------------------------------------------------------------- farm · right

	moneyRight:Header({ Text = "Money" })

	moneyRight:Toggle({
		Name = "Sell When Full",
		Default = true,
		Callback = function(state)
			F.sellWhenFull = state
		end,
	}, "sellWhenFull")

	moneyRight:Toggle({
		Name = "Buy Upgrades",
		Default = false,
		Callback = function(state)
			F.autoBuy = state
		end,
	}, "autoBuy")

	moneyRight:Dropdown({
		Name = "Spend On",
		Multi = false,
		Required = true,
		Options = { "Everything", "Bag Only", "Pitchfork Only" },
		Default = 1,
		Callback = function(value)
			F.buyAllow = value
		end,
	}, "buyAllow")

	moneyRight:Slider({
		Name = "Pays Back Within",
		Default = 600,
		Minimum = 60,
		Maximum = 1800,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.buyPayback = value
		end,
	}, "buyPayback")

	moneyRight:Slider({
		Name = "Keep In Reserve",
		Default = 0,
		Minimum = 0,
		Maximum = 50,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(value)
			F.buyReserve = value
		end,
	}, "buyReserve")

	--------------------------------------------------------------------- needle

	needleLeft:Header({ Text = "The Needle" })

	needleLeft:Toggle({
		Name = "Highlight The Needle",
		Default = true,
		Callback = function(state)
			F.needleHighlight = state
		end,
	}, "needleHighlight")

	needleLeft:Toggle({
		Name = "Tracer To The Needle",
		Default = true,
		Callback = function(state)
			F.needleTracer = state
		end,
	}, "needleTracer")

	needleLeft:Toggle({
		Name = "Go And Get It",
		Default = false,
		Callback = function(state)
			F.needleFetch = state
		end,
	}, "needleFetch")

	needleLeft:Toggle({
		Name = "Announce The Reveal",
		Default = true,
		Callback = function(state)
			F.needleAnnounce = state
		end,
	}, "needleAnnounce")

	----------------------------------------------------------------------------
	-- the loops
	----------------------------------------------------------------------------

	core:Loop("farm", 0.1, function()
		farm.tick()
	end)

	core:Loop("needle", 0.35, function()
		needle.tick()
	end)

	-- The rainbow list, a slice at a time. Only worth keeping while something is
	-- actually going to walk for one.
	core:Loop("rainbow", 0.25, function()
		if inRound and F.autoCollect == true and (tonumber(F.rainbowWalk) or 0) > 0 then
			pile.sweep()
		end
	end)

	-- Every frame, not three times a second. Where the line has to be drawn
	-- changes every time the camera moves, which is sixty times faster than
	-- anything else here needs to run.
	core:Connect(RunService.Heartbeat, function()
		local root = core:Root()
		local target = (F.needleHighlight == true and F.needleTracer ~= false) and needle.part or nil
		if root and target and target.Parent then
			local relative = root.CFrame:PointToObjectSpace(target.Position)
			local length = relative.Magnitude
			if length > 0.5 then
				tracer.Adornee = root
				tracer.Height = length
				tracer.CFrame = CFrame.lookAt(Vector3.zero, relative) * CFrame.new(0, 0, -length / 2)
				tracer.Visible = true
				return
			end
		end
		if tracer.Visible then
			tracer.Visible = false
			tracer.Adornee = nil
		end
	end)

	-- Nothing in Build may yield. Build runs part way through the loader
	-- assembling the window, and a thread that yields comes back without the
	-- capability to touch the interface.
	seeded.apply(core)

	return {
		Tabs = {
			Farm = farmTab,
			Needle = needleTab,
		},
		Default = farmTab,
		Tips = Module.Tips,
	}
end

return Module
