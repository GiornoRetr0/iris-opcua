Include (OPCUA.Constants, %occInclude, Ensemble)

/// The C++ type-marshalling check: one row of <class>OPCUA.Tests.DataTestDS</class>,
/// polled by the declarative <tt>DataTest</tt> item of
/// <class>OPCUA.Tests.Production</class>, must hold the known values of the public
/// demo server for every scalar, array and matrix type it reads (Boolean, SByte,
/// Byte, Int16/32/64, UInt16/32/64, Float, Double, TimeStamp, XmlElement,
/// StatusCode). Every value is its own assertion, so any mismatch fails the run.
///
/// That server (<parameter>ServerURL</parameter>) is the only one carrying these
/// nodes and values. It is not part of the compose setup, and from the docker
/// stack its endpoint accepts TCP but fails the OPC UA handshake
/// (BadConnectionClosed). When it cannot be connected to, every test reports
/// <b>skipped</b>, never passed. The suite was written for an APPINT namespace,
/// which the compose setup does not have either. It runs in OPCUA.
///
/// Gathering starts <class>OPCUA.Tests.Production</class>. That means stopping the
/// pipeline production for a few seconds (it is restarted afterwards), and the
/// suite refuses to run if any other production is running.
Class OPCUA.Tests.Live.DataTest Extends %UnitTest.TestCase
{

/// The DataTest item's URL in <class>OPCUA.Tests.Production</class>.
Parameter ServerURL = "opc.tcp://opcuaserver.com:48010";

Parameter Production = "OPCUA.Tests.Production";

Parameter PipelineProduction = "OPCUA.Pipeline.Production";

Parameter Item = "DataTest";

/// ID of the gathered DataTestDS row, or "" when nothing was gathered.
Property RecordId As %String;

/// Why nothing could be checked (the server is unreachable).
Property SkipReason As %String(MAXLEN = "");

/// Why gathering failed although the server was reachable. Reported as a failure.
Property GatherError As %String(MAXLEN = "");

/// Gather one row, or record why not. <tt>^||OPCUA.Tests("dataTestRecord")</tt>
/// names an existing DataTestDS row to check instead (test-only, to show the
/// checks fail on wrong data).
Method OnBeforeAllTests() As %Status
{
    set tGiven = $Get(^||OPCUA.Tests("dataTestRecord"))
    if tGiven '= "" {
        set ..RecordId = tGiven
        Quit $$$OK
    }
    set tSC = ..Reachable(..#ServerURL)
    if $$$ISERR(tSC) {
        set ..SkipReason = "public OPC UA server "_..#ServerURL_" unreachable: "_$System.Status.GetOneErrorText(tSC)
        Quit $$$OK
    }
    set tSC = ..Gather(.tId)
    if $$$ISERR(tSC) {
        set ..GatherError = $System.Status.GetErrorText(tSC)
    } else {
        set ..RecordId = tId
    }
    Quit $$$OK
}

Method TestScalars()
{
    set tRow = ..Row()
    Quit:'$IsObject(tRow)
    set BooleanCD = 0
    set SByteCD = 31
    set ByteCD = 0
    set Int16CD = 0
    set UInt16CD = 600
    set Int32CD = 50
    set UInt32CD = 448
    set Int64CD = 0
    set UInt64CD = 700
    set FloatCD = $double(77)
    set DoubleCD = $double(4.5569875151026986159)
    set TimeStampCD = "2021-02-22 01:02:58.5540300"
    set XMLElementCD = "<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0)
    set StatusCodeCD = 0

    do $$$AssertEquals(tRow.Boolean.Value, BooleanCD, "scalar Boolean")
    do $$$AssertEquals(tRow.SByte.Value, SByteCD, "scalar SByte")
    do $$$AssertEquals(tRow.Byte.Value, ByteCD, "scalar Byte")
    do $$$AssertEquals(tRow.Int16.Value, Int16CD, "scalar Int16")
    do $$$AssertEquals(tRow.UInt16.Value, UInt16CD, "scalar UInt16")
    do $$$AssertEquals(tRow.Int32.Value, Int32CD, "scalar Int32")
    do $$$AssertEquals(tRow.UInt32.Value, UInt32CD, "scalar UInt32")
    do $$$AssertEquals(tRow.Int64.Value, Int64CD, "scalar Int64")
    do $$$AssertEquals(tRow.UInt64.Value, UInt64CD, "scalar UInt64")
    do $$$AssertEquals(tRow.Float.Value, FloatCD, "scalar Float")
    do $$$AssertEquals(tRow.Double.Value, DoubleCD, "scalar Double")
    do $$$AssertEquals(tRow.TimeStamp.Value, TimeStampCD, "scalar TimeStamp")
    do $$$AssertEquals(tRow.XMLElement.Value, XMLElementCD, "scalar XMLElement")
    do $$$AssertEquals(tRow.StatusCode.Value, StatusCodeCD, "scalar StatusCode")
    // String is not checked; the old harness left it out too.
}

Method TestArrays()
{
    set tRow = ..Row()
    Quit:'$IsObject(tRow)
    set BooleanArrCD = $LB(1,1,1,1,1,1,1,1,1,1)
    set SByteArrCD = $LB(-5,-4,-3,-2,-1,0,1,2,3,4)
    set ByteArrCD = $LB(0,1,2,3,4,5,6,7,8,9)
    set Int16ArrCD = $LB(6,1,1,1,1,0,1,2,3,4)
    set UInt16ArrCD = $LB(0,1,2,3,4,5,6,7,8,9)
    set Int32ArrCD = $LB(-5,-4,-3,-2,-1,0,1,2,3,4)
    set UInt32ArrCD = $LB(0,1,2,3,4,5,6,7,8,9)
    set Int64ArrCD = $LB(-5,-4,-3,-2,-1,0,1,2,3,4)
    set UInt64ArrCD = $LB(0,1,2,3,4,5,6,7,8,9)
    set FloatArrCD = $LB($double(6.1167511940002441406),$double(20.100000381469726562),$double(20.200000762939453125),$double(20.299999237060546875),$double(20.399999618530273437),20.5,$double(20.600000381469726562),$double(20.700000762939453125),$double(20.799999237060546875),$double(20.899999618530273437))
    set DoubleArrCD = $LB($double(10),$double(10.2),$double(10.4),$double(10.6),$double(10.8),$double(11),$double(11.2),$double(11.4),$double(11.6),$double(11.8))
    set TimeStampArrCD = $LB("2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300")
    set XmlElementArrCD = $LB("<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0))
    set StatusCodeArrCD = $LB(0,$ZHEX("80310000"),$ZHEX("80330000"),$ZHEX("80360000"),$ZHEX("803A0000"),$ZHEX("80400000"),0,$ZHEX("80310000"),$ZHEX("80330000"),$ZHEX("80360000"))

    do ..CheckElements("BooleanArr", tRow.BooleanArr.Values, BooleanArrCD)
    do ..CheckElements("SByteArr", tRow.SByteArr.Values, SByteArrCD)
    do ..CheckElements("ByteArr", tRow.ByteArr.Values, ByteArrCD)
    do ..CheckElements("Int16Arr", tRow.Int16Arr.Values, Int16ArrCD)
    do ..CheckElements("UInt16Arr", tRow.UInt16Arr.Values, UInt16ArrCD)
    do ..CheckElements("Int32Arr", tRow.Int32Arr.Values, Int32ArrCD)
    do ..CheckElements("UInt32Arr", tRow.UInt32Arr.Values, UInt32ArrCD)
    do ..CheckElements("Int64Arr", tRow.Int64Arr.Values, Int64ArrCD)
    do ..CheckElements("UInt64Arr", tRow.UInt64Arr.Values, UInt64ArrCD)
    do ..CheckElements("FloatArr", tRow.FloatArr.Values, FloatArrCD)
    do ..CheckElements("DoubleArr", tRow.DoubleArr.Values, DoubleArrCD)
    do ..CheckElements("TimeStampArr", tRow.TimeStampArr.Values, TimeStampArrCD)
    do ..CheckElements("XMLElementArr", tRow.XMLElementArr.Values, XmlElementArrCD)
    do ..CheckElements("StatusCodeArr", tRow.StatusCodeArr.Values, StatusCodeArrCD)
}

Method TestMatrices()
{
    set tRow = ..Row()
    Quit:'$IsObject(tRow)
    set BooleanMatrixCD = $lb($lb($lb(0,1,0),$lb(1,0,1),$lb(0,1,0),$lb(1,0,1)),$lb($lb(0,1,0),$lb(1,0,1),$lb(0,1,0),$lb(1,0,1)))
    set SByteMatrixCD = $lb($lb($lb(0,1,2),$lb(3,4,5),$lb(6,7,8),$lb(9,10,11)),$lb($lb(12,13,14),$lb(15,16,17),$lb(18,19,20),$lb(21,22,23)))
    set Int16MatrixCD = $lb($lb($lb(0,1,2),$lb(3,4,5),$lb(6,7,8),$lb(9,10,11)),$lb($lb(12,13,14),$lb(15,16,17),$lb(18,19,20),$lb(21,22,23)))
    set UInt16MatrixCD = $lb($lb($lb(0,1,2),$lb(3,4,5),$lb(6,7,8),$lb(9,10,11)),$lb($lb(12,13,14),$lb(15,16,17),$lb(18,19,20),$lb(21,22,23)))
    set Int32MatrixCD = $lb($lb($lb(0,1,2),$lb(3,4,5),$lb(6,7,8),$lb(9,10,11)),$lb($lb(12,13,14),$lb(15,16,17),$lb(18,19,20),$lb(21,22,23)))
    set UInt32MatrixCD = $lb($lb($lb(0,1,2),$lb(3,4,5),$lb(6,7,8),$lb(9,10,11)),$lb($lb(12,13,14),$lb(15,16,17),$lb(18,19,20),$lb(21,22,23)))
    set Int64MatrixCD = $lb($lb($lb(0,1,2),$lb(3,4,5),$lb(6,7,8),$lb(9,10,11)),$lb($lb(12,13,14),$lb(15,16,17),$lb(18,19,20),$lb(21,22,23)))
    set UInt64MatrixCD = $lb($lb($lb(0,1,2),$lb(3,4,5),$lb(6,7,8),$lb(9,10,11)),$lb($lb(12,13,14),$lb(15,16,17),$lb(18,19,20),$lb(21,22,23)))
    set FloatMatrixCD = $lb($lb($lb($double(0),$double(3.1415927410125732421),$double(6.2831854820251464843)),$lb($double(9.424777984619140625),$double(12.566370964050292968),$double(15.707963943481445312)),$lb($double(18.84955596923828125),$double(21.99114990234375),$double(25.132741928100585937)),$lb($double(28.274333953857421875),$double(31.415927886962890625),$double(34.557521820068359375))),$lb($lb($double(37.6991119384765625),$double(40.84070587158203125),$double(43.9822998046875)),$lb($double(47.123889923095703125),$double(50.265483856201171875),$double(53.407077789306640625)),$lb($double(56.54866790771484375),$double(59.6902618408203125),$double(62.83185577392578125)),$lb($double(65.97344970703125),$double(69.11504364013671875),$double(72.25662994384765625))))
    set DoubleMatrixCD = $lb($lb($lb($double(0),$double(3.1415926500000002086),$double(6.2831853000000004172)),$lb($double(9.4247779500000010699),$double(12.566370600000000834),$double(15.707963250000000599)),$lb($double(18.849555900000002139),$double(21.991148550000001904),$double(25.132741200000001668)),$lb($double(28.274333850000001433),$double(31.415926500000001198),$double(34.557519150000004516))),$lb($lb($double(37.699111800000004279),$double(40.840704450000004044),$double(43.982297100000003808)),$lb($double(47.123889750000003573),$double(50.265482400000003337),$double(53.407075050000003102)),$lb($double(56.548667700000002867),$double(59.690260350000002631),$double(62.831853000000002396)),$lb($double(65.973445650000002161),$double(69.115038300000009031),$double(72.256630950000001689))))

    do $$$AssertEquals(..FirstDiff(tRow.BooleanMatrix.Values, BooleanMatrixCD, 3), "", "BooleanMatrix matches")
    do $$$AssertEquals(..FirstDiff(tRow.SByteMatrix.Values, SByteMatrixCD, 3), "", "SByteMatrix matches")
    do $$$AssertEquals(..FirstDiff(tRow.Int16Matrix.Values, Int16MatrixCD, 3), "", "Int16Matrix matches")
    do $$$AssertEquals(..FirstDiff(tRow.UInt16Matrix.Values, UInt16MatrixCD, 3), "", "UInt16Matrix matches")
    do $$$AssertEquals(..FirstDiff(tRow.Int32Matrix.Values, Int32MatrixCD, 3), "", "Int32Matrix matches")
    do $$$AssertEquals(..FirstDiff(tRow.UInt32Matrix.Values, UInt32MatrixCD, 3), "", "UInt32Matrix matches")
    do $$$AssertEquals(..FirstDiff(tRow.Int64Matrix.Values, Int64MatrixCD, 3), "", "Int64Matrix matches")
    do $$$AssertEquals(..FirstDiff(tRow.UInt64Matrix.Values, UInt64MatrixCD, 3), "", "UInt64Matrix matches")
    do $$$AssertEquals(..FirstDiff(tRow.FloatMatrix.Values, FloatMatrixCD, 3), "", "FloatMatrix matches")
    do $$$AssertEquals(..FirstDiff(tRow.DoubleMatrix.Values, DoubleMatrixCD, 3), "", "DoubleMatrix matches")
}

/// The gathered row. Otherwise asserts skipped (server unreachable) or failed
/// (gathering failed, or the row is missing), and returns "".
Method Row() As OPCUA.Tests.DataTestDS
{
    if ..SkipReason '= "" {
        do $$$AssertSkipped(..SkipReason)
        Quit ""
    }
    if ..GatherError '= "" {
        do $$$AssertFailure("gathering failed: "_..GatherError)
        Quit ""
    }
    set tRow = ##class(OPCUA.Tests.DataTestDS).%OpenId(..RecordId)
    do $$$AssertTrue($IsObject(tRow), "DataTestDS row '"_..RecordId_"' exists")
    Quit tRow
}

