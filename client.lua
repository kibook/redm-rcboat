local RCBoat
local Driver
local Camera

RegisterNetEvent("rcboat:torpedoFired")
RegisterNetEvent("rcboat:torpedoReloaded")
RegisterNetEvent("rcboat:boatSunk")

function PrepareSoundset(soundsetName, p1)
	return Citizen.InvokeNative(0xD9130842D7226045, soundsetName, p1)
end

function PlaySoundFromPosition(audioName, x, y, z, audioRef, isNetwork, p6, p7, p8)
	return Citizen.InvokeNative(0xCCE219C922737BFA, audioName, x, y, z, audioRef, isNetwork, p6, p7, p8)
end

function RemoveSoundset(soundsetName)
	return Citizen.InvokeNative(0x531A78D6BF27014B, soundsetName)
end

function IsUsingKeyboard(padIndex)
	return Citizen.InvokeNative(0xA571D46727E2B718, padIndex)
end

function LoadModel(model)
	if not IsModelInCdimage(model) then
		return false
	end

	RequestModel(model)

	while not HasModelLoaded(model) do
		Citizen.Wait(0)
	end

	return true
end

function CreateRCBoat()
	LoadModel(Config.RCBoatModel)

	local playerPed = PlayerPedId()
	local playerPos = GetEntityCoords(playerPed)
	local playerYaw = GetEntityHeading(playerPed)

	local r = math.rad(-playerYaw)
	local spawnPos = playerPos + vector3(5 * math.sin(r), 5 * math.cos(r), 0)

	local rcboat = CreateVehicle(Config.RCBoatModel, spawnPos, playerYaw, true, false, false, false)

	SetModelAsNoLongerNeeded(Config.RCBoatModel)

	return rcboat
end

function CreateDriver()
	LoadModel(Config.DriverModel)

	local driver = CreatePedInsideVehicle(RCBoat, Config.DriverModel, -1, false, false, false)

	SetModelAsNoLongerNeeded(Config.DriverModel)

	SetEntityVisible(driver, false)
	SetEntityInvincible(driver, true)
	FreezeEntityPosition(driver, true)
	SetBlockingOfNonTemporaryEvents(driver, true)
	SetPedFleeAttributes(driver, 0, false)

	return driver
end

function DeployRCBoat()
	RCBoat = CreateRCBoat()
	Driver = CreateDriver()
end

function PlaySound(set, name, coords)
	Citizen.CreateThread(function()
		while not PrepareSoundset(set, 0) do
			Citizen.Wait(0)
		end

		PlaySoundFromPosition(name, coords, set, false, 0, true, 0)

		Citizen.Wait(2000)

		RemoveSoundset(set)
	end)
end

function StowRCBoat()
	DeleteVehicle(RCBoat)
	RCBoat = nil

	DeletePed(Driver)
	Driver = nil

	if Camera then
		ToggleCamera()
	end
end

function ToggleCamera()
	if Camera then
		RenderScriptCams(false, true, 500, true, true)
		DestroyCam(Camera)
		Camera = nil
	else
		Camera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
		AttachCamToEntity(Camera, RCBoat, 0.0, -1.0, 0.4, true)
		RenderScriptCams(true, true, 500, true, true)
	end
end

function Accelerate(prompt)
	TaskVehicleTempAction(Driver, RCBoat, 9, 1)
end

function Deaccelerate(prompt)
	TaskVehicleTempAction(Driver, RCBoat, 6, 2500)
end

function Reverse(prompt)
	TaskVehicleTempAction(Driver, RCBoat, 28, 1)
end

function TurnLeft(prompt)
	if prompt.acceleratePrompt:isControlPressed() then
		TaskVehicleTempAction(Driver, RCBoat, 7, 1)
	elseif prompt.reversePrompt:isControlPressed() then
		TaskVehicleTempAction(Driver, RCBoat, 13, 1)
	else
		TaskVehicleTempAction(Driver, RCBoat, 4, 1)
	end
end

function TurnRight(prompt)
	if prompt.acceleratePrompt:isControlPressed() then
		TaskVehicleTempAction(Driver, RCBoat, 8, 1)
	elseif prompt.reversePrompt:isControlPressed() then
		TaskVehicleTempAction(Driver, RCBoat, 14, 1)
	else
		TaskVehicleTempAction(Driver, RCBoat, 5, 1)
	end
end

-- Two or more prompts that perform the same function
local AltPrompts = {}

function AltPrompts:new(prompts)
	self.__index = self
	local self = setmetatable({}, self)

	self.prompts = prompts or {}

	return self
end

function AltPrompts:addPrompt(prompt)
	table.insert(self.prompts, prompt)
end

function AltPrompts:setEnabled(toggle)
	for _, prompt in ipairs(self.prompts) do
		prompt:setEnabled(toggle)
	end
end

function AltPrompts:setText(text)
	for _, prompt in ipairs(self.prompts) do
		prompt:setText(text)
	end
end

local TorpedoPrompts = AltPrompts:new()

