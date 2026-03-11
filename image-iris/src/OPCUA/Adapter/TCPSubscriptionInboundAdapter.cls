/// An inbound adapter for accessing data 
/// using an OPC UA subscription to monitored items on an OPC UA server.
Class OPCUA.Adapter.TCPSubscriptionInboundAdapter Extends OPCUA.Adapter.Common
{

/// Configurable settings
Parameter SETTINGS = "ReestablishOnEmptyResult:Connection,RequestedPublishingInterval:OPC-UA Subscription,RequestedLifetimeCount:OPC-UA Subscription,RequestedMaxKeepAliveCount:OPC-UA Subscription,MaxNotificationsPerPublish:OPC-UA Subscription,SubscriptionPollingTimeout:OPC-UA Subscription,RequestedSamplingInterval:OPC-UA Subscription,RequestedQueueSize:OPC-UA Subscription";

// *** PROPERTIES INFLUENCED BY SETTINGS ***

/// The requested cyclic rate (in milliseconds) that the Subscription 
/// is being requested to return Notifications to the Client. 
/// Notice that the actual rate is set by the server and may be 
/// different from that requested.
/// If the requested value is 0 or negative, then 
/// the Server shall revise with the fastest supported publishing interval.
/// Defined in section 5.13.2.2 of the OPC UA specification.
Property RequestedPublishingInterval As %Numeric [ InitialExpression = 500 ];

/// When the publishing timer has expired this number of times without 
/// a Publish request being available to send a NotificationMessage, 
/// then the Subscription shall be deleted by the Server.
/// Notice that the actual lifetime count is set by the server and may be 
/// different from that requested.
/// The lifetime count must be a minimum of three times the keep keep-alive count.
/// Defined in section 5.13.2.2 of the OPC UA specification.
Property RequestedLifetimeCount As %Integer [ InitialExpression = 10000 ];

/// When the publishing timer has expired this number of times without 
/// requiring any NotificationMessage to be sent, the Subscription 
/// sends a keep-alive Message to the Client.
/// Notice that the actual keep-alive count is set by the server and may be 
/// different from that requested.
/// If the requested value is 0, the Server shall revise with 
/// the smallest supported keep-alive count.
/// Defined in section 5.13.2.2 of the OPC UA specification.
Property RequestedMaxKeepAliveCount As %Integer [ InitialExpression = 10 ];

/// The maximum number of notifications that the Client wishes to receive 
/// in a single Publish response. A value of zero indicates that there is no limit.
/// Defined in section 5.13.2.2 of the OPC UA specification.
Property MaxNotificationsPerPublish As %Integer [ InitialExpression = 100 ];

/// The timeout applied to each poll made by the client of the 
/// OPC UA server requesting notifications for changes to 
/// monitored items. Necessarily, the minimum time required to 
/// execute the poll.
Property SubscriptionPollingTimeout As %Integer [ InitialExpression = 500 ];

/// Indicates whether, in the event that no notifications are returned 
/// by the target server for a given subscription polling attempt, 
/// any existing connection to that server should
/// be abandoned and an attempt made to reestablish the connection. A 
/// value of 1 indicates so; a value of 0 not. If indicated as a value 
/// higher than one, then the value also indicates the number of times
/// that such subscription polling attempts must return no notifications
/// before the connection should be abandoned and an attempt made to 
/// reestablish it.
Property ReestablishOnEmptyResult As %Integer [ InitialExpression = 0 ];

/// A duration in milliseconds indicating the interval at which 
/// monitored items on the server should be assessed by the server 
/// in order to determine if changes have occurred. A value of zero 
/// indicates that the server should use the fastest practical rate. 
/// A negative number indicates that the defualt rate should be used.
/// Notice that the actual sampling intervals are set by the server
/// and may be different than those requested. Notice also that, in 
/// this application, only a single rate may be requested and that 
/// that rate must be applicable to all monitored items for the 
/// subscription. Defined in section 7.16 of the OPC UA specification.
Property RequestedSamplingInterval As %Numeric [ InitialExpression = 500 ];

/// Indicates the number of data changes that the server should remember,
/// for any given monitored item, for reporting to the client when the 
/// client next polls asking for recent data changes. A value of one 
/// indicates that the server should keep track of only the most recent
/// value, and any poll request by the client will be answered with only
/// that most recent value regardless of how many times a data change 
/// has occurred since the time of the last poll of the server by the 
/// client. A value of zero indicates that the default quantity should
/// be used. Notice that, in this application, only a single queue size
/// may be requested and that requested queue size is assumed to be 
/// applicable to all monitored items for the subscription. Notice also
/// that the actual queue sizes for monitored items on the server are 
/// set by the server and may be different than requested. Defined in
/// section 7.16 of the OPC UA specification.
Property RequestedQueueSize As %Integer [ InitialExpression = 1 ];

// *** PRIVATE PROPERTIES ***

Property Specification As %List [ Private ];

Property QueryHandle As %Integer [ Private ];

Property QtySequentialEmptyResults As %Integer [ InitialExpression = 0, Private ];

Property MaxInternalQueueSize As %Integer [ InitialExpression = 0, Private ];

Property MaxBatchSize As %Integer [ InitialExpression = 0, Private ];

// *** METHODS ***

/// Must be called before connecting. 
/// (OPCUA.Service.TCPSubscriptionService calls this function in its OnInit() event.)
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
	
		set tSC = ##super()
		Quit:$$$ISERR(tSC)
		
		$$$TRACE("OPCUA subscription adapter connected to "_..URL)

	} catch (e) {
		Set tSC=e.AsStatus()
	}
	
	if $$$ISERR(tSC) {
		$$$TRACE("OPCUA subscription adapter unable to connect to "_..URL_" : "_$SYSTEM.Status.GetErrorText(tSC))
		Quit tSC
	} 

	try {

		#dim tHandle as %Integer
		#dim tPublishingInterval as %Double = ..RequestedPublishingInterval
		#dim tLifetimeCount as %Integer = ..RequestedLifetimeCount
		#dim tMaxKeepAliveCount as %Integer = ..RequestedMaxKeepAliveCount
		#dim tSamplingInterval as %Integer = ..RequestedSamplingInterval
		#dim tQueueSize as %Integer = ..RequestedQueueSize
		#dim tMaxInternalQueueSize as %Integer = ..MaxInternalQueueSize

		set tSC = ..Client.CreateSubscriptionSetB(.tHandle,..Specification,.tPublishingInterval,.tLifetimeCount,.tMaxKeepAliveCount,..MaxNotificationsPerPublish,.tSamplingInterval,.tQueueSize,tMaxInternalQueueSize)
		Quit:$$$ISERR(tSC)

		set ..QueryHandle = tHandle

		$$$LOGINFO("OPCUA subscription created: Handle="_..QueryHandle_", PublishingInterval="_tPublishingInterval_", LifetimeCount="_tLifetimeCount_", MaxKeepAliveCount="_tMaxKeepAliveCount_", MaxSamplingInterval="_tSamplingInterval_", MinQueueSize="_tQueueSize)

	} catch (e) {
		Set tSC=e.AsStatus()
	}
	
	if $$$ISERR(tSC) {
	
		$$$LOGERROR("OPCUA subscription query setup failed : "_$SYSTEM.Status.GetErrorText(tSC))

		do ..Disconnect()

		Quit tSC
	} 
	
	Quit tSC  // Quit $$$OK
}