/// One array: its length, then its elements, naming the first that differs.
Method CheckElements(pName As %String, pValues As %ListOfDataTypes, pWant As %List)
{
    if '$IsObject(pValues) {
        do $$$AssertFailure(pName_" has no values")
        Quit
    }
    do $$$AssertEquals(pValues.Count(), $ListLength(pWant), pName_" length")
    // Up to the longer of the two, so a short or empty array cannot match.
    set tAt = "", tLen = pValues.Count()
    set:$ListLength(pWant)>tLen tLen = $ListLength(pWant)
    for i=1:1:tLen {
        if pValues.GetAt(i) '= $ListGet(pWant, i) {
            set tAt = i
            quit
        }
    }
    do $$$AssertEquals(tAt, "", pName_" elements match"_$Select(tAt="":"", 1:" (first difference at "_tAt_": got "_pValues.GetAt(tAt)_", want "_$ListGet(pWant, tAt)_")"))
}

/// "" when <var>pGot</var> equals <var>pWant</var>, a <var>pDims</var>-deep
/// nested list. Otherwise the path of the first difference and both values.
ClassMethod FirstDiff(pGot, pWant, pDims As %Integer, pPath As %String = "") As %String
{
    if pDims = 0 {
        Quit $Select(pGot=pWant:"", 1:pPath_": got "_pGot_", want "_pWant)
    }
    if '$ListValid(pGot) || ($ListLength(pGot) '= $ListLength(pWant)) {
        Quit pPath_": got "_$Select($ListValid(pGot):$ListLength(pGot)_" elements", 1:"no list")_", want "_$ListLength(pWant)
    }
    for i=1:1:$ListLength(pWant) {
        set tDiff = ..FirstDiff($ListGet(pGot, i), $ListGet(pWant, i), pDims - 1, pPath_"["_i_"]")
        return:tDiff'="" tDiff
    }
    Quit ""
}

