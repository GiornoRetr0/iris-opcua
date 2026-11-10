Include (%callout, OPCUA.Constants)

Class OPCUA.Adapter.Common Extends Ens.InboundAdapter
{

/// Configurable settings.
///
/// DataSourceClass renders as a dropdown of available device schemas, populated
/// from the common superclass OPCUA.DataSource.DeviceSchema. Note that
/// Ens.ContextSearch.SubclassOf takes the superclass in a parameter named
/// "class" (not "super"), and already excludes abstract classes, so the abstract
/// DeviceSchema base never appears in the list.
Parameter SETTINGS = "URL:Connection,ConnectionRetryTimeout:Connection,AlwaysConnect:Connection,DataSourceClass:Data:selector?context={Ens.ContextSearch/SubclassOf?class=OPCUA.DataSource.DeviceSchema},DeviceNodePaths:Data,Credentials:Connection:credentialsSelector,SecurityMode:Security,ClientURI:Security,PublicCertificate:Security,PrivateKey:Security,TrustListDir:Security,RevocationListDir:Security,LogFileTag:Logging";

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
/// in ConnectionRetryTimeout. On by default: unchecked, an outage
/// longer than ConnectionRetryTimeout stops collection until the
/// item is restarted, even once the server is back.
Property AlwaysConnect As %Boolean [ InitialExpression = 1 ];

/// The name of the DataSource class specifying the
/// data types and nodes from which to obtain data
/// as well as the fields in which to deposit the results.
Property DataSourceClass As %String;

/// The OPC UA device root nodes to read, one per line. Each line produces one
/// table row per poll cycle, tagged with its NodePath.
/// <p>Accepted forms per line:
/// <ul>
/// <li><tt>ns=2;s=Plant.AC1</tt> — string NodeId</li>
/// <li><tt>ns=2;i=1047</tt> — numeric NodeId</li>
/// <li><tt>i=85</tt> — NodeId in namespace 0</li>
/// </ul>
/// An optional label may follow a pipe, and becomes the NodePath value:
/// <tt>ns=2;s=Plant.AC1|AC1</tt>. Blank lines and lines starting with # are
/// ignored, so the list can be commented.
/// <p>Each device is browsed at connect time and its children matched by name
/// against the schema's columns, so adding a device is a one-line edit here —
/// no regeneration and no recompile. Only used by the row-source services; the
/// declarative Examples/Tests path ignores it.
Property DeviceNodePaths As %String(MAXLEN = 32000);

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

		do ..ApplyLogFile()
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

/// Point the native library's log at <property>LogFileTag</property>. A failure
/// is logged as a warning, not returned: the library log is a diagnostic aid, so
/// it should not stop the service collecting data. Before, the status was
/// overwritten by the next call and the failure went unseen.
Method ApplyLogFile() [ Private ]
{
	set tSC = ..Client.SetLogFile(..LogFileTag)
	if $$$ISERR(tSC) {
		$$$LOGWARNING("Could not set the OPC UA library log file '"_..LogFileTag_"': "_$System.Status.GetErrorText(tSC))
	}
}

/// The library's IsConnected flag for <var>pClient</var>, and its client reset
/// flag in <var>pResetFlag</var>. Both are 0 when the state cannot be read: the
/// enquiry leaves its outputs unset on failure, and a -1 placeholder left there
/// counts as connected, so the polling adapter would never reconnect.
ClassMethod ConnectedState(pClient As OPCUA.Client, Output pResetFlag As %Integer) As %Integer
{
	set tConnected = 0, pResetFlag = 0
	Try {
		set tSC = pClient.GetClientState("", .tConnected, "", "", .tReset)
		if $$$ISERR(tSC) {
			set tConnected = 0
		} else {
			set pResetFlag = +$Get(tReset)
		}
	} Catch (e) {
		set tConnected = 0
	}
	Quit +tConnected
}

Method Connect() As %Status [ Private ]
{
	#dim tSC as %Status = $$$OK
	
	try {

		if ..ResetClientFlag '= 0 {

			do ..ApplyLogFile()
			set tSC = ..Client.SetupClient("",..SecurityMode,..ClientURI,..PublicCertificate,..PrivateKey,..TrustListDir,..RevocationListDir)

			if $$$ISERR(tSC) {

				$$$LOGERROR("Error encountered while resetting client [c.c] : "_$SYSTEM.Status.GetErrorText(tSC))
				Quit

			} else {

				$$$LOGINFO("OPCUA Client reset [c.c]")
			}
		}

		// Username and password come from the Credentials setting, an
		// Ens.Config.Credentials ID, never from plain-text settings. Ens resolves
		// the ID case-insensitively, and unset or "none" gives an empty entry: an
		// anonymous session. An ID that names no entry leaves no object, and is an
		// error rather than a silent anonymous connect. Setting Credentials again
		// reloads the entry, so a password changed in the Portal applies at the
		// next connect.
		set tUser = "", tPassword = ""
		if ..Credentials '= "" {
			set ..Credentials = ..Credentials
			if '$IsObject(..%CredentialsObj) {
				set tSC = $$$ERROR($$$GeneralError, "Credentials entry '"_..Credentials_"' does not exist")
				Quit
			}
			set tUser = ..%CredentialsObj.Username, tPassword = ..%CredentialsObj.Password
		}
		set tSC = ..Client.Connect(..URL, tUser, tPassword)
		//Quit:$$$ISERR(tSC)

	} catch (e) {
		set tSC = e.AsStatus()
	}

	Quit tSC
}

