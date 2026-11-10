Include (%occInclude, Ensemble)

/// Offline tests for <class>OPCUA.REST.CredentialsService</class> (<tt>/credentials</tt>)
/// and for <tt>credentials</tt> in
/// <method>OPCUA.REST.ClientManager.ExtractConnectionParams</method>: the console's OPC UA
/// passwords live in IRIS credentials entries, and no response ever carries one.
///
/// Uses entries prefixed <tt>OPCUA.Tests.Svc</tt> and a throwaway production,
/// <tt>OPCUA.Tests.Tmp.CredSvcProduction</tt>, that is never started, holding one item
/// whose Credentials setting names an entry.
Class OPCUA.Tests.Unit.CredentialsServiceTest Extends %UnitTest.TestCase
{

Parameter Production = "OPCUA.Tests.Tmp.CredSvcProduction";

Parameter Entry = "OPCUA.Tests.SvcCred";

Parameter Password = "s3cretSvcTest";

Method OnBeforeAllTests() As %Status
{
	do ..Cleanup()
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#Production)
	set tDef.Super = "Ens.Production"
	set tDef.Description = "Throwaway production for CredentialsServiceTest. Never started."
	set tX = ##class(%Dictionary.XDataDefinition).%New()
	set tX.Name = "ProductionDefinition"
	do tX.Data.Write("<Production Name="""_..#Production_"""><Item Name=""TmpCredSvcItem"" ClassName=""OPCUA.Service.TCPPollingRowSourceService"" Enabled=""false""><Setting Target=""Adapter"" Name=""Credentials"">"_$ZConvert(..#Entry, "U")_"</Setting></Item></Production>")
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
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	do ..DropEntries()
	Quit $$$OK
}

/// Create stores username and password; List shows the entry, who uses it (matched in
/// any case, as Ens matches IDs) and nothing that looks like a password.
Method TestCreateAndList()
{
	set tSC = ##class(OPCUA.REST.CredentialsService).Create({"id": (..#Entry), "username": "opcuser", "password": (..#Password)}, .tResult)
	do $$$AssertStatusOK(tSC, "create")
	do $$$AssertEquals(tResult.id, ..#Entry, "create returns the ID")
	do $$$AssertNotTrue(tResult.%ToJSON() [ ..#Password, "create does not echo the password")
	set tCred = ##class(Ens.Config.Credentials).%OpenId(..#Entry)
	do $$$AssertTrue($IsObject(tCred) && (tCred.Username = "opcuser") && (tCred.Password = ..#Password), "entry holds username and password")

	do $$$AssertStatusOK(##class(OPCUA.REST.CredentialsService).List(.tList), "list")
	set tJSON = tList.%ToJSON()
	do $$$AssertNotTrue(tJSON [ ..#Password, "list carries no password")
	set tFound = ""
	for i=0:1:tList.%Size()-1 { set:tList.%Get(i).id=..#Entry tFound = tList.%Get(i) }
	do $$$AssertTrue($IsObject(tFound), "list includes the entry")
	Quit:'$IsObject(tFound)
	do $$$AssertEquals(tFound.username, "opcuser", "list shows the username")
	do $$$AssertNotTrue(tFound.%IsDefined("password"), "no password field")
	do $$$AssertEquals(tFound.usedBy.%Size(), 1, "one user: "_tFound.usedBy.%ToJSON())
	do $$$AssertTrue(tFound.usedBy.%Get(0) [ "TmpCredSvcItem", "usedBy names the item: "_tFound.usedBy.%ToJSON())
	do $$$AssertEquals(tFound.pipeline, "", "not made by deploy")
}

/// A taken ID, in any case, is 409 and leaves the entry alone; unusable IDs and a
/// missing username are 400.
Method TestCreateRefusals()
{
	do $$$AssertStatusOK(##class(OPCUA.REST.CredentialsService).Create({"id": (..#Entry), "username": "opcuser", "password": (..#Password)}, .tResult), "create")
	set tSC = ##class(OPCUA.REST.CredentialsService).Create({"id": ($ZConvert(..#Entry, "L")), "username": "other", "password": "other"}, .tResult)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 409, "taken ID in another case is 409: "_##class(OPCUA.REST.Error).Text(tSC))
	do $$$AssertEquals(##class(Ens.Config.Credentials).%OpenId(..#Entry).Password, ..#Password, "entry unchanged")

	for tBad = "", "has space", "a|b", $Translate($Justify("", 51), " ", "x"), "none", "NONE" {
		set tSC = ##class(OPCUA.REST.CredentialsService).Create({"id": (tBad), "username": "u"}, .tResult)
		do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "ID '"_tBad_"' is 400: "_##class(OPCUA.REST.Error).Text(tSC))
	}
	set tSC = ##class(OPCUA.REST.CredentialsService).Create({"id": (..#Entry_"2"), "password": "p"}, .tResult)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "no username is 400")
	do $$$AssertNotTrue(##class(Ens.Config.Credentials).%ExistsId(..#Entry_"2"), "and creates nothing")
}

/// Update changes what it is given and keeps the rest: no password keeps the stored
/// one, a new one replaces it. An empty username is 400, an unknown ID 404.
Method TestUpdate()
{
	do $$$AssertStatusOK(##class(OPCUA.REST.CredentialsService).Create({"id": (..#Entry), "username": "opcuser", "password": (..#Password)}, .tResult), "create")

	do $$$AssertStatusOK(##class(OPCUA.REST.CredentialsService).Update($ZConvert(..#Entry, "L"), {"username": "renamed"}, .tResult), "update username, ID in another case")
	set tCred = ##class(Ens.Config.Credentials).%OpenId(..#Entry)
	do $$$AssertEquals(tCred.Username, "renamed", "username changed")
	do $$$AssertEquals(tCred.Password, ..#Password, "password kept")
	kill tCred

	do $$$AssertStatusOK(##class(OPCUA.REST.CredentialsService).Update(..#Entry, {"password": ""}, .tResult), "empty password")
	do $$$AssertEquals(##class(Ens.Config.Credentials).%OpenId(..#Entry).Password, ..#Password, "empty password keeps the stored one")

	do $$$AssertStatusOK(##class(OPCUA.REST.CredentialsService).Update(..#Entry, {"password": "changed"}, .tResult), "update password")
	set tCred = ##class(Ens.Config.Credentials).%OpenId(..#Entry)
	do $$$AssertTrue((tCred.Password = "changed") && (tCred.Username = "renamed"), "password changed, username kept")
	do $$$AssertNotTrue(tResult.%ToJSON() [ "changed", "update does not echo the password")
	kill tCred

	set tSC = ##class(OPCUA.REST.CredentialsService).Update(..#Entry, {"username": ""}, .tResult)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "empty username is 400")
	set tSC = ##class(OPCUA.REST.CredentialsService).Update("OPCUA.Tests.SvcNoSuch", {"username": "u"}, .tResult)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 404, "unknown ID is 404")
}

/// <tt>credentials</tt> resolves to the entry's username and password on the server;
/// inline username and password still work; both together, or an unknown ID, are 400.
Method TestConnectionParams()
{
	do $$$AssertStatusOK(##class(OPCUA.REST.CredentialsService).Create({"id": (..#Entry), "username": "opcuser", "password": (..#Password)}, .tResult), "create")
	set tURL = "opc.tcp://nowhere.invalid:4840"

	set tSC = ##class(OPCUA.REST.ClientManager).ExtractConnectionParams({"url": (tURL), "credentials": (..#Entry)}, .tU, .tM, .tUser, .tPass)
	do $$$AssertStatusOK(tSC, "credentials resolve")
	do $$$AssertTrue((tUser = "opcuser") && (tPass = ..#Password), "to the entry's username and password")

	set tSC = ##class(OPCUA.REST.ClientManager).ExtractConnectionParams({"url": (tURL), "username": "inline", "password": "pw"}, .tU, .tM, .tUser, .tPass)
	do $$$AssertTrue($$$ISOK(tSC) && (tUser = "inline") && (tPass = "pw"), "inline username and password pass through")

	set tSC = ##class(OPCUA.REST.ClientManager).ExtractConnectionParams({"url": (tURL)}, .tU, .tM, .tUser, .tPass)
	do $$$AssertTrue($$$ISOK(tSC) && (tUser = "") && (tPass = ""), "neither is anonymous")

	set tSC = ##class(OPCUA.REST.ClientManager).ExtractConnectionParams({"url": (tURL), "credentials": (..#Entry), "username": "inline"}, .tU, .tM, .tUser, .tPass)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "both is 400")

	set tSC = ##class(OPCUA.REST.ClientManager).ExtractConnectionParams({"url": (tURL), "credentials": "OPCUA.Tests.SvcNoSuch"}, .tU, .tM, .tUser, .tPass)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "unknown ID is 400")
	do $$$AssertTrue(##class(OPCUA.REST.Error).Text(tSC) [ "OPCUA.Tests.SvcNoSuch", "and names it")
}

ClassMethod DropEntries()
{
	for tId = ..#Entry, ..#Entry_"2" {
		do:##class(Ens.Config.Credentials).%ExistsId(tId) ##class(Ens.Config.Credentials).%DeleteId(tId)
	}
}

ClassMethod Cleanup()
{
	do ..DropEntries()
	set tProd = ..#Production
	&sql(DELETE FROM Ens_Config.Item WHERE Production = :tProd)
	do:##class(Ens.Config.Production).%ExistsId(tProd) ##class(Ens.Config.Production).%DeleteId(tProd)
	do:##class(%Dictionary.ClassDefinition).%ExistsId(tProd) $System.OBJ.Delete(tProd, "-d")
}

}
