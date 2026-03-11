Include (%callout, OPCUA.Constants, Ensemble)

/// Date and time-related utility functions used in conjunction with
/// the OPC-UA connector.
Class OPCUA.DateTimeUtils
{

ClassMethod OPCUA2HOROLOG(Output pHOROLOG As %String, ByRef pOPCUA As %Integer) As %Status
{
	#dim tSC as %Status = $$$OK

	try {

		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfDateConvOPCUA2HOROLOG,"",$LB(pOPCUA))
    
        If $List(tRetval,1)'=0 Set tSC=##class(OPCUA.Client).DecodeError(tRetval) Quit

		set pHOROLOG = $List(tRetval,2)

	} catch (e) {
		set tSC = e.AsStatus()
	}

	Quit tSC
}

ClassMethod HOROLOG2OPCUA(Output pOPCUA As %Integer, ByRef pHOROLOG As %String) As %Status
{
	#dim tSC as %Status = $$$OK

	try {

		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfDateConvHOROLOG2OPCUA,"",$LB(pHOROLOG))
    
        If $List(tRetval,1)'=0 Set tSC=##class(OPCUA.Client).DecodeError(tRetval) Quit

		set pOPCUA = $List(tRetval,2)

	} catch (e) {
		set tSC = e.AsStatus()
	}

	Quit tSC
}

ClassMethod OPCUA2ODBC(Output pODBC As %String, ByRef pOPCUA As %Integer) As %Status
{
	#dim tSC as %Status = $$$OK

	try {

		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfDateConvOPCUA2ODBC,"",$LB(pOPCUA))
    
        If $List(tRetval,1)'=0 Set tSC=##class(OPCUA.Client).DecodeError(tRetval) Quit

		set pODBC = $List(tRetval,2)

	} catch (e) {
		set tSC = e.AsStatus()
	}

	Quit tSC
}

ClassMethod ODBC2OPCUA(Output pOPCUA As %Integer, ByRef pODBC As %String) As %Status
{
	#dim tSC as %Status = $$$OK

	try {

		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfDateConvODBC2OPCUA,"",$LB(pODBC))
    
        If $List(tRetval,1)'=0 Set tSC=##class(OPCUA.Client).DecodeError(tRetval) Quit

		set pOPCUA = $List(tRetval,2)

	} catch (e) {
		set tSC = e.AsStatus()
	}

	Quit tSC
}

ClassMethod OPCUA2UNIX(Output pUNIX As %Integer, ByRef pOPCUA As %Integer) As %Status
{
	#dim tSC as %Status = $$$OK

	try {

		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfDateConvOPCUA2UNIX,"",$LB(pOPCUA))
    
        If $List(tRetval,1)'=0 Set tSC=##class(OPCUA.Client).DecodeError(tRetval) Quit

		set pUNIX = $List(tRetVal,2)

	} catch (e) {
		set tSC = e.AsStatus()
	}

	Quit tSC
}

ClassMethod UNIX2OPCUA(Output pOPCUA As %Integer, ByRef pUNIX As %Integer) As %Status
{
	#dim tSC as %Status = $$$OK

	try {

		Set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfDateConvUNIX2OPCUA,"",$LB(pUNIX))
    
        If $List(tRetval,1)'=0 Set tSC=##class(OPCUA.Client).DecodeError(tRetval) Quit

		set pOPCUA = $List(tRetVal,2)

	} catch (e) {
		set tSC = e.AsStatus()
	}

	Quit tSC
}

}
