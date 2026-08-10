Include (OPCUA.Constants, Ensemble)

/// IRIS OPC UA Secure Write Example
Class Examples.OPCUA.SecureWrite
{

/// Using a secure connection, writes an integer value to a specific
/// node on an OPC UA server, and then subsequently resets the value
/// of that node back to what it was originally. Notice that this 
/// function operates on a node also referenced in the subscription
/// data feed example Examples.OPCUADS.SecureExample, and that the
/// effects of this test can be seen in the output of that example
/// when that data feed is enabled and sourcing data. 
ClassMethod Run()
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {

		set tSC = ##class(OPCUA.Utils).Initialize()
		Quit:$$$ISERR(tSC)
		
		set tClient = ##class(OPCUA.Client).%New()

		set tSC = tClient.Initialize()
		Quit:$$$ISERR(tSC)

		set tClientURI = "urn:secuac"
		set tCertificatePathname = "/usr/irissys/uac/certs/secuac.crt.der"
		set tPrivateKeyPathname = "/usr/irissys/uac/certs/secuac.key.der"
		set tTrustListDir = "/usr/irissys/uac/certs/trustdir"
		set tRevocationListDir = "/usr/irissys/uac/certs/crldir"
		set tSC = tClient.SetupClient(,$$$OpcuaMessageSecurityModeSignAndEncrypt,tClientURI,tCertificatePathname,tPrivateKeyPathname,tTrustListDir,tRevocationListDir)
		Quit:$$$ISERR(tSC)

		set tSC = tClient.Connect("opc.tcp://certified-server","user1","password")
		Quit:$$$ISERR(tSC)

		#dim tResults as %List

		w !!, "Reading data (0): "
		set tSC = tClient.ReadValueAttribute(.tResults, "the.answer", 1, $$$OpcuaNodeIdTypeString)
		Quit:$$$ISERR(tSC)

		zw tResults

		set tValue = $LI(tResults,5)

		w "Writing 57... "
		set tSC = tClient.WriteValueAttribute(57, $$$OpcuaDataTypeInt32, "the.answer", 1, $$$OpcuaNodeIdTypeString)
		Quit:$$$ISERR(tSC)

		w "Reading data (1): "
		set tSC = tClient.ReadValueAttribute(.tResults, "the.answer", 1, $$$OpcuaNodeIdTypeString)
		Quit:$$$ISERR(tSC)

		zw tResults

		Hang 1

		w "Writing 42... "
		set tSC = tClient.WriteValueAttribute(tValue, $$$OpcuaDataTypeInt32, "the.answer", 1, $$$OpcuaNodeIdTypeString)
		Quit:$$$ISERR(tSC)

		w "Reading data (2): "
		set tSC = tClient.ReadValueAttribute(.tResults, "the.answer", 1, $$$OpcuaNodeIdTypeString)
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
