RegisterNetEvent("rcboat:torpedoFired")

AddEventHandler("rcboat:torpedoFired", function(netId)
	TriggerClientEvent("rcboat:torpedoFired", -1, netId)
end)
