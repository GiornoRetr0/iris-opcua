Include (%occInclude, Ensemble)

/// End-to-end approval flow of managed Sign & Encrypt against the demo certified-server.
///
/// Approval is the server administrator's act, outside IRIS, so this class cannot run
/// alone: the host script <tt>demo/iris/secure-e2e.sh</tt> runs the phases through
/// <tt>OPCUA.Tests.Runner.Run</tt> with host-side steps in between (reset the server's
/// trust folder, <tt>docker cp</tt> IRIS's certificate into it, curl checks):
/// <ol>
/// <li><method>TestPhase1</method>: test store, identity, trust, managed /test is
///     <tt>clientNotApproved</tt>, a managed pipeline logs that once, the client
///     certificate is exported to <tt>/tmp/opcua-e2e/client.der</tt>.</li>
/// <li><method>TestPhase2</method>: after approval /test connects, the pipeline
///     recovers without a production restart and writes rows, a different pin is
///     refused as <tt>serverChanged</tt>.</li>
/// <li><method>TestPhase3</method>: an identity whose files expire is refused before
///     any native connect.</li>
/// <li><method>TestCleanup</method>: removes everything the phases made.</li>
/// </ol>
/// The phases share <tt>^%OPCUA.Security.Override</tt> (set by phase 1), which redirects
/// the whole store, for the production's jobs and the REST app as well as for these
/// tests, so the instance's real identity is never touched. Every method is skipped
/// unless named explicitly (<tt>Runner.Run</tt>), so <tt>Runner.Live()</tt> leaves it alone.
Class OPCUA.Tests.Live.SecureE2ETest Extends %UnitTest.TestCase
{

Parameter URL = "opc.tcp://certified-server:4840";

Parameter Schema = "OPCUA.Tests.Tmp.E2ESchema";

Parameter Pipeline = "TmpE2ESecure";

Parameter Work = "/tmp/opcua-e2e/";

Parameter Store = "^%OPCUA.SecurityE2E";

Parameter Fixtures = "/tmp/opcua-dev/fixtures/certified-server/";

Parameter Failed = "OPCUA managed Sign & Encrypt connection failed (clientNotApproved)";

Parameter Recovered = "OPCUA managed Sign & Encrypt connection recovered";

Method Skipped() As %Boolean
{
	If '##class(OPCUA.Utils).SupportsPki() {
		Do $$$AssertSkipped("connector 0.5 PKI is not available")
		Quit 1
	}
	If '$Get(^||OPCUA.Tests("explicit")) {
		Do $$$AssertSkipped("end-to-end phase: run it through demo/iris/secure-e2e.sh (Runner.Run)")
		Quit 1
	}
	Quit 0
}

/// Phases 2 and 3 need what phase 1 set up.
Method NeedPhase1() As %Boolean
{
	If $Get(^%OPCUA.Security.Override("global")) '= ..#Store {
		Do $$$AssertFailure("phase 1 has not run (the test store override is not set)")
		Quit 0
	}
	Quit 1
}

// ==================== phase 1: before approval ====================

