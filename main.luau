--// Prism · entry point
--//
--// One script for every game. It works out which game module to load from
--// game.GameId, so the same link works everywhere and there is only ever one
--// key, one config folder and one window to maintain.

local BRAND = "Meridian Hub"
local SHORT = "Meridian"
local OLD_NAMES = { "Prism" }
local VERSION = "0.3.0"

-- The key screen is always on now, because it is what everyone will actually
-- meet first and it should never be the part nobody looked at. The check itself
-- is a placeholder until Luarmor is bought; see verifyKey for the two lines
-- that change.
local REQUIRE_KEY = true

local DISCORD = "https://discord.gg/prism"

-- Where the modules come from. On the machine they are written on they sit in
-- the executor's workspace folder; for everybody else they come off the raw
-- host.
--
-- Worked out rather than set, so this file is the same file in both places. A
-- mode that has to be flipped by hand means the copy in the repo is the working
-- copy with one line changed, and that line is the one that gets forgotten.
-- The branch testers load from. Every branch's copy of this file names the same
-- one on purpose: promoting a build is then a fast-forward with nothing to edit,
-- and there is no line to forget. The cost is that a link pointing at any other
-- branch would fetch that branch's main.luau and everything else from this one,
-- so there is only ever one link to hand out and this is the branch it names.
local CHANNEL = "stable"

local SOURCE = {
	folder = "Meridian/",
	base = ("https://raw.githubusercontent.com/prathahanh/meridian-hub/%s/"):format(CHANNEL),
}

SOURCE.mode = (function()
	local ok, body = pcall(function()
		return readfile(SOURCE.folder .. "main.luau")
	end)
	if ok and type(body) == "string" and #body > 0 then
		return "local"
	end
	return "remote"
end)()

local GAMES = {
	{ id = 10230942274, path = "games/ability_arena.luau", name = "Ability Arena" },
	{ id = 10563114921, path = "games/steal_an_egg.luau", name = "Steal An Egg" },
}

--------------------------------------------------------------------------------

local function fetch(path)
	if SOURCE.mode == "local" then
		return readfile(SOURCE.folder .. path)
	end
	return game:HttpGet(SOURCE.base .. path)
end

local function import(path)
	local source = fetch(path)
	local chunk, err = loadstring(source, "=" .. BRAND .. "/" .. path)
	if not chunk then
		error(("%s failed to load %s: %s"):format(BRAND, path, tostring(err)), 0)
	end
	return chunk()
end

-- A second run should replace the first, not stack on top of it.
local genv = getgenv()
for _, key in ipairs({ "Meridian", "Prism" }) do
	local previous = genv[key]
	if type(previous) == "table" and previous.Unload then
		pcall(previous.Unload)
	end
	genv[key] = nil
end

-- Unloading whatever finished before us is not enough, and he has seen why:
-- two hubs on screen at once, every click landing on whichever happened to be
-- in front.
--
-- The sweep above only catches a run that had already published a handle. Two
-- runs starting within a second of each other - a relaunch queued for a
-- teleport and a loader run by hand, which is exactly what a session of testing
-- looks like - both find nothing to unload and both finish.
--
-- So each run takes a number, and the newest number wins. A run that finds a
-- newer one has appeared while it was loading stops where it is rather than
-- putting a second window up.
local RUN = (tonumber(genv.MeridianRun) or 0) + 1
genv.MeridianRun = RUN

local function stale()
	return genv.MeridianRun ~= RUN
end

-- That alone is not enough. Rejoining the game throws away the environment
-- that remembered the old window while the hidden gui container survives, so
-- the next run would build a second menu on top of an orphaned one, and every
-- click would land on whichever happened to be in front. Sweep by name.
local function removeOldWindows()
	local roots = {}
	local ok, hidden = pcall(function()
		return gethui()
	end)
	if ok and hidden then
		table.insert(roots, hidden)
	end
	table.insert(roots, game:GetService("CoreGui"))

	for _, root in ipairs(roots) do
		for _, gui in ipairs(root:GetChildren()) do
			if gui:IsA("ScreenGui") then
				local base = gui:FindFirstChild("Base")
				local sidebar = base and base:FindFirstChild("Sidebar")
				local holder = sidebar
					and sidebar:FindFirstChild("Information")
					and sidebar.Information:FindFirstChild("InformationHolder")
				local title = holder
					and holder:FindFirstChild("TitleFrame")
					and holder.TitleFrame:FindFirstChild("Title")
				if title then
					local matches = title.Text == BRAND
					for _, old in ipairs(OLD_NAMES) do
						matches = matches or title.Text == old
					end
					if matches then
						pcall(function()
							gui:Destroy()
						end)
					end
				end
			end
		end
	end
