Include (%callout, OPCUA.Constants, Ensemble)

/// This class implements an interface to portions of the open source open62541 library,
/// allowing for the creation of two different types of data feeds that can be used
/// to import data into IRIS from OPC UA servers located locally, across a LAN, and/or
/// over the Internet. Security features such as encrypted 
/// transmission and password authentication are not implemented at this time.
/// Details about open62541 can be found at https://open62541.org.
/// This client provides the ability to connect to an OPC UA server locally,
/// across a LAN, or over the Internet. 
/// <ul>
/// <li>Periodic Polling Data Feeds</li> -- Data feeds of this type are implemented as 
/// a simple request to an OPC UA server asking for a set of one or more node attributes 
/// to be returned. The query is first declared to this OPC UA client using
/// <method>ReadBulkSetup</method> and subsequently, <method>ReadBulkPoll</method> can 
/// be used poll the server with a TCP/IP request in order to obtain the results
/// representing a snapshot in time. <method>ReadBulkPoll</method> will return one 
/// complete row of results each time it is executed, and can be used
/// as many times as is necessary. Later, when IRIS has finished using the feed, 
/// the query specification can be deleted from the client
/// using the method <method>ReadBulkClear</method>.</li>
/// <li>Subscribing Data Feeds</li> -- Data feeds of this type are implemented using 
/// the OPC UA subscription framework whereby an OPC UA server is tasked with 
/// monitoring one or more variables held within it, and reporting any changes to 
/// those variables back to the requesting client. Feeds of this type can be declared
/// using <method>CreateSubscriptionSet</method>, and subsequently, the client may
/// request notfication of any recent changes with <method>PollSubscriptionSet</method>.
/// Later, when IRIS has finisihed using the feed, the subscription can be deleted on
/// the server using <method>DeleteSubscriptionSet</method>.</li>
/// </ul>
Class OPCUA.Client Extends %RegisteredObject
{

/// Error Text Domain
Parameter DOMAIN = "OPCUA";

/// The handle to the library's instance of the OPC UA client
Property Handle As %Integer [ InitialExpression = 0, Private ];

/// Used internally to interpret error codes returned by the client.
ClassMethod DecodeError(list As %String) As %Status [ Final ]
{
	Set tType=$List(list,2),tCode=$List(list,3),tMsgTxt=$List(list,4)
	If tType=$$$ErrorTypeNone {
		Set tTypeTxt=$$$Text("No Error")
	} elseif tType=$$$ErrorTypeInfo {
		Set tTypeTxt=$$$Text("Incomplete w/o Err")
	} elseif tType=$$$ErrorTypeApp {
		Set tTypeTxt=$$$Text("Application Error")
	} elseif tType=$$$ErrorTypeCallin {
		Set tTypeTxt=$$$Text("Callin Error")
	} elseif tType=$$$ErrorTypeOPCUA {
		Set tTypeTxt=$$$Text("OPC Error")
	} elseif tType=$$$ErrorTypeClient {
		Set tTypeTxt=$$$Text("Client Error")
	} elseif tType=$$$ErrorTypeServer {
		Set tTypeTxt=$$$Text("Server Error")
	} elseif tType=$$$ErrorTypeUnknown {
		Set tTypeTxt="Unknown Error"
	} else {
		Set tTypeTxt=$$$Text("Undefined Error")
	}
	
	//Quit $$$ERROR($$$OPCUACLIENT,tCode,tTypeTxt,tMsgTxt)
	Quit $$$ERROR($$$OPCUACLIENT,tMsgTxt)
}

/// Loads the IrisOPCUA library if necessary
ClassMethod InitializeLibrary() As %Status [ Final, Internal, Private ]
{
	return ##class(OPCUA.Utils).Initialize()
}

/// Private, Create a client
Method Create() As %Status [ Final, Internal, Private ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {

		#; Ensure library initialization
		Set tSC = ..InitializeLibrary()
		Quit:$$$ISERR(tSC)

		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfCreateClientB,"")
        
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit
        
        #; Cache Handle of the Client instance
        Set ..Handle=$List(tRetval,2)
		
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// Private, Destroy a client
Method Destroy() As %Status [ Final, Internal, Private ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfDestroyClientB,"",$listbuild(..Handle))
        
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit
        
        #; Cache Handle of the Client instance
        Set ..Handle=0
		
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// Outputs the name of a corresponding UA status code.
ClassMethod GetStatusCodeName(Output StatusCodeName As %String, StatusCode As %Integer) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Ensure library initialization
		Set tSC = ..InitializeLibrary()
		Quit:$$$ISERR(tSC)

		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfGetStatusCodeNameB,"",$LB(StatusCode))
        
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        #; Set output variables
        Set StatusCodeName = $LI(tRetval,2)
        
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// Outputs the name of a corresponding code indicating the client state.
ClassMethod GetClientStateName(Output ClientStateName As %String, ClientStateCode As %Integer) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Ensure library initialization
		Set tSC = ..InitializeLibrary()
		Quit:$$$ISERR(tSC)

		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfGetClientStateNameB,"",$LB(ClientStateCode))
        
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        #; Set output variables
        Set ClientStateName = $LI(tRetval,2)
        
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// Outputs the name of a corresponding code indicating the secure channel state.
ClassMethod GetChannelStateName(ChannelStateCode As %Integer, ByRef pSC As %Status = "") As %String [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim tRetName As %String = ""
	
	Try {
		
		#; Ensure library initialization
		Set tSC = ..InitializeLibrary()
		Quit:$$$ISERR(tSC)

		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfGetChannelStateName,"",$LB(ChannelStateCode))
        
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        #; Set output variables
        Set tRetName = $LI(tRetval,2)

	} Catch (e) {
		Set tSC=e.AsStatus()
	}

	set pSC = tSC
	return tRetName
}

