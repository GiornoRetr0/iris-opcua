Include %occInclude

/// Unit tests for schema creation: upfront name checks, cleanup on failure, and
/// serial class delete safety.
///
/// Closes audit #12 and the "schema delete can remove a shared class" smaller issue.
Class OPCUA.Tests.Unit.SchemaCreateTest Extends %UnitTest.TestCase
{

Parameter TmpSchema = "OPCUA.Tests.Tmp.SchemaCreate";

Parameter TmpSerial = "OPCUA.Tests.Tmp.SchemaCreate.MotorType";

Parameter TmpHandWritten = "OPCUA.Tests.Tmp.HandWritten";

Method OnAfterAllTests() As %Status
{
	do ..DropSchema(..#TmpSchema)
	do ..DropClass(..#TmpSerial)
	do ..DropClass(..#TmpHandWritten)
	kill ^||OPCUA.Tests("badProp")
	kill ^||OPCUA.Tests("deleteFailClass")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	kill ^||OPCUA.Tests("badProp")
	kill ^||OPCUA.Tests("deleteFailClass")
	Quit $$$OK
}

/// Pre-create the serial class name a nested schema would use. Assert Create
/// fails with "already exists" naming that class, and that the main class does
/// **not** exist afterwards.
Method TestNameTakenRefusedUpfront()
{
	do ..DropSchema(..#TmpSchema)
	do ..DropClass(..#TmpSerial)

	// Pre-create the serial class that the schema would try to generate
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#TmpSerial)
	set tDef.Super = "%SerialObject"
	set tDef.Description = "Throwaway class blocking a serial name"
	set tSC = tDef.%Save()
	do $$$AssertStatusOK(tSC, "Pre-create serial class")
	Quit:$$$ISERR(tSC)

	set tSC = $System.OBJ.Compile(..#TmpSerial, "ck-d")
	do $$$AssertStatusOK(tSC, "Compile serial class")
	Quit:$$$ISERR(tSC)

	// Attempt to create a schema with a nested column whose serial class name
	// matches the existing class
	set tBody = {}
	set tBody.className = ..#TmpSchema
	set tBody.dataSourceName = "SchemaCreate"
	set tBody.defaultNamespace = 1

	set tColumns = []
	// A nested column: Motor is the folder, Temperature is the leaf
	set tCol = {}
	set tCol.displayName = "Temperature"
	set tCol.inferredType = "Double"
	set tRelPath = ["Motor", "Temperature"]
	set tCol.relativePath = tRelPath
	do tColumns.%Push(tCol)
	set tBody.columns = tColumns

	set tSC = ##class(OPCUA.REST.SchemaService).Create(tBody, .tResult)
	do $$$AssertNotTrue($$$ISOK(tSC), "Create refuses when serial class name is taken")

	set tMsg = $System.Status.GetErrorText(tSC)
	do $$$AssertTrue(tMsg [ ..#TmpSerial, "error names the blocking class: "_tMsg)
	do $$$AssertTrue((tMsg [ "exists") || (tMsg [ "already"), "error says the class exists: "_tMsg)

	do $$$AssertNotTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#TmpSchema), "main class was not created after upfront check failed")
	do $$$AssertTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#TmpSerial), "pre-existing serial class still exists")
}

/// Make the main class fail to compile (test hook that injects an invalid property
/// type). Assert every serial class created by the call is gone, and an immediate
/// retry without the hook succeeds.
Method TestFailedCompileCleansUp()
{
	do ..DropSchema(..#TmpSchema)
	do ..DropClass(..#TmpSerial)

	// Set the test hook that makes GenerateSchemaClass inject a bad property type
	set ^||OPCUA.Tests("badProp") = 1

	// Attempt to create a schema with nested columns
	set tBody = {}
	set tBody.className = ..#TmpSchema
	set tBody.dataSourceName = "SchemaCreate"
	set tBody.defaultNamespace = 1

	set tColumns = []
	// Nested column: Motor folder with Temperature leaf
	set tCol1 = {}
	set tCol1.displayName = "Temperature"
	set tCol1.inferredType = "Double"
	set tRelPath1 = ["Motor", "Temperature"]
	set tCol1.relativePath = tRelPath1
	do tColumns.%Push(tCol1)

	// Flat column
	set tCol2 = {}
	set tCol2.displayName = "Humidity"
	set tCol2.inferredType = "Double"
	set tRelPath2 = ["Humidity"]
	set tCol2.relativePath = tRelPath2
	do tColumns.%Push(tCol2)
	set tBody.columns = tColumns

	set tSC = ##class(OPCUA.REST.SchemaService).Create(tBody, .tResult)
	do $$$AssertNotTrue($$$ISOK(tSC), "Create fails when compile fails")

	do $$$AssertNotTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#TmpSchema), "main class is gone after failed compile")
	do $$$AssertNotTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#TmpSerial), "serial class is gone after failed compile")

	// Clear the test hook and retry — should succeed
	kill ^||OPCUA.Tests("badProp")
	set tSC = ##class(OPCUA.REST.SchemaService).Create(tBody, .tResult)
	do $$$AssertStatusOK(tSC, "Create succeeds without the hook")
	Quit:$$$ISERR(tSC)

	do $$$AssertTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#TmpSchema), "main class exists after successful create")
	do $$$AssertTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#TmpSerial), "serial class exists after successful create")
}

/// Make the main class fail to compile and the cleanup delete also fail. Assert the
/// returned error contains both the original compile error and the cleanup failure.
Method TestFailedRollbackReported()
{
	do ..DropSchema(..#TmpSchema)
	do ..DropClass(..#TmpSerial)

	// Set the test hook that makes GenerateSchemaClass inject a bad property type
	set ^||OPCUA.Tests("badProp") = 1
	// Set the test hook that makes the serial class delete fail during rollback
	set ^||OPCUA.Tests("deleteFailClass") = ..#TmpSerial

	// Attempt to create a schema with nested columns
	set tBody = {}
	set tBody.className = ..#TmpSchema
	set tBody.dataSourceName = "SchemaCreate"
	set tBody.defaultNamespace = 1

	set tColumns = []
	// Nested column: Motor folder with Temperature leaf
	set tCol1 = {}
	set tCol1.displayName = "Temperature"
	set tCol1.inferredType = "Double"
	set tRelPath1 = ["Motor", "Temperature"]
	set tCol1.relativePath = tRelPath1
	do tColumns.%Push(tCol1)

	// Flat column
	set tCol2 = {}
	set tCol2.displayName = "Humidity"
	set tCol2.inferredType = "Double"
	set tRelPath2 = ["Humidity"]
	set tCol2.relativePath = tRelPath2
	do tColumns.%Push(tCol2)
	set tBody.columns = tColumns

	set tSC = ##class(OPCUA.REST.SchemaService).Create(tBody, .tResult)
	do $$$AssertNotTrue($$$ISOK(tSC), "Create fails when compile fails")

	set tMsg = $System.Status.GetErrorText(tSC)
	do $$$AssertTrue(tMsg [ "ThisClassDoesNotExist", "error contains original compile error: "_tMsg)
	do $$$AssertTrue(tMsg [ "rollback", "error mentions rollback failure: "_tMsg)
	do $$$AssertTrue(tMsg [ ..#TmpSerial, "error names the class that failed to delete: "_tMsg)
}

/// A hand-written class OPCUA.Tests.Tmp.HandWritten with a property typed as schema
/// S's serial class. Delete S, and assert the serial class still exists.
Method TestSharedSerialClassKept()
{
	do ..DropSchema(..#TmpSchema)
	do ..DropClass(..#TmpSerial)
	do ..DropClass(..#TmpHandWritten)

	// Create a schema with a nested column
	set tBody = {}
	set tBody.className = ..#TmpSchema
	set tBody.dataSourceName = "SchemaCreate"
	set tBody.defaultNamespace = 1

	set tColumns = []
	set tCol = {}
	set tCol.displayName = "Temperature"
	set tCol.inferredType = "Double"
	set tRelPath = ["Motor", "Temperature"]
	set tCol.relativePath = tRelPath
	do tColumns.%Push(tCol)
	set tBody.columns = tColumns

	set tSC = ##class(OPCUA.REST.SchemaService).Create(tBody, .tResult)
	do $$$AssertStatusOK(tSC, "Create schema with nested column")
	Quit:$$$ISERR(tSC)

	do $$$AssertTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#TmpSerial), "serial class created")

	// Create a hand-written class that references the serial class
	set tHWDef = ##class(%Dictionary.ClassDefinition).%New(..#TmpHandWritten)
	set tHWDef.Super = "%Persistent"
	set tHWDef.Description = "Hand-written class sharing a serial type"

	set tProp = ##class(%Dictionary.PropertyDefinition).%New()
	set tProp.Name = "MotorData"
	set tProp.Type = ..#TmpSerial
	do tHWDef.Properties.Insert(tProp)

	set tSC = tHWDef.%Save()
	do $$$AssertStatusOK(tSC, "Create hand-written class")
	Quit:$$$ISERR(tSC)

	set tSC = $System.OBJ.Compile(..#TmpHandWritten, "ck-d")
	do $$$AssertStatusOK(tSC, "Compile hand-written class")
	Quit:$$$ISERR(tSC)

	// Delete the schema — the shared serial class must survive
	set tDelBody = {"name": (..#TmpSchema)}
	set tSC = ##class(OPCUA.REST.SchemaService).Delete(tDelBody, .tDelResult)
	do $$$AssertStatusOK(tSC, "Delete schema")
	Quit:$$$ISERR(tSC)

	do $$$AssertNotTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#TmpSchema), "main schema is gone")
	do $$$AssertTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#TmpSerial), "shared serial class still exists after schema delete")
	do $$$AssertTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#TmpHandWritten), "hand-written class still exists")
}

ClassMethod DropSchema(pClassName As %String)
{
	if ##class(%Dictionary.ClassDefinition).%ExistsId(pClassName) {
		do $classmethod(pClassName, "%KillExtent")
		do $System.OBJ.Delete(pClassName, "-d")
	}
	kill ^OPCUA.DataSource(pClassName)
}

ClassMethod DropClass(pClassName As %String)
{
	if ##class(%Dictionary.ClassDefinition).%ExistsId(pClassName) {
		Try {
			do $classmethod(pClassName, "%KillExtent")
		} Catch {}
		do $System.OBJ.Delete(pClassName, "-d")
	}
}

}
