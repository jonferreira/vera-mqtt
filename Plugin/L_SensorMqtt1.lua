module("L_SensorMqtt1", package.seeall)

-- Service ID strings used by this device.
SERVICE_ID = "urn:upnp-sensor-mqtt-se:serviceId:SensorMqtt1"
SENSOR_MQTT_LOG_NAME = "SensorMqtt: "

local DEVICE_ID
local HANDLERS = {}
local ITEMS_NEEDED = 0
local WATCH = {}

local mqttServerIp = nil
local mqttServerPort = 0
local mqttServerUser = nil
local mqttServerPassword = nil
local mqttTopicPattern = nil
local mqttServerStatus = nil
local mqttServerConnected = nil
local mqttWatches = "{}"
local mqttAlias = "{}"
local mqttLastMessage = ""
local mqttClientSerial = luup.pk_accesspoint
-- Time in seconds between calls to MQTT:client:handler()
-- Decrease to 1 second if subscriptions are implemented
local mqttEventProcessingInterval = 5

local watches = {}
local alias = {}

local index=1
local configMonitors = {}

local mqttClient = nil
package.loaded.MQTT = nil
local MQTT = require("mqtt_library")

json = nil

-- ------------------------------------------------------------------
-- Convenience functions for consistent logging convention throughput SensorMqtt
-- grep '\(^01\|^02\|^35\|^50\).*SensorMqtt' /var/log/cmh/LuaUPnP.log
-- ------------------------------------------------------------------
local function log(text, level)
	luup.log(SENSOR_MQTT_LOG_NAME .. text, (level or 50))
end

local function log_info(text)	-- Appears as normal text
	log(text, 50)		-- grep '^50.*SensorMqtt'
end

local function log_warn(text)	-- Appears as yellow text [02]
	log(text, 2)		-- grep '^2.*SensorMqtt'
end

local function log_error(text)  -- Appears as red text	[01]
	log(text, 1)		-- grep '^1.*SensorMqtt'
end

local function log_debug(text)  -- Reported with verbose logging enabled [35]
	log(text, 35)
end

-- ------------------------------------------------------------------
-- Determine the current client connection status
-- ------------------------------------------------------------------
local function connectedToBroker()
	local status, result = pcall(mqttClient.handler, mqttClient)
	return status
end

-- ------------------------------------------------------------------
-- Update the Vera MQTT Connection Status Variables & UI, if changed
-- ------------------------------------------------------------------
local function setConnectionStatus()

	local function statusAsStr(state)
		return state and "Connected" or "Disconnected"
	end

	local currentStatus  = connectedToBroker()
	local previousStatus = luup.variable_get(SERVICE_ID, "mqttServerConnected", DEVICE_ID) == "1" and true or false

	if ( currentStatus ~= previousStatus ) then
		log_info("MQTT connection status changed from \"" .. statusAsStr(previousStatus) .. "\" to \"" .. statusAsStr(currentStatus) .. "\"")
		luup.variable_set(SERVICE_ID, "mqttServerStatus",    statusAsStr(currentStatus), DEVICE_ID)
		luup.variable_set(SERVICE_ID, "mqttServerConnected", currentStatus and "1" or "0", DEVICE_ID)
	end
end

-- ------------------------------------------------------------------
-- Connect to MQTT
-- ------------------------------------------------------------------
local function connectToMqtt()
	local clientId = "Vera-" .. mqttClientSerial

	log_info("Connecting as MQTT client: " .. clientId .. " to mqttServerIp: " .. mqttServerIp .. " mqttServerPort: " .. mqttServerPort .. "...")
	-- TODO: Add checks for IP and Port
	mqttServerPort = tonumber(mqttServerPort)

	-- Cleanup previous client instances e.g. server disconnect, ping/publish fail, etc.
	if ( mqttClient ~= nil ) then
		mqttClient:destroy()
		mqttClient = nil
	end

	-- Instantiate the MQTT client with connection attributes.
	mqttClient = MQTT.client.create(mqttServerIp, mqttServerPort)

	if ( mqttClient ~= nil ) then
		-- Ensure that the mqtt:handler() sends a PINGREQ every 60 seconds
		mqttClient.KEEP_ALIVE_TIME = 60

		-- If a username and password are provided, set the broker authentication
		if ( mqttServerUser ~= "" and mqttServerPassword ~= "" ) then
			log_debug("Authenticating with username: " .. mqttServerUser)
			mqttClient:auth(mqttServerUser, mqttServerPassword)
		end

		-- Connect to broker, if possible
		local result = mqttClient:connect(clientId, "Will_Topic/", 2, 1, "testament_msg")
		if ( result == nil ) then
			log_info("Successfully connected to broker: " .. mqttServerIp .. " on port " .. mqttServerPort)
		else
			log_warn("Failed to connect, reason: " .. result)
		end
	else
		log_error("Internal error - failed to instantiate MQTT.client using MQTT.client.create()")
	end

	-- Finally, set the connection status
	setConnectionStatus()