function FireTorpedo(prompt)
	TorpedoPrompts:setEnabled(false)

	local rcboatCoords = GetEntityCoords(RCBoat)
	local heading = GetEntityHeading(RCBoat)

	LoadModel(Config.TorpedoModel)

	local r = math.rad(-heading)
	local startCoords = rcboatCoords + vector3(2 * math.sin(r), 2 * math.cos(r), 0)

	local torpedo = CreateObjectNoOffset(Config.TorpedoModel, startCoords, true, false, true, false)

	SetModelAsNoLongerNeeded(Config.TorpedoModel)

	SetEntityHeading(torpedo, heading)

	local velocity = vector3(Config.TorpedoSpeed * math.sin(r), Config.TorpedoSpeed * math.cos(r), 0.0)
	SetEntityVelocity(torpedo, velocity)

	NetworkRegisterEntityAsNetworked(torpedo)
	TriggerServerEvent("rcboat:torpedoFired", rcboatCoords, ObjToNet(torpedo))

	Citizen.CreateThread(function()
		local text = prompt:getText()

		while torpedo do
			local torpedoCoords = GetEntityCoords(torpedo)
			local distance = #(torpedoCoords - startCoords)
			local range = math.floor(Config.TorpedoRange - distance)

			if HasEntityCollidedWithAnything(torpedo) or range <= 0 then
				AddExplosion(torpedoCoords - vector3(0, 0, 0.5), 23, Config.TorpedoDamage, true, false, 1.0)
				DeleteObject(torpedo)
				torpedo = nil
			else
				SetEntityVelocity(torpedo, velocity)

				TorpedoPrompts:setText(text .. " (" .. range .. "m)")
			end

			Citizen.Wait(0)
		end

		for secs = Config.TorpedoCooldown, 1, -1 do
			TorpedoPrompts:setText(text .. " (" .. secs .. "s)")
			Citizen.Wait(1000)
		end

		TriggerServerEvent("rcboat:torpedoReloaded", GetEntityCoords(RCBoat))

		TorpedoPrompts:setText(text)
		TorpedoPrompts:setEnabled(true)
	end)
end

local SelfDestructPrompts = AltPrompts:new()

function SelfDestruct(prompt)
	SelfDestructPrompts:setEnabled(false)

	Citizen.CreateThread(function()
		local text = prompt:getText()

		for secs = Config.SelfDestructTime, 1, -1 do
			SelfDestructPrompts:setText("~COLOR_RED~" .. text .. " in " .. secs .. "s")
			Citizen.Wait(1000)
		end

		AddExplosion(GetEntityCoords(RCBoat) - vector3(0, 0, 0.5), 23, Config.SelfDestructDamage, true, false, 1.0)
		SetEntityHealth(RCBoat, 0)

		SelfDestructPrompts:setText(text)
		SelfDestructPrompts:setEnabled(true)
	end)
end

-- Primary controls
local RCBoatPrompts = UipromptGroup:new("RC Boat")

local AcceleratePrompt = RCBoatPrompts:addPrompt(`INPUT_FRONTEND_UP`, "Accelerate")
AcceleratePrompt:setOnControlPressed(Accelerate)
AcceleratePrompt:setOnControlJustReleased(Deaccelerate)

local ReversePrompt = RCBoatPrompts:addPrompt(`INPUT_FRONTEND_DOWN`, "Reverse")
ReversePrompt:setOnControlPressed(Reverse)
ReversePrompt:setOnControlJustReleased(Deaccelerate)

local TurnLeftPrompt = RCBoatPrompts:addPrompt(`INPUT_FRONTEND_LEFT`, "Turn Left")
TurnLeftPrompt:setOnControlPressed(TurnLeft)
TurnLeftPrompt.acceleratePrompt = AcceleratePrompt
TurnLeftPrompt.reversePrompt = ReversePrompt

local TurnRightPrompt = RCBoatPrompts:addPrompt(`INPUT_FRONTEND_RIGHT`, "Turn Right")
TurnRightPrompt:setOnControlPressed(TurnRight)
TurnRightPrompt.acceleratePrompt = AcceleratePrompt
TurnRightPrompt.reversePrompt = ReversePrompt

local ToggleCameraPrompt = RCBoatPrompts:addPrompt(`INPUT_FRONTEND_ACCEPT`, "Toggle Camera")
ToggleCameraPrompt:setHoldMode(true)
ToggleCameraPrompt:setOnHoldModeJustCompleted(ToggleCamera)

local TorpedoPrompt = RCBoatPrompts:addPrompt(`INPUT_GAME_MENU_EXTRA_OPTION`, "Fire Torpedo")
TorpedoPrompt:setOnControlJustReleased(FireTorpedo)
TorpedoPrompts:addPrompt(TorpedoPrompt)

local SelfDestructPrompt = RCBoatPrompts:addPrompt(`INPUT_FRONTEND_CANCEL`, "Self-destruct")
SelfDestructPrompt:setHoldMode(true)
SelfDestructPrompt:setOnHoldModeJustCompleted(SelfDestruct)
SelfDestructPrompts:addPrompt(SelfDestructPrompt)

-- Alternate controls for controllers that avoids left D-pad
local AltRCBoatPrompts = UipromptGroup:new("RC Boat")

