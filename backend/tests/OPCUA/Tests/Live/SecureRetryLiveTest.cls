Include (%occInclude, Ensemble)

/// A managed Sign & Encrypt pipeline whose server is not trusted yet must not fail to
/// start: the adapter logs the refusal, stays fail-closed (no native connect) and keeps
/// retrying, and starts getting further once the server has been reviewed and trusted.
/// Runs against a redirected test store (^%OPCUA.Security.Override) so the instance's own
/// identity and trust are never touched. The certified-server does not trust the test
/// identity, so after trusting, the adapter reaches the connect stage and is diagnosed
/// clientNotApproved: proof that Setup was re-resolved without a production restart.
Class OPCUA.Tests.Live.SecureRetryLiveTest Extends %UnitTest.TestCase
{

Parameter URL = "opc.tcp://certified-server:4840";

Parameter Schema = "OPCUA.Tests.Tmp.RetrySchema";

Parameter Pipeline = "TmpRetrySecure";

Parameter Work = "/tmp/opcua-retry/";

Parameter Store = "^%OPCUA.SecurityRetry";

Parameter Fixtures = "/tmp/opcua-dev/fixtures/certified-server/";

Method TestUntrustedServerKeepsRetrying()
{
	If '##class(OPCUA.Utils).SupportsPki() {
		Do $$$AssertSkipped("connector 0.5 PKI is not available")
		Quit
	}
	If '##class(%File).Exists(..#Fixtures_"myCA.crt.der") {
		Do $$$AssertSkipped("certified-server CA fixtures missing (run demo/iris/dev-load.sh)")
		Quit
	}
	Set tProd = ##class(OPCUA.REST.DeployService).#ProductionClass
	Set tExisted = ##class(%Dictionary.ClassDefinition).%ExistsId(tProd)
	Do ##class(Ens.Director).GetProductionStatus(.tName, .tState)
	Set tWasRunning = ((tName = tProd) && (tState = 1))
	Try {
		Do ..RemoveEverything()
		Do ##class(%File).CreateDirectoryChain(..#Work)
		Set ^%OPCUA.Security.Override("global") = ..#Store
		Set ^%OPCUA.Security.Override("root") = ..#Work_"pki"
		Set tSC = ##class(OPCUA.Security.Identity).Create("", 0, "", .tStatus)
		Do $$$AssertStatusOK(tSC, "identity created")
		Quit:$$$ISERR(tSC)

		If 'tExisted Do ##class(OPCUA.REST.DeployService).EnsureProductionExists()
		Set tSC = ..BuildSchema()
		Do $$$AssertStatusOK(tSC, "schema generated")
		Quit:$$$ISERR(tSC)
		Set tSC = ##class(OPCUA.REST.DeployService).AddServiceItem({"url": (..#URL), "securityMode": 3, "callInterval": 1}, ..#Schema, ..#Pipeline, "polling", "ns=1;i=50000|Demo")
		Do $$$AssertStatusOK(tSC, "managed pipeline item added")
		Quit:$$$ISERR(tSC)
		Set ^||OPCUA.Tests("retryStart") = $ZDateTime($ZTimeStamp, 3)
		Set tSC = ##class(OPCUA.REST.PipelineService).Toggle({"name": (..#Pipeline)}, .tToggle)
		Do $$$AssertStatusOK(tSC, "pipeline enabled")
		Quit:$$$ISERR(tSC)

		// Not trusted: refused and logged, but the item is alive and keeps retrying.
		Do $$$AssertTrue(..WaitLog("is not ready, will retry", 1, 40), "the refusal is logged")
		Do $$$AssertTrue(..WaitLog("does not trust this OPC UA server yet", 1, 5), "and names the cause")
		Hang 5
		Do $$$AssertEquals(..LogCount("initialization failed"), 0, "the item did not fail to initialise")
		Do $$$AssertTrue(..Jobs() > 0, "the item still has a running job (monitor status "_..HostStatus()_")")
		Do $$$AssertEquals(..LogCount("connection failed (clientNotApproved)"), 0, "no native connect was attempted")

		// Review and trust the server, add its issuer: the next attempt resolves.
		Set tSC = ##class(OPCUA.Security.Trust).Inspect(..#URL, .tInspect)
		Do $$$AssertStatusOK(tSC, "server inspected")
		Quit:$$$ISERR(tSC)
		Set tSC = ##class(OPCUA.Security.Trust).Trust(..#URL, tInspect.certificate.sha256, "Retry test", .tTrust)
		Do $$$AssertStatusOK(tSC, "server trusted")
		Set tSC = ##class(OPCUA.Security.Trust).AddIssuer(..#URL, ..Hex(..#Fixtures_"myCA.crt.der"), ..Hex(..#Fixtures_"myCA.crl"), .tIssuer)
		Do $$$AssertStatusOK(tSC, "issuer added")
		Do $$$AssertTrue(..WaitLog("connection failed (clientNotApproved)", 1, 60), "the adapter reaches the connect stage by itself: IRIS is not approved by the server")
		Do $$$AssertEquals(..LogCount("initialization failed"), 0, "still never failed to initialise")
	} Catch (e) {
		Do $$$AssertFailure("raised "_e.DisplayString())
	}
	Do ..RemoveEverything()
	If 'tWasRunning Try { Do ##class(Ens.Director).StopProduction(10, 1) } Catch {}
	If 'tExisted {
		Try {
			If ##class(Ens.Config.Production).%ExistsId(tProd) Do ##class(Ens.Config.Production).%DeleteId(tProd)
			If ##class(%Dictionary.ClassDefinition).%ExistsId(tProd) Do $System.OBJ.Delete(tProd, "-d")
		} Catch {}
	}
	Do $$$AssertNotTrue($Data(^%OPCUA.Security.Override), "overrides removed")
}