end

-- ------------------------------------------------------------------
-- Publish an MQTT message
-- ------------------------------------------------------------------
local function publishMessage(topic, payload)

	log_debug("Publish topic: " ..topic.. " message:" .. payload)

	-- If we aren't connected for some reason, then connect first
	if ( not connectedToBroker() ) then
	   connectToMqtt()
	end

	-- Try to publish.  Mqtt standard is fire and forget on publishing.
	local ok, result = pcall(mqttClient.publish, mqttClient, topic, payload)
	if ( not ok ) then
		log_warn("Unable to publish, connection down.  Discarding message: " .. payload)
		setConnectionStatus()
	end
end

-- ------------------------------------------------------------------
-- Process incoming MQTT events, will send PINGREQ after KEEP_ALIVE expires
-- (non-local so MIOS can invoke it)
-- Subscription callbacks will be invoked from this call stack
-- mqttEventProcessingInterval defines the time in seconds to process
-- new mqtt events.
-- ------------------------------------------------------------------
function processMqttEvents()

	-- Ensure processMqttEvents() will run again no matter what happens (e.g. untrapped exception)
	luup.call_delay('processMqttEvents', mqttEventProcessingInterval)

	-- Make a protected call to mqtt handler because it will raise an exception if the client
	-- is not connected to the broker.  If handler() fails, set our state to disconnected.
	local ok, result = pcall(mqttClient.handler, mqttClient)
	if ( not ok or result ~= nil ) then
		-- This is non-fatal.  Client will reconnect on next variable change/publish
		log_debug("Connection down: " .. result or "unknown reason")
		setConnectionStatus()
	end
end

