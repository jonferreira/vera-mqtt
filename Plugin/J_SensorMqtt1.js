var MQTT = {
    browserIE: false,
    services: {},
    watches: {},
    alias: {},
    SID: 'urn:upnp-sensor-mqtt-se:serviceId:SensorMqtt1',
    userData: undefined
}

function MQTT_showExistingServices(device)
{

    MQTT_detectBrowser();
    MQTT_defineUIStyle();

    var html = '';

    html += '<DIV style="margin-top: 15px;">'
    html += '<button type="button" style="margin-right: 10px; background-color: ' + MQTT.buttonBgColor + '; color: white; height: 25px; width: 110px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="MQTT_updateServicesTable(' + device + ');">Refresh table</button>';
    html += '<button type="button" style="margin-right: 10px; background-color: ' + MQTT.buttonBgColor + '; color: white; height: 25px; width: 110px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="MQTT_save(' + device + ');">Save Changes</button>';
    html += '<select id="filterServices" onChange="MQTT_filterServicesTable();"><option selected value="ALL">All</option></select>';
    html += '<label id="SavedLabel"></label>'
    html += '</DIV>'

	html += '<DIV id="servicesTable" style="margin:15px"/>'

	set_panel_html(html);

	MQTT_updateServicesTable(device);
}

function MQTT_updateServicesTable(device) {

    var html = '<table border="1" style="width:100%">';
    html += '<tr align="left" style="background-color: ' + MQTT.tableTitleBgColor + '; color: white">';
    html += '<th style="padding-left: 10px;"></td>';
    html += '<th style="padding-left: 10px; min-width: 150px;">Service</td>';
    html += '<th style="padding-left: 10px; min-width: 150px;">Variable</td>';
    html += '<th style="padding-left: 10px; min-width: 150px;">Label</td>';
    html += '</tr>';

    var selectedService = '';

    var htmlServices;
    htmlServices = '<option value="ALL"';
    if (selectedService == 'ALL') {
        htmlServices += ' selected';
        validSelection = true;
    }
    htmlServices += '>All</option>';

    if (typeof api !== 'undefined') {
        MQTT.userData = api.getUserData();
    }
    else {
        MQTT.userData = jsonp.ud;
    }

    MQTT.watches = JSON.parse(get_device_state(device, MQTT.SID, "mqttWatches", 1));

    var devices = MQTT.userData.devices;

    var nb = 0;
    //loop through each device
    for (devicesCount = 0; devicesCount < devices.length; devicesCount++) {
        //get each available service and variable...
        var states = devices[devicesCount].states;
        for (statesCount = 0; statesCount < states.length; statesCount++) {

                //add service if needed
                if (!MQTT.services.hasOwnProperty(states[statesCount].service)) {
                    MQTT.services[states[statesCount].service] = {};
                }
                //add variable if needed
                if (!MQTT.services[states[statesCount].service][states[statesCount].variable]) {
                    MQTT.services[states[statesCount].service][states[statesCount].variable] = {};
                
                    //are we monitoring this?
                    if (MQTT.watches[states[statesCount].service]) {
                        if(MQTT.watches[states[statesCount].service][states[statesCount].variable]) {
                            MQTT.services[states[statesCount].service][states[statesCount].variable].Monitor = true;
                            //what will we name it?
                            if (MQTT.watches[states[statesCount].service][states[statesCount].variable]){
                                MQTT.services[states[statesCount].service][states[statesCount].variable].Label = MQTT.watches[states[statesCount].service][states[statesCount].variable];
                            } else {
                                MQTT.services[states[statesCount].service][states[statesCount].variable].Label = states[statesCount].variable;
                            }
                        } else {
                            MQTT.services[states[statesCount].service][states[statesCount].variable].Monitor = false;
                            MQTT.services[states[statesCount].service][states[statesCount].variable].Label = states[statesCount].variable;
                        }
                    } else {
                        MQTT.services[states[statesCount].service][states[statesCount].variable].Monitor = false;
                        MQTT.services[states[statesCount].service][states[statesCount].variable].Label = states[statesCount].variable;
                    }
                }
        }
    }

    for (s in MQTT.services) {
        var service = MQTT.services[s];
        for (v in service) {
            var variable = service[v];

            html += '<tr align="left">';
            html += '<td style="min-width: 25px; text-align: center;"><input id="SelectServiceVariable' + nb + '" type="checkbox" value="' + nb + '" ';
            if (variable.Monitor) {
                html += "checked";
            } 
            html += ' onchange="MQTT_pushChanges(' + nb + ',' + device + ');"></td>';
            html += '<td style="padding-left: 10px" id="Service' + nb + '">' + s + '</td>';
            html += '<td style="padding-left: 10px" id="Variable' + nb + '">' + v + '</td>';
            html += '<td><input id="Label' + nb + '" type="text" name="Label' + nb + '" value="' + variable.Label + '" onchange="MQTT_pushChanges(' + nb + ',' + device + ');" style="width:100%"></td>';
            html += '</tr>';
            nb++;

        }

        htmlServices += '<option value="' + s + '"';
        if (selectedService == s) {
            htmlServices += ' selected';
        }
        htmlServices += '>' + s + '</option>';

    }

    html += '</table>';

    jQuery('#servicesTable').html(html);

    jQuery('#filterServices').html(htmlServices);

}

