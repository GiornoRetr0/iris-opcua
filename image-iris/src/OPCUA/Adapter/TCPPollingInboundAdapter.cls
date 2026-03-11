/// An inbound adapter for accessing data on an OPC UA server
/// by repeated polling of the server for results.
Class OPCUA.Adapter.TCPPollingInboundAdapter Extends OPCUA.Adapter.Common
{

Property Specification As %List [ Private ];

Property QueryHandle As %Integer [ Private ];

/// Must be called before connecting. 
/// (OPCUA.Service.TCPPollingService calls this function in its OnInit() event.)
Method Configure(pSpecification As %List) As %Status
{
	#dim tSC as %Status = $$$OK
		
	try {

		set ..Specification = pSpecification

	} catch (e) {
		set tSC = e.AsStatus()
	}

	Quit tSC
}

/// Used internally to setup of the OPC-UA client, connect to the 
/// server, and intialize the query that will be used to poll for
/// results.
Method Connect() As %Status
{
	#dim tSC as %Status = $$$OK

	try {

		if ..QueryHandle > 0 {

			set tSC = ..Client.ReadBulkClear(..QueryHandle)
			// do not quit on clear failure

			set ..QueryHandle = 0
		}

		#dim tmp as %Integer
		set tSC = ..Client.ReadBulkSetupC(.tmp,..Specification)
		Quit:$$$ISERR(tSC)

		set ..QueryHandle = tmp

		set tSC = ##super()
		Quit:$$$ISERR(tSC)

	} catch (e) {
		Set tSC=e.AsStatus()
	}
	
	Quit tSC  // Quit $$$OK
}

/// Used internally in order to handle poll results.
Method OnTask() As %Status
{
	#dim tSC as %Status = $$$OK

	#dim tQtyProcessed as %Integer = 0
	#dim tStartTime as %TimeStamp = $ZTimestamp
	
	try {

		if '..IsConnected {

			set tSC = ..Connect()
			$$$ThrowOnError(tSC)

			$$$LOGINFO("OPCUA adapter connected to "_..URL)			
		}

		#dim tList as %List

		set tSC = ..Client.ReadBulkPollC(.tList,..QueryHandle)
		Quit:$$$ISERR(tSC)

		set tSC = ..BusinessHost.ProcessInput(.tList)  
		Quit:$$$ISERR(tSC)

	} catch (e) {
		Set tSC = e.AsStatus()
	}

	set tEndTime = $ZTimestamp
	set tElapsedTime = ##class(%SYSTEM.SQL).DATEDIFF("ms",tStartTime,tEndTime) / 1000.0 // in seconds

	if $$$ISERR(tSC) {
	
		try {
			#dim tTmp as %Integer = -1
			do ..Client.GetClientState("",.tTmp)
			set ..IsConnected = tTmp
		} catch (e) {
			set ..IsConnected = 0
		}

		if ..LastReportedError '= tSC {

			if ##class(OPCUA.Utils).AreSimilarOpcuaDisconnectErrors($SYSTEM.Status.GetErrorText(..LastReportedError),$SYSTEM.Status.GetErrorText(tSC)) {

				$$$TRACE("Error encountered : "_$SYSTEM.Status.GetErrorText(tSC)_" : "_..Client.GetClientStateString())

			} else {

				$$$LOGERROR("Error encountered : "_$SYSTEM.Status.GetErrorText(tSC)_" : "_..Client.GetClientStateString())
			}

			set ..LastReportedError = tSC
			set ..BusinessHost.%WaitForNextCallInterval = 1	

		} else {
			$$$TRACE("Error encountered : "_$SYSTEM.Status.GetErrorText(tSC)_" : "_..Client.GetClientStateString())
		}

		$$$SetHostMonitor(..BusinessHost.%ConfigName,$$$eMonitorStatus,"Error")

		if ##class(%SYSTEM.SQL).DATEDIFF("s",..ConnectionRetryEndTime,$ZTimestamp) > 0 && (..AlwaysConnect=0){
			if ..AlwaysConnect {
				$$$LOGWARNING("Client has not been able to establish the conection within the last "_..ConnectionRetryTimeout_" seconds")
				set ..ConnectionRetryEndTime = ##class(%SYSTEM.SQL).DATEADD("s",..ConnectionRetryTimeout,$ZTimestamp)
			} else {
				$$$LOGERROR("Connection retry period concluded. Unable to establish connection.")
				set ..BusinessHost.%QuitTask = 1
			}
			return tSC
		}

	} else {

		set ..IsConnected = 1

		set ..LastReportedError = tSC // $$$OK
		set ..BusinessHost.%WaitForNextCallInterval = 1
		
		$$$TRACE("1 record entered in "_tElapsedTime_" seconds. : "_..Client.GetClientStateString())

		$$$SetHostMonitor(..BusinessHost.%ConfigName,$$$eMonitorStatus,"OK")

		set ..ConnectionRetryEndTime = ##class(%SYSTEM.SQL).DATEADD("s",..ConnectionRetryTimeout,$ZTimestamp)

	} 

	Quit $$$OK
}

/// Used internally to disconnect the OPC-UA client.
Method OnTearDown() As %Status
{
	try {
		do ..Client.ReadBulkClear(..QueryHandle)	// Perhaps unnecessary
	} catch (e) {}

	return ##super()
}

}
