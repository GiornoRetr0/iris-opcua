Include %occInclude

/// The one way the console changes the pipeline production.
///
/// Every console read-modify-save of <tt>OPCUA.Pipeline.Production</tt> (deploy,
/// toggle, delete, rebind) runs <method>Begin</method>, then its change, then
/// <method>Commit</method>, then <method>End</method>:
/// <ul>
/// <li>Begin takes one named lock, <tt>^OPCUA.ProductionEdit</tt>, with a timeout,
/// so two console edits never interleave. A busy lock is refused at once with
/// "in progress" rather than waiting forever.</li>
/// <li>Begin rereads the production from disk and records the production class's
/// <tt>TimeChanged</tt>. Every <tt>SaveToClass</tt> moves it, the Portal's included.</li>
/// <li>Commit refuses if that stamp moved, so a Portal save made during our edit is
/// not overwritten. Otherwise it runs <tt>%Save</tt> and <tt>SaveToClass</tt> once.</li>
/// </ul>
///
/// The Portal does not take our lock, and its own save checks no timestamp. Two
/// gaps are therefore known and cannot be closed with documented APIs:
/// <ol>
/// <li>A Portal save that lands in the millisecond window between Commit's stamp
/// check and its SaveToClass is still overwritten in the class.</li>
/// <li>A Portal page loaded before a console edit and saved after it overwrites the
/// console's change. That is the Portal's code, so it can't be closed from our side.</li>
/// </ol>
Class OPCUA.REST.ProductionEdit
{

/// The shared production class that holds all pipeline service items.
Parameter ProductionClass = "OPCUA.Pipeline.Production";

/// Seconds Begin waits for another console edit to finish.
Parameter LockTimeout = 10;

/// The production being edited. Tests point this at a throwaway production
/// through <tt>^||OPCUA.Tests("production")</tt>.
ClassMethod ProductionClass() As %String
{
	Quit $Get(^||OPCUA.Tests("production"), ..#ProductionClass)
}

/// Lock, reread the production, and record its change stamp.
///
/// On failure the lock is already released and <var>pProd</var> is "". On success
/// the caller must call <method>End</method>.
ClassMethod Begin(Output pProd As Ens.Config.Production, Output pStamp As %String, pTimeout As %Numeric = {..#LockTimeout}) As %Status
{
	set pProd = "", pStamp = ""
	lock +^OPCUA.ProductionEdit:pTimeout
	if '$Test Quit ##class(OPCUA.REST.Error).Conflict("Another change to the pipelines is in progress; try again.")

	#dim tSC As %Status = $$$OK
	Try {
		set tClass = ..ProductionClass()
		// Read the stamp before the data. A save in between then makes Commit
		// refuse a fresh copy, which is safe. The other order would miss it.
		set pStamp = ..Stamp(tClass)
		set pProd = ##class(Ens.Config.Production).%OpenId(tClass, 0, .tSC)
		if '$IsObject(pProd) {
			set tSC = ##class(OPCUA.REST.Error).Make(500, "Cannot open production: "_tClass, tSC)
			Quit
		}
		// %OpenId hands back an object this process already holds, unchanged.
		// Reread it, and its items, so the edit starts from what is on disk.
		set tSC = pProd.%Reload()
		Quit:$$$ISERR(tSC)
		for i=1:1:pProd.Items.Count() {
			set tSC = pProd.Items.GetAt(i).%Reload()
			Quit:$$$ISERR(tSC)
		}
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	if $$$ISERR(tSC) {
		set pProd = ""
		do ..End()
	}
	Quit tSC
}

/// Save the production, unless someone saved it since <method>Begin</method>.
/// Does not release the lock; call <method>End</method>.
ClassMethod Commit(pProd As Ens.Config.Production, pStamp As %String) As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		if ..Stamp(pProd.Name) '= pStamp {
			set tSC = ##class(OPCUA.REST.Error).Conflict("The pipeline production was changed by someone else (for example in the Management Portal); reload and try again.")
			Quit
		}
		set tSC = pProd.%Save()
		Quit:$$$ISERR(tSC)
		set tSC = pProd.SaveToClass()
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Release the edit lock. Harmless when it is not held.
ClassMethod End()
{
	lock -^OPCUA.ProductionEdit
}

/// Change one config item in a single locked open and save.
///
/// <var>pSettings</var> is keyed by target, then setting name, for example
/// <tt>{"Adapter":{"DeviceNodePaths":"..."}}</tt>. A setting the item lacks is
/// added. <var>pFields</var> sets item properties, for example
/// <tt>{"Category":"OPCUA,Line"}</tt>.
ClassMethod UpdateItem(pItemName As %String, pSettings As %DynamicObject = "", pFields As %DynamicObject = "") As %Status
{
	set tSC = ..Begin(.tProd, .tStamp)
	Quit:$$$ISERR(tSC) tSC
	Try {
		set tItem = ..FindItem(tProd, pItemName)
		if '$IsObject(tItem) {
			set tSC = ##class(OPCUA.REST.Error).NotFound("Pipeline '"_pItemName_"' not found in production")
			Quit
		}
		if $IsObject(pSettings) {
			set tTargets = pSettings.%GetIterator()
			while tTargets.%GetNext(.tTarget, .tValues) {
				set tIter = tValues.%GetIterator()
				while tIter.%GetNext(.tName, .tValue) {
					do ..SetSetting(tItem, tTarget, tName, tValue)
				}
			}
		}
		if $IsObject(pFields) {
			set tIter = pFields.%GetIterator()
			while tIter.%GetNext(.tName, .tValue) {
				set $Property(tItem, tName) = tValue
			}
		}
		set tSC = ..Commit(tProd, tStamp)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	do ..End()
	Quit tSC
}

/// The item with exactly this name, or "". Walks the list rather than using
/// <tt>FindItemByConfigName</tt>, which parses "Name|Class" syntax out of the name.
ClassMethod FindItem(pProd As Ens.Config.Production, pItemName As %String, Output pIndex As %Integer) As Ens.Config.Item
{
	set pIndex = 0
	for i=1:1:pProd.Items.Count() {
		if pProd.Items.GetAt(i).Name = pItemName {
			set pIndex = i
			return pProd.Items.GetAt(i)
		}
	}
	Quit ""
}

/// Set a setting on an item, adding it when absent.
ClassMethod SetSetting(pItem As Ens.Config.Item, pTarget As %String, pName As %String, pValue As %String) [ Private ]
{
	for i=1:1:pItem.Settings.Count() {
		set tSetting = pItem.Settings.GetAt(i)
		if (tSetting.Name = pName) && (tSetting.Target = pTarget) {
			set tSetting.Value = pValue
			return
		}
	}
	set tSetting = ##class(Ens.Config.Setting).%New()
	set tSetting.Target = pTarget
	set tSetting.Name = pName
	set tSetting.Value = pValue
	do pItem.Settings.Insert(tSetting)
}

/// The production class's last-change time, read from disk. Every SaveToClass
/// moves it.
ClassMethod Stamp(pClass As %String) As %String [ Private ]
{
	set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT TimeChanged FROM %Dictionary.ClassDefinition WHERE ID = ?", pClass)
	if tRS.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, tRS.%SQLCODE, tRS.%Message))
	Quit $Select(tRS.%Next():tRS.TimeChanged, 1:"")
}

/// The namespace's production name and state, with status. Tests stand in for a
/// state they cannot force (Troubled) through <tt>^||OPCUA.Tests("productionStatus")</tt>
/// as <tt>$LB(name, state)</tt>.
ClassMethod ProductionStatus(Output pName As %String, Output pState As %Integer) As %Status
{
	set tFake = $Get(^||OPCUA.Tests("productionStatus"))
	if tFake '= "" {
		set pName = $ListGet(tFake, 1), pState = $ListGet(tFake, 2)
		Quit $$$OK
	}
	Quit ##class(Ens.Director).GetProductionStatus(.pName, .pState)
}