/// Outputs the name of a corresponding code indicating the session state.
ClassMethod GetSessionStateName(SessionStateCode As %Integer, ByRef pSC As %Status = "") As %String [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim tRetName As %String = ""
	
	Try {
		
		#; Ensure library initialization
		Set tSC = ..InitializeLibrary()
		Quit:$$$ISERR(tSC)

		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfGetSessionStateName,"",$LB(SessionStateCode))
        
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        #; Set output variables
        Set tRetName = $LI(tRetval,2)

	} Catch (e) {
		Set tSC=e.AsStatus()
	}

	set pSC = tSC
	return tRetName
}

/// Outputs the name of the corresponding error code. 
ClassMethod GetSimpleErrorCodeName(Output ErrorName As %String, ErrorCode As %Integer) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Ensure library initialization
		Set tSC = ..InitializeLibrary()
		Quit:$$$ISERR(tSC)

		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfGetSimpleErrorCodeNameB,"",$LB(ErrorCode))
        
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        #; Set output variables
        Set ErrorName = $LI(tRetval,2)
        
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// This callback method is invoked by the %New method to provide 
/// notification that a new instance of an object is being created.
Method %OnNew() As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException

	Quit tSC
}

/// This function must be called prior to using most functions of this class.
/// It is usually appropriate to call this function immediately after
/// instantiating the object.
Method Initialize() As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Create the client
		Set tSC=..Create()
	
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// Outputs the client state and connection status
Method GetClientState(Output ConnectionStatus As %Integer, Output IsConnected As %Integer, Output SecureChannelStatus As %Integer, Output SessionStatus As %Integer, Output ClientResetFlag As %Integer) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfGetClientStateD,"",$LB(..Handle))

        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        #; Set output variables
        Set ConnectionStatus = $LI(tRetval,2)
        Set IsConnected = $LI(tRetval,3)
        Set SecureChannelStatus = $LI(tRetval,4)
        Set SessionStatus = $LI(tRetval,5)
		Set ClientResetFlag = $LI(tRetval,6)
        
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// Outputs a human-readable string describing the client state and connection status
Method GetClientStateString(ByRef pSC As %Status = "") As %String [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim tRetStr As %String = ""
	#dim e As %Exception.AbstractException	

	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfGetClientStateD,"",$LB(..Handle))

        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        #; Set output variables
        Set ConnectionStatus = $LI(tRetval,2)
        Set IsConnected = $LI(tRetval,3)
        Set SecureChannelStatus = $LI(tRetval,4)
        Set SessionStatus = $LI(tRetval,5)
		Set ResetFlag = $LI(tRetval,6)
        
		#dim tConnStatusDesc as %String
		do ##class(OPCUA.Client).GetStatusCodeName(.tConnStatusDesc,ConnectionStatus)

		set tRetStr = "ChannelStatus='"_..GetChannelStateName(SecureChannelStatus)_"', SessionStatus='"_..GetSessionStateName(SessionStatus)_"', ConnectionStatus='"_tConnStatusDesc_"'"
		if ResetFlag = 1 {
			set tRetStr = tRetStr_" (Client reset scheduled)"
		}

	} Catch (e) {
		Set tSC=e.AsStatus()
	}

	set pSC = tSC
	return tRetStr
}

