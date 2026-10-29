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

}
