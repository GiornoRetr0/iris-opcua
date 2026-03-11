Class Examples.OPCUADS.Utils
{

ClassMethod LoadOnInstallation()
{
	set ^Ens.AutoStart = "Examples.OPCUADS.Production"
	set ^Ens.AutoStart("StartupPriority") = 0
}

}