/// Sets logfile
Method SetLogFile(LogFileName As %String) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {

		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfSetLogFile,"",$LB(LogFileName))
		
		#; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// Performs necessary setup functions prior to client's connecting
/// to a server. Should be called subsequently to Initialize().
Method SetupClient(ConnectionTimeout As %Integer = 3000, MessageSecurityMode As %Integer = 1, ClientURI = "", CertificatePathname As %String = "", PrivateKeyPathname As %String = "", TrustListDir As %String = "", RevocationListDir As %String = "", ResetFlag As %Integer = 0) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {

		#; Set the unicode flag for the connector
		set tVersionIsUnicode = $System.Version.IsUnicode()

		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfSetupClientC,"",$LB(..Handle,ConnectionTimeout,MessageSecurityMode,ClientURI,CertificatePathname,PrivateKeyPathname,TrustListDir,RevocationListDir,tVersionIsUnicode,ResetFlag))
		
		#; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// This callback method is invoked by the %Close method to provide 
/// notification that the current object is being closed.
Method %OnClose() As %Status
{
	Quit ..Destroy()
}

/// Creates a connection to the specified URL.
Method Connect(url As %String, Username As %String = "", Password As %String = "") As %Status [ Final ]
{
	// Notice that JN placed the URL in the %OnNew() Method

	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		if Username = "" {

			// Anonymous
			Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfConnectB,"",$LB(..Handle,url))

		} else {

			Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfConnectUser,"",$LB(..Handle,url,Username,Password))
		}
                
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// Disconnects a client from a server that it is connected to.
Method Disconnect() As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfDisconnectB,"",$LB(..Handle))
    
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

Method Browse(Output Results As %List, NodeTypes As %List, NodeNamespaces As %List, NodeIds As %List) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfBrowse,"",$LB(..Handle,NodeTypes,NodeNamespaces,NodeIds))
  
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        #; Set output variables
        //Set Results = $LI(tRetval,2)
        Set Results = tRetval
		        
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

// --------------------------------------------------------------------------------------------

// Functions for use with Periodic Polling Data Feeds

// --------------------------------------------------------------------------------------------