end

pcall(removeOldWindows)

local MacLib = loadstring(game:HttpGet("https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.txt"))()
local Core = import("core.luau")

local core = Core.new({ Name = BRAND, Version = VERSION })

--------------------------------------------------------------------------------
-- which game are we in
--------------------------------------------------------------------------------

local entry = nil
for _, candidate in ipairs(GAMES) do
	if candidate.id == game.GameId then
		entry = candidate
		break
	end
end

if not entry then
	local Window = MacLib:Window({
		Title = BRAND,
		Subtitle = "Unsupported game",
		Size = UDim2.fromOffset(520, 300),
		DragStyle = 1,
		DisabledWindowControls = {},
		ShowUserInfo = true,
		Keybind = Enum.KeyCode.K,
		AcrylicBlur = true,
	})
	local tab = Window:TabGroup():Tab({ Name = "Games", Image = "rbxassetid://7541897766" })
	local section = tab:Section({ Side = "Left" })
	section:Header({ Text = "Nothing for this game yet" })
	section:Paragraph({
		Header = "Supported right now",
		Body = "Ability Arena and Steal An Egg.\n\nSend the id below and it can be next.",
	})
	section:Button({
		Name = "Copy Game ID",
		Callback = function()
			setclipboard(tostring(game.GameId))
			Window:Notify({ Title = BRAND, Description = "Copied " .. tostring(game.GameId), Lifetime = 4 })
		end,
	})
	section:Button({
		Name = "Copy Discord Link",
		Callback = function()
			setclipboard(DISCORD)
		end,
	})
	tab:Select()
	genv.Meridian = {
		Unload = function()
			Window:Unload()
		end,
	}
	return
end

--------------------------------------------------------------------------------
-- key screen
--------------------------------------------------------------------------------

-- Placeholders until Luarmor exists. Short on purpose so testing is not a
-- typing exercise. The value is the tier the dashboard will report.
--
-- One key each for the testers, so a bug report says who sent it and cutting
-- one person off is deleting one line. Be clear about what this is: while the
-- repo is public anybody can read this table, so a key says who you are and
-- restricts nothing. Restriction arrives with Luarmor. Keys are lowercased and
-- stripped of spaces before they are checked, so write them that way here.
local TEST_KEYS = {
	dev = "Developer",
	free = "Free",
}

local function verifyKey(entered)
	-- Luarmor swap, once Premium is bought:
	--   local api = loadstring(game:HttpGet("https://sdkapi-public.luarmor.net/library.lua"))()
	--   api.script_id = SCRIPT_ID
	--   local reply = api.check_key(entered)
	--   core.Tier, core.KeyExpiresAt = reply.note, reply.auth_expire
	--   return reply.code == "KEY_VALID"
	if type(entered) ~= "string" then
		return false
	end
	local cleaned = entered:lower():gsub("%s", "")
	local tier = TEST_KEYS[cleaned]
	if not tier then
		return false
	end
	core.Tier = tier
	core.Key = cleaned
	return true
end

--------------------------------------------------------------------------------
-- surviving a server hop
--------------------------------------------------------------------------------

-- A teleport ends this script. The Farm tab's Server panel teleports on purpose,
-- and without this an unattended farm arrives in the new server with no hub at
-- all, which makes the feature it was built for pointless.
--
-- The key rides along inside the queued string rather than in a file on disk.
-- Nothing about how keys are checked changes, and nothing is left behind on the
-- machine afterwards.
local function relaunchSource()
	if SOURCE.mode == "local" then
		return ("loadstring(readfile(%q), %q)()"):format(SOURCE.folder .. "main.luau", "=" .. BRAND .. "/main.luau")
	end
	return ("loadstring(game:HttpGet(%q))()"):format(SOURCE.base .. "main.luau")
end

-- Everything that is switched on travels with it. Without this the farm
-- arrives in the busier server it just chose with every control back at its
-- default, which is to say switched off, and the hop it took is worse than
-- having stayed. Only plain values go: a colour or a keybind is not JSON and is
-- not worth the trouble, and the player being hunted by name will not be in the
-- new server anyway.
local CARRY_SKIP = { watchPlayer = true }

local function carriedFlags()
	local out = {}
	for flag, value in pairs(core.Flags) do
		if not CARRY_SKIP[flag] then
			local kind = typeof(value)
			if kind == "boolean" or kind == "number" or kind == "string" then
				out[flag] = value
			elseif kind == "table" then
				local list, plain = {}, true
				for index, item in ipairs(value) do
					if typeof(item) == "string" then
						list[index] = item
					else
						plain = false
						break
					end
				end
				if plain and #list > 0 then
					out[flag] = list
				end
			end
		end
	end
	return out
