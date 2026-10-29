Include %occInclude

/// Unit tests verifying Status columns hold every unsigned 32-bit OPC UA StatusCode.
///
/// Closes audit #14.
Class OPCUA.Tests.Unit.StatusWidthTest Extends %UnitTest.TestCase
{

Parameter TmpSchema = "OPCUA.Tests.Tmp.StatusWidth";

Method OnAfterAllTests() As %Status
{
	do ..DropSchema(..#TmpSchema)
	Quit $$$OK
}

/// Save rows with Status 2147483648, 2155085824 and 0, then read them back by
/// SQL and assert they're equal. Bad codes >= 0x80000000 must not overflow.
Method TestBadCodeRoundTrip()
{
	do ..DropSchema(..#TmpSchema)

	// Create a schema with one Integer column
	set tBody = {}
	set tBody.className = ..#TmpSchema
	set tBody.dataSourceName = "StatusWidth"
	set tBody.defaultNamespace = 1

	set tColumns = []
	set tCol = {}
	set tCol.displayName = "Sensor"
	set tCol.inferredType = "Integer"
	set tRelPath = ["Sensor"]
	set tCol.relativePath = tRelPath
	do tColumns.%Push(tCol)
	set tBody.columns = tColumns

	set tSC = ##class(OPCUA.REST.SchemaService).Create(tBody, .tResult)
	do $$$AssertStatusOK(tSC, "Create schema")
	Quit:$$$ISERR(tSC)

	// Save rows with three Status codes: 2147483648 (0x80000000), 2155085824 (0x80740000), 0
	set tCodes = $LISTBUILD(2147483648, 2155085824, 0)
	set tPtr = 0
	kill tIds
	while $LISTNEXT(tCodes, tPtr, tCode) {
		set tRow = $classmethod(..#TmpSchema, "%New")
		set tSensorDV = ##class(OPCUA.Types.IntegerDataValue).%New()
		set tSensorDV.SourceTimeStamp = "2024-10-29 12:00:00"
		set tSensorDV.ServerTimeStamp = "2024-10-29 12:00:01"
		set tSensorDV.Status = tCode
		set tSensorDV.Value = 42
		set tRow.Sensor = tSensorDV
		set tRow.NodePath = "ns=1;s=Device" _ tCode
		set tSC = tRow.%Save()
		do $$$AssertStatusOK(tSC, "%Save with Status " _ tCode)
		Quit:$$$ISERR(tSC)
		set tIds(tCode) = tRow.%Id()
	}
	Quit:$$$ISERR(tSC)

	// Read them back via SQL and verify the Status column matches
	for tCode = 2147483648, 2155085824, 0 {
		set tId = tIds(tCode)
		&sql(SELECT Sensor_Status INTO :tReadStatus FROM OPCUA_Tests_Tmp.StatusWidth WHERE ID = :tId)
		do $$$AssertEquals(SQLCODE, 0, "SQL SELECT for Status " _ tCode)
		Quit:SQLCODE'=0
		do $$$AssertEquals(tReadStatus, tCode, "Status " _ tCode _ " round-trips unchanged")
	}
}

/// SELECT COUNT(*) WHERE Sensor_Status >= 2147483648 = 2, and ORDER BY
/// Sensor_Status DESC puts 2155085824 first. Bad codes must behave numerically.
Method TestBadCodeSqlCompare()
{
	do ..DropSchema(..#TmpSchema)

	// Create schema
	set tBody = {}
	set tBody.className = ..#TmpSchema
	set tBody.dataSourceName = "StatusWidth"
	set tBody.defaultNamespace = 1

	set tColumns = []
	set tCol = {}
	set tCol.displayName = "Temp"
	set tCol.inferredType = "Double"
	set tRelPath = ["Temp"]
	set tCol.relativePath = tRelPath
	do tColumns.%Push(tCol)
	set tBody.columns = tColumns

	set tSC = ##class(OPCUA.REST.SchemaService).Create(tBody, .tResult)
	do $$$AssertStatusOK(tSC, "Create schema")
	Quit:$$$ISERR(tSC)

	// Save rows with Status codes 2147483648, 2155085824, 0
	set tCodes = $LISTBUILD(2147483648, 2155085824, 0)
	set tPtr = 0
	while $LISTNEXT(tCodes, tPtr, tCode) {
		set tRow = $classmethod(..#TmpSchema, "%New")
		set tTempDV = ##class(OPCUA.Types.DoubleDataValue).%New()
		set tTempDV.SourceTimeStamp = "2024-10-29 12:00:00"
		set tTempDV.ServerTimeStamp = "2024-10-29 12:00:01"
		set tTempDV.Status = tCode
		set tTempDV.Value = 20.5
		set tRow.Temp = tTempDV
		set tRow.NodePath = "ns=1;s=Sensor" _ tCode
		set tSC = tRow.%Save()
		do $$$AssertStatusOK(tSC, "%Save with Status " _ tCode)
		Quit:$$$ISERR(tSC)
	}
	Quit:$$$ISERR(tSC)

	// WHERE Status >= 2147483648 should return 2 rows
	&sql(SELECT COUNT(*) INTO :tCount FROM OPCUA_Tests_Tmp.StatusWidth WHERE Temp_Status >= 2147483648)
	do $$$AssertEquals(SQLCODE, 0, "COUNT WHERE Status >= 2147483648")
	Quit:SQLCODE'=0
	do $$$AssertEquals(tCount, 2, "2 rows with Status >= 2147483648")

	// ORDER BY Status DESC should put 2155085824 first
	&sql(DECLARE c1 CURSOR FOR
		SELECT Temp_Status INTO :tStatus FROM OPCUA_Tests_Tmp.StatusWidth ORDER BY Temp_Status DESC)
	&sql(OPEN c1)
	&sql(FETCH c1)
	do $$$AssertEquals(SQLCODE, 0, "FETCH first row")
	Quit:SQLCODE'=0
	do $$$AssertEquals(tStatus, 2155085824, "ORDER BY DESC puts 2155085824 first")
	&sql(CLOSE c1)
}

/// Query INFORMATION_SCHEMA.COLUMNS for Sensor_Status's DATA_TYPE. It must
/// report BIGINT, not INTEGER.
Method TestProjectedType()
{
	do ..DropSchema(..#TmpSchema)

	// Create schema
	set tBody = {}
	set tBody.className = ..#TmpSchema
	set tBody.dataSourceName = "StatusWidth"
	set tBody.defaultNamespace = 1

	set tColumns = []
	set tCol = {}
	set tCol.displayName = "Value"
	set tCol.inferredType = "Integer"
	set tRelPath = ["Value"]
	set tCol.relativePath = tRelPath
	do tColumns.%Push(tCol)
	set tBody.columns = tColumns

	set tSC = ##class(OPCUA.REST.SchemaService).Create(tBody, .tResult)
	do $$$AssertStatusOK(tSC, "Create schema")
	Quit:$$$ISERR(tSC)

	// Query INFORMATION_SCHEMA.COLUMNS for Value_Status's DATA_TYPE
	set tTableName = "StatusWidth"
	set tColumnName = "Value_Status"
	&sql(SELECT DATA_TYPE INTO :tDataType
		FROM INFORMATION_SCHEMA.COLUMNS
		WHERE TABLE_SCHEMA = 'OPCUA_Tests_Tmp'
		AND TABLE_NAME = :tTableName
		AND COLUMN_NAME = :tColumnName)

	do $$$AssertEquals(SQLCODE, 0, "Query INFORMATION_SCHEMA.COLUMNS")
	Quit:SQLCODE'=0

	do $$$AssertEquals($ZCONVERT(tDataType, "U"), "BIGINT", "Value_Status projects as BIGINT")
}

ClassMethod DropSchema(pClassName As %String)
{
	if ##class(%Dictionary.ClassDefinition).%ExistsId(pClassName) {
		Try {
			do $classmethod(pClassName, "%KillExtent")
		} Catch {}
		do $System.OBJ.Delete(pClassName, "-d")
	}
	kill ^OPCUA.DataSource(pClassName)
}

}