/// Prepares a query that can be subsequently executed repeatedly. 
/// The data elements requested are specified in four lists of equal length:
/// <ul>
/// <li>NodeTypes -- A list of numeric values indicating the type of node id 
/// that is used to identify the node. (e.g. $$$OpcuaNodeIdTypeString means 
/// a string is used to identify the node.)</li>
/// <li>NodeNamespaces -- A list of numeric values indicating the namespace 
/// for each requested node.</li>
/// <li>NodeIds -- A list of numeric or string values indicating the primary
/// identifier used to identify each requested node.</li>
/// <li>NodeAttributes -- A kist of numeric values indicating the attribute 
/// to be returned for each requested node. (e.g. $$$OpcuaAttributeValue 
/// means that the value attribute should be returned.)
/// </ul>
/// The QueryHandle is an output parameter that can subsequently
/// be used to identify this particular query so that it can be executed
/// and results for it obtained; this function simply declares the query.
/// (This function is not deprecated, but <method>ReadBulkSetupC</method> 
/// is preferred.)
Method ReadBulkSetup(Output QueryHandle As %Integer, NodeTypes As %List, NodeNamespaces As %List, NodeIds As %List, NodeAttributes As %List) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfReadBulkSetup,"",$LB(..Handle,NodeTypes,NodeNamespaces,NodeIds,NodeAttributes))
  
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        #; Set output variables
        Set QueryHandle = $LI(tRetval,2)
        
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// [DEPRECATED] Prepares a query that can be subsequently executed repeatedly.
/// The data elements requested are specified in two lists of equal length, a
/// a list of lists representing serialized node id objects, and a numeric list 
/// of attribute identifiers.
/// (This function is deprecated; <method>ReadBulkSetupC</method> is preferred.)
Method ReadBulkSetupB(Output QueryHandle As %Integer, NodeIds As %List, NodeAttributes As %List) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#dim NodeIdCLs as %List

		Set NodeIdCLs = NodeIds

		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfReadBulkSetupB,"",$LB(..Handle,NodeIdCLs,NodeAttributes))
  
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        #; Set output variables
        Set QueryHandle = $LI(tRetval,2)
        
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// Prepares a query that can be subsequently executed repeatedly.
/// Data elements requested are detailed in a particular specification 
/// format that is the output of the OPCUA.DataSource framework.
/// Such specifications are in the form of multidimensional lists which 
/// feature three top-level elements: (1) the DataSource name, 
/// (2) the name of the global on which the results will be saved, and 
/// (3) a multidimensional sublist identifying the property elements. 
/// For the purposes of this function, only the sublist of element 
/// three is relevant. That sublist begins with an empty element, which 
/// is then followed by other elements, each further element itself 
/// being a list, that list with the elements:
/// <ul>
/// <li>The type of the element: 1 = primitive, 2 = standard OPC UA</li>
/// <li>One as pPropertyPath_"."_oProp.Name e.g. "[MyDataSource2].Temperature"</li>
/// <li>The namespace</li>
/// <li>The node name or number</li>
/// <li>The attribute id number</li>
/// </ul>
/// For the purposes of this function, only the last three 
/// elements---the namespace, the node name/number, and attribute id---are
/// relevant.
Method ReadBulkSetupC(Output QueryHandle As %Integer, ByRef Specification As %List) As %Status [ Final ]
{
	// Specifications are supplied in the form of %List
	// 1. DataSource name
	// 2. The name of the global on which to save the results
	// 3. A multidimensional %List of property elements.
	//		1. The first element is perhaps usually null (or the name of the class if a subclass?)
	//		2. Property elements take the form of a list with elements:
	//			1. The type of element: 1 = Primitives, 2 = Standard OPCUA, 3 = ?
	//			2. The pPropertyPath_"."_oProp.Name e.g. "[MyDataSource2].Temperature"
	//			3. The namespace
	//			4. The node name, a string NodeId identifier
	//			5. The AttributeId

	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfReadBulkSetupC,"",$LB(..Handle,Specification))
  
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        #; Set output variables
        Set QueryHandle = $LI(tRetval,2)
        
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// Executes a query previously prepared with either ReadBulkSetup(),
/// ReadBulkSetupB(), or ReadBulkSetupC(). Results are returned as a
/// <class>%List</class> of primitives without time stamps.
/// (This function is not deprecated, but <method>ReadBulkPollC</method> 
/// is preferred.)
Method ReadBulkPoll(Output Results As %List, QueryHandle As %Integer) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfReadBulkPoll,"",$LB(..Handle,QueryHandle))

        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        Set Results = tRetval
        
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
		
	Quit tSC
}