/// Can an anonymous, unsecured session be opened on <var>pURL</var>?
ClassMethod Reachable(pURL As %String) As %Status
{
    set tSC = $$$OK
    try {
        $$$ThrowOnError(##class(OPCUA.Utils).Initialize())
        set tClient = ##class(OPCUA.Client).%New()
        $$$ThrowOnError(tClient.Initialize())
        $$$ThrowOnError(tClient.SetupClient())
        $$$ThrowOnError(tClient.Connect(pURL))
        do tClient.Disconnect()
    } catch e {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

/// Run the DataTest item until it has stored a row, then put the productions
/// back: the item disabled, and the pipeline production running again if it was.
ClassMethod Gather(Output pId As %String) As %Status
{
    set pId = ""
    set tSC = ##class(Ens.Director).GetProductionStatus(.tRunning, .tState)
    Quit:$$$ISERR(tSC) tSC
    set tWasPipeline = (tRunning = ..#PipelineProduction) && (tState = 1)
    if (tRunning '= "") && (tRunning '= ..#PipelineProduction) && (tRunning '= ..#Production) && $Case(tState, 1:1, 3:1, 4:1, :0) {
        Quit $$$ERROR($$$GeneralError, "Production '"_tRunning_"' is running; DataTest does not stop productions it does not own")
    }
    set tSC = $$$OK
    try {
        do ##class(OPCUA.Tests.DataTestDS).%KillExtent()
        if (tRunning '= "") && $Case(tState, 1:1, 3:1, 4:1, :0) {
            $$$ThrowOnError(##class(Ens.Director).StopProduction(10, 1))
        }
        $$$ThrowOnError(##class(Ens.Director).StartProduction(..#Production))
        $$$ThrowOnError(##class(Ens.Director).EnableConfigItem(..#Item, 1))
        set tStart = $ZHorolog, tId = ""
        for {
            &sql(SELECT MAX(ID) INTO :tId FROM OPCUA_Tests.DataTestDS)
            if (SQLCODE = 0) && (tId '= "") {
                set pId = tId
                quit
            }
            quit:(($ZHorolog-tStart)>=30)
            hang 0.5
        }
        if pId = "" $$$ThrowStatus($$$ERROR($$$GeneralError, "DataTest stored no row within 30 s"))
    } catch e {
        set tSC = e.AsStatus()
    }
    // Put things back whatever happened.
    do ##class(Ens.Director).EnableConfigItem(..#Item, 0)
    do ##class(Ens.Director).GetProductionStatus(.tNow, .tNowState)
    do:tNow=..#Production ##class(Ens.Director).StopProduction(10, 1)
    do:tWasPipeline ##class(Ens.Director).StartProduction(..#PipelineProduction)
    Quit tSC
}

}
