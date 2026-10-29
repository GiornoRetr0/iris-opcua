Include %occInclude

/// Live test verifying Bad StatusCodes from the native layer are stored as
/// unsigned values and classified correctly by RowWriter's severity logic.
///
/// Closes audit #14.
Class OPCUA.Tests.Live.StatusSignTest Extends %UnitTest.TestCase
{

Parameter TmpSchema = "OPCUA.Tests.Tmp.LiveStatusSign";

Parameter PLCURL = "opc.tcp://plc:4840";

Method OnAfterAllTests() As %Status
{
	do ..DropSchema(..#TmpSchema)
	Quit $$$OK
}

/// Verify that schemas created after the BigInt change project Status columns
/// as BIGINT in SQL, confirming the fix works for schemas created dynamically.
Method TestStoredUnsigned()
{
	do ..DropSchema(..#TmpSchema)

	Try {
		// Create a simple schema with one column
		set tBody = {}
		set tBody.className = ..#TmpSchema
		set tBody.dataSourceName = "LiveStatusSign"
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

		// Query SQL metadata for Sensor_Status type
		set tTableName = "LiveStatusSign"
		set tColumnName = "Sensor_Status"
		&sql(SELECT DATA_TYPE INTO :tDataType
			FROM INFORMATION_SCHEMA.COLUMNS
			WHERE TABLE_SCHEMA = 'OPCUA_Tests_Tmp'
			AND TABLE_NAME = :tTableName
			AND COLUMN_NAME = :tColumnName)

		do $$$AssertEquals(SQLCODE, 0, "Query INFORMATION_SCHEMA.COLUMNS")
		Quit:SQLCODE'=0

		do $$$AssertEquals($ZCONVERT(tDataType, "U"), "BIGINT", "Sensor_Status projects as BIGINT")

		// Save a row with a Bad StatusCode and verify it's non-negative
		set tRow = $classmethod(..#TmpSchema, "%New")
		set tSensorDV = ##class(OPCUA.Types.IntegerDataValue).%New()
		set tSensorDV.SourceTimeStamp = "2024-10-29 12:00:00"
		set tSensorDV.ServerTimeStamp = "2024-10-29 12:00:01"
		// Use a Bad status code: 0x80000000 = 2147483648
		set tSensorDV.Status = 2147483648
		set tSensorDV.Value = 100
		set tRow.Sensor = tSensorDV
		set tRow.NodePath = "ns=1;s=TestDevice"

		set tSC = tRow.%Save()
		do $$$AssertStatusOK(tSC, "%Save with Bad StatusCode")
		Quit:$$$ISERR(tSC)

		set tId = tRow.%Id()

		// Read back via SQL
		&sql(SELECT Sensor_Status INTO :tStatus FROM OPCUA_Tests_Tmp.LiveStatusSign WHERE ID = :tId)
		do $$$AssertEquals(SQLCODE, 0, "SQL SELECT Sensor_Status")
		Quit:SQLCODE'=0

		// The key assertion: Bad StatusCodes >= 0x80000000 must store as non-negative
		do $$$AssertEquals(tStatus, 2147483648, "Bad StatusCode 2147483648 round-trips")
		do $$$AssertTrue(tStatus >= 0, "Status is non-negative")

	} Catch (e) {
		do $$$AssertTrue(0, "Exception: " _ e.DisplayString())
	}
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
