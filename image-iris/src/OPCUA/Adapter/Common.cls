Include (%callout, OPCUA.Constants)

Class OPCUA.Adapter.Common Extends Ens.InboundAdapter
{

/// Configurable settings
Parameter SETTINGS = "URL:Connection,ConnectionRetryTimeout:Connection,AlwaysConnect:Connection,DataSourceClass:Data,Username:User,Password:User,SecurityMode:Security,ClientURI:Security,PublicCertificate:Security,PrivateKey:Security,TrustListDir:Security,RevocationListDir:Security,LogFileTag:Logging";

// *** PROPERTIES INFLUENCED BY SETTINGS ***

/// The URL of the server from which data is sought. 
/// (e.g. <i>opc.tcp://servername:4840</i>)
Property URL As %String(MAXLEN = 200);

/// The duration (in seconds), since the last time that 
/// the OPC UA client was able to connect to the target
/// OPC UA server, after which no more connection attempts
/// will be made. If AlwaysConnect is checked, a warning will
/// be issued instead
Property ConnectionRetryTimeout As %Integer [ InitialExpression = 600 ];

/// Indicates whether the OPC UA client should always attempt
/// to connect to the target OPC UA server, regardless of any
/// previous connection failures. If checked, a warning will
/// be periodically issued after the duration specified 
/// in ConnectionRetryTimeout
Property AlwaysConnect As %Boolean [ InitialExpression = 0 ];

/// The name of the DataSource class specifying the 
/// data types and nodes from which to obtain data
/// as well as the fields in which to deposit the results.
Property DataSourceClass As %String;

/// The username with which to log on to the OPC UA server.
Property Username As %String;

/// The password with which to log on to the OPC UA server.
Property Password As %String;

Property SecurityMode As %String(DISPLAYLIST = ",None,Sign & Encrypt", VALUELIST = ",1,3") [ InitialExpression = "1", Required ];

/// The "application URI" of this IRIS OPC UA connector. 
/// Notice that this identifying string may need to match
/// comparable identifying strings noted within certificates
/// used to identify this application to the target OPC UA
/// server.
Property ClientURI As %String(MAXLEN = 200);

/// The full pathname of the certificate that is to be 
/// used to identify the IRIS OPC UA connector as a client 
/// to the OPC UA server. Notice that this certificate may 
/// need to have been signed by a certicate authority that
/// is trusted by the target OPC UA server. Should be
/// supplied in DER format.
Property PublicCertificate As %String(MAXLEN = 900);

/// The full pathname of the private key that is to be used
/// by this IRIS OPC UA connector in communications with the
/// target OPC UA server. Should be supplied in DER format.
Property PrivateKey As %String(MAXLEN = 900);

/// The full pathname of the directory in which the certificates
/// of trusted sources are kept. Importantly, this directory
/// may need to hold a valid certificate of the certificate authority
/// that signs a target OPC UA server's identifying certificates,
/// or a trusted certificate of a target OPC UA server itself.
/// Certificates in this directory should be supplied in 
/// DER format.
Property TrustListDir As %String(MAXLEN = 900);

/// The full pathname of the directory in which certificate 
/// revocation lists (CRLs) are to be held. Such CRLs may be
/// required for connecting to any given OPC UA server even  
/// in the event that no certificates have been revoked in
/// regards to that server.
Property RevocationListDir As %String(MAXLEN = 900);

/// Indicates a tag that will identify a logfile for supplemental
/// logging regarding this process. If omitted, supplemental 
/// logging will not be performed. Importantly, under some circumstances,
/// use of this supplemental logging can result in a great amount of 
/// being written to disk and may result in degradation of application 
/// performance. Consequently, it is recommended that this feature only 
/// be used for the purposes of development and debugging and not for 
/// general system monitoring. 
Property LogFileTag As %String(MAXLEN = 50);

// *** PRIVATE PROPERTIES ***

Property Client As OPCUA.Client [ Private ];

Property IsConnected As %Integer [ Private ];

Property ResetClientFlag As %Integer [ Private ];

Property LastReportedError As %Status [ Private ];

Property ConnectionRetryEndTime As %TimeStamp [ Private ];

// *** METHODS ***

Method OnInit() As %Status
{
	#dim tSC as %Status = $$$OK

	try {

		set ..IsConnected = 0
		set ..ResetClientFlag = 0

		set ..ConnectionRetryEndTime = ##class(%SYSTEM.SQL).DATEADD("s",..ConnectionRetryTimeout,$ZTimestamp)

		set ..Client = ##class(OPCUA.Client).%New()
		set tSC = ..Client.Initialize()
		Quit:$$$ISERR(tSC)

		set tSC = ..Client.SetLogFile(..LogFileTag)
		set tSC = ..Client.SetupClient("",..SecurityMode,..ClientURI,..PublicCertificate,..PrivateKey,..TrustListDir,..RevocationListDir)
		Quit:$$$ISERR(tSC)

	} catch (e) {
		Set tSC=e.AsStatus()
	}
	
	if $$$ISERR(tSC) {
		$$$LOGERROR("OPCUA Client initialization failed [c.oi] : "_$SYSTEM.Status.GetErrorText(tSC))
		Quit tSC
	} 
	
	Quit tSC  // Quit $$$OK
}

Method Connect() As %Status [ Private ]
{
	#dim tSC as %Status = $$$OK
	
	try {

		if ..ResetClientFlag '= 0 {

			set tSC = ..Client.SetLogFile(..LogFileTag)
			set tSC = ..Client.SetupClient("",..SecurityMode,..ClientURI,..PublicCertificate,..PrivateKey,..TrustListDir,..RevocationListDir)

			if $$$ISERR(tSC) {

				$$$LOGERROR("Error encountered while resetting client [c.c] : "_$SYSTEM.Status.GetErrorText(tSC))
				Quit

			} else {

				$$$LOGINFO("OPCUA Client reset [c.c]")
			}
		}

		set tSC = ..Client.Connect(..URL,..Username,..Password)
		//Quit:$$$ISERR(tSC)

	} catch (e) {
		set tSC = e.AsStatus()
	}

	Quit tSC
}

Method Disconnect() As %Status [ Private ]
{
	#dim tSC as %Status = $$$OK
	
	try {
	
		set tSC = ..Client.Disconnect()
		//Quit:$$$ISERR(tSC)

	} catch (e) {
		set tSC = e.AsStatus()
	}

	Quit tSC
}

Method OnTearDown() As %Status
{
	#dim tSC as %Status = $$$OK

	try {
	
		set tSC = ..Client.Disconnect()
				
	} catch (e) {
		Set tSC=e.AsStatus()
	}
	
	Quit tSC
}

}
