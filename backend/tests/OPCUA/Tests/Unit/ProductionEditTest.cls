Include (%occInclude, Ensemble)

/// Offline tests for <class>OPCUA.REST.ProductionEdit</class>: the lock, the
/// stale-save check and the one-save item update.
///
/// Works on a throwaway production, <tt>OPCUA.Tests.Tmp.EditProduction</tt>, that
/// is never started. <tt>^||OPCUA.Tests("production")</tt> points ProductionEdit
/// at it. The class's <tt>OnConfigChange</tt> counts SaveToClass calls in
/// <tt>^||OPCUA.Tests("saves")</tt>, because SaveToClass calls it once per save.
Class OPCUA.Tests.Unit.ProductionEditTest Extends %UnitTest.TestCase
{

Parameter Production = "OPCUA.Tests.Tmp.EditProduction";

/// A name with a space, a dot and a hyphen (Review Focus 1).
Parameter OddName = "Line 3.Press-A";

Parameter ServiceClass = "OPCUA.Service.TCPPollingRowSourceService";

Method OnBeforeAllTests() As %Status
{
	do ..DropProduction()
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#Production)
	set tDef.Super = "Ens.Production"
	set tDef.Description = "Throwaway production for ProductionEditTest. Never started."

	set tX = ##class(%Dictionary.XDataDefinition).%New()
	set tX.Name = "ProductionDefinition"
	do tX.Data.Write("<Production Name="""_..#Production_""">")
	for tName = ..#OddName, "Other" {
		do tX.Data.Write("<Item Name="""_tName_""" ClassName="""_..#ServiceClass_""" Enabled=""false"">")
		do tX.Data.Write("<Setting Target=""Adapter"" Name=""DeviceNodePaths"">old</Setting></Item>")
	}
	do tX.Data.Write("</Production>")
	do tDef.XDatas.Insert(tX)

	set tM = ##class(%Dictionary.MethodDefinition).%New()
	set tM.Name = "OnConfigChange"
	set tM.ClassMethod = 1
	set tM.FormalSpec = "pProduction:Ens.Config.Production,pItem:Ens.Config.Item"
	do tM.Implementation.WriteLine("	set ^||OPCUA.Tests(""saves"") = $Get(^||OPCUA.Tests(""saves"")) + 1")
	do tDef.Methods.Insert(tM)

	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC
	set tSC = $System.OBJ.Compile(..#Production, "ck-d")
	Quit:$$$ISERR(tSC) tSC
	Quit ##class(Ens.Config.Production).LoadFromClass(..#Production)
}

Method OnAfterAllTests() As %Status
{
	do ..DropProduction()
	kill ^||OPCUA.Tests("production"), ^||OPCUA.Tests("saves")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	set ^||OPCUA.Tests("production") = ..#Production
	kill ^IRIS.Temp.OPCUATests("edit")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	// Releases a lock-holding job, if one is still waiting.
	kill ^IRIS.Temp.OPCUATests("edit")
	do ##class(OPCUA.REST.ProductionEdit).End()
	Quit $$$OK
}

/// A held edit lock makes Begin fail fast with "in progress", instead of waiting
/// forever.
Method TestLockBusy()
{
	set ^IRIS.Temp.OPCUATests("edit", "hold") = 1
	job ##class(OPCUA.Tests.Unit.ProductionEditTest).HoldLock()::5
	do $$$AssertTrue($Test, "lock-holding job started")
	for i=1:1:50 { quit:$Get(^IRIS.Temp.OPCUATests("edit", "held"))  hang 0.1 }
	do $$$AssertTrue($Get(^IRIS.Temp.OPCUATests("edit", "held")), "job holds the edit lock")

	set tSC = ##class(OPCUA.REST.ProductionEdit).Begin(.tProd, .tStamp, 1)
	do $$$AssertNotTrue($$$ISOK(tSC), "Begin refuses while another process holds the lock")
	do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "in progress", "error says in progress: "_$System.Status.GetErrorText(tSC))
	do $$$AssertNotTrue($IsObject($Get(tProd)), "no production handed out")
}

/// A save by someone else between Begin and Commit is refused, and the other
/// change survives in storage and in the class.
Method TestStaleCommitRefused()
{
	set tSC = ##class(OPCUA.REST.ProductionEdit).Begin(.tProd, .tStamp)
	do $$$AssertStatusOK(tSC, "Begin")
	Quit:$$$ISERR(tSC)

	// The other writer is a separate process, as the Portal is. In this process
	// %OpenId would hand back our own copy.
	job ##class(OPCUA.Tests.Unit.ProductionEditTest).PortalLikeSave(..#Production, "Other", "fromPortal")::5
	for i=1:1:50 { quit:$Data(^IRIS.Temp.OPCUATests("edit", "saved"))  hang 0.1 }
	do $$$AssertEquals($Get(^IRIS.Temp.OPCUATests("edit", "saved")), 1, "the other save succeeded")

	set tItem = ..FindItem(tProd, ..#OddName)
	do ..SetDevices(tItem, "fromConsole")
	set tSC = ##class(OPCUA.REST.ProductionEdit).Commit(tProd, tStamp)
	do ##class(OPCUA.REST.ProductionEdit).End()
	do $$$AssertNotTrue($$$ISOK(tSC), "stale Commit is refused")
	do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "changed by someone else", "error says changed by someone else: "_$System.Status.GetErrorText(tSC))
	kill tItem, tProd

	do $$$AssertEquals(..StoredDevices("Other"), "fromPortal", "the other change survived in storage")
	do $$$AssertTrue(..ClassHas("fromPortal"), "the other change survived in the class")
	do $$$AssertNotTrue(..ClassHas("fromConsole"), "the refused change was not written to the class")
	do $$$AssertNotEquals(..StoredDevices(..#OddName), "fromConsole", "the refused change was not written to storage")
}

/// One UpdateItem applies a setting, a new setting and a field in a single save.
Method TestUpdateItemOneSave()
{
	set tBefore = ..Stamp()
	set ^||OPCUA.Tests("saves") = 0
	set tSC = ##class(OPCUA.REST.ProductionEdit).UpdateItem("Other",
		{"Adapter":{"DeviceNodePaths":"one-save","CallInterval":"7"}},
		{"Category":"A,B"})
	do $$$AssertStatusOK(tSC, "UpdateItem")
	do $$$AssertEquals(^||OPCUA.Tests("saves"), 1, "exactly one SaveToClass")
	do $$$AssertNotEquals(..Stamp(), tBefore, "production class TimeChanged moved")

	set tItem = ..FindItem(..FreshProduction(), "Other")
	do $$$AssertEquals(..Setting(tItem, "DeviceNodePaths"), "one-save", "existing setting updated")
	do $$$AssertEquals(..Setting(tItem, "CallInterval"), "7", "missing setting inserted")
	do $$$AssertEquals(tItem.Category, "A,B", "field set")
	do $$$AssertTrue(..ClassHas("one-save") && ..ClassHas("A,B"), "both changes are in the class")
}

/// Item names with spaces, dots and hyphens are matched exactly.
Method TestNamesWithPunctuation()
{
	set tSC = ##class(OPCUA.REST.ProductionEdit).UpdateItem(..#OddName, {"Adapter":{"DeviceNodePaths":"odd-name"}})
	do $$$AssertStatusOK(tSC, "UpdateItem on '"_..#OddName_"'")
	do $$$AssertEquals(..StoredDevices(..#OddName), "odd-name", "the punctuated item changed")
	do $$$AssertNotEquals(..StoredDevices("Other"), "odd-name", "the other item did not")

	set tSC = ##class(OPCUA.REST.ProductionEdit).UpdateItem("Line 3", {"Adapter":{"DeviceNodePaths":"x"}})
	do $$$AssertNotTrue($$$ISOK(tSC), "a name prefix does not match")
	do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "not found", "error says not found")
}

/// JOB entry: hold the edit lock until the test kills the flag.
ClassMethod HoldLock()
{
	lock +^OPCUA.ProductionEdit
	set ^IRIS.Temp.OPCUATests("edit", "held") = 1
	for i=1:1:300 { quit:'$Get(^IRIS.Temp.OPCUATests("edit", "hold"))  hang 0.1 }
	lock -^OPCUA.ProductionEdit
}

/// JOB entry: change one item the way the Portal does. Fresh open, item %Save,
/// then SaveToClass, without our lock.
ClassMethod PortalLikeSave(pProduction As %String, pItem As %String, pValue As %String)
{
	set tOK = 0
	try {
		set tProd = ##class(Ens.Config.Production).%OpenId(pProduction)
		set tItem = ..FindItem(tProd, pItem)
		do ..SetDevices(tItem, pValue)
		set tSC = tItem.%Save()
		if $$$ISOK(tSC) set tSC = tProd.SaveToClass(tItem)
		set tOK = $$$ISOK(tSC)
	} catch e {}
	set ^IRIS.Temp.OPCUATests("edit", "saved") = tOK
}

ClassMethod FindItem(pProd As Ens.Config.Production, pName As %String) As Ens.Config.Item
{
	for i=1:1:pProd.Items.Count() {
		return:pProd.Items.GetAt(i).Name=pName pProd.Items.GetAt(i)
	}
	Quit ""
}

ClassMethod SetDevices(pItem As Ens.Config.Item, pValue As %String)
{
	for i=1:1:pItem.Settings.Count() {
		set tSetting = pItem.Settings.GetAt(i)
		set:tSetting.Name="DeviceNodePaths" tSetting.Value = pValue
	}
}

ClassMethod Setting(pItem As Ens.Config.Item, pName As %String) As %String
{
	for i=1:1:pItem.Settings.Count() {
		return:pItem.Settings.GetAt(i).Name=pName pItem.Settings.GetAt(i).Value
	}
	Quit ""
}

/// The stored production, reread from disk.
ClassMethod FreshProduction() As Ens.Config.Production
{
	set tProd = ##class(Ens.Config.Production).%OpenId(..#Production, 0)
	do tProd.%Reload()
	for i=1:1:tProd.Items.Count() { do tProd.Items.GetAt(i).%Reload() }
	Quit tProd
}

ClassMethod StoredDevices(pItem As %String) As %String
{
	Quit ..Setting(..FindItem(..FreshProduction(), pItem), "DeviceNodePaths")
}

ClassMethod ClassHas(pText As %String) As %Boolean
{
	set tX = ##class(%Dictionary.XDataDefinition).%OpenId(..#Production_"||ProductionDefinition", 0)
	Quit:'$IsObject(tX) 0
	do tX.%Reload()
	Quit tX.Data.Read(1000000) [ pText
}

ClassMethod Stamp() As %String
{
	set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TimeChanged FROM %Dictionary.ClassDefinition WHERE ID = ?", ..#Production)
	Quit $Select(tRS.%Next():tRS.TimeChanged, 1:"")
}

ClassMethod DropProduction()
{
	set tProd = ..#Production
	&sql(DELETE FROM Ens_Config.Item WHERE Production = :tProd)
	do:##class(Ens.Config.Production).%ExistsId(tProd) ##class(Ens.Config.Production).%DeleteId(tProd)
	do:##class(%Dictionary.ClassDefinition).%ExistsId(tProd) $System.OBJ.Delete(tProd, "-d")
}

}
