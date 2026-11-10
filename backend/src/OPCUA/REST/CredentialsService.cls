Include %occInclude

/// IRIS credentials entries (<tt>Ens.Config.Credentials</tt>) for the console's OPC UA
/// servers: the one place an OPC UA password is stored. A saved server in the console
/// holds only the entry's ID and sends it as <tt>credentials</tt>;
/// <method>OPCUA.REST.ClientManager.ExtractConnectionParams</method> reads the username
/// and password here on the server, and deploy puts the same ID in the pipeline's
/// Credentials setting. So the console, and every pipeline bound to the same server,
/// share one entry, and the browser never holds the password.
///
/// No method returns a password. Every one needs %Ens_Credentials (R to list, W to
/// create or change), as the Management Portal's credentials page does.
Class OPCUA.REST.CredentialsService
{

/// <tt>Ens.Config.Credentials.SystemName</tt>'s MAXLEN.
Parameter IdMax = 50;

/// Every credentials entry in this namespace, sorted by ID:
/// <tt>[{id, username, usedBy: ["Item (Production)", ...], pipeline}]</tt>.
/// <tt>pipeline</tt> names the pipeline deploy made the entry for (deleted with it),
/// or is "" for an entry anyone else made.
ClassMethod List(Output pResult As %DynamicArray) As %Status
{
	set pResult = []
	#dim tSC As %Status = $$$OK
	Try {
		if '$System.Security.Check(##class(OPCUA.REST.DeployService).#CredentialsResource, "R") {
			set tSC = ##class(OPCUA.REST.DeployService).NoCredentialsAccess("list credentials", "R")
			Quit
		}
		set tSC = ##class(OPCUA.REST.DeployService).CredentialsUsage(.tUsage)
		Quit:$$$ISERR(tSC)
		// Embedded SQL: no SQL privilege needed, as for the console's other queries.
		&sql(DECLARE cCredList CURSOR FOR
			SELECT SystemName, Username INTO :tId, :tUser
			FROM Ens_Config.Credentials ORDER BY SystemName)
		&sql(OPEN cCredList)
		if SQLCODE < 0 {
			set tSC = ##class(OPCUA.REST.Error).Make(500, "Failed to query Ens_Config.Credentials", $$$ERROR($$$SQLError, SQLCODE, $Get(%msg)))
			Quit
		}
		for {
			&sql(FETCH cCredList)
			Quit:SQLCODE=100
			if SQLCODE < 0 {
				set tSC = ##class(OPCUA.REST.Error).Make(500, "Failed to query Ens_Config.Credentials", $$$ERROR($$$SQLError, SQLCODE, $Get(%msg)))
				Quit
			}
			set tUsed = []
			set tLower = $ZConvert(tId, "L"), k = ""
			for {
				set k = $Order(tUsage(tLower, k))
				Quit:k=""
				do tUsed.%Push(k)
			}
			do pResult.%Push({"id": (tId), "username": (tUser), "usedBy": (tUsed), "pipeline": ($Get(^OPCUA.OwnedCredentials(tId)))})
		}
		&sql(CLOSE cCredList)
	} Catch (e) {
		set tSC = e.AsStatus()
		&sql(CLOSE cCredList)
	}
	Quit tSC
}

/// Create an entry. Body: <tt>{id, username, password}</tt>.
/// 400 for an unusable ID or no username, 409 if the ID is taken (in any case, as Ens
/// matches IDs), 403 without %Ens_Credentials:W. The password may be empty.
ClassMethod Create(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	set pResult = {}
	#dim tSC As %Status = $$$OK
	Try {
		set tId = pBody.%Get("id"), tUser = pBody.%Get("username")
		set tSC = ..ValidateId(tId)
		Quit:$$$ISERR(tSC)
		if tUser = "" { set tSC = ##class(OPCUA.REST.Error).BadRequest("Credentials need a username.") Quit }
		if '##class(OPCUA.REST.DeployService).CanWriteCredentials() {
			set tSC = ##class(OPCUA.REST.DeployService).NoCredentialsAccess("create credentials '"_tId_"'", "W")
			Quit
		}
		set tTaken = ##class(OPCUA.REST.DeployService).FindCredentialsId(tId)
		if tTaken '= "" {
			set tSC = ##class(OPCUA.REST.Error).Conflict("Credentials '"_tTaken_"' already exist. Choose them from the list, or use another ID.")
			Quit
		}
		set tSC = ##class(Ens.Config.Credentials).SetCredential(tId, tUser, pBody.%Get("password"), 0)
		if $$$ISERR(tSC) { set tSC = ##class(OPCUA.REST.Error).Make(500, "Could not create credentials '"_tId_"'", tSC) Quit }
		set pResult.id = tId, pResult.username = tUser
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Change entry <var>pId</var> (matched in any case). Body: <tt>{username, password}</tt>.
/// An absent or empty password keeps the stored one; an absent username keeps it too.
/// Pipelines using the entry read it on their next connect.
/// 404 if there is no such entry, 403 without %Ens_Credentials:W.
ClassMethod Update(pId As %String, pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	set pResult = {}
	#dim tSC As %Status = $$$OK
	Try {
		set tId = ##class(OPCUA.REST.DeployService).FindCredentialsId(pId)
		if tId = "" { set tSC = ##class(OPCUA.REST.Error).NotFound("Credentials '"_pId_"' do not exist in namespace "_$Namespace_".") Quit }
		if '##class(OPCUA.REST.DeployService).CanWriteCredentials() {
			set tSC = ##class(OPCUA.REST.DeployService).NoCredentialsAccess("change credentials '"_tId_"'", "W")
			Quit
		}
		if pBody.%IsDefined("username") && (pBody.%Get("username") = "") {
			set tSC = ##class(OPCUA.REST.Error).BadRequest("Credentials need a username.")
			Quit
		}
		set tCred = ##class(Ens.Config.Credentials).%OpenId(tId, 4, .tSC)
		if '$IsObject(tCred) { set tSC = ##class(OPCUA.REST.Error).Make(500, "Cannot open credentials '"_tId_"'", tSC) Quit }
		set:pBody.%IsDefined("username") tCred.Username = pBody.%Get("username")
		// Not setting Password leaves the stored one: Ens writes it only when set.
		set:pBody.%Get("password")'="" tCred.Password = pBody.%Get("password")
		set tSC = tCred.%Save()
		if $$$ISERR(tSC) { set tSC = ##class(OPCUA.REST.Error).Make(500, "Could not save credentials '"_tId_"'", tSC) Quit }
		set pResult.id = tId, pResult.username = tCred.Username
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// 400 unless <var>pId</var> is 1 to 50 letters, digits, '.', '-' or '_' (what
/// <method>OPCUA.REST.DeployService.CredentialsId</method> produces, so IDs read cleanly
/// in the Portal), and not <tt>none</tt>, which means "no credentials" to Ens.
ClassMethod ValidateId(pId As %String) As %Status
{
	if (pId = "") || ($Length(pId) > ..#IdMax) || ($ZStrip(pId, "*AN", ".-_") '= "") {
		Quit ##class(OPCUA.REST.Error).BadRequest("Use a credentials ID of 1 to "_..#IdMax_" letters, digits, '.', '-' or '_'.")
	}
	if $ZConvert(pId, "L") = "none" {
		Quit ##class(OPCUA.REST.Error).BadRequest("'none' means no credentials; choose another ID.")
	}
	Quit $$$OK
}

}