function MQTT_filterServicesTable() {

    if (jQuery('#filterServices option:selected').index() >= 0) {
        selectedService = jQuery('#filterServices').val();
    }

    table = jQuery('#servicesTable table tr')

    var i = -1;

    table.each(function () {
        $this = $(this)

        if (i >= 0) {
            if (selectedService == 'ALL') {

                $this[0].style.display = 'table-row';

            } else {

                if (selectedService == jQuery("#Service" + i)[0].innerHTML) {
                    $this[0].style.display = 'table-row';
                } else {
                    $this[0].style.display = 'none';
                }
            }
        }
        i++;
    });

}

function MQTT_pushChanges(line, device) {

    var selected = jQuery("#SelectServiceVariable" + line)[0].checked;
    var service = jQuery("#Service" + line)[0].innerHTML;
    var variable = jQuery("#Variable" + line)[0].innerHTML;
    var label = jQuery("#Label" + line)[0].value;

    //save to object

    if (selected) {

        //add service if needed
        if (!MQTT.watches.hasOwnProperty(service)) {
            MQTT.watches[service] = {};
        }

        MQTT.watches[service][variable] = label;

        //_console(JSON.stringify(MQTT.watches[service][variable]));

    } else {
        //remove from watch list
        if (MQTT.watches.hasOwnProperty(service)) {
            delete MQTT.watches[service][variable];

            if (Object.size(MQTT.watches[service]) == 0) {
                delete MQTT.watches[service];
            }

        }
    }
	
	set_device_state(device, MQTT.SID, "mqttWatches", JSON.stringify(MQTT.watches), 0);
	jQuery("#SavedLabel")[0].innerHTML = "Settings Saved";

}

function MQTT_save(device) {

    //set_device_state(device, MQTT.SID, "mqttWatches", JSON.stringify(MQTT.watches), 0);

    //jQuery("#SavedLabel")[0].innerHTML = "Settings Saved";

    luupRestart();

}

function MQTT_showDeviceAlias(device) {

    MQTT_detectBrowser();
    MQTT_defineUIStyle();

    var html = '';

    html += '<DIV style="margin-top: 15px;">'
    html += '<button type="button" style="margin-right: 10px; background-color: ' + MQTT.buttonBgColor + '; color: white; height: 25px; width: 110px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="MQTT_updateDeviceAliasTable(' + device + ');">Refresh table</button>';
    html += '<button type="button" style="margin-right: 10px; background-color: ' + MQTT.buttonBgColor + '; color: white; height: 25px; width: 110px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="MQTT_saveAlias(' + device + ');">Save Changes</button>';
    html += '<label id="SavedAliasLabel"></label>'
    html += '</DIV>'

    html += '<DIV id="aliasTable" style="margin:15px"/>'

    set_panel_html(html);

    MQTT_updateDeviceAliasTable(device);

}

