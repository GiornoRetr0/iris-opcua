Include OPCUA.Constants

/// A business service that uses the TCPSubscriptionInboundAdapter
/// to receive change notifications from multiple OPC UA row sources (devices)
/// sharing the same column schema, producing one row per row source per notification.
/// Each row includes a NodePath column identifying the source device.
///
/// Row source metadata is stored in ^OPCUA.RowSource(DataSourceClass) at deploy time.
/// The service builds a combined specification (N row sources x M columns) and
/// splits each notification batch item back into N rows.
Class OPCUA.Service.TCPSubscriptionRowSourceService Extends Ens.BusinessService
{

Parameter ADAPTER = "OPCUA.Adapter.TCPSubscriptionInboundAdapter";

Property Adapter As OPCUA.Adapter.TCPSubscriptionInboundAdapter;

/// Number of row sources (devices)
Property RowSourceCount As %Integer [ Private ];

/// Number of columns per row source
Property ColumnCount As %Integer [ Private ];

/// $LB(path1, path2, ...) — NodePath values for each row source
Property RowSourcePaths As %List [ Private ];

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
			set tSC = $$$ERROR($$$GeneralError, "No row source metadata found for "_tDSClass_". Expected ^OPCUA.RowSource entry.")
			Quit
		}

		set ..RowSourceCount = $LI(tRSData, 1)
		set ..ColumnCount = $LI(tRSData, 2)
		set tRSList = $LI(tRSData, 3)

		if ..RowSourceCount < 1 || (..ColumnCount < 1) {
			set tSC = $$$ERROR($$$GeneralError, "Invalid row source metadata: "_..RowSourceCount_" row sources, "_..ColumnCount_" columns")
			Quit
		}

		// 2. Build row source paths list
		set tPaths = ""
		for i=1:1:..RowSourceCount {
			set tRS = $LI(tRSList, i)
			set tPaths = tPaths _ $LB($LI(tRS, 1))
		}
		set ..RowSourcePaths = tPaths

		// 3. Get the column spec template from Projection
		set tBaseSpec = ##class(OPCUA.DataSource.Projection).GetOPCUAConfigSpec(tDSClass)
		set tDSName = $LI(tBaseSpec, 1)
		set tStorageGlobal = $LI(tBaseSpec, 2)
		set tColumnSpec = $LI(tBaseSpec, 3)

		// 4. Build combined specification: N row sources x M columns
		set tCombinedEntries = $LB("")
		for iRS=1:1:..RowSourceCount {
			set tRS = $LI(tRSList, iRS)
			set tAbsNodeRefs = $LI(tRS, 5)

			for iCol=1:1:..ColumnCount {
				set tColEntry = $LI(tColumnSpec, iCol + 1)
				set tAbsRef = $LI(tAbsNodeRefs, iCol)
				set tAbsNS = $LI(tAbsRef, 1)
				set tAbsNodeId = $LI(tAbsRef, 2)

				// Force type 2 so C++ returns full DataValue with timestamps
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

		$$$LOGINFO("Configuring OPCUA row-source subscription adapter: "_..RowSourceCount_" row sources x "_..ColumnCount_" columns = "_..RowSourceCount*..ColumnCount_" monitored items")

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
		set tExpectedLen = ..RowSourceCount * ..ColumnCount + 1
		set tActualLen = $LL(pInputAsList)

		if tActualLen < tExpectedLen {
			$$$LOGWARNING("Row source subscription result length mismatch: expected "_tExpectedLen_", got "_tActualLen)
		}

		// Split the flat result into N rows, one per row source.
		// Each element is a serialized DataValue: $LB(sourceTS, serverTS, status, value)
		for iRS=1:1:..RowSourceCount {
			set tOffset = (iRS - 1) * ..ColumnCount
			set tServerTS = ""
			set tSourceTS = ""

			set tRowData = $LB("")
			set tRowData = tRowData _ $LB($LI(..RowSourcePaths, iRS))

			// Extract raw values from each DataValue
			set tValues = ""
			for iCol=1:1:..ColumnCount {
				set tValIndex = tOffset + iCol + 1
				set tDV = $LI(pInputAsList, tValIndex)

				if $ListValid(tDV) && ($LL(tDV) >= 4) {
					if iCol = 1 {
						set tSourceTS = $LI(tDV, 1)
						set tServerTS = $LI(tDV, 2)
					}
					set tValues = tValues _ $LB($LI(tDV, 4))
				} else {
					set tValues = tValues _ $LB(tDV)
				}
			}

			// Assemble: $LB("", nodePath, serverTS, sourceTS, val1, val2, ...)
			set tRowData = tRowData _ $LB(tServerTS, tSourceTS) _ tValues

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