end

core.QueueRelaunch = function()
	local queue = queue_on_teleport or queueonteleport
	if type(queue) ~= "function" then
		return false
	end
	local carry = ""
	if type(core.Key) == "string" and core.Key ~= "" then
		carry = ("getgenv().%sKey = %q "):format(SHORT, core.Key)
	end
	local packed, blob = pcall(function()
		return game:GetService("HttpService"):JSONEncode(carriedFlags())
	end)
	if packed and type(blob) == "string" then
		carry = carry .. ("getgenv().%sCarry = %q "):format(SHORT, blob)
	end
	local source = carry .. relaunchSource()
	-- Nothing to do if the queue already holds exactly this, and doing nothing
	-- matters: clearing and re-queueing on a timer means there is always a
	-- moment when the queue is empty, and a teleport landing in one of those
	-- moments is a farm that spends the rest of the night in a new server doing
	-- nothing. In the steady state this now touches the queue zero times.
	if core.LastRelaunch == source then
		return true
	end
	local clear = clear_teleport_queue or clearqueueonteleport or cleartpqueue or clearteleportqueue
	if type(clear) == "function" then
		pcall(clear)
	end
	local ok, why = pcall(queue, source)
	core.LastRelaunchError = not ok and tostring(why) or nil
	if ok then
		-- Kept so a session that comes back without its switches can be asked
		-- what it queued, rather than guessed at.
		core.LastRelaunch = source
	end
	return ok
end

-- Put them back through the controls rather than into the flag table. A flag
-- written on its own leaves the switch on screen saying the opposite of what
-- the hub is doing, which is a whole afternoon of confusion the first time it
-- happens.
local function applyCarried(blob)
	local ok, decoded = pcall(function()
		return game:GetService("HttpService"):JSONDecode(blob)
	end)
	if not ok or type(decoded) ~= "table" then
		return 0
	end
	local byFlag = {}
	for _, control in ipairs(core.Controls or {}) do
		if control.flag then
			byFlag[control.flag] = control
		end
	end
	-- The flag first, always, and then the control on top of it.
	--
	-- The three kinds do not behave the same and that is worth knowing: a
	-- toggle's UpdateState and a dropdown's UpdateSelection both run the
	-- control's callback, so the flag follows by itself. A slider's UpdateValue
	-- moves the handle and nothing else. Restoring sliders through the control
	-- alone left every number on screen correct and every number in use back at
	-- its default, which is the worst of the three possible outcomes.
	local applied = 0
	for flag, value in pairs(decoded) do
		core.Flags[flag] = value
		local entry = byFlag[flag]
		if entry then
			pcall(function()
				if entry.kind == "Toggle" then
					entry.control:UpdateState(value)
				elseif entry.kind == "Slider" then
					entry.control:UpdateValue(value)
				elseif entry.kind == "Dropdown" then
					entry.control:UpdateSelection(value)
				end
			end)
			-- A toggle's callback may have written something else on the way
			-- past, so it wins over the value that arrived.
			applied += 1
		end
	end
	return applied
end

-- The key screen is no longer a Maclib window. Tabs, a profile card and a globe
-- all tell a stranger something about the hub before they have a key, and the
-- point of that screen is to give away nothing. See key.luau.

--------------------------------------------------------------------------------
-- the real window
--------------------------------------------------------------------------------