function MQTT_updateDeviceAliasTable(device) {

    var html = '<table border="1" style="width:100%">';
    html += '<tr align="left" style="background-color: ' + MQTT.tableTitleBgColor + '; color: white">';
    html += '<th style="padding-left: 10px;"></td>';
    html += '<th style="padding-left: 10px; min-width: 150px;">Id</td>';
    html += '<th style="padding-left: 10px; min-width: 150px;">Name</td>';
    html += '<th style="padding-left: 10px; min-width: 150px;">Alias</td>';
    html += '</tr>';

    if (typeof api !== 'undefined') {
        MQTT.userData = api.getUserData();
    }
    else {
        MQTT.userData = jsonp.ud;
    }

    MQTT.alias = JSON.parse(get_device_state(device, MQTT.SID, "mqttAlias", 1));

    var devices = MQTT.userData.devices;

    var nb = 0;
    //loop through each device
    for (i in devices) {
	
		if (typeof devices[i].id !== 'undefined') {

			html += '<tr align="left">';
			html += '<td style="min-width: 25px; text-align: center;"><input id="SelectAlias' + nb + '" type="checkbox" value="' + nb + '" ';
			if (MQTT.alias[devices[i].id]) {
				html += "checked";
			}
			html += ' onchange="MQTT_pushAliasChanges(' + nb + ',' + device + ');"></td>';
			html += '<td style="padding-left: 10px" id="ID' + nb + '">' + devices[i].id + '</td>';
			html += '<td style="padding-left: 10px" id="Name' + nb + '">' + devices[i].name + '</td>';
			if (MQTT.alias[devices[i].id]) {
				html += '<td><input id="Label' + nb + '" type="text" name="Label' + nb + '" value="' + MQTT.alias[devices[i].id] + '" onchange="MQTT_pushAliasChanges(' + nb + ',' + device + ');" style="width:100%"></td>';
			} else {
				html += '<td><input id="Label' + nb + '" type="text" name="Label' + nb + '" value="' + devices[i].name + '" onchange="MQTT_pushAliasChanges(' + nb + ',' + device + ');" style="width:100%"></td>';
			}
			html += '</tr>';
			nb++;
		
		}

    }

    html += '</table>';

    jQuery('#aliasTable').html(html);

}

function MQTT_pushAliasChanges(line, device){

    var selected = jQuery("#SelectAlias" + line)[0].checked;
    var id = jQuery("#ID" + line)[0].innerHTML;
    var label = jQuery("#Label" + line)[0].value;

    //save to object

    if (selected) {

        //add alias if needed
        if (!MQTT.alias.hasOwnProperty(id)) {
            MQTT.alias[id] = {};
        }

        MQTT.alias[id] = label;

    } else {
        //remove from watch list
        if (MQTT.alias.hasOwnProperty(id)) {
            delete MQTT.alias[id];
        }
    }
	
	set_device_state(device, MQTT.SID, "mqttAlias", JSON.stringify(MQTT.alias), 0);
    jQuery("#SavedAliasLabel")[0].innerHTML = "Settings Saved";

}

function MQTT_saveAlias(device) {

    //set_device_state(device, MQTT.SID, "mqttAlias", JSON.stringify(MQTT.alias), 0);

    //jQuery("#SavedAliasLabel")[0].innerHTML = "Settings Saved";

    luupRestart();

}

function MQTT_detectBrowser() {
    if (navigator.userAgent.toLowerCase().indexOf('msie') >= 0
		|| navigator.userAgent.toLowerCase().indexOf('trident') >= 0) {
        MQTT.browserIE = true;
    }
    else {
        MQTT.browserIE = false;
    }
}

function MQTT_defineUIStyle() {
    if (typeof api !== 'undefined') {
        MQTT.buttonBgColor = '#006E47';
        MQTT.tableTitleBgColor = '#00A652';
    }
    else {
        MQTT.buttonBgColor = '#3295F8';
        MQTT.tableTitleBgColor = '#025CB6';
    }
}

function MQTT_selectAllServices(state) {
    var version = parseFloat(jQuery().jquery.substr(0, 3));
    var i = 0;
    while (jQuery('#SelectServiceVariable' + i).length > 0) {
        if (version < 1.6) {
            jQuery('#SelectServiceVariable' + i).attr('checked', state);
        }
        else {
            jQuery('#SelectServiceVariable' + i).prop('checked', state);
        }
        i++;
    }
}

function luupRestart() {

    var q = {
        'id': 'lu_reload',
        'source': 'devapp1',
        'rand': Math.random()
    };

    new Ajax.Request(command_url + '/data_request', {
        method: 'get',
        parameters: q,
        onSuccess: function (response) {
        },
        onFailure: function (response) {
        },
        onComplete: function (response) {
        }
    });

}

Object.size = function (obj) {
    var size = 0, key;
    for (key in obj) {
        if (obj.hasOwnProperty(key)) size++;
    }
    return size;
};