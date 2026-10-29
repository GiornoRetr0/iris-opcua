Include (%occInclude, Ensemble)

/// Live tests for audit #15 against <tt>plc</tt>, which accepts anonymous
/// sessions and <tt>user1</tt>/<tt>password</tt>, and refuses any other
/// username or password with <tt>BadUserAccessDenied</tt>. A wrong password in a
/// credentials entry therefore fails a connect only when that entry is really
/// what the connect used, which is what these tests check.
Class OPCUA.Tests.Live.SecuredPipelineTest Extends %UnitTest.TestCase
{

Parameter SchemaClass = "OPCUA.Tests.TmpSecuredSchema";

Parameter ProductionClass = "OPCUA.Pipeline.Production";

Parameter PipelineName = "TmpSecured";

/// A test-only entry standing in for one the client made in the Portal.
Parameter WrongEntry = "OPCUA.Tests.LiveWrongCred";

/// A test-only entry with the right password, named in another case on deploy.
Parameter RightEntry = "OPCUA.Tests.LiveRightCred";

Method OnBeforeAllTests() As %Status
{
	do ..DoCleanup()
	Quit ..BuildSchema()
}

Method OnAfterAllTests() As %Status
{
	do ..DoCleanup()
	Quit $$$OK
}

/// Deploy with a username and password, then rebind: the coverage check
/// connects with the entry's username and password. With the entry's password
/// made wrong, the same rebind fails to connect, so the entry is what it used.
Method TestRebindWithCredentials()
{
	set tName = ..#PipelineName
	set tId = ##class(OPCUA.REST.DeployService).CredentialsId(tName)
	set tSC = ..Deploy(tName, {"username": "user1", "password": "password"})
	do $$$AssertStatusOK(tSC, "secured deploy")
	Quit:$$$ISERR(tSC)

	set tSC = ##class(OPCUA.REST.PipelineService).Rebind({"name": (tName), "devices": "i=85|Objects"}, .tResult)
	do $$$AssertStatusOK(tSC, "secured rebind connects")

	// The entry is ours, created by the deploy above, so the test may change it.
	do $$$AssertStatusOK(##class(Ens.Config.Credentials).SetCredential(tId, "user1", "wrong", 1), "make the entry's password wrong")
	set tSC = ##class(OPCUA.REST.PipelineService).Rebind({"name": (tName), "devices": "i=85|Objects"}, .tResult)
	set tText = ##class(OPCUA.REST.Error).Text(tSC)
	do $$$AssertNotTrue($$$ISOK(tSC), "rebind with a wrong password in the entry is refused")
	do $$$AssertTrue(tText [ "BadUserAccessDenied", "refused by the server: "_tText)

	do $$$AssertStatusOK(##class(Ens.Config.Credentials).SetCredential(tId, "user1", "password", 1), "restore the entry")
	set tSC = ##class(OPCUA.REST.PipelineService).Rebind({"name": (tName), "devices": "i=85|Objects"}, .tResult)
	do $$$AssertStatusOK(tSC, "rebind connects again")
}

/// Deploy with an existing credentials ID runs its coverage check with that
/// entry: an entry holding a wrong password makes the deploy fail to connect.
Method TestDeployCheckUsesCredentialsEntry()
{
	do $$$AssertStatusOK(##class(Ens.Config.Credentials).SetCredential(..#WrongEntry, "user1", "wrong", 1), "entry with a wrong password")
	set tSC = ..Deploy(..#PipelineName_"Wrong", {"credentials": (..#WrongEntry)})
	set tText = ##class(OPCUA.REST.Error).Text(tSC)
	do $$$AssertNotTrue($$$ISOK(tSC), "deploy with a wrong-password entry is refused")
	do $$$AssertTrue(tText [ "BadUserAccessDenied", "refused by the server: "_tText)
	do $$$AssertTrue(##class(Ens.Config.Credentials).%ExistsId(..#WrongEntry), "the given entry is untouched")
}

/// A running pipeline connects with its credentials entry. Two pipelines
/// share the schema: one entry right, one made wrong after deploy. The right
/// one stores rows, the wrong one stores none and reports an error.
Method TestRunningPipelineUsesCredentials()
{
	set tGood = ..#PipelineName_"Good", tBad = ..#PipelineName_"Bad"
	do $$$AssertStatusOK(..Deploy(tGood, {"username": "user1", "password": "password", "devices": "i=85|Good"}), "deploy good")
	do $$$AssertStatusOK(..Deploy(tBad, {"username": "user1", "password": "password", "devices": "i=85|Bad"}), "deploy bad")
	// Ens matches credentials IDs in any case; so do deploy and the adapter.
	set tCase = ..#PipelineName_"Case"
	do $$$AssertStatusOK(##class(Ens.Config.Credentials).SetCredential(..#RightEntry, "user1", "password", 1), "client entry with the right password")
	do $$$AssertStatusOK(..Deploy(tCase, {"credentials": ($ZConvert(..#RightEntry, "L")), "devices": "i=85|Case"}), "deploy with credentials in another case")
	set tBadId = ##class(OPCUA.REST.DeployService).CredentialsId(tBad)
	do $$$AssertStatusOK(##class(Ens.Config.Credentials).SetCredential(tBadId, "user1", "wrong", 1), "make bad's entry wrong")

	set tStart = $ZDateTime($ZTimeStamp, 3)
	for tName = tGood, tBad, tCase {
		set tSC = ##class(OPCUA.REST.PipelineService).Toggle({"name": (tName)}, .tResult)
		do $$$AssertStatusOK(tSC, "enable "_tName)
	}

	// Wait for the good pipeline's rows, then a few more cycles for the bad one.
	for i=1:1:300 { quit:(..Rows("Good")>0)&&(..Rows("Case")>0)  hang 0.1 }
	do $$$AssertTrue(..Rows("Good") > 0, "pipeline with the right password stores rows")
	do $$$AssertTrue(..Rows("Case") > 0, "pipeline naming its entry in another case stores rows")
	hang 3
	do $$$AssertEquals(..Rows("Bad"), 0, "pipeline with a wrong password stores none")
	set tBadName = tBad
	&sql(SELECT COUNT(*) INTO :tDenied FROM Ens_Util.Log WHERE ConfigName = :tBadName AND TimeLogged >= :tStart AND Text [ 'BadUserAccessDenied')
	do $$$AssertTrue((SQLCODE = 0) && (tDenied > 0), "bad pipeline logs BadUserAccessDenied")

	for tName = tGood, tBad, tCase {
		do ##class(OPCUA.REST.PipelineService).Delete({"name": (tName)}, .tResult)
	}
}

// ==================== helpers ====================

ClassMethod Deploy(pName As %String, pExtra As %DynamicObject) As %Status
{
	set tBody = {"dataSourceName": (pName), "schemaClass": (..#SchemaClass), "mode": "polling", "url": (..URL()), "devices": "i=85|Objects", "callInterval": 1}
	set tIter = pExtra.%GetIterator()
	while tIter.%GetNext(.tKey, .tVal) { do tBody.%Set(tKey, tVal) }
	Quit ##class(OPCUA.REST.DeployService).Deploy(tBody, .tResult)
}

ClassMethod Rows(pPath As %String) As %Integer
{
	set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_##class(OPCUA.REST.SchemaService).TableName(..#SchemaClass)_" WHERE NodePath = ?", pPath)
	Quit:tRS.%SQLCODE<0 -1
	Quit $Select(tRS.%Next():tRS.%GetData(1), 1:0)
}

ClassMethod URL() As %String
{
	Quit $Get(^||OPCUA.Tests("url"), "opc.tcp://plc")
}

ClassMethod DoCleanup()
{
	for tSuffix = "", "Wrong", "Good", "Bad", "Case" {
		set tName = ..#PipelineName_tSuffix
		try {
			do ##class(OPCUA.REST.PipelineService).Delete({"name": (tName)}, .tResult)
		} catch e {}
		&sql(DELETE FROM Ens_Config.Item WHERE Name = :tName)
		// Test-only IDs: the entries deploy made for these pipelines.
		set tId = "OPCUA-"_tName
		try { set tId = ##class(OPCUA.REST.DeployService).CredentialsId(tName) } catch e {}
		do:##class(Ens.Config.Credentials).%ExistsId(tId) ##class(Ens.Config.Credentials).%DeleteId(tId)
		kill ^OPCUA.OwnedCredentials(tId)
	}
	for tEntry = ..#WrongEntry, ..#RightEntry {
		do:##class(Ens.Config.Credentials).%ExistsId(tEntry) ##class(Ens.Config.Credentials).%DeleteId(tEntry)
	}
	try {
		do:##class(%Dictionary.CompiledClass).%ExistsId(..#SchemaClass) $classmethod(..#SchemaClass, "%KillExtent")
	} catch e {}
	do:##class(%Dictionary.ClassDefinition).%ExistsId(..#SchemaClass) $System.OBJ.Delete(..#SchemaClass, "-d")
	kill ^OPCUA.DataSource(..#SchemaClass)
}

/// A one-column schema that the plc's Objects folder resolves (SA1).
ClassMethod BuildSchema() As %Status
{
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#SchemaClass)
	set tDef.Description = "Throwaway schema for SecuredPipelineTest"
	set tDef.Super = "%Persistent,OPCUA.DataSource.DeviceSchema"

	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUADATASOURCE", tParam.Default = "TmpSecured"
	do tDef.Parameters.Insert(tParam)
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUDEFAULTANAMESPACE", tParam.Default = 1
	do tDef.Parameters.Insert(tParam)

	set tProp = ##class(%Dictionary.PropertyDefinition).%New()
	set tProp.Name = "NodePath", tProp.Type = "%String"
	do tProp.Parameters.SetAt(500, "MAXLEN")
	do tDef.Properties.Insert(tProp)

	set tProp = ##class(%Dictionary.PropertyDefinition).%New()
	set tProp.Name = "SA1", tProp.Type = "OPCUA.Types.IntegerDataValue"
	do tProp.Parameters.SetAt("SA1", "OPCUANODENAME")
	do tDef.Properties.Insert(tProp)

	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC
	Quit $System.OBJ.Compile(..#SchemaClass, "ck-d")
}

}
