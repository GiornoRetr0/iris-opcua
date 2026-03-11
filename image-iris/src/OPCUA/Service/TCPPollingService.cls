Include OPCUA.Constants

/// A business service that uses the TCPPollingInboundAdpater
/// to access data with OPC UA and append that data to a table.
Class OPCUA.Service.TCPPollingService Extends Ens.BusinessService
{

Parameter ADAPTER = "OPCUA.Adapter.TCPPollingInboundAdapter";

Property Adapter As OPCUA.Adapter.TCPPollingInboundAdapter;

Method OnInit() As %Status
{
	#dim tSC as %Status = $$$OK

	try {
		
		// Get the spec
		set tSpecification = ##class(OPCUA.DataSource.Projection).GetOPCUAConfigSpec(..Adapter.DataSourceClass)

		$$$LOGINFO("Configuring OPCUA polling adapter")
		set tSC = ..Adapter.Configure(.tSpecification)
	
	} catch (e) {
		set tSC = e.AsStatus()
	}

	Quit tSC
}

Method OnProcessInput(ByRef pInputAsList As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
 	#dim tSC as %Status = $$$OK
 
	try {
	
		set $LI(pInputAsList,1) = ""

		set tSC = $CLASSMETHOD(..Adapter.DataSourceClass,"SaveSourcedData",.pInputAsList)

	} catch (e) {
		set tSC = e.AsStatus()
	}

	return tSC
}

}
