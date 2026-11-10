Include (%occInclude, Ensemble)

/// Live test: an IRIS account holding only the role the terminal installer
/// creates (<tt>OPCUA_API_&lt;NS&gt;</tt>: OPCUA_API:U plus the namespace database
/// :RW, see <tt>IRISConfig.ClientInstaller.CreateApp</tt>) can use the console's
/// schema and pipeline operations that need no credentials entry. Each one works,
/// or fails with a readable 403; none is an opaque 500 (dynamic SQL privilege
/// errors, SQLCODE -99, were).
///
/// Covered: schema list, describe, create, delete (refused while in use, and done
/// when unused), deploy, rebind and delete of a pipeline without credentials, and
/// the pipeline list. Not covered: toggle, which starts or updates the production,
/// and credentials, which need %Ens_Credentials (CredentialsTest). The row count is
/// dynamic SQL on the schema table, so for this role it is unknown (a 403, caught).
///
/// A throwaway user and role run every step in a JOB, logged in as that user, on a
/// throwaway production (<tt>^||OPCUA.Tests("production")</tt>) that is never
/// started. The deploy and rebind coverage checks browse the plc.
Class OPCUA.Tests.Live.ApiRoleTest Extends %UnitTest.TestCase
{

Parameter Production = "OPCUA.Tests.Tmp.RoleProduction";

/// Bound to the pipeline, so its delete is refused.
Parameter Schema = "OPCUA.Tests.Tmp.RoleSchema";

/// Bound to nothing, with a serial folder class, so its delete goes through
/// (and checks that no other class shares the folder class).
Parameter UnusedSchema = "OPCUA.Tests.Tmp.RoleUnused";

Parameter Pipeline = "TmpRolePipeline";

Parameter User = "OPCUATestApiRoleUser";

Parameter Role = "OPCUATestApiRole";

/// The installer's API resource.
Parameter ApiResource = "OPCUA_API";

Method OnBeforeAllTests() As %Status
{
	do ..Cleanup()
	set tSC = ..BuildSchema(..#Schema, 0)
	Quit:$$$ISERR(tSC) tSC
	set tSC = ..BuildSchema(..#UnusedSchema, 1)
	Quit:$$$ISERR(tSC) tSC
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#Production)
	set tDef.Super = "Ens.Production"
	set tDef.Description = "Throwaway production for ApiRoleTest. Never started."
	set tX = ##class(%Dictionary.XDataDefinition).%New()
	set tX.Name = "ProductionDefinition"
	do tX.Data.Write("<Production Name="""_..#Production_"""></Production>")
	do tDef.XDatas.Insert(tX)
	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC
	set tSC = $System.OBJ.Compile(..#Production, "ck-d")
	Quit:$$$ISERR(tSC) tSC
	set tSC = ##class(Ens.Config.Production).LoadFromClass(..#Production)
	Quit:$$$ISERR(tSC) tSC
	set ^||OPCUA.Tests("production") = ..#Production
	Quit ##class(OPCUA.REST.DeployService).AddServiceItem({"url": (..URL())}, ..#Schema, ..#Pipeline, "polling", "i=85|Objects")
}

Method OnAfterAllTests() As %Status
{
	do ..Cleanup()
	kill ^||OPCUA.Tests("production")
	Quit $$$OK
}

Method TestInstallerRoleOnly()
{
	set tSC = ..CreateUser(.tPassword)
	do $$$AssertStatusOK(tSC, "throwaway user with only the installer's role")
	Quit:$$$ISERR(tSC)
	Try {
		kill ^IRIS.Temp.OPCUATests("role")
		job ##class(OPCUA.Tests.Live.ApiRoleTest).RoleJob(..#User, tPassword, ..#Production, ..#Schema, ..#UnusedSchema, ..#Pipeline, ..URL())::10
		do $$$AssertTrue($Test, "role job started")
		for i=1:1:300 { quit:$Data(^IRIS.Temp.OPCUATests("role", "done"))  hang 0.1 }
		do $$$AssertEquals($Get(^IRIS.Temp.OPCUATests("role", "login")), 1, "job logged in as the throwaway user")
		do $$$AssertEquals($Get(^IRIS.Temp.OPCUATests("role", "error")), "", "job raised no error")

		// Every step: OK, or a readable 403, never a 500.
		for tStep = "schemas", "describe", "pipelines", "deleteInUse", "rebind", "deleteUnused", "createSchema", "deploy", "deletePipeline", "dynamicSQL" {
			set tGot = $Get(^IRIS.Temp.OPCUATests("role", tStep))
			set tCode = $ListGet(tGot, 1), tText = $ListGet(tGot, 2)
			do $$$AssertTrue(tGot '= "", tStep_" ran")
			do $$$AssertTrue(tCode '= 500, tStep_" is not a 500: "_tCode_" "_tText)
			do:tCode=403 $$$AssertTrue(tText [ "privilege", tStep_" 403 says which privilege is missing: "_tText)
		}
		// The ones that need no extra privilege must work.
		for tStep = "schemas", "describe", "pipelines", "rebind", "deleteUnused", "createSchema", "deploy", "deletePipeline" {
			do $$$AssertEquals($ListGet($Get(^IRIS.Temp.OPCUATests("role", tStep)), 1), 200, tStep_" works: "_$ListGet($Get(^IRIS.Temp.OPCUATests("role", tStep)), 2))
		}
		set tGot = $Get(^IRIS.Temp.OPCUATests("role", "dynamicSQL"))
		do $$$AssertEquals($ListGet(tGot, 1), 403, "dynamic SQL without the privilege is a 403: "_$ListGet(tGot, 2))
		do $$$AssertTrue($ListGet(tGot, 2) [ ..#User, "and names the account")
		set tGot = $Get(^IRIS.Temp.OPCUATests("role", "deleteInUse"))
		do $$$AssertEquals($ListGet(tGot, 1), 409, "deleting the bound schema is refused as in use: "_$ListGet(tGot, 2))
		do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(..#Schema), "bound schema kept")
		do $$$AssertNotTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#UnusedSchema), "unused schema deleted")
		do $$$AssertNotTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#UnusedSchema_".FolderType"), "and its folder class")
		do $$$AssertTrue($Get(^IRIS.Temp.OPCUATests("role", "listed")), "the schema list shows the schema with its usage")
		do $$$AssertEquals($Get(^IRIS.Temp.OPCUATests("role", "usedBy")), ..#Pipeline, "describe names the pipeline using it")
		do $$$AssertEquals(..ItemSetting(..#Pipeline, "DeviceNodePaths"), "i=85|ObjectsRole", "rebind saved the new device list")
	} Catch (e) {
		do $$$AssertTrue(0, "Exception: "_e.DisplayString())
	}
	do ..DropUser()
	kill ^IRIS.Temp.OPCUATests("role")
}

/// JOB entry: log in as <var>pUser</var>, then record $LB(httpCode, text) per step.
/// A failed login quits the job, so nothing runs with the parent's privileges.
ClassMethod RoleJob(pUser As %String, pPassword As %String, pProduction As %String, pSchema As %String, pUnused As %String, pPipeline As %String, pURL As %String)
{
	set tKey = $Name(^IRIS.Temp.OPCUATests("role"))
	try {
		set tLogin = $System.Security.Login(pUser, pPassword)
		set @tKey@("login") = tLogin
		if 'tLogin {
			set @tKey@("done") = 1
			Quit
		}
		set ^||OPCUA.Tests("production") = pProduction

		set tSC = ##class(OPCUA.REST.SchemaService).List({}, .tList)
		do ..Record(tKey, "schemas", tSC)
		if $$$ISOK(tSC) {
			for i=0:1:tList.%Size()-1 {
				set tItem = tList.%Get(i)
				set:(tItem.schemaClass=pSchema)&&(tItem.usedBy.%Size()=1) @tKey@("listed") = 1
			}
		}
		set tSC = ##class(OPCUA.REST.SchemaService).Get({"className": (pSchema)}, .tOne)
		do ..Record(tKey, "describe", tSC)
		set:$$$ISOK(tSC) @tKey@("usedBy") = tOne.usedBy.%Get(0).name
		set tSC = ##class(OPCUA.REST.PipelineService).List({}, .tPipes)
		do ..Record(tKey, "pipelines", tSC)
		set tSC = ##class(OPCUA.REST.SchemaService).Delete({"className": (pSchema)}, .tResult)
		do ..Record(tKey, "deleteInUse", tSC)
		set tSC = ##class(OPCUA.REST.PipelineService).Rebind({"name": (pPipeline), "devices": "i=85|ObjectsRole"}, .tResult)
		do ..Record(tKey, "rebind", tSC)
		set tSC = ##class(OPCUA.REST.SchemaService).Delete({"className": (pUnused)}, .tResult)
		do ..Record(tKey, "deleteUnused", tSC)
		set tSC = ##class(OPCUA.REST.SchemaService).Create({"className": (pUnused_"Created"), "dataSourceName": "RoleCreated", "defaultNamespace": 1, "columns": [{"displayName": "SA1", "inferredType": "%Integer", "relativePath": ["SA1"], "nodeNs": 1}]}, .tResult)
		do ..Record(tKey, "createSchema", tSC)
		set tSC = ##class(OPCUA.REST.DeployService).Deploy({"schemaClass": (pSchema), "dataSourceName": (pPipeline_"Deployed"), "mode": "polling", "url": (pURL), "devices": "i=85|Objects"}, .tResult)
		do ..Record(tKey, "deploy", tSC)
		set tSC = ##class(OPCUA.REST.PipelineService).Delete({"name": (pPipeline_"Deployed")}, .tResult)
		do ..Record(tKey, "deletePipeline", tSC)
		// Dynamic SQL on a schema table it has no SELECT privilege for: a 403.
		try {
			do ##class(OPCUA.Utils).ExecQuery("SELECT COUNT(*) FROM "_##class(OPCUA.REST.SchemaService).TableName(pSchema))
			set tSC = $$$OK
		} catch eQuery {
			set tSC = eQuery.AsStatus()
		}
		do ..Record(tKey, "dynamicSQL", tSC)
	} catch e {
		set @tKey@("error") = e.DisplayString()
	}
	set @tKey@("done") = 1
}

ClassMethod Record(pKey As %String, pStep As %String, pSC As %Status) [ Private ]
{
	set @pKey@(pStep) = $ListBuild(##class(OPCUA.REST.Error).HttpCode(pSC), ##class(OPCUA.REST.Error).Text(pSC))
}

// ==================== helpers ====================

ClassMethod URL() As %String
{
	Quit $Get(^||OPCUA.Tests("url"), "opc.tcp://plc")
}

ClassMethod ItemSetting(pName As %String, pSetting As %String) As %String
{
	set tProd = ##class(Ens.Config.Production).%OpenId(..#Production, 0)
	Quit:'$IsObject(tProd) ""
	do tProd.%Reload()
	set tItem = ##class(OPCUA.REST.ProductionEdit).FindItem(tProd, pName)
	Quit:'$IsObject(tItem) ""
	do tItem.%Reload()
	for i=1:1:tItem.Settings.Count() {
		if tItem.Settings.GetAt(i).Name = pSetting Return tItem.Settings.GetAt(i).Value
	}
	Quit ""
}

/// A one-column schema the plc's Objects folder resolves (SA1). With
/// <var>pFolder</var>, also a serial folder class, as nested schemas have.
ClassMethod BuildSchema(pClass As %String, pFolder As %Boolean) As %Status
{
	if pFolder {
		set tSerial = ##class(%Dictionary.ClassDefinition).%New(pClass_".FolderType")
		set tSerial.Super = "%SerialObject"
		set tSerial.PropertyClass = "OPCUA.DataSource.PropertyClass"
		set tSerial.Description = "Throwaway folder class for ApiRoleTest"
		set tProp = ##class(%Dictionary.PropertyDefinition).%New()
		set tProp.Name = "SA2", tProp.Type = "OPCUA.Types.IntegerDataValue"
		do tProp.Parameters.SetAt("SA2", "OPCUANODENAME")
		do tSerial.Properties.Insert(tProp)
		set tSC = tSerial.%Save()
		Quit:$$$ISERR(tSC) tSC
		set tSC = $System.OBJ.Compile(pClass_".FolderType", "ck-d")
		Quit:$$$ISERR(tSC) tSC
	}
	set tDef = ##class(%Dictionary.ClassDefinition).%New(pClass)
	set tDef.Description = "Throwaway schema for ApiRoleTest"
	set tDef.Super = "%Persistent,OPCUA.DataSource.DeviceSchema"
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUADATASOURCE", tParam.Default = $Piece(pClass, ".", *)
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
	if pFolder {
		set tProp = ##class(%Dictionary.PropertyDefinition).%New()
		set tProp.Name = "Folder", tProp.Type = pClass_".FolderType"
		do tDef.Properties.Insert(tProp)
	}
	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC
	Quit $System.OBJ.Compile(pClass, "ck-d")
}

/// The throwaway role grants what the installer's OPCUA_API_&lt;NS&gt; role grants:
/// the API resource :U and the namespace database :RW. The API resource is made
/// only when it is missing, and then removed again by <method>Cleanup</method>.
ClassMethod CreateUser(Output pPassword As %String) As %Status
{
	New $Namespace
	set tDbResource = ##class(OPCUA.Tests.Unit.CredentialsTest).DatabaseResource()
	set pPassword = "Tmp-"_$Translate($System.Encryption.Base64Encode($System.Encryption.GenCryptRand(18)), "+/=", "xyz")
	set $Namespace = "%SYS"
	do ..DropUserInSys()
	if '##class(Security.Resources).Exists(..#ApiResource) {
		set tSC = ##class(Security.Resources).Create(..#ApiResource, "Created by OPCUA.Tests.Live.ApiRoleTest", "")
		Quit:$$$ISERR(tSC) tSC
		set ^IRIS.Temp.OPCUATests("roleResource") = 1
	}
	set tSC = ##class(Security.Roles).Create(..#Role, "Throwaway role for OPCUA.Tests.Live.ApiRoleTest", ..#ApiResource_":U,"_tDbResource_":RW")
	Quit:$$$ISERR(tSC) tSC
	Quit ##class(Security.Users).Create(..#User, ..#Role, pPassword, "Throwaway user for OPCUA.Tests.Live.ApiRoleTest")
}

ClassMethod DropUser()
{
	New $Namespace
	set $Namespace = "%SYS"
	do ..DropUserInSys()
}

ClassMethod DropUserInSys() [ Private ]
{
	do:##class(Security.Users).Exists(..#User) ##class(Security.Users).Delete(..#User)
	do:##class(Security.Roles).Exists(..#Role) ##class(Security.Roles).Delete(..#Role)
	if $Get(^IRIS.Temp.OPCUATests("roleResource")) {
		do:##class(Security.Resources).Exists(..#ApiResource) ##class(Security.Resources).Delete(..#ApiResource)
		kill ^IRIS.Temp.OPCUATests("roleResource")
	}
}

/// Remove the throwaway user, role, production and schemas. Every name is test-only.
ClassMethod Cleanup()
{
	do ..DropUser()
	kill ^IRIS.Temp.OPCUATests("role")
	set tProd = ..#Production
	&sql(DELETE FROM Ens_Config.Item WHERE Production = :tProd)
	do:##class(Ens.Config.Production).%ExistsId(tProd) ##class(Ens.Config.Production).%DeleteId(tProd)
	do:##class(%Dictionary.ClassDefinition).%ExistsId(tProd) $System.OBJ.Delete(tProd, "-d")
	for tClass = ..#Schema, ..#UnusedSchema, ..#UnusedSchema_"Created" {
		if ##class(%Dictionary.ClassDefinition).%ExistsId(tClass) {
			Try { do $classmethod(tClass, "%KillExtent") } Catch {}
			do $System.OBJ.Delete(tClass, "-d")
		}
		do:##class(%Dictionary.ClassDefinition).%ExistsId(tClass_".FolderType") $System.OBJ.Delete(tClass_".FolderType", "-d")
		kill ^OPCUA.DataSource(tClass)
	}
}

}
