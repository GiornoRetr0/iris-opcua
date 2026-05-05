Include %occInclude

/// Custom SAM metrics published on /api/monitor/metrics under the opcua_ prefix.
/// Registered via SYS.Monitor.SAM.Config.AddApplicationClass() in the installer.
/// GetSensors() runs on every scrape, so keep it cheap: read globals and SQL counts only,
/// never touch live OPC UA client handles.
Class OPCUA.Monitor.Metrics Extends %SYS.Monitor.SAM.Abstract
{

Parameter PRODUCT = "opcua";

Parameter ProductionClass = "OPCUA.Pipeline.Production";

/// Emit one metric family per scrape. Label "id" = pipeline config item name.
Method GetSensors() As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		new $namespace
		set $namespace = "OPCUA"

		// Total pipeline count (no label)
		set tPipelineCount = 0

		if ##class(%Dictionary.ClassDefinition).%ExistsId(..#ProductionClass) {
			set tProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
			if $IsObject(tProd) {
				do ##class(Ens.Director).GetProductionStatus(.tRunningProd, .tProdState)
				set tProdRunning = (tRunningProd = ..#ProductionClass) && (tProdState = 1)

				set tPipelineCount = tProd.Items.Count()

				for i=1:1:tPipelineCount {
					set tCfgItem = tProd.Items.GetAt(i)
					set tName = tCfgItem.Name

					do ..SetSensor("pipeline_enabled", +tCfgItem.Enabled, tName)

					set tDSClass = ..GetSettingValue(tCfgItem, "DataSourceClass")

					set tRSCount = 0, tColCount = 0
					if tDSClass '= "" {
						set tRSData = $Get(^OPCUA.RowSource(tDSClass))
						if tRSData '= "" {
							set tRSCount = +$LI(tRSData, 1)
							set tColCount = +$LI(tRSData, 2)
						}
					}
					do ..SetSensor("pipeline_rowsources", tRSCount, tName)
					do ..SetSensor("pipeline_columns", tColCount, tName)

					set tRowCount = 0
					if (tDSClass '= "") && ##class(%Dictionary.ClassDefinition).%ExistsId(tDSClass) {
						set tPkg = $Piece(tDSClass, ".", 1, *-1)
						set tCls = $Piece(tDSClass, ".", *)
						set tSchema = $Select(tPkg="":"SQLUser", 1:$Replace(tPkg, ".", "_"))
						set tTable = tSchema_"."_tCls
						Try {
							set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_tTable)
							if $IsObject(tRS) && tRS.%Next() set tRowCount = +tRS.%GetData(1)
						} Catch (eSQL) {}
					}
					do ..SetSensor("pipeline_rows", tRowCount, tName)

					set tRunning = 0
					if tProdRunning {
						set tRunning = +##class(Ens.Director).IsItemEnabled(tName, .tSCCheck)
					}
					do ..SetSensor("pipeline_running", tRunning, tName)
				}
			}
		}

		do ..SetSensor("pipelines_total", tPipelineCount)

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Get a setting value from a config item by name.
ClassMethod GetSettingValue(pItem As Ens.Config.Item, pName As %String) As %String [ Private ]
{
	set tValue = ""
	for i=1:1:pItem.Settings.Count() {
		set tSetting = pItem.Settings.GetAt(i)
		if tSetting.Name = pName {
			set tValue = tSetting.Value
			Quit
		}
	}
	Quit tValue
}

}
