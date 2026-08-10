Include (OPCUA.Constants, Ensemble)

/// IRIS OPC UA Simple Write Example
Class Examples.OPCUA.SimpleWrite
{

/// Writes each of an integer and a double value to a specific node 
/// on a publicly-accessible OPC UA server, and shows the change by
/// reading values from the node beforehand and afterwards.
ClassMethod Run() As %Status
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {

		set tSC = ##class(OPCUA.Utils).Initialize()
		Quit:$$$ISERR(tSC)
		
		set tClient = ##class(OPCUA.Client).%New()

		set tSC = tClient.Initialize()
		Quit:$$$ISERR(tSC)

		set tSC = tClient.SetupClient()
		Quit:$$$ISERR(tSC)

		set tSC = tClient.Connect("opc.tcp://opcuaserver.com:48010")
		Quit:$$$ISERR(tSC)

		#dim tResults as %List
		#dim tValue as %Integer

		w !!, "Temperature         (0): "
		set tSC = tClient.ReadValueAttribute(.tResults, "AirConditioner_1.Temperature", 3, $$$OpcuaNodeIdTypeString)
		Quit:$$$ISERR(tSC)
		zw tResults

		w "TemperatureSetPoint (0): "
		set tSC = tClient.ReadValueAttribute(.tResults, "AirConditioner_1.TemperatureSetPoint", 3, $$$OpcuaNodeIdTypeString)
		Quit:$$$ISERR(tSC)
		zw tResults

		set tValue = 63  // Integer
		w "Writing "_tValue_"... "
		set tSC = tClient.WriteValueAttribute($DECIMAL(tValue), $$$OpcuaDataTypeUInt16, "AirConditioner_1.TemperatureSetPoint", 3, $$$OpcuaNodeIdTypeString)
		Quit:$$$ISERR(tSC)

		w !, "Temperature         (1): "
		set tSC = tClient.ReadValueAttribute(.tResults, "AirConditioner_1.Temperature", 3, $$$OpcuaNodeIdTypeString)
		Quit:$$$ISERR(tSC)
		zw tResults

		w "TemperatureSetPoint (1): "
		set tSC = tClient.ReadValueAttribute(.tResults, "AirConditioner_1.TemperatureSetPoint", 3, $$$OpcuaNodeIdTypeString)
		Quit:$$$ISERR(tSC)
		zw tResults

		w "Waiting 2 seconds..."
		Hang 2

		set tValue = 731.5 // Double
		w !, "Writing "_tValue_"... "
		set tSC = tClient.WriteValueAttribute($DOUBLE(tValue), $$$OpcuaDataTypeDouble, "AirConditioner_1.TemperatureSetPoint", 3, $$$OpcuaNodeIdTypeString)
		Quit:$$$ISERR(tSC)

		w !, "Temperature         (2): "
		set tSC = tClient.ReadValueAttribute(.tResults, "AirConditioner_1.Temperature", 3, $$$OpcuaNodeIdTypeString)
		Quit:$$$ISERR(tSC)
		zw tResults

		w "TemperatureSetPoint (2): "
		set tSC = tClient.ReadValueAttribute(.tResults, "AirConditioner_1.TemperatureSetPoint", 3, $$$OpcuaNodeIdTypeString)
		Quit:$$$ISERR(tSC)
		zw tResults

		w !!

		set tSC = tClient.Disconnect()

	} Catch (e) {
		Set tSC=e.AsStatus()
	}

	Quit tSC
}

}
