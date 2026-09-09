--// Meridian · TEMPLATE
--// Copy this to games/<game_name>.luau, fill in the two ids at the top, and
--// add one line to the GAMES table in main.luau. Nothing else is shared.
--//
--// Read LAUNCH.md before you start. It is short and every line in it was paid
--// for by a bug that shipped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Module = {
	GameId = 0,
	Name = "Template",
}

-- Hover text, one line each, written for somebody who has never seen the code.
-- No mechanisms, no numbers you would not actually set.
Module.Tips = {
	["Example Toggle"] = "What it does, in the words a player would use.",
}

--------------------------------------------------------------------------------
-- file scope
--------------------------------------------------------------------------------
--
-- Build is ONE function against Luau's ceiling of 200 local registers, and a
-- real game module reaches it. Every feature past the first dozen lives out
-- here on a table and gets handed what it needs once, through a wire function.
-- That costs nothing inside Build.
--
-- ./check.sh games/<your file>.luau catches the ceiling before the executor
-- does. luau-analyze does NOT catch it.

local feature = { bits = nil }

function feature.wire(bits)
	feature.bits = bits
end

function feature.tick()
	local bits = feature.bits
	if not bits or bits.F.exampleToggle ~= true then
		return
	end
	-- one step per call, never two, and every step behind a gate
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
	-- Network.Fire calls FireServer and Network.Invoke calls InvokeServer, and
	-- which one is right is a property of the remote, not of what you want. A
	-- RemoteFunction fired throws, and a client throwing at the server several
	-- times a second is what gets accounts removed.
	--
	-- Names in a game's network map routinely have no remote behind them. Ask
	-- the folder, not the map.
	local Remotes = ReplicatedStorage:FindFirstChild("Network")

	local function ask(name, ...)
		if type(name) ~= "string" then
			return false, "no such action"
		end
		local folder = Remotes
		if not folder or not folder.Parent then
			folder = ReplicatedStorage:FindFirstChild("Network")
			Remotes = folder
		end
		local remote = folder and folder:FindFirstChild(name)
		if not remote then
			return false, "this game has no " .. name
		end
		if remote:IsA("RemoteFunction") then
			local ok, value, reason = pcall(function(...)
				return remote:InvokeServer(...)
			end, ...)
			if not ok then
				return false, tostring(value)
			end
			return value ~= false, reason
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
	-- twice a second is the one thing that reliably gets an account kicked.
	local nextDue = {}

	local function due(key, interval)
		local now = os.clock()
		if now < (nextDue[key] or 0) then
			return false
		end
		nextDue[key] = now + interval
		return true
	end

	feature.wire({
		F = F,
		ask = ask,
		due = due,
		core = core,
		player = LocalPlayer,
	})

	----------------------------------------------------------------------------
	-- the interface
	----------------------------------------------------------------------------

	local mainTab = tabGroup:Tab({ Name = "Main", Image = "rbxassetid://10723407389" })
	local left = mainTab:Section({ Side = "Left" })

	left:Header({ Text = "Example" })

	left:Toggle({
		Name = "Example Toggle",
		Default = false,
		Callback = function(state)
			F.exampleToggle = state
		end,
	}, "exampleToggle")

	-- Maclib fires a Toggle's callback when it is created and does NOT fire a
	-- Slider's or a Dropdown's, so a slider default never reaches the flag
	-- unless the reading code falls back to the same number the control shows.
	-- Keep the two in step or the switch lies about what it does.

	core:Loop("main", 1, function()
		feature.tick()
	end)

	-- Nothing in Build may yield. Build runs part way through the loader
	-- assembling the window, and a thread that yields comes back without the
	-- capability to touch the interface. Use task.spawn for anything that waits.

	return {
		Tabs = {
			Main = mainTab,
		},
		Default = mainTab,
		Tips = Module.Tips,
	}
end

return Module