/// Executes a query previously prepared with either ReadBulkSetup() 
/// ReadBulkSetupB(), or ReadBulkSetupC(). Results are returned as a <class>%List</class>
/// of <class>%List</class> for where each sublist consists of a 
/// requested primitive accompanied by its source timestamp.
/// (This function is not deprecated, but <method>ReadBulkPollC</method> 
/// is preferred.)
Method ReadBulkPollB(Output Results As %List, QueryHandle As %Integer) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfReadBulkPollB,"",$LB(..Handle,QueryHandle))

        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        Set Results = tRetval
        
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	
	Quit tSC
}

/// Executes a query previously prepared with either ReadBulkSetup() 
/// ReadBulkSetupB(), or ReadBulkSetupC(). Results are returned as a <class>%List</class>
/// where each returned element is a <class>%List</class> representing 
/// a subclass of <class>OPCUA.Types.AbstractDataValue</class>.
Method ReadBulkPollC(Output Results As %List, QueryHandle As %Integer) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfReadBulkPollC,"",$LB(..Handle,QueryHandle,"",""))

        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        Set Results = tRetval
        
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	
	Quit tSC
}

/// Deletes a previously prepared query specification.
Method ReadBulkClear(QueryHandle As %Integer) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfReadBulkClear,"",$LB(..Handle,QueryHandle))
    
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

// --------------------------------------------------------------------------------------------

// Functions for use with Subscribing Data Feeds

// --------------------------------------------------------------------------------------------

/// [DEPRECATED] Creates and OPC UA subscription so as to receive updates 
/// regarding changes made to monitored items on a server. The data elements 
/// requested are specified in two lists of equal length, a list of lists 
/// representing serialized node id objects, and a numeric list of attribute 
/// identifiers. (This function is deprecated; 
/// <method>CreateSubscriptionSetB</method> is preferred.)
Method CreateSubscriptionSet(Output QueryHandle As %Integer, NodeIds As %List, NodeAttributes As %List, ByRef PublishingInterval As %Double, ByRef LifetimeCount As %Integer, ByRef MaxKeepAliveCount As %Integer, MaxNotificationsPerPublish As %Integer) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#dim NodeIdCLs as %List

		Set NodeIdCLs = NodeIds

		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfCreateSubscription,"",$LB(..Handle,NodeIdCLs,NodeAttributes,PublishingInterval,LifetimeCount,MaxKeepAliveCount,MaxNotificationsPerPublish))
  
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        #; Set output variables
        Set QueryHandle = $LI(tRetval,2)
		Set PublishingInterval = $LI(tRetval,3)	// server-accepted value
		Set LifetimeCount = $LI(tRetval,4)		// server-accepted value
		Set MaxKeepAliveCount = $LI(tRetval,5)	// server-accepted value

	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// Creates an OPC UA subscription so as to receive updates regarding 
