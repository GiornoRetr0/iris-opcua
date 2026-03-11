Include %occInclude

Class IRISConfig.Installer
{

/// Main entry point — creates OPCUA namespace, imports source, configures everything.
/// Must be called from %SYS namespace.
ClassMethod Install() As %Status
{
	Set tSC = $$$OK
	Try
	{
		Set tDBDir = "/usr/irissys/mgr/opcua/"

		// Create database directory
		Do ##class(%File).CreateDirectoryChain(tDBDir)

		// Create database
		Set tSC = ##class(SYS.Database).CreateDatabase(tDBDir)
		$$$ThrowOnError(tSC)

		// Register database in config
		Set tDBProps("Directory") = tDBDir
		Set tSC = ##class(Config.Databases).Create("OPCUA", .tDBProps)
		$$$ThrowOnError(tSC)

		// Create namespace
		Set tNSProps("Globals") = "OPCUA"
		Set tNSProps("Routines") = "OPCUA"
		Set tSC = ##class(Config.Namespaces).Create("OPCUA", .tNSProps)
		$$$ThrowOnError(tSC)

		// Enable interoperability
		Set tSC = ##class(%EnsembleMgr).EnableNamespace("OPCUA")
		$$$ThrowOnError(tSC)

		// Switch to OPCUA namespace and import source
		ZN "OPCUA"

		// Load include files first (LoadDir skips .inc files)
		Do $System.OBJ.Load("/opt/irisapp/src/OPCUA/Constants.inc", "k")
		// Load all classes then compile
		Do $System.OBJ.LoadDir("/opt/irisapp/src/", "k", , 1)
		Do $System.OBJ.CompileAll("ck")

		// Configure connector (non-fatal if .so missing), credentials, and web app
		Do ..LoadConnectorAndDemos("OPCUA")

		Set tSC = ..CreateCredentials("OPCUA")
		$$$ThrowOnError(tSC)

		Set tSC = ..CreateWebApp("OPCUA")
		$$$ThrowOnError(tSC)

		// Disable password change requirement for demo accounts
		Set tSC = ..DisablePasswordExpiration()
		$$$ThrowOnError(tSC)
	}
	Catch (oException)
	{
		Set tSC = oException.AsStatus()
		Do $System.Status.DisplayError(tSC)
	}

	Quit tSC
}

/// This method will create an Interoperability credential meant to be used on Interoperability Productions.
/// It will use the standard SuperUser/sys password for demos.
ClassMethod CreateCredentials(pNamespace As %String) As %Status
{
	Set tSC = $$$OK
	Try
	{
		Set tNS=$Namespace
		ZN pNamespace

		Set tSC = ##class(Ens.Config.Credentials).SetCredential("IrisOpcUaDemo", "SuperUser", "sys", 1)
		Quit:$System.Status.IsError(tSC)
	}
	Catch (oException)
	{
		Set tSC = oException.AsStatus()
	}

	ZN tNS

	Quit tSC
}

/// Create the /opcua/api web application for REST endpoints.
/// Switches to %SYS namespace to call Security.Applications API.
/// Idempotent — skips if the web app already exists.
ClassMethod CreateWebApp(pNamespace As %String) As %Status
{
	Set tSC = $$$OK
	Try
	{
		Set tNS = $Namespace
		ZN "%SYS"

		// Check if web app already exists
		if ##class(Security.Applications).Exists("/csp/opcua/api") {
			ZN tNS
			Quit
		}

		// Define web application properties
		set tProps("Name") = "/csp/opcua/api"
		set tProps("NameSpace") = pNamespace
		set tProps("DispatchClass") = "OPCUA.REST.Handler"
		set tProps("Description") = "OPC UA Adapter REST API"
		set tProps("Enabled") = 1
		set tProps("AutheEnabled") = 32
		set tProps("Resource") = ""

		set tSC = ##class(Security.Applications).Create("/csp/opcua/api", .tProps)

		ZN tNS
	}
	Catch (oException)
	{
		// Restore namespace on error
		Try { ZN tNS } Catch (e2) {}
		Set tSC = oException.AsStatus()
	}

	Quit tSC
}

/// Disable password expiration and change-on-login for default demo accounts.
ClassMethod DisablePasswordExpiration() As %Status
{
	Set tSC = $$$OK
	Try
	{
		Set tNS = $Namespace
		ZN "%SYS"

		For tUser = "_SYSTEM", "SuperUser", "Admin" {
			If ##class(Security.Users).Exists(tUser) {
				Set tSC = ##class(Security.Users).Get(tUser, .tProps)
				$$$ThrowOnError(tSC)
				Set tProps("ChangePassword") = 0
				Set tProps("PasswordNeverExpires") = 1
				Set tSC = ##class(Security.Users).Modify(tUser, .tProps)
				$$$ThrowOnError(tSC)
			}
		}

		ZN tNS
	}
	Catch (oException)
	{
		Try { ZN tNS } Catch (e2) {}
		Set tSC = oException.AsStatus()
	}

	Quit tSC
}

ClassMethod LoadConnectorAndDemos(pNamespace As %String) As %Status
{
	Set tSC = $$$OK
	Try
	{
		Set tNS=$Namespace
		ZN pNamespace

        set tSC = ##class(OPCUA.Utils).Install("/usr/irissys/bin/irisopcua.so")

		Do ##class(Examples.OPCUADS.Utils).LoadOnInstallation()
	}
	Catch (oException)
	{
		Set tSC = oException.AsStatus()
	}

	ZN tNS

	Quit tSC
}

}
