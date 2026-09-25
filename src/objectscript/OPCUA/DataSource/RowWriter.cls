Include %occInclude

/// Shared row assembly for polling and subscription device schemas.
/// New schemas store complete OPCUA.Types DataValues, including inside folders.
/// Existing plain schemas retain their old storage layout without recompilation.
Class OPCUA.DataSource.RowWriter Extends %RegisteredObject
{

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

/// The projection records 2 for full DataValues and 1 for legacy plain values.
/// In the same leaf order used by Resolver.GetSchemaColumns() and device masks.
Property FullDataValues As %List [ Private ];

Method Initialize(pDSClass As %String) As %Status
{
	#dim tSC As %Status = $$$OK

	try {
		set tDSClass = pDSClass
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

		// Read the existing projection's leaf types rather than guessing from the
		// pipeline version. This also keeps already-deployed plain schemas working.
		set tSpec = ##class(OPCUA.DataSource.Projection).GetOPCUAConfigSpec(tDSClass)
		set tEntries = $LI(tSpec, 3)
		set ..FullDataValues = ""
		for i=2:1:$LL(tEntries) {
			set tEntry = $LI(tEntries, i)
			continue:tEntry=""
			set ..FullDataValues = ..FullDataValues _ $LB($LI(tEntry, 1) = 2)
		}

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
		set ..NodePathPos = 0, ..ServerTSPos = 0, ..SourceTSPos = 0
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

/// Build one device row. The caller owns persistence and service logging.
/// pResultIndex starts at 1 (the batch marker) and advances only for present nodes.
Method BuildRow(ByRef pInput As %List, pMask As %List, pPath As %String, ByRef pResultIndex As %Integer, Output pRow As %List) As %Status
{
	#dim tSC As %Status = $$$OK
	set pRow = ""
	try {
		if $LL(pMask) '= $LL(..FullDataValues) {
			set tSC = $$$ERROR($$$GeneralError, "Device mask does not match the compiled schema")
			Quit
		}
		set tColumnCount = $LL(pMask)
		set tServerTS = ""
		set tSourceTS = ""
		set tGotTimestamp = 0

		// Keep each leaf DataValue intact; legacy plain properties receive its value.
		// Unresolved columns consume no result entry — they are simply NULL.
		kill tLeafValues
		set tLeafIdx = 0
		for iCol=1:1:tColumnCount {
			set tLeafIdx = tLeafIdx + 1
			if '+$LI(pMask, iCol) {
				set tLeafValues(tLeafIdx) = ""
				continue
			}

			set pResultIndex = pResultIndex + 1
			set tDV = $LI(pInput, pResultIndex)

			if $ListValid(tDV) && ($LL(tDV) >= 4) {
				if 'tGotTimestamp {
					set tSourceTS = $LI(tDV, 1)
					set tServerTS = $LI(tDV, 2)
					set tGotTimestamp = 1
				}
				// A DataValue is already serialized in OPCUA.Types storage order:
				// source timestamp, server timestamp, status, value (or array values).
				set tLeafValues(tLeafIdx) = $Select($LI(..FullDataValues, iCol):tDV, 1:$LI(tDV, 4))
			} else {
				if $LI(..FullDataValues, iCol) && (tDV '= "") {
					$$$ThrowStatus($$$ERROR($$$GeneralError, "Malformed DataValue for device '"_pPath_"', column "_iCol))
				}
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
		set pRow = ""
		for p=1:1:..RowSize { set pRow = pRow _ $LB("") }
		set $LI(pRow, 1) = ""
		set $LI(pRow, ..NodePathPos) = pPath
		if ..ServerTSPos > 0 set $LI(pRow, ..ServerTSPos) = tServerTS
		if ..SourceTSPos > 0 set $LI(pRow, ..SourceTSPos) = tSourceTS
		for v=1:1:$LL(tValues) {
			if v <= $LL(..DataColumnPositions) {
				set $LI(pRow, $LI(..DataColumnPositions, v)) = $LI(tValues, v)
			}
		}
	} catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
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
