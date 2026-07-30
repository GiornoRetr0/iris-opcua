Include OPCUA.Constants

/// A business service that uses the TCPPollingInboundAdapter
/// to poll data from multiple OPC UA devices sharing the same device schema,
/// producing one row per device per poll cycle.
/// Each row includes a NodePath column identifying the source device.
///
/// The device list comes from the adapter's DeviceNodePaths setting, and each
/// device's nodes are resolved by name at connect time (see
/// <class>OPCUA.DataSource.Resolver</class>). Devices may have partial column
/// coverage: a column with no matching node on a given device is stored as NULL
/// and logged. Adding a device is therefore a one-line setting edit — no
/// regeneration, no recompile.
Class OPCUA.Service.TCPPollingRowSourceService Extends Ens.BusinessService
{

Parameter ADAPTER = "OPCUA.Adapter.TCPPollingInboundAdapter";

Property Adapter As OPCUA.Adapter.TCPPollingInboundAdapter;

/// Nesting specification for building nested $LB storage (empty = flat layout).
/// Derived from the compiled schema class at OnInit().
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

		if '##class(%Dictionary.CompiledClass).%ExistsId(tDSClass) {
			set tSC = $$$ERROR($$$GeneralError, "Schema class '"_tDSClass_"' does not exist or is not compiled")
			Quit
		}

		// Read compiled class storage to determine actual $LB positions.
		// IRIS default storage orders properties alphabetically, so we must
		// discover the actual positions of NodePath, ServerTimeStamp,
		// SourceTimeStamp and each data column.
		set tSC = ..DiscoverStorageLayout(tDSClass)
		Quit:$$$ISERR(tSC)

		// Derive the nesting layout from the class rather than from stored
		// metadata, so it can never go stale relative to the compiled schema.
		set tSC = ##class(OPCUA.DataSource.Resolver).DeriveNestingSpec(tDSClass, .tNesting)
		Quit:$$$ISERR(tSC)
		set ..NestingSpec = tNesting

		// The specification itself is resolved by the adapter once connected —
		// browsing the devices requires a live session. See
		// OPCUA.Adapter.TCPPollingInboundAdapter.ResolveSpecification().

	} catch (e) {
		set tSC = e.AsStatus()
	}

	Quit tSC
}

/// Discover the compiled storage layout: row width and the $LB position of
/// NodePath, the two timestamps, and each data column.
Method DiscoverStorageLayout(pDSClass As %String) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	try {
		set oClassDef = ##class(%Dictionary.CompiledClass).%OpenId(pDSClass)
		if '$IsObject(oClassDef) {
			set tSC = $$$ERROR($$$GeneralError, "Cannot open compiled class: "_pDSClass)
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
	} catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

Method OnProcessInput(ByRef pInputAsList As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	#dim tSC As %Status = $$$OK

	try {
		// Masks and NodePath values are discovered per connect by the adapter.
		set tMasks = ..Adapter.RowSourceMasks
		set tPaths = ..Adapter.RowSourcePaths
		set tRSCount = $LL(tMasks)

		if tRSCount = 0 {
			// Nothing resolved (e.g. every device unreachable) — no rows to write.
			Quit
		}

		// Result has one entry per resolved node, plus metadata at position 1.
		set tResultIdx = 1

		for iRS=1:1:tRSCount {
			set tMask = $LI(tMasks, iRS)
			set tColumnCount = $LL(tMask)
			set tServerTS = ""
			set tSourceTS = ""
			set tGotTimestamp = 0

			// Extract flat leaf values from adapter result (ordered by mask).
			// Unresolved columns consume no result entry — they are simply NULL.
			kill tLeafValues
			set tLeafIdx = 0
			for iCol=1:1:tColumnCount {
				set tLeafIdx = tLeafIdx + 1
				if '+$LI(tMask, iCol) {
					set tLeafValues(tLeafIdx) = ""
					continue
				}

				set tResultIdx = tResultIdx + 1
				set tDV = $LI(pInputAsList, tResultIdx)

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
			}

			// Build the values portion of the row data
			set tValues = ""
			if ..NestingSpec = "" {
				// No nesting: flat $LB
				for v=1:1:tLeafIdx {
					set tValues = tValues _ $LB($Get(tLeafValues(v)))
				}
			} else {
				// Nesting: assemble nested $LB from the derived nesting spec
				set tValues = ..BuildNestedValues(..NestingSpec, .tLeafValues)
			}

			// Build row data matching the actual %Persistent storage layout.
			// Storage positions are alphabetical, so we place each value at
			// its compiled storage position rather than assuming a fixed order.
			set tRowData = ""
			for p=1:1:..RowSize { set tRowData = tRowData _ $LB("") }
			set $LI(tRowData, 1) = ""
			set $LI(tRowData, ..NodePathPos) = $LI(tPaths, iRS)
			set $LI(tRowData, ..ServerTSPos) = tServerTS
			set $LI(tRowData, ..SourceTSPos) = tSourceTS
			for v=1:1:$LL(tValues) {
				if v <= $LL(..DataColumnPositions) {
					set $LI(tRowData, $LI(..DataColumnPositions, v)) = $LI(tValues, v)
				}
			}

			set tSC = $CLASSMETHOD(..Adapter.DataSourceClass, "SaveSourcedData", .tRowData)
			if $$$ISERR(tSC) {
				$$$LOGERROR("Failed to save device "_iRS_" ("_$LI(tPaths, iRS)_"): "_$System.Status.GetErrorText(tSC))
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