/// Used internally in order to handle poll results.
Method OnTask() As %Status
{
	#dim tSC as %Status = $$$OK

	#dim tQtyProcessed as %Integer = 0
	#dim tProcessingErrors as %Integer = 0
	
	#dim tStartTime as %TimeStamp = $ZTimestamp

	try {
		
		if (..IsConnected < 1) || (..ResetClientFlag '= 0) {

			set tSC = ..Connect()
			$$$ThrowOnError(tSC)

			set ..ResetClientFlag = 0
			set ..IsConnected = 1
			$$$LOGINFO("OPCUA adapter connected to "_..URL)			
		}

		#dim tList as %List

		set tSC = ..Client.PollSubscriptionSet(.tList,..QueryHandle,..SubscriptionPollingTimeout,..MaxBatchSize,1)
		Quit:$$$ISERR(tSC)

		//set tSC = ..BusinessHost.ProcessInput(.tList)  

		// *********

		set tQty = $LI(tList,2)
		set tBatch = $LI(tList,3)
		set tQueueStats = $LI(tList,4)

		set tQtyLost = $LI(tQueueStats,7) - $LI(tQueueStats,3) // Qty lost after - before
		set tQueueSizeLimit = $LI(tQueueStats,1) // zero if unlimited

		if tQtyLost > 0 {
			$$$LOGERROR("Data loss ("_tQtyLost_" elements). Internal queue size insufficient for incoming data rate.")
		} elseif tQueueSizeLimit > 0 {
			set tQueueUsage = $LI(tQueueStats,4) / tQueueSizeLimit // Queue size before processing / Max allowed size
			if tQueueUsage > 0.5 {
				$$$LOGWARNING("Internal queue utilized at greater than 50% capacity: "_tQueueUsage)
			}
		}

		if (..MaxBatchSize '= 0) && (tQty >= ..MaxBatchSize) {
			set tCurrentQueueSize = $LI(tQueueStats,6)
			set tQueueItemsProcessed = $LI(tQueueStats,4) - tCurrentQueueSize // Queue size before - after processing
			$$$LOGWARNING("Batch size capacity warning. Performance may degrade. Current queue items processed = "_tQueueItemsProcessed_". Current internal queue size = "_tCurrentQueueSize_".")
		}

		for i=1:1:tQty {

			// Ensure that this is set even in the event of error.
			// (If an error occurs within ProcessInput(), then 
			// %WaitForNextCallInterval should hopefully still be set.)
			set ..BusinessHost.%WaitForNextCallInterval = 1 

			set tSC = ..BusinessHost.ProcessInput($LI(tBatch,i))  

			if $$$ISERR(tSC) {

				$$$TRACE("Error encountered processing adapter output, continuing... : "_$SYSTEM.Status.GetErrorText(tSC))
				set tProcessingErrors = tProcessingErrors + 1

			} else {

				set tQtyProcessed = tQtyProcessed + 1
			}

		}

		// *********

		// Again, ensure that %WaitForNextCallInterval remains set.
		set ..BusinessHost.%WaitForNextCallInterval = 1
			
		Quit:$$$ISERR(tSC)

	} catch (e) {
		Set tSC = e.AsStatus()
	}

	set tEndTime = $ZTimestamp
	set tElapsedTime = ##class(%SYSTEM.SQL).DATEDIFF("ms",tStartTime,tEndTime) / 1000.0 // in seconds

	if $$$ISERR(tSC) {

		try {

			#dim tTmpConn as %Integer = -1
			#dim tTmpReset as %Integer = 0
			
			do ..Client.GetClientState("",.tTmpConn,"","",.tTmpReset)
			
			set ..IsConnected = tTmpConn
			set ..ResetClientFlag = tTmpReset
		
		} catch (e) {
			set ..IsConnected = 0
			set ..ResetClientFlag = 0
		}

		if ..LastReportedError '= tSC {

			if ##class(OPCUA.Utils).ErrTextIsTypeInfo($SYSTEM.Status.GetErrorText(tSC)) {

				//$$$LOGINFO($SYSTEM.Status.GetErrorText(tSC))
				$$$TRACE($SYSTEM.Status.GetErrorText(tSC))
				set ..BusinessHost.%WaitForNextCallInterval = 0

			} elseif ##class(OPCUA.Utils).AreSimilarOpcuaDisconnectErrors($SYSTEM.Status.GetErrorText(..LastReportedError),$SYSTEM.Status.GetErrorText(tSC)) {

				$$$TRACE("Error encountered : "_$SYSTEM.Status.GetErrorText(tSC)_" : "_..Client.GetClientStateString())
				set ..BusinessHost.%WaitForNextCallInterval = 1	

			} else {

				$$$LOGERROR("Error encountered : "_$SYSTEM.Status.GetErrorText(tSC)_" : "_..Client.GetClientStateString())
				set ..BusinessHost.%WaitForNextCallInterval = 1	
			}
			set ..LastReportedError = tSC

		} else {
			$$$TRACE("Error encountered : "_$SYSTEM.Status.GetErrorText(tSC)_" : "_..Client.GetClientStateString())
		}

		$$$SetHostMonitor(..BusinessHost.%ConfigName,$$$eMonitorStatus,"Error")

		if (##class(%SYSTEM.SQL).DATEDIFF("ms",..ConnectionRetryEndTime,$ZTimestamp) > 0) {
			if ..AlwaysConnect {
				$$$LOGWARNING("Client has not been able to establish the conection within the last "_..ConnectionRetryTimeout_" seconds")
				set ..ConnectionRetryEndTime = ##class(%SYSTEM.SQL).DATEADD("s",..ConnectionRetryTimeout,$ZTimestamp)
			} else {
				$$$LOGERROR("Error encountered : Maximum time since a successful response exceeded : "_$SYSTEM.Status.GetErrorText(tSC))
				if ..IsConnected {
					set ..IsConnected = 0
				}
				set ..BusinessHost.%QuitTask = 1
			}
			return tSC
		}

	} else {
	
		set ..IsConnected = 1

		set ..LastReportedError = tSC // $$$OK
		set ..BusinessHost.%WaitForNextCallInterval = 1
		
		if tProcessingErrors > 0 {

			$$$LOGWARNING(tProcessingErrors_" processing error(s) encountered concurrent with the successful entry of "_tQtyProcessed_" record(s) : "_..Client.GetClientStateString())

			set ..QtySequentialEmptyResults = 0

		} elseif tQtyProcessed > 0 {

			//$$$TRACE("1 record entered in "_tElapsedTime_" seconds.")
			$$$TRACE(tQtyProcessed_" record(s) entered in "_tElapsedTime_" seconds with no errors encountered : "_..Client.GetClientStateString())	

			set ..QtySequentialEmptyResults = 0

		} else {
		
			// No results were returned. Is the client connected?
			try {
				#dim tTmp as %Integer = -1
				do ..Client.GetClientState("",.tTmp)
				set ..IsConnected = tTmp
			} catch (e) {
				set ..IsConnected = 0
			}

			if ..IsConnected = 0 {

				$$$LOGWARNING("Connection lost : "_..Client.GetClientStateString())

			} elseif ..ReestablishOnEmptyResult > 0 {

				$$$TRACE(tQtyProcessed_" record(s) entered in "_tElapsedTime_" seconds with no errors encountered : "_..Client.GetClientStateString())	
				
				// Connection may have been dropped and should perhaps be reestablished 
				set ..QtySequentialEmptyResults = ..QtySequentialEmptyResults + 1

				if ..QtySequentialEmptyResults >= ..ReestablishOnEmptyResult {

					$$$LOGWARNING("Maximum number of sequential empty results exceeded. Disconnecting.")	

					try {
						set tSC = ..Client.ReadBulkClear(..QueryHandle)
					} catch (e) {
						set tSC = e.AsStatus()
					}

					if $$$ISERR(tSC) {
						$$$TRACE("Ignoring error encountered when deleting old subscription : "_$SYSTEM.Status.GetErrorText(tSC))
					}

					try {
						set tSC = ..Client.Disconnect()
					} catch (e) {
						set tSC = e.AsStatus()
					}

					if $$$ISERR(tSC) {
						$$$TRACE("Ignoring error encountered when disconnecting : "_$SYSTEM.Status.GetErrorText(tSC))
					}

					set ..IsConnected = 0
					set ..ResetClientFlag = 1
					set ..QtySequentialEmptyResults = 0
				}

			} else {

				$$$TRACE(tQtyProcessed_" record(s) entered in "_tElapsedTime_" seconds with no errors encountered : "_..Client.GetClientStateString())	
			}

		}

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
