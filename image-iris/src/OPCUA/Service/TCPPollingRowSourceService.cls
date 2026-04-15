Include OPCUA.Constants

/// A business service that uses the TCPPollingInboundAdapter
/// to poll data from multiple OPC UA row sources (devices) sharing the same
/// column schema, producing one row per row source per poll cycle.
/// Each row includes a NodePath column identifying the source device.
///
/// Row sources may have partial column coverage (union merge). Missing columns
/// are stored as NULL. Column masks in ^OPCUA.RowSource control which columns
/// each row source reads.
Class OPCUA.Service.TCPPollingRowSourceService Extends Ens.BusinessService
{

Parameter ADAPTER = "OPCUA.Adapter.TCPPollingInboundAdapter";

Property Adapter As OPCUA.Adapter.TCPPollingInboundAdapter;

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

/// Nesting specification for building nested $LB storage (empty = flat layout)
Property NestingSpec As %List [ Private ];

/// Total number of $LB positions in a storage row (storage entries + 1 for class marker)
Property RowSize As %Integer [ Private ];

/// $LB position for NodePath in storage
Property NodePathPos As %Integer [ Private ];

/// $LB position for ServerTimeStamp in storage
Property ServerTSPos As %Integer [ Private ];

/// $LB position for SourceTimeStamp in storage
Property SourceTSPos As %Integer [ Private ];

/// $LB(pos1, pos2, ...) — maps data column index to $LB position in storage
Property DataColumnPositions As %List [ Private ];

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

		// Load nesting spec if present (position 5)
		set ..NestingSpec = ""
		if $LL(tRSData) >= 5 {
			set ..NestingSpec = $LI(tRSData, 5)
		}

		if ..RowSourceCount < 1 || (..ColumnCount < 1) {
			set tSC = $$$ERROR($$$GeneralError, "Invalid row source metadata: "_..RowSourceCount_" row sources, "_..ColumnCount_" columns")
			Quit
		}

		// 1b. Read compiled class storage to determine actual $LB positions.
		// IRIS default storage orders properties alphabetically, so we must
		// discover the actual positions of NodePath, ServerTimeStamp,
		// SourceTimeStamp and each data column.
		set oClassDef = ##class(%Dictionary.CompiledClass).%OpenId(tDSClass)
		if '$IsObject(oClassDef) {
			set tSC = $$$ERROR($$$GeneralError, "Cannot open compiled class: "_tDSClass)
			Quit
		}
		set oEntries = oClassDef.Storages.GetAt(1).Data.GetAt(1).Values
		set ..RowSize = oEntries.Count()
		set tDataPositions = ""
		for i=1:1:oEntries.Count() {
			set tPropName = oEntries.GetAt(i).Value
			set tPos = i
			if tPropName = "NodePath" { set ..NodePathPos = tPos }
			elseif tPropName = "ServerTimeStamp" { set ..ServerTSPos = tPos }
			elseif tPropName = "SourceTimeStamp" { set ..SourceTSPos = tPos }
			elseif $Extract(tPropName, 1) '= "%" {
				set tDataPositions = tDataPositions _ $LB(tPos)
			}
		}
		set ..DataColumnPositions = tDataPositions

		// 2. Build row source paths, column masks, active counts
		set tPaths = ""
		set tMasks = ""
		set tCounts = ""
		set ..TotalSpecEntries = 0
		for i=1:1:..RowSourceCount {
			set tRS = $LI(tRSList, i)
			// tRS = $LB(path, nodeNs, nodeId, nodeIdType, columnMask, absNodeRefs)
			set tPaths = tPaths _ $LB($LI(tRS, 1))
			set tMask = $LI(tRS, 5)
			set tMasks = tMasks _ $LB(tMask)
			// Count active columns
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

		$$$LOGINFO("Configuring OPCUA row-source polling adapter: "_..RowSourceCount_" row sources x "_..ColumnCount_" columns, "_..TotalSpecEntries_" active spec entries")

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
		// Result has TotalSpecEntries + 1 entries (first is metadata)
		set tResultIdx = 1  // current position in pInputAsList (skip metadata at pos 1)

		for iRS=1:1:..RowSourceCount {
			set tMask = $LI(..ColumnMasks, iRS)
			set tServerTS = ""
			set tSourceTS = ""
			set tGotTimestamp = 0

			// Extract flat leaf values from adapter result (ordered by mask)
			// First pass: collect all leaf values and timestamps
			kill tLeafValues
			set tLeafIdx = 0
			for iCol=1:1:..ColumnCount {
				if +$LI(tMask, iCol) {
					set tResultIdx = tResultIdx + 1
					set tDV = $LI(pInputAsList, tResultIdx)
					set tLeafIdx = tLeafIdx + 1

					if $ListValid(tDV) && ($LL(tDV) >= 4) {
						if 'tGotTimestamp {
							set tSourceTS = $LI(tDV, 1)
							set tServerTS = $LI(tDV, 2)
							set tGotTimestamp = 1
						}
						set tLeafValues(tLeafIdx) = $LI(tDV, 4)
					} else {
						set tLeafValues(tLeafIdx) = tDV
					}
				} else {
					set tLeafIdx = tLeafIdx + 1
					set tLeafValues(tLeafIdx) = ""
				}
			}

			// Build the values portion of the row data
			set tValues = ""
			if ..NestingSpec = "" {
				// No nesting: flat $LB as before
				for v=1:1:tLeafIdx {
					set tValues = tValues _ $LB($Get(tLeafValues(v)))
				}
			} else {
				// Nesting: assemble nested $LB from nesting spec
				set tValues = ..BuildNestedValues(..NestingSpec, .tLeafValues)
			}

			// Build row data matching the actual %Persistent storage layout.
			// Storage positions are alphabetical, so we place each value at
			// its compiled storage position rather than assuming a fixed order.
			set tRowData = ""
			for p=1:1:..RowSize { set tRowData = tRowData _ $LB("") }
			set $LI(tRowData, 1) = ""
			set $LI(tRowData, ..NodePathPos) = $LI(..RowSourcePaths, iRS)
			set $LI(tRowData, ..ServerTSPos) = tServerTS
			set $LI(tRowData, ..SourceTSPos) = tSourceTS
			for v=1:1:$LL(tValues) {
				if v <= $LL(..DataColumnPositions) {
					set $LI(tRowData, $LI(..DataColumnPositions, v)) = $LI(tValues, v)
				}
			}

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

/// Build a nested $LB from the nesting spec and flat leaf values.
/// For "leaf" entries, inserts the leaf value directly.
/// For "serial" entries, builds an inner $LB for the serial object's properties.
ClassMethod BuildNestedValues(pNestingSpec As %List, ByRef pLeafValues) As %List
{
	set tResult = ""
	for i=1:1:$LL(pNestingSpec) {
		set tEntry = $LI(pNestingSpec, i)
		set tType = $LI(tEntry, 1)

		if tType = "leaf" {
			set tLeafIdx = $LI(tEntry, 2)
			set tResult = tResult _ $LB($Get(pLeafValues(tLeafIdx)))
		} elseif tType = "serial" {
			// Build inner $LB for the serial object
			set tInnerSpec = $LI(tEntry, 3)
			set tAllNull = 1
			for j=1:1:$LL(tInnerSpec) {
				set tInner = $LI(tInnerSpec, j)
				set tInnerLeafIdx = $LI(tInner, 2)
				if $Get(pLeafValues(tInnerLeafIdx)) '= "" {
					set tAllNull = 0
					quit
				}
			}
			if tAllNull {
				set tResult = tResult _ $LB("")
			} else {
				set tInnerLB = ""
				for j=1:1:$LL(tInnerSpec) {
					set tInner = $LI(tInnerSpec, j)
					set tInnerLeafIdx = $LI(tInner, 2)
					set tInnerLB = tInnerLB _ $LB($Get(pLeafValues(tInnerLeafIdx)))
				}
				set tResult = tResult _ $LB(tInnerLB)
			}
		}
	}
	quit tResult
}

}