Method TestPhase1()
{
	Quit:..Skipped()
	// A clean slate, then the redirected store.
	Do ..RemoveEverything()
	Do ##class(%File).CreateDirectoryChain(..#Work)
	Set ^%OPCUA.Security.Override("global") = ..#Store
	Set ^%OPCUA.Security.Override("root") = ..#Work_"pki"

	Set tSC = ##class(OPCUA.Security.Identity).Create("", 0, "", .tStatus)
	Do $$$AssertStatusOK(tSC, "identity created")
	Quit:$$$ISERR(tSC)
	Set tClientFp = tStatus.fingerprint
	Do $$$AssertEquals(tStatus.ready, 1, "identity ready")

	// Trust the server (the user's review step) and give it the CA's issuer + CRL.
	Set tSC = ##class(OPCUA.Security.Trust).Inspect(..#URL, .tInspect)
	Do $$$AssertStatusOK(tSC, "server inspected")
	Quit:$$$ISERR(tSC)
	Do $$$AssertEquals(tInspect.offersSignAndEncrypt, 1, "server offers Sign & Encrypt")
	Do $$$AssertEquals(tInspect.needsIssuer, 1, "CA-signed server needs its issuer")
	Set tServerFp = tInspect.certificate.sha256
	Set tSC = ##class(OPCUA.Security.Trust).Trust(..#URL, tServerFp, "E2E certified-server", .tTrust)
	Do $$$AssertStatusOK(tSC, "server certificate trusted")
	Quit:$$$ISERR(tSC)
	Set tCA = ..#Fixtures_"myCA.crt.der", tCRL = ..#Fixtures_"myCA.crl"
	If '##class(%File).Exists(tCA) || '##class(%File).Exists(tCRL) {
		Do $$$AssertFailure("CA fixtures missing in "_..#Fixtures_" (the script runs dev-load.sh first)")
		Quit
	}
	Set tSC = ##class(OPCUA.Security.Trust).AddIssuer(..#URL, ..Hex(tCA), ..Hex(tCRL), .tIssuer)
	Do $$$AssertStatusOK(tSC, "issuer and CRL added")
	Quit:$$$ISERR(tSC)

	// The pin is stored.
	Do ##class(OPCUA.Security.Trust).List(.tList)
	Do $$$AssertEquals(tList.%Size(), 1, "one trusted server")
	Do $$$AssertEquals(tList.%Get(0).fingerprint, tServerFp, "its pin is the presented fingerprint")
	Set ^%OPCUA.Security.Override("e2e", "clientFp") = tClientFp
	Set ^%OPCUA.Security.Override("e2e", "serverFp") = tServerFp

	// Managed /test: not approved yet.
	Set tSC = ##class(OPCUA.REST.ConnectionService).Test({"url": (..#URL), "securityMode": 3}, .tRes)
	Do $$$AssertStatusOK(tSC, "/test answers")
	Do $$$AssertEquals(tRes.connected, 0, "managed /test does not connect before approval")
	Do $$$AssertEquals(tRes.security.managed, 1, "managed")
	Do $$$AssertEquals(tRes.security.identityReady, 1, "identity ready")
	Do $$$AssertEquals(tRes.security.serverTrusted, 1, "server trusted")
	Do $$$AssertEquals(tRes.security.diagnosis.category, "clientNotApproved", "diagnosis: the server must approve IRIS")
	Do $$$AssertEquals(tRes.security.diagnosis.clientFingerprint, tClientFp, "the diagnosis names IRIS's fingerprint")

	// Export IRIS's certificate for the host to hand to the server.
	Set tSC = ##class(OPCUA.Security.Identity).CertificateBytes("der", .tDer, .tName)
	Do $$$AssertStatusOK(tSC, "certificate exported")
	Quit:$$$ISERR(tSC)
	Set tFile = ##class(%Stream.FileBinary).%New()
	Do tFile.LinkToFile(..#Work_"client.der")
	Do tFile.Write(tDer)
	Do $$$AssertStatusOK(tFile.%Save(), "client.der written")

	// A managed row-source pipeline against the server, started now. Remember what the
	// production looked like, so the cleanup leaves it as found.
	Set tProd = ##class(OPCUA.REST.DeployService).#ProductionClass
	Set tExisted = ##class(%Dictionary.ClassDefinition).%ExistsId(tProd)
	Do ##class(Ens.Director).GetProductionStatus(.tName, .tState)
	Set ^%OPCUA.Security.Override("e2e", "prodExisted") = tExisted
	Set ^%OPCUA.Security.Override("e2e", "prodRunning") = ((tName = tProd) && (tState = 1))
	// A fresh instance has no pipeline production until the first deploy makes it.
	If 'tExisted Do ##class(OPCUA.REST.DeployService).EnsureProductionExists()
	Set tSC = ..BuildSchema()
	Do $$$AssertStatusOK(tSC, "schema generated")
	Quit:$$$ISERR(tSC)
	Set tSC = ##class(OPCUA.REST.DeployService).AddServiceItem({"url": (..#URL), "securityMode": 3, "callInterval": 1}, ..#Schema, ..#Pipeline, "polling", "ns=1;i=50000|Demo")
	Do $$$AssertStatusOK(tSC, "managed pipeline item added")
	Quit:$$$ISERR(tSC)
	Set ^%OPCUA.Security.Override("e2e", "start") = $ZDateTime($ZTimeStamp, 3)
	Set tSC = ##class(OPCUA.REST.PipelineService).Toggle({"name": (..#Pipeline)}, .tToggle)
	Do $$$AssertStatusOK(tSC, "pipeline enabled")
	Quit:$$$ISERR(tSC)

	// The adapter explains the refusal in the event log, once however often it retries.
	Do $$$AssertTrue(..WaitLog(..#Failed, 1, 40), "the adapter logs the diagnosis")
	Hang 10
	Set tTries = ..LogCount("Client reset")
	Do $$$AssertTrue(tTries >= 2, "the adapter retried several times meanwhile ("_tTries_" resets logged)")
	Do $$$AssertEquals(..LogCount(..#Failed), 1, "the diagnosis is logged once, not on every retry")
	Do $$$AssertEquals(..LogCount(..#Recovered), 0, "no recovery yet")
	Do $$$AssertEquals(..Rows(), 0, "no rows before approval")
}

// ==================== phase 2: after approval ====================

Method TestPhase2()
{
	Quit:..Skipped()
	Quit:'..NeedPhase1()
	Set tClientFp = ^%OPCUA.Security.Override("e2e", "clientFp")
	Set tServerFp = ^%OPCUA.Security.Override("e2e", "serverFp")

	// The correct pin connects.
	Set tSC = ##class(OPCUA.REST.ConnectionService).Test({"url": (..#URL), "securityMode": 3}, .tRes)
	Do $$$AssertStatusOK(tSC, "/test answers")
	Do $$$AssertEquals(tRes.connected, 1, "managed /test connects after approval: "_tRes.error)
	Do $$$AssertEquals(tRes.securityMode, 3, "in Sign & Encrypt")
	Do $$$AssertEquals(tRes.security.diagnosis, "", "no diagnosis when connected")

	// The running pipeline recovered by itself and writes rows.
	Do $$$AssertTrue(..WaitLog(..#Recovered, 1, 60), "the adapter reconnected without a production restart and logged the recovery")
	Do $$$AssertTrue(..WaitRows(60), "the managed pipeline wrote at least one row ("_..Rows()_")")
	Do $$$AssertEquals(..LogCount(..#Recovered), 1, "exactly one recovery line")
	Do $$$AssertEquals(..LogCount(..#Failed), 1, "still only the one failure line")
	Do $$$AssertEquals(..RowsWithValue(), 1, "a stored measurement holds a value")

	// Stop the pipeline so the pin swap below concerns only the calls made here.
	Set tSC = ##class(OPCUA.REST.PipelineService).Toggle({"name": (..#Pipeline)}, .tToggle)
	Do $$$AssertStatusOK(tSC, "pipeline disabled")

	// A different (valid) fingerprint as the pin: the connect is refused, not tried unsecured.
	Try {
		Do ..SetPin(tClientFp)
		Set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, ..#URL, 3)
		Do $$$AssertStatusNotOK(tSC, "a different pin refuses the connect")
		Set tConnected = 0
		If $IsObject($Get(tClient)) Do tClient.GetClientState("", .tConnected)
		Do $$$AssertEquals(+tConnected, 0, "no session was opened")
		Do ##class(OPCUA.REST.ClientManager).Disconnect($Get(tClient))
		Set tSC = ##class(OPCUA.REST.ConnectionService).Test({"url": (..#URL), "securityMode": 3}, .tSwapped)
		Do $$$AssertEquals(tSwapped.connected, 0, "/test with the swapped pin does not connect")
		Do $$$AssertEquals(tSwapped.security.diagnosis.category, "serverChanged", "diagnosis")
		Do $$$AssertEquals(tSwapped.security.diagnosis.message, "Server certificate changed"_$Char(8212)_"review and approve the replacement.", "exact message")
	} Catch (e) {
		Do $$$AssertFailure("pin swap case raised "_e.DisplayString())
	}
	Do ..SetPin(tServerFp)
	Set tSC = ##class(OPCUA.REST.ConnectionService).Test({"url": (..#URL), "securityMode": 3}, .tBack)
	Do $$$AssertEquals(tBack.connected, 1, "the correct pin connects again")
}

// ==================== phase 3: identity that expires ====================

Method TestPhase3()
{
	Quit:..Skipped()
	Quit:'..NeedPhase1()
	Set tFx = ..#Work_"fx/"
	Do ##class(%File).CreateDirectoryChain(tFx)
	Set tCrt = tFx_"use.crt.der", tKey = tFx_"use.key.der"
	// A valid pair of the user's own, referenced in place.
	Set tSC = ##class(OPCUA.Security.Native).CreateIdentity(tCrt, tKey, "urn:e2e:fixture", "e2e", "E2E fixture")
	Do $$$AssertStatusOK(tSC, "fixture pair")
	Quit:$$$ISERR(tSC)
	Do ##class(OPCUA.Security.Identity).Status(.tNow)
	Set tSC = ##class(OPCUA.Security.Identity).UseFiles(tCrt, tKey, 1, tNow.fingerprint, .tUsed)
	Do $$$AssertStatusOK(tSC, "use existing files")
	Quit:$$$ISERR(tSC)
	Do $$$AssertEquals(tUsed.ready, 1, "ready while valid")
	// The files expire (a file replaced on disk): a matching expired pair at the same paths.
	Set tOK = ..MakeExpiredPair(tFx, tCrt, tKey)
	Do $$$AssertTrue(tOK, "expired pair made")
	Quit:'tOK
	Do ##class(OPCUA.Security.Identity).Status(.tStatus)
	Do $$$AssertEquals(tStatus.ready, 0, "the identity is no longer ready")
	Set tText = ""
	Set tIter = tStatus.errors.%GetIterator()
	While tIter.%GetNext(.k, .tErr) { Set tText = tText_tErr.code_" " }
	Do $$$AssertTrue(tText [ "expired", "status says expired: "_tText)
	// Managed /test refuses with the identity error, without touching the network.
	Set tSC = ##class(OPCUA.REST.ConnectionService).Test({"url": (..#URL), "securityMode": 3}, .tRes)
	Do $$$AssertStatusOK(tSC, "/test answers")
	Do $$$AssertEquals(tRes.connected, 0, "managed /test refuses an expired identity")
	Do $$$AssertEquals(tRes.security.identityReady, 0, "identity not ready")
	Do $$$AssertTrue(tRes.error [ "expired", "the error says expired: "_tRes.error)
	Do $$$AssertEquals(tRes.security.diagnosis.category, "identityInvalid", "an identity problem, not a server diagnosis")
	Set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, ..#URL, 3)
	Do $$$AssertStatusNotOK(tSC, "ClientManager.Connect refuses too")
	Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "expired", "with the same reason")
	Do ##class(OPCUA.REST.ClientManager).Disconnect($Get(tClient))
}

// ==================== cleanup ====================

Method TestCleanup()
{
	Quit:..Skipped()
	Set tExisted = $Get(^%OPCUA.Security.Override("e2e", "prodExisted"), 1)
	Set tRunning = $Get(^%OPCUA.Security.Override("e2e", "prodRunning"), 1)
	Do ..RemoveEverything()
	Do $$$AssertNotTrue($Data(^%OPCUA.Security.Override), "overrides removed")
	Set tStore = ..#Store
	Do $$$AssertNotTrue($Data(@tStore), "test store removed")
	Do $$$AssertNotTrue(##class(%File).DirectoryExists(..#Work), "work directory removed")
	Do $$$AssertNotTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#Schema), "schema removed")
	Set tItem = ..#Pipeline
	&sql(SELECT COUNT(*) INTO :tN FROM Ens_Config.Item WHERE Name = :tItem)
	Do $$$AssertEquals(tN, 0, "pipeline item removed")
	Set tProd = ##class(OPCUA.REST.DeployService).#ProductionClass
	Do ##class(Ens.Director).GetProductionStatus(.tName, .tState)
	If 'tExisted Do $$$AssertNotTrue(##class(%Dictionary.ClassDefinition).%ExistsId(tProd), "the production phase 1 had to create is removed")
	If 'tRunning Do $$$AssertNotTrue((tName = tProd) && (tState = 1), "the production phase 1 started is stopped again")
}

// ==================== helpers ====================

/// Pipeline, schema, overrides, test store and files. Safe to call when nothing exists.
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
	// The production as it was found: stopped again if phase 1 started it, and removed
	// if phase 1 had to create it.
	If $Get(^%OPCUA.Security.Override("e2e", "prodRunning")) = 0 {
		Try { Do ##class(Ens.Director).StopProduction(10, 1) } Catch {}
	}
	If $Get(^%OPCUA.Security.Override("e2e", "prodExisted")) = 0 {
		Set tProd = ##class(OPCUA.REST.DeployService).#ProductionClass
		Try {
			If ##class(Ens.Config.Production).%ExistsId(tProd) Do ##class(Ens.Config.Production).%DeleteId(tProd)
			If ##class(%Dictionary.ClassDefinition).%ExistsId(tProd) Do $System.OBJ.Delete(tProd, "-d")
		} Catch {}
	}
	Kill ^%OPCUA.Security.Override
	Set tStore = ..#Store
	Kill @tStore
	Do ##class(%File).RemoveDirectoryTree(..#Work)
}

/// Two columns one folder down in the server's Demo folder, as the schema builder would make.
ClassMethod BuildSchema() As %Status
{
	Set tCols = [
		{"displayName": "Double", "inferredType": "%Double", "relativePath": ["Scalar", "Double"]},
		{"displayName": "Boolean", "inferredType": "%Boolean", "relativePath": ["Scalar", "Boolean"]}]
	Quit ##class(OPCUA.REST.SchemaService).GenerateSchemaClass(..#Schema, "TmpE2E", tCols, 1, .tColNS, .tSerial)
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

/// Overwrites the stored pin, as a server presenting another certificate looks.
ClassMethod SetPin(pFp As %String)
{
	Set tKey = ##class(OPCUA.Security.Store).ServerKey(..#URL)
	Do ##class(OPCUA.Security.Store).GetServer(tKey, .e)
	Set e.fingerprint = pFp
	Do ##class(OPCUA.Security.Store).SaveServer(tKey, e)
}

/// Event-log lines of the pipeline since phase 1 containing <var>pText</var>.
ClassMethod LogCount(pText As %String) As %Integer
{
	Set tItem = ..#Pipeline, tStart = $Get(^%OPCUA.Security.Override("e2e", "start"))
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

ClassMethod Rows() As %Integer
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_##class(OPCUA.REST.SchemaService).TableName(..#Schema))
	Quit:(tRS.%SQLCODE < 0) -1
	Quit $Select(tRS.%Next(): tRS.%GetData(1), 1: 0)
}

ClassMethod WaitRows(pSeconds As %Integer) As %Boolean
{
	For i = 1:1:pSeconds * 2 {
		Quit:(..Rows() > 0)
		Hang 0.5
	}
	Quit ..Rows() > 0
}

/// 1 if some stored row has a non-null Double value.
ClassMethod RowsWithValue() As %Boolean
{
	Set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_##class(OPCUA.REST.SchemaService).TableName(..#Schema)_" WHERE Scalar_Double_Value IS NOT NULL")
	Quit:(tRS.%SQLCODE < 0) 0
	Quit $Select(tRS.%Next(): tRS.%GetData(1) > 0, 1: 0)
}

/// A DER certificate that expired in 2020 and its DER key, at pCrt and pKey (container openssl; test only).
ClassMethod MakeExpiredPair(pDir As %String, pCrt As %String, pKey As %String) As %Boolean
{
	Set d = pDir
	Set tRC = ..Openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", d_"e.key.pem", "-out", d_"e.tmp.pem", "-days", "1", "-subj", "/CN=expired")
	Quit:tRC 0
	Open d_"index.txt":"NWS":2
	Close d_"index.txt"
	Set f = ##class(%Stream.FileCharacter).%New()
	Do f.LinkToFile(d_"ca.cnf")
	Do f.WriteLine("[ca]"), f.WriteLine("default_ca=x"), f.WriteLine("[x]")
	Do f.WriteLine("database="_d_"index.txt"), f.WriteLine("new_certs_dir="_d), f.WriteLine("serial="_d_"serial")
	Do f.WriteLine("default_md=sha256"), f.WriteLine("policy=p"), f.WriteLine("[p]"), f.WriteLine("commonName=supplied")
	Do f.%Save()
	Set s = ##class(%Stream.FileCharacter).%New()
	Do s.LinkToFile(d_"serial"), s.WriteLine("01"), s.%Save()
	Set tRC = ..Openssl("req", "-new", "-key", d_"e.key.pem", "-subj", "/CN=expired", "-out", d_"e.csr")
	Quit:tRC 0
	Set tRC = ..Openssl("ca", "-batch", "-config", d_"ca.cnf", "-selfsign", "-keyfile", d_"e.key.pem", "-in", d_"e.csr", "-out", d_"e.old.pem", "-startdate", "20200101000000Z", "-enddate", "20200102000000Z", "-notext")
	Quit:tRC 0
	Set tRC = ..Openssl("x509", "-in", d_"e.old.pem", "-outform", "DER", "-out", pCrt)
	Quit:tRC 0
	Set tRC = ..Openssl("pkey", "-in", d_"e.key.pem", "-outform", "DER", "-out", pKey)
	Quit 'tRC
}

ClassMethod Openssl(pArgs...) As %Integer
{
	Quit $ZF(-100, "/STDOUT=""/dev/null"" /STDERR=""/dev/null""", "openssl", pArgs...)
}

}
