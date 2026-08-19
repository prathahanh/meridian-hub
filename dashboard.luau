--// Meridian · dashboard
--//
--// A real tab, built out of Maclib's own sections, labels and buttons.
--//
--// The first version was an overlay drawn by hand over the content area, and
--// it was wrong twice over: it never matched a real tab however carefully the
--// colours were copied, and you had to press a close button to get out of it
--// instead of just clicking another tab. Both problems go away by not drawing
--// it ourselves. It is reached from the sidebar like any other tab.

local Dashboard = {}

local function clock(seconds)
	if not seconds or seconds <= 0 then
		return "unlimited"
	end
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if days > 0 then
		return ("%dd %dh"):format(days, hours)
	end
	if hours > 0 then
		return ("%dh %dm"):format(hours, minutes)
	end
	return ("%dm"):format(math.max(minutes, 1))
end

function Dashboard.Attach(core, base, tab, info)
	if not tab then
		return
	end

	----------------------------------------------------------------------------
	-- panels
	----------------------------------------------------------------------------

	-- All three on the right, on purpose. Settings already holds the hub panel
	-- and Maclib's config on the left, so putting these there too left the
	-- rebalancing to sort out four panels against one while they were still
	-- being added, and it shuffled them into a different order each run.
	local keyPanel = tab:Section({ Side = "Right" })
	keyPanel:Header({ Text = "Key" })
	local accessLabel = keyPanel:Label({ Text = "Access · " .. tostring(info.tier or "Free") })
	local expiresLabel = keyPanel:Label({ Text = "Expires · " .. clock(info.expiresIn) })
	local versionLabel = keyPanel:Label({ Text = "Version · v" .. tostring(info.version) })

	local sessionPanel = tab:Section({ Side = "Right" })
	sessionPanel:Header({ Text = "Session" })
	local gameLabel = sessionPanel:Label({ Text = "Game · " .. tostring(info.game) })
	local upLabel = sessionPanel:Label({ Text = "Running for · just started" })
	local hitsLabel = sessionPanel:Label({ Text = "Hits · 0" })
	local rateLabel = sessionPanel:Label({ Text = "An hour · 0" })

	local linksPanel = tab:Section({ Side = "Right" })
	linksPanel:Header({ Text = "Links" })

	linksPanel:Button({
		Name = "Copy Discord Link",
		Callback = function()
			if info.discord then
				setclipboard(info.discord)
				core:Notify(info.brand, "Link copied", 3)
			end
		end,
	})

	linksPanel:Button({
		Name = "Unload",
		Callback = function()
			if info.onUnload then
				info.onUnload()
			end
		end,
	})

	----------------------------------------------------------------------------
	-- live figures
	----------------------------------------------------------------------------

	-- The game module cannot write to the interface at all, so it leaves its
	-- numbers on core.Stats and they are read from here. That is also why no tab
	-- carries a status paragraph any more: the figures live in one place.
	local started = os.clock()

	core:Loop("dashboard", 1, function()
		local elapsed = os.clock() - started
		pcall(function()
			upLabel:UpdateName("Running for · " .. (elapsed < 60 and "just started" or clock(elapsed)))

			if info.expiresAt then
				expiresLabel:UpdateName("Expires · " .. clock(info.expiresAt - os.time()))
			end
			if core.Tier then
				accessLabel:UpdateName("Access · " .. tostring(core.Tier))
			end

			local stats = core.Stats
			hitsLabel:UpdateName("Hits · " .. tostring(stats and stats.Hits or 0))
			rateLabel:UpdateName("An hour · " .. tostring(stats and stats.Rate or 0))
			if stats and stats.Holding then
				gameLabel:UpdateName(("Game · %s, holding %s"):format(tostring(info.game), tostring(stats.Holding)))
			end
		end)
	end)

	----------------------------------------------------------------------------
	-- the profile card
	----------------------------------------------------------------------------
	--
	-- It used to open this tab. It does not any more: he did not want the card
	-- to be a button, and a panel that is already reachable from the sidebar
	-- does not need a second door into it.

	return { Tab = tab }
	-- No close button anywhere. Leaving is clicking another tab, which is the
	-- whole reason this stopped being an overlay.
end

return Dashboard
