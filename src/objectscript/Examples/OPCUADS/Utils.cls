Class Examples.OPCUADS.Utils
{

ClassMethod LoadOnInstallation()
{
	// No auto-start — pipelines are managed via the wizard UI
	kill ^Ens.AutoStart
}

}
