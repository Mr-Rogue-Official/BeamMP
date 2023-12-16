--====================================================================================
-- All work by jojos38 & Titch2000.
-- You have no permission to edit, redistribute or upload. Contact us for more info!
--====================================================================================

--- positionGE API.
--- Author of this documentation is Titch
--- @module positionGE
--- @usage applyPos(...) -- internal access
--- @usage positionGE.handle(...) -- external access


local M = {}

local actualSimSpeed = 1

--[[
	["X-Y"] = table
		[update] = table
			[pos] = array[3]
			[rot] = array[4]
			[vel] = array[3]
			[rvel] = array[4]
			[tim] = float
			[ping] = float
		[last_tim] = float
		[exec_at] = float
		[executed] = bool
]]
local POSSMOOTHER = {}


--- Called on specified interval by positionGE to simulate our own tick event to collect data.
local function tick()
	local ownMap = MPVehicleGE.getOwnMap() -- Get map of own vehicles
	for i,v in pairs(ownMap) do -- For each own vehicle
		local veh = be:getObjectByID(i) -- Get vehicle
		if veh then
			veh:queueLuaCommand("positionVE.getVehicleRotation()")
		end
	end
end



--- Wraps vehicle position, rotation etc. data from player own vehicles and sends it to the server.
-- INTERNAL USE
-- @param data table The position and rotation data from VE
-- @param gameVehicleID number The vehicle ID according to the local game
local function sendVehiclePosRot(data, gameVehicleID)
	if MPGameNetwork.launcherConnected() then
		local serverVehicleID = MPVehicleGE.getServerVehicleID(gameVehicleID) -- Get serverVehicleID
		if serverVehicleID and MPVehicleGE.isOwn(gameVehicleID) then -- If serverVehicleID not null and player own vehicle
			local decoded = jsonDecode(data)
			local simspeedReal = simTimeAuthority.getReal()

			decoded.isTransitioning = (simTimeAuthority.get() ~= simspeedReal) or nil

			simspeedReal = simTimeAuthority.getPause() and 0 or simspeedReal -- set velocities to 0 if game is paused

			for k,v in pairs(decoded.vel) do decoded.vel[k] = v*simspeedReal end
			for k,v in pairs(decoded.rvel) do decoded.rvel[k] = v*simspeedReal end

			data = jsonEncode(decoded)
			MPGameNetwork.send('Zp:'..serverVehicleID..":"..data)
		end
	end
end


--- This function serves to send the position data received for another players vehicle from GE to VE, where it is handled.
-- @param data table The data to be applied as position and rotation
-- @param serverVehicleID string The VehicleID according to the server.
local function applyPos(decoded, serverVehicleID)
	local vehicle = MPVehicleGE.getVehicleByServerID(serverVehicleID)
	if not vehicle then log('E', 'applyPos', 'Could not find vehicle by ID '..serverVehicleID) return end


	--local decoded = jsonDecode(data)

	local simspeedFraction = 1/simTimeAuthority.getReal()

	for k,v in pairs(decoded.vel) do decoded.vel[k] = v*simspeedFraction end
	for k,v in pairs(decoded.rvel) do decoded.rvel[k] = v*simspeedFraction end

	decoded.localSimspeed = simspeedFraction

	data = jsonEncode(decoded)


	local veh = be:getObjectByID(vehicle.gameVehicleID)
	if veh then -- vehicle already spawned, send data
		if veh.mpVehicleType == nil then
			veh:queueLuaCommand("MPVehicleVE.setVehicleType('R')")
			veh.mpVehicleType = 'R'
		end
		veh:queueLuaCommand("positionVE.setVehiclePosRot('"..data.."')")
	end
	local deltaDt = math.max((decoded.tim or 0) - (vehicle.lastDt or 0), 0.001)
	vehicle.lastDt = decoded.tim
	local ping = math.floor(decoded.ping*1000) -- (d.ping-deltaDt)

	vehicle.ping = ping
	vehicle.fps = 1/deltaDt
	vehicle.position = Point3F(decoded.pos[1],decoded.pos[2],decoded.pos[3])

	local owner = vehicle:getOwner()
	if owner then UI.setPlayerPing(owner.name, ping) end-- Send ping to UI
end


