RegisterNetEvent("rcboat:fireTorpedo")

AddEventHandler("rcboat:fireTorpedo", function(netId)
	TriggerClientEvent("rcboat:fireTorpedo", -1, netId)
end)
