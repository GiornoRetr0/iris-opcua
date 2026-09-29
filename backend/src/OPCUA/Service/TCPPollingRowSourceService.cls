Include OPCUA.Constants

/// A business service that uses the TCPPollingInboundAdapter
/// to poll data from multiple OPC UA devices sharing the same device schema,
/// producing one row per device per poll cycle.
/// Each row includes a NodePath column identifying the source device.
///
/// The device list comes from the adapter's DeviceNodePaths setting, and each
/// device's nodes are resolved by name at connect time (see
/// <class>OPCUA.DataSource.Resolver</class>). Devices may have partial column
/// coverage: a column with no matching node on a given device is stored as NULL
/// and logged. Adding a device is therefore a one-line setting edit — no
/// regeneration, no recompile.
Class OPCUA.Service.TCPPollingRowSourceService Extends Ens.BusinessService
{

Parameter ADAPTER = "OPCUA.Adapter.TCPPollingInboundAdapter";

Property Adapter As OPCUA.Adapter.TCPPollingInboundAdapter;

/// Per-service schema layout; shared implementation for both collection modes.
Property RowWriter As OPCUA.DataSource.RowWriter [ Private ];

Method OnInit() As %Status
{
	set ..RowWriter = ##class(OPCUA.DataSource.RowWriter).%New()
	Quit ..RowWriter.Initialize(..Adapter.DataSourceClass)
}

Method OnProcessInput(ByRef pInputAsList As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	#dim tSC As %Status = $$$OK
	try {
		set tMasks = ..Adapter.RowSourceMasks
		set tPaths = ..Adapter.RowSourcePaths
		set tResultIdx = 1
		for iRS=1:1:$LL(tMasks) {
			set tSC = ..RowWriter.BuildRow(.pInputAsList, $LI(tMasks, iRS), $LI(tPaths, iRS), .tResultIdx, .tRowData, .tQualityChanges)
			Quit:$$$ISERR(tSC)
			do ..RowWriter.LogQualityChanges($LI(tPaths, iRS), tQualityChanges)
			set tSC = $CLASSMETHOD(..Adapter.DataSourceClass, "SaveSourcedData", .tRowData)
			if $$$ISERR(tSC) {
				$$$LOGERROR("Failed to save device "_iRS_" ("_$LI(tPaths, iRS)_"): "_$System.Status.GetErrorText(tSC))
				set tSC = $$$OK
			}
		}
	} catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

}