--- The raw message from the server. This is unpacked first and then sent to applyPos()
-- @param rawData string The raw message data.
local function handle(rawData)
	local code, serverVehicleID, data = string.match(rawData, "^(%a)%:(%d+%-%d+)%:({.*})")
	if code == 'p' then
		local decoded = jsonDecode(data)
		if settings.getValue("enablePosSmoother") then
			if POSSMOOTHER[serverVehicleID] == nil then -- new id
				local new = {}
				new.update = decoded
				new.last_tim = new.update.tim
				new.exec_at = os.clock()
				new.executed = false
				POSSMOOTHER[serverVehicleID] = new
				
			else -- existing id
				if decoded.tim < 1 then -- vehicle may have been reloaded
					POSSMOOTHER[serverVehicleID].update = decoded
					POSSMOOTHER[serverVehicleID].last_tim = decoded.tim
					POSSMOOTHER[serverVehicleID].exec_at = os.clock()
					POSSMOOTHER[serverVehicleID].executed = false
				elseif decoded.tim < POSSMOOTHER[serverVehicleID].update.tim then
					-- do nothing, data is outdated
				else
					local entry = POSSMOOTHER[serverVehicleID]
					entry.update = decoded
					entry.executed = false
					
					--[[local current_time = os.clock()
					local tim_dif_ms = (entry.update.tim - entry.last_tim) * 1000 -- diff since last pos update
					local tim_dif_ms_smooth = 32 - tim_dif_ms -- we usually get a packet every 32 ms, lets see how we differ from that
					local exec_offset_ms = 24 + tim_dif_ms_smooth -- lets intentionally exec 24 ms later, offset by the tick inconsistency
					--local exec_offset_ms = 16 - tim_dif_ms -- lets intentionally exec 16 ms later, offset by the tick inconsistency
					local exec_at_ms = current_time + (exec_offset_ms / 1000)
					entry.exec_at = exec_at_ms
					
					print(serverVehicleID .. " - " .. current_time .. " - " .. tim_dif_ms .. " - " .. tim_dif_ms_smooth .. " - " .. exec_offset_ms .. " - " .. exec_at_ms .. " - " .. entry.exec_at)
					--print(serverVehicleID .. " - " .. current_time .. " - " .. tim_dif_ms .. " - " .. exec_offset_ms .. " - " .. exec_at_ms .. " - " .. entry.exec_at)]]
					
					-- all in one line
					entry.exec_at = os.clock() + ((24 + (32 - ((entry.update.tim - entry.last_tim) * 1000))) / 1000)
					POSSMOOTHER[serverVehicleID] = entry
				end
			end
		else
			applyPos(decoded, serverVehicleID)
		end
	else
		log('W', 'handle', "Received unknown packet '"..tostring(code).."'! ".. rawData)
	end
end


--- This function is for setting a ping value for use in the math of predition of the positions 
-- @param ping number The Ping value
local function setPing(ping)
	local p = ping/1000
	for i = 0, be:getObjectCount() - 1 do
		local veh = be:getObject(i)
		if veh then
			veh:queueLuaCommand("positionVE.setPing("..p..")")
		end
	end
end


--- This function is to allow for the setting of the vehicle/objects position.
-- @param gameVehicleID number The local game vehicle / object ID
-- @param x number Coordinate x
-- @param y number Coordinate y
-- @param z number Coordinate z
local function setPosition(gameVehicleID, x, y, z) -- TODO: this is only here because there seems to be no way to set vehicle position in vehicle lua without resetting the vehicle
	local veh = be:getObjectByID(gameVehicleID)
	veh:setPositionNoPhysicsReset(Point3F(x, y, z))
end

--- This function is used for setting the simulation speed 
--- @param speed number
local function setActualSimSpeed(speed)
	actualSimSpeed = speed*(1/simTimeAuthority.getReal())
end

--- This function is used for getting the simulation speed 
--- @return number actualSimSpeed
local function getActualSimSpeed()
	return actualSimSpeed
end

local function onUpdate(dt)
	local current_time = os.clock()
	for serverVehicleID, _ in pairs(POSSMOOTHER) do
		if not POSSMOOTHER[serverVehicleID].executed then
			if current_time >= POSSMOOTHER[serverVehicleID].exec_at then
				applyPos(POSSMOOTHER[serverVehicleID].update, serverVehicleID)
				POSSMOOTHER[serverVehicleID].last_tim = POSSMOOTHER[serverVehicleID].update.tim
				POSSMOOTHER[serverVehicleID].executed = true
			end
		end
	end
end

local function onSettingsChanged()
	if not settings.getValue("enablePosSmoother") then -- nil/false
		POSSMOOTHER = {}
	end
end

M.applyPos          = applyPos
M.tick              = tick
M.handle            = handle
M.sendVehiclePosRot = sendVehiclePosRot
M.setPosition       = setPosition
M.setPing           = setPing
M.setActualSimSpeed = setActualSimSpeed
M.getActualSimSpeed = getActualSimSpeed
M.onUpdate          = onUpdate
M.onSettingsChanged = onSettingsChanged
M.onInit = function() setExtensionUnloadMode(M, "manual") end

return M