/// Make a saved change take effect in the running production, and report
/// honestly whether that happened.
///
/// <var>pRestarted</var> is 1 only when our production is running and
/// <tt>UpdateProduction</tt> returned OK. When the production is not running at all
/// there is nothing to update: the result is OK, <var>pRestarted</var> is 0 and
/// <var>pNote</var> says why. When it is ours but suspended or troubled, or the
/// update fails, the error says why. Callers prefix it with what was saved.
ClassMethod ApplyToRunning(Output pRestarted As %Boolean, Output pNote As %String) As %Status
{
	set pRestarted = 0, pNote = ""
	set tSC = ..ProductionStatus(.tName, .tState)
	Quit:$$$ISERR(tSC) tSC

	if tName '= ..ProductionClass() {
		set pNote = "The pipeline production is not running, so the change takes effect when it starts."
		Quit $$$OK
	}
	// State: Running = 1, Stopped = 2, Suspended = 3, Troubled = 4
	if tState = 2 {
		set pNote = "The pipeline production is stopped, so the change takes effect when it starts."
		Quit $$$OK
	}
	if tState '= 1 {
		set tText = $Case(tState, 3:"suspended", 4:"troubled", :"in state "_tState)
		Quit $$$ERROR($$$GeneralError, "production '"_tName_"' is "_tText)
	}
	set tSC = ##class(Ens.Director).UpdateProduction()
	Quit:$$$ISERR(tSC) tSC
	set pRestarted = 1
	Quit $$$OK
}

}