local function start(Chrome, UI, Dashboard, module, hidden)
	local Window = MacLib:Window({
		Title = BRAND,
		Subtitle = ("%s · v%s"):format(entry.name, VERSION),
		-- Tall enough that every tab fits without the list scrolling. Seven of
		-- them need about 404 pixels, and the old 620 height only gave 391,
		-- which is what pushed Settings out of sight.
		Size = UDim2.fromOffset(880, 660),
		DragStyle = 1,
		DisabledWindowControls = {},
		ShowUserInfo = true,
		Keybind = Enum.KeyCode.K,
		AcrylicBlur = true,
	})

	-- Hidden before the first frame anyone could see, so the ceremony finishes
	-- on a clean screen rather than over a window that already arrived.
	local base = Chrome.Find(BRAND)
	if base and hidden then
		base.Visible = false
	end

	-- The return matters. Maclib hands back a notification object with Cancel
	-- on it, and that object is the only way the close button on a notification
	-- can dismiss it through Maclib's own exit animation rather than by
	-- destroying the frame under it.
	core:SetNotifier(function(title, description, lifetime)
		return Window:Notify({ Title = title, Description = description, Lifetime = lifetime })
	end)

	Window:GlobalSetting({
		Name = "UI Blur",
		Default = Window:GetAcrylicBlurState(),
		Callback = function(state)
			Window:SetAcrylicBlurState(state)
		end,
	})
	Window:GlobalSetting({
		Name = "Notifications",
		Default = Window:GetNotificationsState(),
		Callback = function(state)
			Window:SetNotificationsState(state)
		end,
	})
	Window:GlobalSetting({
		Name = "Show User Info",
		Default = Window:GetUserInfoState(),
		Callback = function(state)
			Window:SetUserInfoState(state)
		end,
	})

	-- Indexed, so every control the game module creates is searchable without
	-- the module having to know the search exists.
	local tabGroup = core:IndexTabs(Window:TabGroup())
	local built = module.Build({
		core = core,
		Window = Window,
		MacLib = MacLib,
		TabGroup = tabGroup,
	})

	----------------------------------------------------------------------------
	-- settings, same on every game
	----------------------------------------------------------------------------

	local settingsGroup = Window:TabGroup()
	local indexedSettings = core:IndexTabs(settingsGroup)

	----------------------------------------------------------------------------
	-- settings, same on every game
	----------------------------------------------------------------------------

	local settings = indexedSettings:Tab({ Name = "Settings", Image = "rbxassetid://7541906831" })
	local left = settings:Section({ Side = "Left" })

	-- No version paragraph. The dashboard behind the profile card carries that,
	-- and the menu key is a control sitting right underneath this header.
	left:Header({ Text = BRAND })

	left:Toggle({
		Name = "Feature Keybinds",
		Default = true,
		Callback = function(state)
			core.Flags.keybinds = state
		end,
	}, "keybinds")

	left:Keybind({
		Name = "Menu Key",
		Default = Enum.KeyCode.K,
		Callback = function() end,
		onBinded = function(bind)
			Window:SetKeybind(bind)
		end,
	}, "menuKey")

	-- Links used to live here. They belong to the dashboard, which is what the
	-- profile card opens, so Settings is settings and nothing else.

	-- SetFolder only exists once a window has been made, so it cannot move above
	-- the window call, and the config section has to come after it or it lists
	-- the wrong folder. Maclib ignores the side it is handed and always builds
	-- the config into the left column; ui.luau moves it across once the tab is
	-- actually built, because until then neither column exists.
	MacLib:SetFolder(SHORT)
	settings:InsertConfigSection("Right")

	local unload = function()
		core:Unload()
		pcall(function()
			Window:Unload()
		end)
		genv.Meridian = nil
	end

	Window.onUnloaded(function()
		core:Unload()
	end)

	if built and built.Default then
		built.Default:Select()
	end

	local ok, err = pcall(function()
		base = Chrome.Apply(core, BRAND, { window = Window, skipOpen = hidden })
		if base then
			UI.Apply(core, base, Window, built and built.Tips or {})
			-- Folded into Settings rather than being its own tab. Its panels sit
			-- beside the config, and the profile card selects Settings.
			Dashboard.Attach(core, base, settings, {
				brand = BRAND,
				version = VERSION,
				game = entry.name,
				tier = core.Tier or "Free",
				expiresAt = core.KeyExpiresAt,
				discord = DISCORD,
				onUnload = function()
					Window:Dialog({
						Title = BRAND,
						Description = "Close the menu and stop everything it is running?",
						Buttons = {
							{ Name = "Unload", Callback = unload },
							{ Name = "Cancel" },
						},
					})
				end,
			})
		end
	end)
	if not ok then
		warn("[" .. BRAND .. "] chrome: " .. tostring(err))
	end

	pcall(function()
		MacLib:LoadAutoLoadConfig()
	end)

	local tabs = built and built.Tabs or {}
	tabs.Settings = settings

	-- Somebody newer started while this one was building. Take this window back
	-- down rather than leaving two of them up.
	if stale() then
		pcall(unload)
		return nil, nil
	end

	genv.Meridian = {
		Core = core,
		Window = Window,
		Tabs = tabs,
		Unload = unload,
	}

	return Window, base
end

--------------------------------------------------------------------------------
-- entry
--------------------------------------------------------------------------------

local Access = import("key.luau")

if not REQUIRE_KEY then
	start(import("chrome.luau"), import("ui.luau"), import("dashboard.luau"), import(entry.path), false)
	core:Notify(BRAND, entry.name .. " loaded", 4)
	return