/// Overridable hook, invoked by the concrete adapters once a live OPC UA session
/// exists but before the read/subscription query is prepared.
///
/// Row-source services override this to browse each configured device and build
/// the adapter Specification by matching node names — which is only possible with
/// a live session, hence a hook here rather than work done in the service's
/// OnInit(). It runs on every (re)connect, so a device that comes online after
/// startup is picked up automatically.
///
/// The default is a deliberate no-op: the declarative v1 path (Examples,
/// OPCUA.Tests) configures its Specification in OnInit() from the compiled class
/// and must keep behaving exactly as before.
Method ResolveSpecification() As %Status
{
	Quit $$$OK
}

/// Resolve DataSourceClass + DeviceNodePaths into a concrete specification and
/// per-device coverage masks, by browsing each device over the live session.
///
/// Shared by both row-source adapters' ResolveSpecification() overrides, so the
/// polling and subscription paths cannot drift apart. Unresolved columns are
/// logged once per (device, column) and stored as NULL.
Method ResolveRowSourceSpec(Output pSpec As %List, Output pMasks As %List, Output pPaths As %List) As %Status
{
	#dim tSC as %Status = $$$OK
	set pSpec = ""
	set pMasks = ""
	set pPaths = ""

	try {
		if ..DataSourceClass = "" {
			set tSC = $$$ERROR($$$GeneralError, "DataSourceClass is not configured")
			Quit
		}

		if ..DeviceNodePaths = "" {
			set tSC = $$$ERROR($$$GeneralError, "DeviceNodePaths is empty — list at least one OPC UA device root, e.g. ns=2;s=Plant.AC1")
			Quit
		}

		set tSC = ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths(..DeviceNodePaths, .tDevices, .tParseErrors)
		for i=1:1:$LL($Get(tParseErrors)) {
			$$$LOGWARNING("Ignoring unusable DeviceNodePaths entry — "_$LI(tParseErrors, i))
		}
		Quit:$$$ISERR(tSC)

		set tSC = ##class(OPCUA.DataSource.Resolver).ResolveSpecification(..Client, ..DataSourceClass, tDevices, .pSpec, .pMasks, .tDiagnostics)
		Quit:$$$ISERR(tSC)

		// Report every unresolved column, naming the device and the column.
		//
		// A partially matching device is a legitimate binding, not an error: the
		// coverage dry run (POST /schemas/:name/validate) shows exactly which
		// columns are missing before deploy, so a device bound anyway was bound
		// deliberately. Its unresolved columns store NULL and say so here.
		for i=1:1:$LL(tDiagnostics) {
			set tD = $LI(tDiagnostics, i)
			$$$LOGWARNING("Device '"_$LI(tD, 1)_"': column '"_$LI(tD, 2)_"' did not resolve — "_$LI(tD, 3)_". It will be stored as NULL.")
		}

		// NodePath values, in device order, for the service to tag rows with.
		for i=1:1:$LL(tDevices) {
			set pPaths = pPaths _ $LB($LI($LI(tDevices, i), 4))
		}

		set tTotal = 0
		for i=1:1:$LL(pMasks) {
			set tMask = $LI(pMasks, i)
			for c=1:1:$LL(tMask) {
				if +$LI(tMask, c) set tTotal = tTotal + 1
			}
		}
		$$$LOGINFO("Resolved "_..DataSourceClass_" against "_$LL(tDevices)_" device(s): "_tTotal_" node(s) to read")

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