/// changes made to monitored items on a server. Data elements for which
/// notifications are requested are detailed in a particular specification 
/// format that is the output of the OPCUA.DataSource framework.
/// The details of this format are the same as those indicated regarding
/// the ReadBulkSetupC() function. The last four arguments of this 
/// function, the PublishingInterval, the LifetimeCount, the 
/// MaxKeepAliveCount, and the MaxNotificationsPerPublish are defined in
/// section 5.13.2.2 of the OPC UA specification.
Method CreateSubscriptionSetB(Output QueryHandle As %Integer, Specification As %List, ByRef PublishingInterval As %Double, ByRef LifetimeCount As %Integer, ByRef MaxKeepAliveCount As %Integer, MaxNotificationsPerPublish As %Integer, SamplingInterval As %Integer, QueueSize As %Integer, MaxInternalQueueSize As %Integer) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfCreateSubscriptionB,"",$LB(..Handle,Specification,PublishingInterval,LifetimeCount,MaxKeepAliveCount,MaxNotificationsPerPublish,SamplingInterval,QueueSize,MaxInternalQueueSize))
  
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        #; Set output variables
        Set QueryHandle = $LI(tRetval,2)
		Set PublishingInterval = $LI(tRetval,3)	// server-accepted value
		Set LifetimeCount = $LI(tRetval,4)		// server-accepted value
		Set MaxKeepAliveCount = $LI(tRetval,5)	// server-accepted value
		Set SamplingInterval = $LI(tRetval,7)	// maximum of server-accepted values
		Set QueueSize = $LI(tRetval,8)			// minimum of server-accepted values

	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	Quit tSC
}

/// Polls a server for changes to a subscription set that has already been 
/// created using <method>CreateSubscriptionSet</method> or 
/// <method>CreateSubscriptionSetB</method>.
/// Results are returned as a <class>%List</class>
/// of <class>%List</class> for where each sublist consists of an
/// output list of elements similar to that from the polling utility.
/// Notice, here, that it is the sublist, and not the main list that bears
/// resemblance to the output of some of the polling functions. This is
/// because, unlike the polling functions, this function can return 
/// multiple rows per invocation.
Method PollSubscriptionSet(Output Results As %List, QueryHandle As %Integer, PollingTimeout As %Integer = 500, MaxLines As %Integer = 0, ClientRegenOpt As %Integer = 0) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfPollSubscription,"",$LB(..Handle,QueryHandle,PollingTimeout,MaxLines,ClientRegenOpt))

        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        Set Results = tRetval
        
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	
	Quit tSC
}

/// Deletes a set of subscriptions with a given server.
Method DeleteSubscriptionSet(QueryHandle As %Integer) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfDeleteSubscription,"",$LB(..Handle,QueryHandle))
    
        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

	} Catch (e) {
		Set tSC=e.AsStatus()
	}

	Quit tSC
}

// --------------------------------------------------------------------------------------------

// Miscellaneous

// --------------------------------------------------------------------------------------------

/// Reads the current value from a node on a server.
Method ReadValueAttribute(Output Results As %List, NodeId, NodeNamespace As %Integer, NodeIdType As %Integer = 0) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfReadAttribute,"",$LB(..Handle,NodeId,NodeNamespace,NodeIdType,$$$OpcuaAttributeValue))

        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

        Set Results = tRetval
        
	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	
	Quit tSC
}

/// Writes a simple value to a single node on a server.
/// <ul>
/// <li>Datum -- The data element to be written. 
/// <li>DataType -- A numeric value indicating the data type of the 
/// data element to be written. (e.g. $$$OpcuaDataTypeString, 
/// $$$OpcuaDataTypeInt32, etc.)
/// <li>NodeId -- A numeric or string values indicating the primary
/// identifier used to identify the requested node.</li>
/// <li>NodeNamespace -- The namespace of the requested node.</li>
/// <li>NodeIdType -- A numeric value indicating the data type used for
/// the NodeId argument, either a string or an integer. (Use 
/// $$$OpcuaNodeIdTypeString or $$$OpcuaNodeIdTypeNumeric.)</li>
/// </ul>
Method WriteValueAttribute(Datum, DataType As %Integer, NodeId, NodeNamespace As %Integer, NodeIdType As %Integer = 0) As %Status [ Final ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {
		
		#; Call the library entry point
		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfWriteAttribute,"",$LB(..Handle,Datum,DataType,NodeId,NodeNamespace,NodeIdType,$$$OpcuaAttributeValue))

        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=..DecodeError(tRetval) Quit

	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	
	Quit tSC
}

}