end

-- A Luau thread inherits the capability set of whatever created it, and the key
-- screen's button callback is a restricted one. Building the hub from inside it
-- produced loops that could not touch the interface at all, failing with "the
-- current thread cannot access Instance" every time they tried to write to a
-- label. setthreadidentity does not help, because capability is not identity.
--
-- So the work is handed back to a thread created here, at the top of the script,
-- where capability is still full. The ceremony only queues it.
-- Loaded here, at the top of the script, and not inside the ceremony. A chunk
-- compiled from a spawned thread inherits that thread's capability set, and
-- every closure in it keeps it for good: modules loaded from inside the unlock
-- callback could not write so much as a label's Text, failing with "the current
-- thread cannot access Instance" forever after. Loading them here is the fix,
-- and it costs four file reads before the key screen appears.
local Chrome = import("chrome.luau")
local UI = import("ui.luau")
local Dashboard = import("dashboard.luau")
local GameModule = import(entry.path)

-- Arming the relaunch belongs to loading the hub, not to one of the two ways of
-- getting in, and putting it in the wrong one of those is what made "leave it
-- running overnight" untrue.
--
-- A key typed at the door goes through Access.Ask and onUnlocked. A key that
-- arrived in the teleport queue skips all of that and returns early, twenty
-- lines below. The arming lived in the first branch only, so the hub armed a
-- relaunch exactly once - when a person typed a key - and every teleport after
-- that landed in a new server with the hub dead and nothing left to bring it
-- back. Both branches call this now.
local function armRelaunch()
	if type(core.QueueRelaunch) ~= "function" then
		return
	end
	core.QueueRelaunch()
	-- Checked often, written rarely. Rebuilding the string is a table walk and a
	-- JSON encode; the queue itself is only touched when a switch has actually
	-- moved since last time, so there is never a moment where it sits empty.
	core:Loop("relaunch", 5, function()
		core.QueueRelaunch()
	end)
end

local carried = getgenv()[SHORT .. "Key"]
getgenv()[SHORT .. "Key"] = nil
if type(carried) == "string" and verifyKey(carried) then
	local window = start(Chrome, UI, Dashboard, GameModule, false)
	if not window or stale() then
		return
	end
	local blob = getgenv()[SHORT .. "Carry"]
	getgenv()[SHORT .. "Carry"] = nil
	local restored = 0
	if type(blob) == "string" then
		restored = applyCarried(blob)
	end
	core.ArrivedAt = os.clock()
	armRelaunch()
	core:Notify(
		BRAND,
		restored > 0 and ("New server, %d settings carried over"):format(restored) or "New server",
		4
	)
	return
end

local queued = nil
task.spawn(function()
	while core.Alive and not queued do
		task.wait(0.05)
	end
	if queued then
		queued()
	end
end)

Access.Ask({
	core = core,
	brand = BRAND,
	discord = DISCORD,
	verify = verifyKey,

	onUnlocked = function(ceremony)
		queued = function()
			-- The modules are already loaded, so the bar paces the window being
			-- built and dressed rather than pretending to measure file reads.
			ceremony:Step(0.3, "interface")
			ceremony:Step(0.6, entry.name:lower())

			ceremony:Step(0.92, "window")

			-- Anything the game module throws used to end here, silently, with the
			-- bar frozen at ninety-two percent and nothing to say whether it was
			-- still working. A key that has been accepted has to reach an interface
			-- or an explanation, never a bar that never moves again.
			local ok, base = pcall(function()
				local _, built = start(Chrome, UI, Dashboard, GameModule, true)
				return built
			end)

			if not ok then
				local why = tostring(base):gsub("^.-:%d+:%s*", "")
				warn(("[%s] %s failed to build: %s"):format(BRAND, entry.name, tostring(base)))
				ceremony:Finish(function()
					core:Notify(BRAND, entry.name .. " did not load. " .. why, 12)
				end)
				return
			end

			-- A newer run took over while this one was building, and it has
			-- already taken this window back down. Say nothing and stop.
			if not base or stale() then
				return
			end

			-- Keep a relaunch queued for whatever teleport comes next, not just
			-- the ones the hub starts. Steal An Egg moves you on its own: the
			-- area egg reset teleports everybody, and a server rotates underneath
			-- an unattended farm several times a night.
			armRelaunch()

			ceremony:Finish(function()
				Access.Reveal(core, base)
				task.delay(0.5, function()
					core:Notify(BRAND, entry.name .. " loaded", 4)
				end)
			end)
		end
	end,
})
