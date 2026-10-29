Include (%occInclude, Ensemble)

/// Offline tests for audit #15: OPC UA passwords live in IRIS credentials
/// entries, never in production settings, and deploy only ever creates, and
/// pipeline delete only ever removes, an entry that deploy itself created.
///
/// Works on a throwaway production, <tt>OPCUA.Tests.Tmp.CredProduction</tt>, that
/// is never started. <tt>^||OPCUA.Tests("production")</tt> points
/// <class>OPCUA.REST.ProductionEdit</class> at it. Items are added with
/// <method>OPCUA.REST.DeployService.AddServiceItem</method>, the part of deploy
/// after the device coverage check, which needs no OPC UA server.
Class OPCUA.Tests.Unit.CredentialsTest Extends %UnitTest.TestCase
{

Parameter Production = "OPCUA.Tests.Tmp.CredProduction";

Parameter Schema = "OPCUA.Tests.Tmp.CredSchema";

/// A credentials entry standing in for one the client made themselves.
Parameter ClientEntry = "OPCUA.Tests.ClientCred";

Parameter Password = "s3cretCredTest";

Method OnBeforeAllTests() As %Status
{
	do ..Cleanup()
	set tSC = ..CreateSchema()
	Quit:$$$ISERR(tSC) tSC
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#Production)
	set tDef.Super = "Ens.Production"
	set tDef.Description = "Throwaway production for CredentialsTest. Never started."
	set tX = ##class(%Dictionary.XDataDefinition).%New()
	set tX.Name = "ProductionDefinition"
	do tX.Data.Write("<Production Name="""_..#Production_"""></Production>")
	do tDef.XDatas.Insert(tX)
	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC
	set tSC = $System.OBJ.Compile(..#Production, "ck-d")
	Quit:$$$ISERR(tSC) tSC
	Quit ##class(Ens.Config.Production).LoadFromClass(..#Production)
}

Method OnAfterAllTests() As %Status
{
	do ..Cleanup()
	kill ^||OPCUA.Tests("production")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	set ^||OPCUA.Tests("production") = ..#Production
	Quit $$$OK
}

/// Review Focus 1: a pipeline name with a space, a dot and a hyphen, and names
/// at the 128-character item-name limit, all map to a credentials ID that
/// <tt>SetCredential</tt> accepts. Long names that differ only at the end stay
/// distinct.
Method TestCredentialsIdSanitised()
{
	set tLong = $Translate($Justify("", 120), " ", "x")
	for tName = "Line 3.Press-A", "Ünïcode/Pipe'Quote""", tLong_"-one", tLong_"-two" {
		set tId = ##class(OPCUA.REST.DeployService).CredentialsId(tName)
		do $$$AssertEquals($Extract(tId, 1, 6), "OPCUA-", "ID '"_tId_"' starts with OPCUA-")
		do $$$AssertTrue($Length(tId) <= 50, "ID '"_tId_"' fits SystemName's MAXLEN")
		do $$$AssertTrue(tId '[ "||", "ID '"_tId_"' has no ID-key separator")
		do:##class(Ens.Config.Credentials).%ExistsId(tId) ##class(Ens.Config.Credentials).%DeleteId(tId)
		do $$$AssertStatusOK(##class(Ens.Config.Credentials).SetCredential(tId, "u", "p", 0), "SetCredential accepts '"_tId_"'")
		do ##class(Ens.Config.Credentials).%DeleteId(tId)
	}
	do $$$AssertEquals(##class(OPCUA.REST.DeployService).CredentialsId("Line 3.Press-A"), "OPCUA-Line_3.Press-A", "space replaced, dot and hyphen kept")
	do $$$AssertNotEquals(##class(OPCUA.REST.DeployService).CredentialsId(tLong_"-one"), ##class(OPCUA.REST.DeployService).CredentialsId(tLong_"-two"), "long names stay distinct")
}

/// Deploying with a username and password writes no password into the
/// production class. The item carries a Credentials setting naming an entry
/// that holds them, and the entry is recorded as ours.
Method TestNoPlainPasswordInProductionClass()
{
	set tName = "TmpCredA"
	set tId = ##class(OPCUA.REST.DeployService).CredentialsId(tName)
	set tSC = ..Add(tName, {"username": "opcuser", "password": (..#Password)})
	do $$$AssertStatusOK(tSC, "deploy with username + password")
	Quit:$$$ISERR(tSC)

	set tXml = ..ProductionXml()
	do $$$AssertTrue(tXml '[ ..#Password, "production class has no password")
	do $$$AssertTrue(tXml '[ "Name=""Password""", "production class has no Password setting")
	do $$$AssertTrue(tXml [ ("Name=""Credentials"">"_tId_"<"), "production class names the credentials entry: "_tXml)

	set tCred = ##class(Ens.Config.Credentials).%OpenId(tId)
	do $$$AssertTrue($IsObject(tCred), "credentials entry "_tId_" exists")
	Quit:'$IsObject(tCred)
	do $$$AssertEquals(tCred.Username, "opcuser", "entry username")
	do $$$AssertTrue(tCred.Password = ..#Password, "entry password")
	do $$$AssertEquals($Get(^OPCUA.OwnedCredentials(tId)), tName, "entry recorded as created by this pipeline")
}

/// A credentials ID that is already taken is never overwritten: deploy refuses
/// with 409, adds no item, and the entry keeps its username and password.
Method TestExistingIdNeverOverwritten()
{
	set tName = "TmpCred"
	set tId = ##class(OPCUA.REST.DeployService).CredentialsId(tName)
	do $$$AssertEquals(tId, "OPCUA-TmpCred", "ID for TmpCred")
	do $$$AssertStatusOK(##class(Ens.Config.Credentials).SetCredential(tId, "clientuser", "clientpw", 0), "client's own entry")

	set tSC = ..Add(tName, {"username": "opcuser", "password": (..#Password)})
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 409, "taken ID refused with 409: "_##class(OPCUA.REST.Error).Text(tSC))

	set tCred = ##class(Ens.Config.Credentials).%OpenId(tId)
	do $$$AssertTrue($IsObject(tCred), "client's entry still exists")
	Quit:'$IsObject(tCred)
	do $$$AssertEquals(tCred.Username, "clientuser", "username unchanged")
	do $$$AssertTrue(tCred.Password = "clientpw", "password unchanged")
	do $$$AssertEquals($Data(^OPCUA.OwnedCredentials(tId)), 0, "not recorded as ours")
	do $$$AssertNotTrue(..ItemExists(tName), "no item added")
}

/// Pipeline delete removes the entry deploy created, and leaves alone one the
/// pipeline merely pointed at, even when that entry has the pipeline's own
/// credentials ID.
Method TestDeleteRemovesOnlyOwned()
{
	set tIdA = ##class(OPCUA.REST.DeployService).CredentialsId("TmpCredOwned")
	set tIdB = ##class(OPCUA.REST.DeployService).CredentialsId("TmpCredShared")
	do $$$AssertStatusOK(##class(Ens.Config.Credentials).SetCredential(..#ClientEntry, "clientuser", "clientpw", 0), "client entry")
	do $$$AssertStatusOK(##class(Ens.Config.Credentials).SetCredential(tIdB, "clientuser", "clientpw", 0), "client entry with B's ID")

	do $$$AssertStatusOK(..Add("TmpCredOwned", {"username": "opcuser", "password": (..#Password)}), "deploy A with username")
	do $$$AssertStatusOK(..Add("TmpCredShared", {"credentials": (tIdB)}), "deploy B with credentials")
	do $$$AssertStatusOK(..Add("TmpCredClient", {"credentials": (..#ClientEntry)}), "deploy C with credentials")
	do $$$AssertTrue(..ProductionXml() [ ("Name=""Credentials"">"_..#ClientEntry_"<"), "C carries the given credentials ID")

	for tName = "TmpCredOwned", "TmpCredShared", "TmpCredClient" {
		do $$$AssertStatusOK(##class(OPCUA.REST.PipelineService).Delete({"name": (tName)}, .tResult), "delete "_tName)
	}
	do $$$AssertNotTrue(##class(Ens.Config.Credentials).%ExistsId(tIdA), "A's own entry deleted")
	do $$$AssertEquals($Data(^OPCUA.OwnedCredentials(tIdA)), 0, "A's ownership marker removed")
	do $$$AssertTrue(##class(Ens.Config.Credentials).%ExistsId(tIdB), "entry with B's ID survives")
	do $$$AssertTrue(##class(Ens.Config.Credentials).%ExistsId(..#ClientEntry), "client entry survives")
}

/// Review Focus 5. With neither username nor credentials, deploy sets no
/// Credentials setting and creates no entry. With a username alone, it creates
/// an entry with an empty password.
Method TestAnonymousAndUserOnly()
{
	set tIdAnon = ##class(OPCUA.REST.DeployService).CredentialsId("TmpCredAnon")
	do $$$AssertStatusOK(..Add("TmpCredAnon", {}), "anonymous deploy")
	do $$$AssertNotTrue(##class(Ens.Config.Credentials).%ExistsId(tIdAnon), "no entry for an anonymous pipeline")
	do $$$AssertEquals(..ItemSetting("TmpCredAnon", "Credentials"), "", "no Credentials setting")

	set tIdUser = ##class(OPCUA.REST.DeployService).CredentialsId("TmpCredUser")
	do $$$AssertStatusOK(..Add("TmpCredUser", {"username": "opcuser"}), "username-only deploy")
	set tCred = ##class(Ens.Config.Credentials).%OpenId(tIdUser)
	do $$$AssertTrue($IsObject(tCred), "entry created for a username-only pipeline")
	Quit:'$IsObject(tCred)
	do $$$AssertEquals(tCred.Username, "opcuser", "entry username")
	do $$$AssertTrue(tCred.Password = "", "entry password is empty")
	do $$$AssertEquals(..ItemSetting("TmpCredUser", "Credentials"), tIdUser, "Credentials setting names it")
}

/// An unknown credentials ID is a 400 naming it, raised before any connection
/// is tried (the URL points nowhere). Sending both credentials and a username is
/// ambiguous, and is a 400 too.
Method TestUnknownCredentialsIs400()
{
	set tBody = {"schemaClass": (..#Schema), "dataSourceName": "TmpCredUnknown", "url": "opc.tcp://nowhere.invalid:4840", "devices": "i=85", "credentials": "OPCUA.Tests.NoSuchEntry"}
	set tSC = ##class(OPCUA.REST.DeployService).Deploy(tBody, .tResult)
	set tText = ##class(OPCUA.REST.Error).Text(tSC)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "unknown credentials refused with 400: "_tText)
	do $$$AssertTrue(tText [ "OPCUA.Tests.NoSuchEntry", "error names the ID: "_tText)

	do $$$AssertStatusOK(##class(Ens.Config.Credentials).SetCredential(..#ClientEntry, "clientuser", "clientpw", 1), "client entry")
	do tBody.%Set("credentials", ..#ClientEntry), tBody.%Set("username", "opcuser")
	set tSC = ##class(OPCUA.REST.DeployService).Deploy(tBody, .tResult)
	set tText = ##class(OPCUA.REST.Error).Text(tSC)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "credentials + username refused with 400: "_tText)
	do $$$AssertTrue(tText [ "credentials", "error explains: "_tText)
}

// ==================== helpers ====================

ClassMethod Add(pName As %String, pBody As %DynamicObject) As %Status
{
	do pBody.%Set("url", "opc.tcp://plc")
	Quit ##class(OPCUA.REST.DeployService).AddServiceItem(pBody, ..#Schema, pName, "polling", "i=85")
}

ClassMethod ProductionXml() As %String
{
	set tX = ##class(%Dictionary.XDataDefinition).%OpenId(..#Production_"||ProductionDefinition")
	Quit:'$IsObject(tX) ""
	do tX.Data.Rewind()
	Quit tX.Data.Read(3000000)
}

ClassMethod ItemExists(pName As %String) As %Boolean
{
	set tProd = ##class(Ens.Config.Production).%OpenId(..#Production, 0)
	Quit:'$IsObject(tProd) 0
	Quit $IsObject(##class(OPCUA.REST.ProductionEdit).FindItem(tProd, pName))
}

ClassMethod ItemSetting(pName As %String, pSetting As %String) As %String
{
	set tProd = ##class(Ens.Config.Production).%OpenId(..#Production, 0)
	Quit:'$IsObject(tProd) ""
	set tItem = ##class(OPCUA.REST.ProductionEdit).FindItem(tProd, pName)
	Quit:'$IsObject(tItem) ""
	for i=1:1:tItem.Settings.Count() {
		if tItem.Settings.GetAt(i).Name = pSetting Return tItem.Settings.GetAt(i).Value
	}
	Quit ""
}

ClassMethod CreateSchema() As %Status
{
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#Schema)
	set tDef.Super = "OPCUA.DataSource.DeviceSchema,%Persistent"
	set tDef.Description = "Throwaway schema for CredentialsTest"
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUADATASOURCE"
	set tParam.Default = "TmpCred"
	do tDef.Parameters.Insert(tParam)
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUDEFAULTANAMESPACE"
	set tParam.Default = "1"
	do tDef.Parameters.Insert(tParam)
	set tProp = ##class(%Dictionary.PropertyDefinition).%New()
	set tProp.Name = "Temperature"
	set tProp.Type = "OPCUA.Types.DoubleDataValue"
	do tProp.Parameters.SetAt("Temperature", "OPCUANODENAME")
	do tDef.Properties.Insert(tProp)
	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC
	Quit $System.OBJ.Compile(..#Schema, "ck-d")
}

/// Remove the throwaway production, schema, and every credentials entry and
/// ownership marker these tests use. Every name here is test-only.
ClassMethod Cleanup()
{
	set tProd = ..#Production
	&sql(DELETE FROM Ens_Config.Item WHERE Production = :tProd)
	do:##class(Ens.Config.Production).%ExistsId(tProd) ##class(Ens.Config.Production).%DeleteId(tProd)
	do:##class(%Dictionary.ClassDefinition).%ExistsId(tProd) $System.OBJ.Delete(tProd, "-d")
	if ##class(%Dictionary.ClassDefinition).%ExistsId(..#Schema) {
		Try { do $classmethod(..#Schema, "%KillExtent") } Catch {}
		do $System.OBJ.Delete(..#Schema, "-d")
	}
	kill ^OPCUA.DataSource(..#Schema)
	set tIds = $LB(..#ClientEntry)
	for tName = "TmpCred", "TmpCredA", "TmpCredOwned", "TmpCredShared", "TmpCredClient", "TmpCredAnon", "TmpCredUser", "TmpCredUnknown" {
		set tId = "OPCUA-"_tName
		Try { set tId = ##class(OPCUA.REST.DeployService).CredentialsId(tName) } Catch {}
		set tIds = tIds_$LB(tId)
	}
	set tPtr = 0
	while $ListNext(tIds, tPtr, tId) {
		do:##class(Ens.Config.Credentials).%ExistsId(tId) ##class(Ens.Config.Credentials).%DeleteId(tId)
		kill ^OPCUA.OwnedCredentials(tId)
	}
}

}
