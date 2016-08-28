MQTT Client Plugin

This plugin provides the ability to publish out any user defined variable to an MQTT Broker.
It is based on the code found here
This is my first plugin so odds are there will be some bugs although so far seems to be working fine.

This plugin is designed for use on systems running UI7.

Features

    User defined Variables to watch
    User defined Device Alias which makes Logic much more intuitive and makes it easier when replacing devices


MQTT Message Example

Code:

{"Payload":{"DeviceId":45,"OldOnOff":"1","OnOff":"0","Time":1453209965},"Topic":"Vera/Events/TestSocket"}


Installation and Configuration

    Upload the attached files
    Create a new device with device_file set to D_SensorMqtt1.xml
    Set desired variable watches on the Watchdog tab
    (optional) Set desired Alias on the Alias tab
    Have fun



Dependencies

There are a few dependencies that should be copied to /usr/lib/lua folder