ClassMethod RemoveEverything()
{
	Try {
		Set tItem = ..#Pipeline
		&sql(SELECT COUNT(*) INTO :tN FROM Ens_Config.Item WHERE Name = :tItem)
		If tN { Do ##class(OPCUA.REST.PipelineService).Delete({"name": (tItem)}, .tR) }
	} Catch {}
	Try {
		If ##class(%Dictionary.ClassDefinition).%ExistsId(..#Schema) {
			Set tSC = ##class(OPCUA.REST.SchemaService).Delete({"className": (..#Schema)}, .tR)
			If $$$ISERR(tSC) {
				Try { Do $ClassMethod(..#Schema, "%KillExtent") } Catch {}
				Do $System.OBJ.Delete(..#Schema, "-d")
			}
		}
	} Catch {}
	Kill ^OPCUA.DataSource(..#Schema)
	Kill ^%OPCUA.Security.Override
	Set tStore = ..#Store
	Kill @tStore
	Do ##class(%File).RemoveDirectoryTree(..#Work)
}

ClassMethod BuildSchema() As %Status
{
	Set tCols = [
		{"displayName": "Double", "inferredType": "%Double", "relativePath": ["Scalar", "Double"]}]
	Quit ##class(OPCUA.REST.SchemaService).GenerateSchemaClass(..#Schema, "TmpRetry", tCols, 1, .tColNS, .tSerial)
}

ClassMethod Hex(pPath As %String) As %String
{
	Set s = ##class(%Stream.FileBinary).%New()
	Do s.LinkToFile(pPath)
	Set tHex = ""
	While 's.AtEnd {
		Set c = s.Read(2000)
		For i = 1:1:$Length(c) Set tHex = tHex_$ZHex($Ascii(c, i)\16)_$ZHex($Ascii(c, i)#16)
	}
	Quit tHex
}

ClassMethod HostStatus() As %String
{
	Quit $$$GetHostMonitor(..#Pipeline, $$$eMonitorStatus)
}

ClassMethod Jobs() As %Integer
{
	Set tRS = ##class(%ResultSet).%New("Ens.Job:Enumerate")
	Do tRS.Execute()
	Set tN = 0
	While tRS.Next() { If tRS.Get("ConfigName") = ..#Pipeline Set tN = tN + 1 }
	Quit tN
}

ClassMethod LogCount(pText As %String) As %Integer
{
	Set tItem = ..#Pipeline, tStart = $Get(^||OPCUA.Tests("retryStart"))
	&sql(SELECT COUNT(*) INTO :tN FROM Ens_Util.Log WHERE ConfigName = :tItem AND TimeLogged >= :tStart AND Text [ :pText)
	Quit $Select(SQLCODE < 0: -1, 1: +$Get(tN))
}

ClassMethod WaitLog(pText As %String, pAtLeast As %Integer, pSeconds As %Integer) As %Boolean
{
	For i = 1:1:pSeconds * 2 {
		Quit:(..LogCount(pText) >= pAtLeast)
		Hang 0.5
	}
	Quit ..LogCount(pText) >= pAtLeast
}

}
