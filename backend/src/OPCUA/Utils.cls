Include (%callout, OPCUA.Constants, Ensemble)

/// Miscellaneous utility functions used in conjunction with
/// the OPC-UA connector.
Class OPCUA.Utils
{

/// Used to load the dynamic library containing the native code
/// for the OPC-UA connector. This function must be called prior
/// to calling many of the methods 
/// of the <class>OPCUA.Client</class> class.
ClassMethod Initialize() As %Status
{
    try {

        #; See ##class(OPCUA.Class).GetStatusCodeName()

        set tOpcuaStatusCode = 0 // Status = "Good"

        If '$Data(%ZUtilsIrisOpcuaLibraryId) throw ##class(%Exception.StatusException).CreateFromStatus(0)

		//set tRetval=$ZF(-6,$$$IrisOPCUALibrary,$$$zfGetStatusCodeNameB,"",$LB(tOpcuaStatusCode))
		set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfGetStatusCodeNameB,"",$LB(tOpcuaStatusCode))

        If $List(tRetval,1)=0 return $$$OK // Library is already initialized

    } catch (e) {
        $$$TRACE("IrisOPCUA may not be loaded")
    }

    #dim tSC as %Status = $$$OK
    #dim tPathname as %String = ""

    try {

        //set tPathname = ^OPCUA.Library.Pathname
        set tSC = ##class(OPCUA.Utils).GetLibPathname(.tPathname)
		$$$ThrowOnError(tSC)
        
        $$$TRACE("Attempting to load IrisOPCUA with pathname '"_tPathname_"'")

        //do $ZF(-4,5,$$$IrisOPCUALibrary,tPathname)
        set %ZUtilsIrisOpcuaLibraryId = $ZF(-4,1,tPathname)

    } catch (e) {
        set tSC = e.AsStatus()
        $$$LOGERROR("Error thrown during IrisOPCUA handle assignment : "_$SYSTEM.Status.GetErrorText(tSC))
    }

    set tSC = $$$OK

    try {

        If '$Data(%ZUtilsIrisOpcuaLibraryId) throw ##class(%Exception.StatusException).CreateFromStatus(0)

		//set tRetval=$ZF(-6,$$$IrisOPCUALibrary,$$$zfGetStatusCodeNameB,"",$LB(0))
		set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfGetStatusCodeNameB,"",$LB(0))

        If $List(tRetval,1)'=0 Set tSC=##class(OPCUA.Client).DecodeError(tRetval)

        if $$$ISERR(tSC) {
            $$$LOGERROR("Unable to load IrisOPCUA : Error returned : "_$SYSTEM.Status.GetErrorText(tSC))
        } Else {

            set tSC = ##class(OPCUA.Utils).GetVersion(.tRetval) // Reusing tRetval
            Quit:$$$ISERR(tSC)
            
            set tVersion = "v"_$LI(tRetval,2)
            $$$LOGINFO("IrisOPCUA loaded successfully : "_tVersion)
        }

    } catch (e) {
        set tSC = e.AsStatus()
        $$$LOGERROR("Unable to load IrisOPCUA : Error thrown : "_$SYSTEM.Status.GetErrorText(tSC))
    }

    Quit tSC
}

/// Used to specify the pathname of a dynamic library, usually
/// one named as <i>irisopcua.so</i>, 
/// that contains the native code for the OPC-UA connector.
ClassMethod Install(pPathname As %String) As %Status
{
    #dim tSC as %Status = $$$OK

    try {    

        set ^OPCUA.Library.Pathname = pPathname

    } catch (e) {
        set tSC = e.AsStatus()
    }

    Quit tSC
}

ClassMethod GetLibPathname(Output pPathname As %String) As %Status
{
    #dim tSC as %Status = $$$OK
    
    try {

        if ($GET(^OPCUA.Library.Pathname) '= "") set pPathname = ^OPCUA.Library.Pathname Quit

        set tPathname = $System.Util.BinaryDirectory()_"IrisOPCUA.dll"
        if ##class(%File).Exists(tPathname) set pPathname = tPathname Quit

        set tPathname = $System.Util.BinaryDirectory()_"irisopcua.so"
        if ##class(%File).Exists(tPathname) set pPathname = tPathname Quit

        set pPathname = ""
        set tSC = $System.Status.Error(5012, "IrisOPCUA.dll/.so")

    } catch (e) {
        set pPathname = ""
        set tSC = e.AsStatus()
    }

    Quit tSC
}

ClassMethod GetUStr(pStr As %String) As %String
{
    set tRet=""

    try {

        if $System.Version.IsUnicode() {

            set tLen=$L(pStr),i=1
            while i <= tLen {
                set c = $E(pStr,i,i)
                if c = "\" {
                    if i + 1 > tLen Quit // ERROR
                    set c = $E(pStr,i+1,i+1)
                    if c = "\" {
                        set tRet=tRet_"\",i=i+2
                    } elseif c = "u" {
                        if i + 5 > tLen Quit // ERROR
                        set tRet=tRet_$C($SYSTEM.Util.HexToDecimal($E(pStr,i+2,i+5))),i=i+6
                    } else { 
                        Quit // ERROR
                    }
                } else { 
                    set tRet=tRet_c,i=i+1
                }
            }

        } else {

            do ##class(OPCUA.Utils).Initialize() // just in case
            set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfGetUStr,"",$LB(pStr,1))

            #; Errors are not returned, fragments instead.
            #; Ignore any error. Return the result.
            set tRet = $LI(tRetval,2)

        }


    } catch (e) {
        // Ignore errors. Return the result.
    }

    return tRet
}

ClassMethod ErrTextIsTypeInfo(ErrText As %String) As %Boolean
{
	set tSubstr = "(Info / No Error"
	return $FIND(ErrText,tSubstr) '= 0
}

ClassMethod AreSimilarOpcuaDisconnectErrors(ErrStr1 As %String, ErrStr2 As %String) As %Boolean
{
    if $FIND(ErrStr1,"0x800A0000") {
        return $FIND(ErrStr2,"0x80AD0000") || $FIND(ErrStr2,"0x80AE0000")
    } elseif $FIND(ErrStr1,"0x80AD0000") {
        return $FIND(ErrStr2,"0x800A0000") || $FIND(ErrStr2,"0x80AE0000")
    } elseif $FIND(ErrStr1,"0x80AE0000") {
        return $FIND(ErrStr2,"0x800A0000") || $FIND(ErrStr2,"0x80AD0000")
    } else {
        return 0
    }
    #; if $FIND(ErrStr1,"0x800A0000") {
    #;     return $FIND(ErrStr2,"0x80AD0000")
    #; } elseif $FIND(ErrStr1,"0x80AD0000") {
    #;     return $FIND(ErrStr2,"0x800A0000")
    #; } else {
    #;     return 0
    #; }
}

ClassMethod GetVersion(Output pOut As %List) As %Status
{
    #dim tSC as %Status = $$$OK

    try {

		set tRetval=$ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfVersion,"")

        #; Test for error condition
        If $List(tRetval,1)'=0 Set tSC=##class(OPCUA.Client).DecodeError(tRetval) Quit

        #; Set output variables
        Set pOut = tRetval
        
	} Catch (e) {
		Set tSC=e.AsStatus()
	}

	Quit tSC
}

}
