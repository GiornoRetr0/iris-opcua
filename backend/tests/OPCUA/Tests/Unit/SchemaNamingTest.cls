Include %occInclude

/// Unit tests for schema naming and table name derivation
Class OPCUA.Tests.Unit.SchemaNamingTest Extends %UnitTest.TestCase
{

/// Test that TableName() honors SqlTableName parameter
Method TestTableNameHonoursSqlTableName()
{
    Set tClassName = "OPCUA.Tests.TmpNamingClass"

    // Clean up any leftover class
    If ##class(%Dictionary.ClassDefinition).%ExistsId(tClassName) {
        Do ##class(%Dictionary.ClassDefinition).%DeleteId(tClassName)
    }

    // Create a simple %Persistent class with custom SqlTableName (not a full DeviceSchema)
    Set tClassDef = ##class(%Dictionary.ClassDefinition).%New()
    Set tClassDef.Name = tClassName
    Set tClassDef.Super = "%Persistent"

    // Set custom SQL table name as a class property
    Set tClassDef.SqlTableName = "Custom_T"

    // Add a minimal property
    Set tProp = ##class(%Dictionary.PropertyDefinition).%New()
    Set tProp.Name = "TestProp"
    Set tProp.Type = "%String"
    Do tClassDef.Properties.Insert(tProp)

    // Save and compile
    Set tSC = tClassDef.%Save()
    Do $$$AssertStatusOK(tSC, "Class creation should succeed")

    If $$$ISOK(tSC) {
        Set tSC = $System.OBJ.Compile(tClassName, "ck")
        Do $$$AssertStatusOK(tSC, "Class compilation should succeed")
    }

    // Test TableName() helper BEFORE cleanup
    If $$$ISOK(tSC) {
        Set tTableName = ##class(OPCUA.REST.SchemaService).TableName(tClassName)
        Do $$$AssertTrue(tTableName [ "Custom_T", "TableName should contain Custom_T, got: "_tTableName)
        Do $$$AssertTrue(tTableName [ ".", "TableName should contain schema separator, got: "_tTableName)

        // Clean up after successful test
        Do $System.OBJ.Delete(tClassName, "-d")
    } Else {
        // Clean up after failed compilation
        If ##class(%Dictionary.ClassDefinition).%ExistsId(tClassName) {
            Do $System.OBJ.Delete(tClassName, "-d")
        }
    }
}

/// A schema whose short name is an SQL reserved word still gets a row count: the
/// dashboard's COUNT(*) quotes the schema and table names. Group, because an
/// unquoted Order happens to parse after a dot, and Group does not.
Method TestRowCountReservedWordTable()
{
    Set tClassName = "OPCUA.Tests.Tmp.Group"
    Do ..DropClass(tClassName)
    Set tClassDef = ##class(%Dictionary.ClassDefinition).%New(tClassName)
    Set tClassDef.Super = "%Persistent"
    Set tClassDef.Description = "Throwaway class for SchemaNamingTest"
    Set tProp = ##class(%Dictionary.PropertyDefinition).%New()
    Set tProp.Name = "TestProp", tProp.Type = "%String"
    Do tClassDef.Properties.Insert(tProp)
    Set tSC = tClassDef.%Save()
    Do $$$AssertStatusOK(tSC, "class saved")
    Set:$$$ISOK(tSC) tSC = $System.OBJ.Compile(tClassName, "ck-d")
    Do $$$AssertStatusOK(tSC, "class compiled")
    If $$$ISOK(tSC) {
        Set tRow = $ClassMethod(tClassName, "%New")
        Set tRow.TestProp = "x"
        Do $$$AssertStatusOK(tRow.%Save(), "one row")
        Kill ^IRIS.Temp.OPCUARowCount(tClassName)
        Do $$$AssertEquals(##class(OPCUA.REST.PipelineService).GetRowCount(tClassName), 1, "row count for table "_##class(OPCUA.REST.SchemaService).TableName(tClassName))
        Do $$$AssertEquals(##class(OPCUA.REST.SchemaService).QuotedTableName(tClassName), """OPCUA_Tests_Tmp"".""Group""", "quoted name")
        Kill ^IRIS.Temp.OPCUARowCount(tClassName)
    }
    Do ..DropClass(tClassName)
}

ClassMethod DropClass(pClassName As %String)
{
    If ##class(%Dictionary.ClassDefinition).%ExistsId(pClassName) {
        Try { Do $ClassMethod(pClassName, "%KillExtent") } Catch {}
        Do $System.OBJ.Delete(pClassName, "-d")
    }
}

}
