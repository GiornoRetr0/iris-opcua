Include (%occInclude, Ensemble)

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

/// 1 for each leaf typed as an OPCUA.Types.NoServerTS measurement, whose
/// stored DataValue drops the server timestamp; 0 otherwise. Same leaf order.
Property OmitServerTS As %List [ Private ];

/// Column labels for log messages ("Folder/Name", or "Name" for a flat column),
/// in the same leaf order as the masks.
Property ColumnLabels As %List [ Private ];

/// Last reading quality seen per device and column:
/// LastSeverity(devicePath, columnIndex) = 0 Good, 1 Uncertain, 2 Bad.
/// Held for the life of the service job, so a change is reported once rather
/// than on every cycle.
Property LastSeverity [ MultiDimensional, Private ];

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
		set tSC = ##class(OPCUA.DataSource.Resolver).DeriveNestingSpec(tDSClass, .tNesting, .tLeafTypes)
		Quit:$$$ISERR(tSC)
		set ..NestingSpec = tNesting
		set ..OmitServerTS = ""
		for i=1:1:$LL(tLeafTypes) {
			set ..OmitServerTS = ..OmitServerTS _ $LB(##class(OPCUA.DataSource.Resolver).OmitsServerTimeStamp($ListGet(tLeafTypes, i)))
		}

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

		set tSC = ##class(OPCUA.DataSource.Resolver).GetSchemaColumns(tDSClass, .tColumns)
		Quit:$$$ISERR(tSC)
		set ..ColumnLabels = ""
		for i=1:1:tColumns {
			set tFolder = $LI(tColumns(i), 5)
			set ..ColumnLabels = ..ColumnLabels _ $LB($Select(tFolder = "":"", 1:tFolder_"/")_$LI(tColumns(i), 3))
		}
		kill ..LastSeverity

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
///
/// pQualityChanges lists the columns whose reading quality changed since this
/// device's previous row, as $LB($LB(columnIndex, oldSeverity, newSeverity, status), ...)
/// with severity 0 Good, 1 Uncertain, 2 Bad and oldSeverity "" on a first reading.
/// A first reading that is Good is not a change. Hand it to
/// <method>LogQualityChanges</method>.
Method BuildRow(ByRef pInput As %List, pMask As %List, pPath As %String, ByRef pResultIndex As %Integer, Output pRow As %List, Output pQualityChanges As %List) As %Status
{
	#dim tSC As %Status = $$$OK
	set pRow = ""
	set pQualityChanges = ""
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
					set tSourceTS = $ListGet(tDV, 1)
					set tServerTS = $ListGet(tDV, 2)
					set tGotTimestamp = 1
				}
				// A DataValue is already serialized in OPCUA.Types storage order:
				// source timestamp, server timestamp, status, value (or array values).
				// A Bad reading has no value, so element 4 is null: $ListGet, not $List.
				set tLeafValues(tLeafIdx) = $Select($LI(..FullDataValues, iCol):tDV, 1:$ListGet(tDV, 4))
				// A NoServerTS measurement stores everything but element 2. The range
				// form keeps null elements (a Bad reading's value) and every payload
				// field after the status.
				if $LI(..FullDataValues, iCol) && $ListGet(..OmitServerTS, iCol) {
					set tLeafValues(tLeafIdx) = $List(tDV, 1, 1) _ $List(tDV, 3, *)
				}

				// Severity is the top two bits of the StatusCode; 3 is reserved and
				// counts as Bad.
				set tStatus = +$ListGet(tDV, 3)
				set tSeverity = $Select(tStatus \ 1073741824 >= 2:2, 1:tStatus \ 1073741824)
				set tLast = $Get(..LastSeverity(pPath, iCol))
				if (tLast '= tSeverity) && '((tLast = "") && (tSeverity = 0)) {
					set pQualityChanges = pQualityChanges _ $LB($LB(iCol, tLast, tSeverity, tStatus))
				}
				set ..LastSeverity(pPath, iCol) = tSeverity
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

/// Write one event-log entry for a device's quality changes from
/// <method>BuildRow</method>: a warning if any column got worse, otherwise an
/// informational line. Columns that changed the same way are grouped, so a
/// device going offline is one line however many columns it has.
Method LogQualityChanges(pPath As %String, pQualityChanges As %List)
{
	Quit:pQualityChanges=""
	set tWorse = 0
	kill tGroups
	for i=1:1:$LL(pQualityChanges) {
		set tChange = $LI(pQualityChanges, i)
		set tOld = $LI(tChange, 2), tNew = $LI(tChange, 3), tStatus = $LI(tChange, 4)
		set:(tOld = "")||(tNew > tOld) tWorse = 1
		set tKey = tOld_"|"_tNew_"|"_tStatus
		set tGroups(tKey) = $Get(tGroups(tKey)) _ $LB($ListGet(..ColumnLabels, $LI(tChange, 1)))
	}

	set tNames = $LB("Good", "Uncertain", "Bad")
	set tText = ""
	set tKey = ""
	for {
		set tKey = $Order(tGroups(tKey))
		quit:tKey=""
		set tOld = $Piece(tKey, "|", 1), tNew = $Piece(tKey, "|", 2), tStatus = $Piece(tKey, "|", 3)
		set tPart = $ListToString(tGroups(tKey), ", ")_": "
		set tPart = tPart _ $Select(tOld = "":"", 1:$LI(tNames, tOld + 1)_" -> ")_$LI(tNames, tNew + 1)
		// Name the status unless it is plain Good, which says nothing new.
		if tStatus '= 0 {
			set tName = ""
			Try { do ##class(OPCUA.Client).GetStatusCodeName(.tName, tStatus) } Catch (e) {}
			set tPart = tPart _ " ("_$Select(tName '= "":tName, 1:"status "_tStatus)_")"
		}
		set tText = tText _ $Select(tText = "":"", 1:"; ") _ tPart
	}

	set tMsg = "Device '"_pPath_"': reading quality "_$Select(tWorse:"degraded", 1:"recovered")_" - "_tText
	if tWorse {
		$$$LOGWARNING(tMsg)
	} else {
		$$$LOGINFO(tMsg)
	}
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