local AltAcceleratePrompt = AltRCBoatPrompts:addPrompt(`INPUT_FRONTEND_UP`, "Accelerate")
AltAcceleratePrompt:setOnControlPressed(Accelerate)
AltAcceleratePrompt:setOnControlJustReleased(Deaccelerate)

local AltReversePrompt = AltRCBoatPrompts:addPrompt(`INPUT_FRONTEND_DOWN`, "Reverse")
AltReversePrompt:setOnControlPressed(Reverse)
AltReversePrompt:setOnControlJustReleased(Deaccelerate)

local AltTurnLeftPrompt = AltRCBoatPrompts:addPrompt(`INPUT_FRONTEND_LB`, "Turn Left")
AltTurnLeftPrompt:setOnControlPressed(TurnLeft)
AltTurnLeftPrompt.acceleratePrompt = AltAcceleratePrompt
AltTurnLeftPrompt.reversePrompt = AltReversePrompt

local AltTurnRightPrompt = AltRCBoatPrompts:addPrompt(`INPUT_FRONTEND_RB`, "Turn Right")
AltTurnRightPrompt:setOnControlPressed(TurnRight)
AltTurnRightPrompt.acceleratePrompt = AltAcceleratePrompt
AltTurnRightPrompt.reversePrompt = AltReversePrompt

local AltToggleCameraPrompt = AltRCBoatPrompts:addPrompt(`INPUT_FRONTEND_ACCEPT`, "Toggle Camera")
AltToggleCameraPrompt:setHoldMode(true)
AltToggleCameraPrompt:setOnHoldModeJustCompleted(ToggleCamera)

local AltTorpedoPrompt = AltRCBoatPrompts:addPrompt(`INPUT_GAME_MENU_EXTRA_OPTION`, "Fire Torpedo")
AltTorpedoPrompt:setOnControlJustReleased(FireTorpedo)
TorpedoPrompts:addPrompt(AltTorpedoPrompt)

local AltSelfDestructPrompt = AltRCBoatPrompts:addPrompt(`INPUT_FRONTEND_CANCEL`, "Self-destruct")
AltSelfDestructPrompt:setHoldMode(true)
AltSelfDestructPrompt:setOnHoldModeJustCompleted(SelfDestruct)
SelfDestructPrompts:addPrompt(AltSelfDestructPrompt)

RegisterCommand("rcboat", function(source, args, raw)
	if RCBoat then
		StowRCBoat()
	else
		DeployRCBoat()
	end
end)

AddEventHandler("onResourceStop", function(resourceName)
	if GetCurrentResourceName() == resourceName and RCBoat then
		StowRCBoat()
	end
end)

AddEventHandler("rcboat:torpedoFired", function(rcBoatCoords, torpedoNetId)
	PlaySound("RCKPT1_Sounds", "TORPEDO_FIRE", rcBoatCoords)
	UseParticleFxAsset("scr_crackpot")
	StartParticleFxLoopedOnEntity("scr_crackpot_torpedo_spray", NetToObj(torpedoNetId), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, false, false, false)
end)

AddEventHandler("rcboat:torpedoReloaded", function(rcBoatCoords)
	PlaySound("RCKPT1_Sounds", "BOAT_RELOAD", rcBoatCoords)
end)

AddEventHandler("rcboat:boatSunk", function(rcBoatCoords)
	PlaySound("RCKPT1_Sounds", "BOAT_SINKS", rcBoatCoords)
end)

Citizen.CreateThread(function()
	TriggerEvent("chat:addSuggestion", "/rcboat", "Deploy or stow a remote-controllable boat")
end)

Citizen.CreateThread(function()
	while true do
		if RCBoat then
			if IsUsingKeyboard(0) then
				RCBoatPrompts:handleEvents()
			else
				AltRCBoatPrompts:handleEvents()
			end

			if Camera then
				SetCamRot(Camera, GetEntityRotation(RCBoat))
			end
		end

		Citizen.Wait(0)
	end
end)

Citizen.CreateThread(function()
	while true do
		if RCBoat then
			local playerPed = PlayerPedId()
			local playerCoords = GetEntityCoords(playerPed)
			local rcBoatCoords = GetEntityCoords(RCBoat)
			local distance = #(playerCoords - rcBoatCoords)
			local rcBoatHealth = GetEntityHealth(RCBoat)

			if rcBoatHealth == 0 or IsPedDeadOrDying(playerPed) or distance > Config.ControlRange then
				TriggerServerEvent("rcboat:boatSunk", rcBoatCoords)
				StowRCBoat()
			end

			local colour

			if distance > Config.ControlRange - 10 then
				colour = "~COLOR_RED~"
			elseif distance > Config.ControlRange - 20 then
				colour = "~COLOR_YELLOW~"
			else
				colour = "~COLOR_WHITE~"
			end

			RCBoatPrompts:setText("RC Boat - " .. rcBoatHealth .. " HP (" .. colour .. math.floor(distance) .. "m~COLOR_WHITE~)")
		end

		Citizen.Wait(500)
	end
end)
