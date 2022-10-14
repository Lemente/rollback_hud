-- LUALOCALS < ---------------------------------------------------------
local io, ipairs, minetest, pairs, sz_pos, sz_table
	= io, ipairs, minetest, pairs, sz_pos, sz_table
local io_close, io_open
	= io.close, io.open
-- LUALOCALS > ---------------------------------------------------------

local modname = minetest.get_current_modname()

------------------------------------------------------------------------
-- MANAGE SELECTED NODES TO DEBUG

local datapath = minetest.get_worldpath() .. "/" .. modname .. ".txt"

local S = minetest.get_translator(modname)

local hud_node = "air"
local hud_player = "all"
local hud_distance = 16
local hud_showtime = true
local hud_time = 86400*3 -- 3 days
local hud_beforetime = 0

cmdlib.register_chatcommand("rollback_hud", {
	params = "[node] [player] [distance] [time] [before_time] [show_time]",
--	custom_syntax = ,
--	implicit_calls = ,
	description = "Show rollback info as hud.",
	privs = {rollback = true},
	func = function(name, params)
		if params.node then hud_node = params.node else hud_node = "all" end
		if params.player then hud_player = params.player else hud_player = "all" end
		if params.distance then
			params.distance = tonumber(params.distance)
			if not params.distance then return false, "Distance needs to be a valid number"
			elseif params.distance > 50 or params.distance < 1 then return false, "Distance should be between 1 and 50"
			else hud_distance = params.distance end
		end
		if params.time then
			if params.time == 0 or params.time == "default" or params.time == nil then
				hud_time = 86400*3 -- default to the past 3 days
			else
				params.time = tonumber(params.time)
				if not params.time then return false, "Time needs to be a valid number, or default"
				else hud_time = params.time end
			end
		end
		if params.show_time then hud_showtime = params.hud_showtime end
	end
})

------------------------------------------------------------------------
-- UPDATE DEBUG HUDS CONTINUOUSLY

local function debugdata(pos)
	local node = pos:node_get()
	local name = node.name .. ":" .. node.param1 .. ":" .. node.param2
	local lines = sz_table:new()
	local environ = sz_table:new()
	local actions = core.rollback_get_node_actions(pos, 1, hud_time, 1)
	local num_actions = #actions
	lines:insert(environ:concat(", "))
	if not actions or num_actions == 0 then return
	else
		local time = os.time()
		for i = num_actions, 1, -1 do
			local action = actions[i]
			lines:insert(minetest.colorize("#000000", S("@1",action.actor)))
			if hud_showtime then lines:insert(S("@1 seconds ago",time - action.time)) end--"il y a @1 secondes"
		end
	end
	return lines:concat("\n")
end

local allhuds = {}

minetest.register_globalstep(function()
		for k, p in pairs(allhuds) do
			for k, h in pairs(p) do
				h(true)
			end
		end
	end)

------------------------------------------------------------------------
-- PERIODICALLY SCAN NODES AND ATTACH HUDS

local function mkhud(player, pos)
	local text = debugdata(pos)
	local id = player:hud_add({
			hud_elem_type = "waypoint",
			world_pos = pos,
			name = text,
			text = "",
			number = 0xffffff,--0xFFFF80,
			precision = 0 -- hides distance
		})
	return function(keep)
		if not keep then return player:hud_remove(id) end
		local t = debugdata(pos)
		if t ~= text then player:hud_change(id, "text", t) end
		text = t
	end
end

local function rescan()
	minetest.after(1, rescan)
	for i, player in ipairs(minetest.get_connected_players()) do
		local n = player:get_player_name()
		local phuds = allhuds[n] or {}
		if not minetest.get_player_privs(player:get_player_name()).rollback then
			for k, v in pairs(phuds) do
				v()
			end
			allhuds[n] = nil
		else
			local newhuds = {}
			local sel = hud_node--[n]
			if sel then
				local bydist = sz_table:new()
				local ppos = sz_pos:new(player:getpos())
				for i, pos in ipairs(ppos:nodes_in_area(hud_distance, sel)) do
					pos = sz_pos:new(pos)
					local d = pos:sub(ppos)
					d = d:dot(d)
					bydist[d] = bydist[d] or { }
					bydist[d][pos:hash()] = pos
				end
				local dists = bydist:keys()
				dists:sort()
				local t = 0
				for i, d in ipairs(dists) do
					for hash, pos in pairs(bydist[d]) do
						t = t + 1
						if t > 1000 then break end
						local hud = phuds[hash] or mkhud(player, pos)
						newhuds[hash] = hud
						phuds[hash] = nil
						hud(true)
					end
					if t > 1000 then break end
				end
			end
			for k, v in pairs(phuds) do
				v()
			end
			allhuds[n] = newhuds
		end
	end
end
minetest.after(1, rescan)
