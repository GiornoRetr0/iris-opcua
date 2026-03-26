Include OPCUA.Constants

/// A business service that uses the TCPSubscriptionInboundAdapter
/// to receive change notifications from multiple OPC UA row sources (devices)
/// sharing the same column schema, producing one row per row source per notification.
/// Each row includes a NodePath column identifying the source device.
///
/// Row sources may have partial column coverage (union merge). Missing columns
/// are stored as NULL. Column masks in ^OPCUA.RowSource control which columns
/// each row source monitors.
Class OPCUA.Service.TCPSubscriptionRowSourceService Extends Ens.BusinessService
{

Parameter ADAPTER = "OPCUA.Adapter.TCPSubscriptionInboundAdapter";

Property Adapter As OPCUA.Adapter.TCPSubscriptionInboundAdapter;

/// Number of row sources (devices)
Property RowSourceCount As %Integer [ Private ];

/// Number of union columns
Property ColumnCount As %Integer [ Private ];

/// $LB(path1, path2, ...) — NodePath values for each row source
Property RowSourcePaths As %List [ Private ];

/// $LB($LB(1,0,1,...), $LB(1,1,1,...), ...) — column masks per row source
Property ColumnMasks As %List [ Private ];

/// $LB(count1, count2, ...) — number of active (mask=1) columns per row source
Property ActiveCounts As %List [ Private ];

/// Total number of spec entries (sum of active counts across all row sources)
Property TotalSpecEntries As %Integer [ Private ];

Method OnInit() As %Status
{
	#dim tSC As %Status = $$$OK

	try {
		set tDSClass = ..Adapter.DataSourceClass
		if tDSClass = "" {
			set tSC = $$$ERROR($$$GeneralError, "DataSourceClass is not configured")
			Quit
		}

		// 1. Load row source metadata
		set tRSData = $Get(^OPCUA.RowSource(tDSClass))
		if tRSData = "" {
			set tSC = $$$ERROR($$$GeneralError, "No row source metadata found for "_tDSClass)
			Quit
		}

		set ..RowSourceCount = $LI(tRSData, 1)
		set ..ColumnCount = $LI(tRSData, 2)
		set tRSList = $LI(tRSData, 3)

		if ..RowSourceCount < 1 || (..ColumnCount < 1) {
			set tSC = $$$ERROR($$$GeneralError, "Invalid row source metadata: "_..RowSourceCount_" row sources, "_..ColumnCount_" columns")
			Quit
		}

		// 2. Build row source paths, column masks, active counts
		set tPaths = ""
		set tMasks = ""
		set tCounts = ""
		set ..TotalSpecEntries = 0
		for i=1:1:..RowSourceCount {
			set tRS = $LI(tRSList, i)
			set tPaths = tPaths _ $LB($LI(tRS, 1))
			set tMask = $LI(tRS, 5)
			set tMasks = tMasks _ $LB(tMask)
			set tActive = 0
			for c=1:1:..ColumnCount {
				if +$LI(tMask, c) set tActive = tActive + 1
			}
			set tCounts = tCounts _ $LB(tActive)
			set ..TotalSpecEntries = ..TotalSpecEntries + tActive
		}
		set ..RowSourcePaths = tPaths
		set ..ColumnMasks = tMasks
		set ..ActiveCounts = tCounts

		// 3. Get the column spec template from Projection
		set tBaseSpec = ##class(OPCUA.DataSource.Projection).GetOPCUAConfigSpec(tDSClass)
		set tDSName = $LI(tBaseSpec, 1)
		set tStorageGlobal = $LI(tBaseSpec, 2)
		set tColumnSpec = $LI(tBaseSpec, 3)

		// 4. Build combined specification: only active columns per row source
		set tCombinedEntries = $LB("")
		for iRS=1:1:..RowSourceCount {
			set tRS = $LI(tRSList, iRS)
			set tMask = $LI(tRS, 5)
			set tAbsNodeRefs = $LI(tRS, 6)

			set tRefIdx = 0
			for iCol=1:1:..ColumnCount {
				if '+$LI(tMask, iCol) continue
				set tRefIdx = tRefIdx + 1

				set tColEntry = $LI(tColumnSpec, iCol + 1)
				set tAbsRef = $LI(tAbsNodeRefs, tRefIdx)
				set tAbsNS = $LI(tAbsRef, 1)
				set tAbsNodeId = $LI(tAbsRef, 2)

				set tNewEntry = $LB(
					2,
					$LI(tColEntry, 2)_"_RS"_iRS,
					tAbsNS,
					tAbsNodeId,
					$LI(tColEntry, 5)
				)
				set tCombinedEntries = tCombinedEntries _ $LB(tNewEntry)
			}
		}

		set tCombinedSpec = $LB(tDSName, tStorageGlobal, tCombinedEntries)

		$$$LOGINFO("Configuring OPCUA row-source subscription adapter: "_..RowSourceCount_" row sources x "_..ColumnCount_" columns, "_..TotalSpecEntries_" monitored items")

		set tSC = ..Adapter.Configure(.tCombinedSpec)

	} catch (e) {
		set tSC = e.AsStatus()
	}

	Quit tSC
}

Method OnProcessInput(ByRef pInputAsList As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	#dim tSC As %Status = $$$OK

	try {
		set tResultIdx = 1

		for iRS=1:1:..RowSourceCount {
			set tMask = $LI(..ColumnMasks, iRS)
			set tServerTS = ""
			set tSourceTS = ""
			set tGotTimestamp = 0

			set tValues = ""
			for iCol=1:1:..ColumnCount {
				if +$LI(tMask, iCol) {
					set tResultIdx = tResultIdx + 1
					set tDV = $LI(pInputAsList, tResultIdx)

					if $ListValid(tDV) && ($LL(tDV) >= 4) {
						if 'tGotTimestamp {
							set tSourceTS = $LI(tDV, 1)
							set tServerTS = $LI(tDV, 2)
							set tGotTimestamp = 1
						}
						set tValues = tValues _ $LB($LI(tDV, 4))
					} else {
						set tValues = tValues _ $LB(tDV)
					}
				} else {
					set tValues = tValues _ $LB("")
				}
			}

			set tRowData = $LB("", $LI(..RowSourcePaths, iRS), tServerTS, tSourceTS) _ tValues

			set tSC = $CLASSMETHOD(..Adapter.DataSourceClass, "SaveSourcedData", .tRowData)
			if $$$ISERR(tSC) {
				$$$LOGERROR("Failed to save row source "_iRS_" ("_$LI(..RowSourcePaths, iRS)_"): "_$System.Status.GetErrorText(tSC))
				set tSC = $$$OK
			}
		}

	} catch (e) {
		set tSC = e.AsStatus()
	}

	return tSC
}

}