-- ------------------------------------------------------------------
-- Callback Watch Configured Sensor Variables (non-local so MIOS can invoke it)
-- ------------------------------------------------------------------
function watchSensorVariable(lul_device, lul_service, lul_variable, lul_value_old, lul_value_new)

	log_debug("Watch event - device: " .. lul_device .. " variable: " .. lul_variable .. " value " .. tostring(lul_value_old) .. " => " .. tostring(lul_value_new))

	local variableUpdate = {}
	variableUpdate.Time = os.time()
	variableUpdate.DeviceId = lul_device
	variableUpdate.DeviceName = alias[tostring(lul_device)] or luup.devices[lul_device].description
	variableUpdate.DeviceType = luup.devices[lul_device].device_type
	variableUpdate.ServiceId = lul_service
	variableUpdate.Variable = lul_variable
	variableUpdate.RoomId = luup.devices[lul_device].room_num
	variableUpdate.RoomName = luup.rooms[variableUpdate.RoomId] or "No Room"
	variableUpdate[watches[lul_service][lul_variable]] = tonumber(lul_value_new) or lul_value_new
	variableUpdate["Old" .. watches[lul_service][lul_variable]] = tonumber(lul_value_old) or lul_value_old

	-- Encode the payload before attributing variableUpdate for
	-- topic generation based upon pattern substitution
	local payload = json:encode(variableUpdate)

	-- Add attributes legal for topic substitution but absent
	-- from mqtt payload (e.g. city, alias, access_point, etc.)
	variableUpdate.SerialNumber = luup.pk_accesspoint
	variableUpdate.City = luup.city
	variableUpdate.Alias = alias[tostring(lul_device)] or lul_device
	tokens = {(lul_service .. ":"):match(((lul_service .. ":"):gsub("[^:]*:", "([^:]*):")))}
	variableUpdate.ServiceName = tokens[#tokens]

	-- Generate the topic using the topic pattern
	local topic = mqttTopicPattern -- <alias for variable mqttVeraIdentifier>
	for i,v in pairs(variableUpdate) do
		topic = string.gsub(topic, "%(" .. i .. "%)", v)
	end

	log_info("Sending [" .. variableUpdate.DeviceName .. "] " .. lul_variable .. " changed to " .. tostring(lul_value_new) .. " from " .. tostring(lul_value_old) .. " on topic " .. topic)
	publishMessage(topic, payload)

	local lastMessage = {}
	lastMessage.Topic = topic
	lastMessage.Payload = payload

	luup.variable_set(SERVICE_ID, "mqttLastMessage", json:encode(lastMessage), DEVICE_ID)

end

-- ------------------------------------------------------------------
-- Register the watch variables
-- ------------------------------------------------------------------
local function registerWatches()

	watches = json:decode(mqttWatches)
	alias = json:decode(mqttAlias)

	log_debug("************************************************ MQTT Settings ************************************************")

	for service,variables in pairs(watches) do
		for varName, label in pairs(variables) do
			log_debug("Watching ".. service .." on variable " .. varName .. " with label " .. label)
			luup.variable_watch("watchSensorVariable", tostring(service), tostring(varName), nil)
		end
	end

end

-- ------------------------------------------------------------------
-- SensorMqtt Plugin Startup method (akin to main)
-- ------------------------------------------------------------------
function startup(lul_device)
	DEVICE_ID = lul_device
	
	_G.watchSensorVariable = watchSensorVariable
	_G.processMqttEvents = processMqttEvents
	
	log_info("Initializing SensorMqtt")

	package.loaded.JSON = nil
	json = require("JSON")

	-- "Generic I/O" device http://wiki.micasaverde.com/index.php/Luup_Device_Categories
	luup.attr_set("category_num", 3, DEVICE_ID)

	luup.variable_set(SERVICE_ID, "mqttServerConnected", "0", DEVICE_ID)

	--Reading variables
	mqttServerIp = luup.variable_get(SERVICE_ID, "mqttServerIp", DEVICE_ID)
	if ( mqttServerIp == nil ) then
		mqttServerIp = "0.0.0.0"
		luup.variable_set(SERVICE_ID, "mqttServerIp", mqttServerIp, DEVICE_ID)
	end
	
	mqttServerPort = luup.variable_get(SERVICE_ID, "mqttServerPort", DEVICE_ID)
	if ( mqttServerPort == nil ) then
		mqttServerPort = "0"
		luup.variable_set(SERVICE_ID, "mqttServerPort", mqttServerPort, DEVICE_ID)
	end

	mqttServerUser = luup.variable_get(SERVICE_ID, "mqttServerUser", DEVICE_ID)
	if ( mqttServerUser == nil ) then
		mqttServerUser = ""
		luup.variable_set(SERVICE_ID, "mqttServerUser", mqttServerUser, DEVICE_ID)
	end

	mqttServerPassword = luup.variable_get(SERVICE_ID, "mqttServerPassword", DEVICE_ID)
	if ( mqttServerPassword == nil ) then
		mqttServerPassword = ""
		luup.variable_set(SERVICE_ID, "mqttServerPassword", mqttServerPassword, DEVICE_ID)
	end

	mqttWatches = luup.variable_get(SERVICE_ID, "mqttWatches", DEVICE_ID)
	if( mqttWatches == nil ) then
		mqttWatches = "{}"
		luup.variable_set(SERVICE_ID, "mqttWatches", mqttWatches, DEVICE_ID)
	end

	mqttAlias = luup.variable_get(SERVICE_ID, "mqttAlias", DEVICE_ID)
	if( mqttAlias == nil ) then
		mqttAlias = "{}"
		luup.variable_set(SERVICE_ID, "mqttAlias", mqttAlias, DEVICE_ID)
	end

	mqttLastMessage = luup.variable_get(SERVICE_ID, "mqttLastMessage", DEVICE_ID)
	if( mqttLastMessage == nil ) then
		mqttLastMessage = ""
		luup.variable_set(SERVICE_ID, "mqttLastMessage", mqttLastMessage, DEVICE_ID)
	end
	
	-- Topic Pattern variables
	-- (SerialNumber) = Vera serial number as shown on home.getvera.com portal.
	-- (City) = the city defined in the controller location tab
	-- (ServiceId) = the service identifier
	-- (ServiceName) = the name of the service
	-- (DeviceId) = the device id
	-- (DeviceName) = the device name / description
	-- (Alias) = the device alias (legacy)
	-- (Variable) = the variable changed under service for device
	--
	-- Legacy pattern = Vera/Event/(Alias)
	-- Recommended = Vera/(SerialNumber)/(DeviceId)/(ServiceName)

	mqttTopicPattern = luup.variable_get(SERVICE_ID, "mqttVeraIdentifier", DEVICE_ID)
	if( mqttTopicPattern == nil ) then
		mqttTopicPattern = "Vera/Events/(Alias)"
		luup.variable_set(SERVICE_ID, "mqttVeraIdentifier", mqttTopicPattern, DEVICE_ID)
	end

	if ( mqttServerIp ~= "0.0.0.0" and mqttServerPort ~= "0" ) then
		connectToMqtt()
	else
		log_warn("You must set the mqttServerIp and the mqttServerPort for the broker in order for the client to connect..")
	end
	
	if ( connectedToBroker() ) then
		registerWatches()
		processMqttEvents() -- kick off the mqtt event handling
	end

        luup.set_failure(false, DEVICE_ID)
end
