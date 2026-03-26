Include OPCUA.Constants

/// A business service that uses the TCPPollingInboundAdapter
/// to poll data from multiple OPC UA row sources (devices) sharing the same
/// column schema, producing one row per row source per poll cycle.
/// Each row includes a NodePath column identifying the source device.
///
/// Row source metadata is stored in ^OPCUA.RowSource(DataSourceClass) at deploy time.
/// The service builds a combined specification (N row sources x M columns) and
/// splits the flat poll result back into N rows.
Class OPCUA.Service.TCPPollingRowSourceService Extends Ens.BusinessService
{

Parameter ADAPTER = "OPCUA.Adapter.TCPPollingInboundAdapter";

Property Adapter As OPCUA.Adapter.TCPPollingInboundAdapter;

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

		// tColumnSpec = $LB("", $LB(type,propPath,ns,nodeId,attr), $LB(...), ...)
		// First element is empty/class name, then M column entries

		// 4. Build combined specification: N row sources x M columns
		set tCombinedEntries = $LB("")
		for iRS=1:1:..RowSourceCount {
			set tRS = $LI(tRSList, iRS)
			// tRS = $LB(path, nodeNs, nodeId, nodeIdType, $LB($LB(ns,id,idType), ...))
			set tAbsNodeRefs = $LI(tRS, 5)

			for iCol=1:1:..ColumnCount {
				// Get the template column entry
				set tColEntry = $LI(tColumnSpec, iCol + 1)

				// Get the absolute node reference for this row source + column
				set tAbsRef = $LI(tAbsNodeRefs, iCol)
				// tAbsRef = $LB(ns, nodeId, nodeIdType)
				set tAbsNS = $LI(tAbsRef, 1)
				set tAbsNodeId = $LI(tAbsRef, 2)

				// Build entry: force type 2 (OPCUA structure) so C++ returns full DataValue
				// with timestamps, even though the DataSource uses plain types
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

		$$$LOGINFO("Configuring OPCUA row-source polling adapter: "_..RowSourceCount_" row sources x "_..ColumnCount_" columns = "_..RowSourceCount*..ColumnCount_" nodes")

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
			$$$LOGWARNING("Row source poll result length mismatch: expected "_tExpectedLen_", got "_tActualLen)
		}

		// Split the flat result into N rows, one per row source.
		// Each element from ReadBulkPollC is a serialized DataValue: $LB(sourceTS, serverTS, status, value)
		// We unwrap to extract raw values and shared timestamps per row.
		for iRS=1:1:..RowSourceCount {
			set tOffset = (iRS - 1) * ..ColumnCount
			set tServerTS = ""
			set tSourceTS = ""

			// Build $LB("", nodePath, serverTS, sourceTS, val1, val2, ..., valM)
			// Position 1: empty (standard convention)
			// Position 2: NodePath
			// Position 3: ServerTimeStamp (shared)
			// Position 4: SourceTimeStamp (shared)
			// Positions 5..M+4: raw column values
			set tRowData = $LB("")
			set tRowData = tRowData _ $LB($LI(..RowSourcePaths, iRS))

			// Placeholder for timestamps — filled from first column's DataValue
			set tTSPos = $LL(tRowData) + 1

			// Extract raw values from each DataValue
			set tValues = ""
			for iCol=1:1:..ColumnCount {
				set tValIndex = tOffset + iCol + 1
				set tDV = $LI(pInputAsList, tValIndex)

				// DataValue is serialized as $LB(sourceTS, serverTS, status, value)
				if $ListValid(tDV) && ($LL(tDV) >= 4) {
					// Extract shared timestamps from the first column
					if iCol = 1 {
						set tSourceTS = $LI(tDV, 1)
						set tServerTS = $LI(tDV, 2)
					}
					// Extract raw value (position 4)
					set tValues = tValues _ $LB($LI(tDV, 4))
				} else {
					// Fallback: not a DataValue structure, store as-is
					set tValues = tValues _ $LB(tDV)
				}
			}

			// Assemble: $LB("", nodePath, serverTS, sourceTS, val1, val2, ...)
			set tRowData = tRowData _ $LB(tServerTS, tSourceTS) _ tValues

			set tSC = $CLASSMETHOD(..Adapter.DataSourceClass, "SaveSourcedData", .tRowData)
			if $$$ISERR(tSC) {
				$$$LOGERROR("Failed to save row source "_iRS_" ("_$LI(..RowSourcePaths, iRS)_"): "_$System.Status.GetErrorText(tSC))
				// Continue with remaining row sources
				set tSC = $$$OK
			}
		}

	} catch (e) {
		set tSC = e.AsStatus()
	}

	return tSC
}

}
