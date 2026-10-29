Include %occInclude

/// Unit tests verifying string columns are not capped at 50 characters.
///
/// Closes audit #13.
Class OPCUA.Tests.Unit.TypeWidthTest Extends %UnitTest.TestCase
{

Parameter TmpSchema = "OPCUA.Tests.Tmp.TypeWidth";

Method OnAfterAllTests() As %Status
{
	do ..DropSchema(..#TmpSchema)
	Quit $$$OK
}

/// Generate a schema with a String column. Save a row with a 5,000-character
/// value and a non-ASCII 200-character value. Assert %Save returns OK. A SQL
/// UPDATE setting the column to a 5,000-character value gives SQLCODE 0.
Method TestLongStringSaves()
{
	do ..DropSchema(..#TmpSchema)

	// Create a schema with a flat String column
	set tBody = {}
	set tBody.className = ..#TmpSchema
	set tBody.dataSourceName = "TypeWidth"
	set tBody.defaultNamespace = 1

	set tColumns = []
	set tCol = {}
	set tCol.displayName = "Message"
	set tCol.inferredType = "String"
	set tRelPath = ["Message"]
	set tCol.relativePath = tRelPath
	do tColumns.%Push(tCol)
	set tBody.columns = tColumns

	set tSC = ##class(OPCUA.REST.SchemaService).Create(tBody, .tResult)
	do $$$AssertStatusOK(tSC, "Create schema with String column")
	Quit:$$$ISERR(tSC)

	// %New a row with a 5,000-character value
	set tLongValue = ""
	for i=1:1:5000 {
		set tLongValue = tLongValue _ "x"
	}
	set tRow = $classmethod(..#TmpSchema, "%New")
	set tMessageDV = ##class(OPCUA.Types.StringDataValue).%New()
	set tMessageDV.SourceTimeStamp = "2024-10-29 12:00:00"
	set tMessageDV.ServerTimeStamp = "2024-10-29 12:00:01"
	set tMessageDV.Status = 0
	set tMessageDV.Value = tLongValue
	set tRow.Message = tMessageDV
	set tRow.NodePath = "ns=1;s=Device1"

	set tSC = tRow.%Save()
	do $$$AssertStatusOK(tSC, "%Save with 5,000-character value")
	Quit:$$$ISERR(tSC)

	set tId = tRow.%Id()

	// Save a non-ASCII 200-character value
	set tUnicodeValue = ""
	for i=1:1:200 {
		// Cycle through "Ü", "ñ", "î", "ç", "ø", "d", "é"
		set tChar = $Case((i # 7), 0:"Ü", 1:"ñ", 2:"î", 3:"ç", 4:"ø", 5:"d", :"é")
		set tUnicodeValue = tUnicodeValue _ tChar
	}
	set tRow2 = $classmethod(..#TmpSchema, "%New")
	set tMessageDV2 = ##class(OPCUA.Types.StringDataValue).%New()
	set tMessageDV2.SourceTimeStamp = "2024-10-29 12:01:00"
	set tMessageDV2.ServerTimeStamp = "2024-10-29 12:01:01"
	set tMessageDV2.Status = 0
	set tMessageDV2.Value = tUnicodeValue
	set tRow2.Message = tMessageDV2
	set tRow2.NodePath = "ns=1;s=Device2"

	set tSC = tRow2.%Save()
	do $$$AssertStatusOK(tSC, "%Save with 200-character non-ASCII value")
	Quit:$$$ISERR(tSC)

	// SQL UPDATE to a 5,000-character value
	set tSqlLongValue = ""
	for i=1:1:5000 {
		set tSqlLongValue = tSqlLongValue _ "y"
	}
	&sql(UPDATE OPCUA_Tests_Tmp.TypeWidth SET Message_Value = :tSqlLongValue WHERE ID = :tId)
	do $$$AssertEquals(SQLCODE, 0, "SQL UPDATE with 5,000-character value gives SQLCODE 0")
}

/// Check the projected SQL type for X_Value reports no 50-character limit via
/// %Library.SQLCatalog or INFORMATION_SCHEMA.COLUMNS.
Method TestProjectedWidth()
{
	do ..DropSchema(..#TmpSchema)

	// Create a schema with a String column
	set tBody = {}
	set tBody.className = ..#TmpSchema
	set tBody.dataSourceName = "TypeWidth"
	set tBody.defaultNamespace = 1

	set tColumns = []
	set tCol = {}
	set tCol.displayName = "Text"
	set tCol.inferredType = "String"
	set tRelPath = ["Text"]
	set tCol.relativePath = tRelPath
	do tColumns.%Push(tCol)
	set tBody.columns = tColumns

	set tSC = ##class(OPCUA.REST.SchemaService).Create(tBody, .tResult)
	do $$$AssertStatusOK(tSC, "Create schema")
	Quit:$$$ISERR(tSC)

	// Query INFORMATION_SCHEMA.COLUMNS for Text_Value's CHARACTER_MAXIMUM_LENGTH
	set tTableName = "TypeWidth"
	set tColumnName = "Text_Value"
	&sql(SELECT CHARACTER_MAXIMUM_LENGTH INTO :tMaxLen
		FROM INFORMATION_SCHEMA.COLUMNS
		WHERE TABLE_SCHEMA = 'OPCUA_Tests_Tmp'
		AND TABLE_NAME = :tTableName
		AND COLUMN_NAME = :tColumnName)

	do $$$AssertEquals(SQLCODE, 0, "Query INFORMATION_SCHEMA.COLUMNS")
	Quit:SQLCODE'=0

	// An unbounded VARCHAR projects as NULL CHARACTER_MAXIMUM_LENGTH in IRIS
	// (or a very large number, depending on version). Definitely not 50.
	if (tMaxLen = 50) {
		do $$$AssertNotEquals(tMaxLen, 50, "Text_Value should not be capped at 50 characters")
	}
}

/// For every class in OPCUA.Types with a counterpart in OPCUA.Types.NoServerTS,
/// the payload properties (not SourceTimeStamp/ServerTimeStamp/Status) have
/// identical names, types and MAXLEN.
Method TestFamiliesInStep()
{
	// List of pairs: main class name -> payload property names (excluding timestamps/status)
	// We check the classes that have string payload properties
	set tTypesToCheck = $LISTBUILD(
		$LISTBUILD("StringDataValue", "Value"),
		$LISTBUILD("LocalizedTextDataValue", "Text,Locale"),
		$LISTBUILD("QualifiedNameDataValue", "Name"),
		$LISTBUILD("NodeIdDataValue", "Identifier"),
		$LISTBUILD("ArrayDataValue.String", "Values")
	)

	set tPtr = 0
	while $LISTNEXT(tTypesToCheck, tPtr, tPair) {
		set tClassName = $LIST(tPair, 1)
		set tPropNames = $LIST(tPair, 2)

		set tMainClass = "OPCUA.Types." _ tClassName
		set tNoSTClass = "OPCUA.Types.NoServerTS." _ tClassName

		// Split property names by comma
		set tPropList = $LISTFROMSTRING(tPropNames, ",")
		set tPropPtr = 0
		while $LISTNEXT(tPropList, tPropPtr, tPropName) {
			set tMainDef = ##class(%Dictionary.PropertyDefinition).%OpenId(tMainClass _ "||" _ tPropName)
			do $$$AssertTrue($IsObject(tMainDef), tMainClass _ "." _ tPropName _ " exists")
			Quit:'$IsObject(tMainDef)

			set tNoSTDef = ##class(%Dictionary.PropertyDefinition).%OpenId(tNoSTClass _ "||" _ tPropName)
			do $$$AssertTrue($IsObject(tNoSTDef), tNoSTClass _ "." _ tPropName _ " exists")
			Quit:'$IsObject(tNoSTDef)

			// Check Type matches
			do $$$AssertEquals(tNoSTDef.Type, tMainDef.Type, tClassName _ "." _ tPropName _ " Type matches")

			// Check MAXLEN parameter matches
			set tMainMaxLen = tMainDef.Parameters.GetAt("MAXLEN")
			set tNoSTMaxLen = tNoSTDef.Parameters.GetAt("MAXLEN")
			do $$$AssertEquals(tNoSTMaxLen, tMainMaxLen, tClassName _ "." _ tPropName _ " MAXLEN matches")
		}
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
