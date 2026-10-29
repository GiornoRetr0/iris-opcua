Include (OPCUA.Constants, %occInclude)

/// Fixtures shared by <class>OPCUA.Tests.Unit.MeasurementMetadataTest</class> and
/// <class>OPCUA.Tests.Live.MeasurementMetadataTest</class>: throwaway schemas built
/// through the real generator, and SQL/storage readers. Holds no tests, and lives
/// outside the Unit and Live packages so the runner never collects it.
Class OPCUA.Tests.MeasurementMetadataBase Extends %UnitTest.TestCase [ Abstract ]
{

/// Package the throwaway generated classes live in.
Parameter TestPackage = "OPCUA.Tests.Tmp";

/// The live server, as set by <method>OPCUA.Tests.Runner.Live</method>.
ClassMethod URL() As %String [ CodeMode = expression ]
{
$Get(^||OPCUA.Tests("url"), "opc.tcp://plc")
}

/// Feed one row whose columns have the given statuses (by column name order
/// Alpha, Beta, Gamma) and return BuildRow's quality changes.
ClassMethod QualityCycle(pWriter, pPath As %String, ByRef pPos, pStatuses As %List, pMaskByName As %List) As %List [ Private ]
{
    set tNames = $LB("Alpha", "Beta", "Gamma")
    set tCount = $LL(tNames)
    kill tStatus, tMaskAt
    for n=1:1:tCount {
        set tStatus(pPos($LI(tNames, n))) = $LI(pStatuses, n)
        set tMaskAt(pPos($LI(tNames, n))) = $LI(pMaskByName, n)
    }
    set tMask = "", tInput = $LB("")
    for i=1:1:tCount {
        set tMask = tMask _ $LB(tMaskAt(i))
        continue:'tMaskAt(i)
        set tInput = tInput _ $LB($LB("2026-06-06 06:06:06", "2026-06-06 06:06:07", tStatus(i), $Select(tStatus(i) \ 1073741824 >= 2:"", 1:1)))
    }
    set tResultIdx = 1
    $$$ThrowOnError(pWriter.BuildRow(.tInput, tMask, pPath, .tResultIdx, .tRow, .tChanges))
    quit tChanges
}

/// Define and compile a one-property Definition subclass. pPlain 1 types the
/// property %String, which the Projection skips when it is NodePath.
ClassMethod CompileDefinition(pClassName As %String, pPropName As %String, pPlain As %Boolean) As %Status [ Private ]
{
    #dim tSC As %Status = $$$OK
    Try {
        do ..DropSchema(pClassName)
        set tDef = ##class(%Dictionary.ClassDefinition).%New(pClassName)
        set tDef.Super = "%Persistent,OPCUA.DataSource.Definition"
        set tParam = ##class(%Dictionary.ParameterDefinition).%New()
        set tParam.Name = "OPCUADATASOURCE"
        set tParam.Default = "TmpProjectionSchema"
        do tDef.Parameters.Insert(tParam)
        set tProp = ##class(%Dictionary.PropertyDefinition).%New()
        set tProp.Name = pPropName
        set tProp.Type = $Select(pPlain:"%String", 1:"OPCUA.Types.DoubleDataValue")
        do tProp.Parameters.SetAt(pPropName, "OPCUANODENAME")
        do tDef.Properties.Insert(tProp)
        $$$ThrowOnError(tDef.%Save())
        set tSC = $System.OBJ.Compile(pClassName, "ck-d")
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

/// Upper-cased SQL column names of a class's table, as ",A,B,...,".
ClassMethod SqlFields(pClassName As %String) As %String [ Private ]
{
    set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT * FROM "_..TableName(pClassName)_" WHERE 1=0")
    set tMeta = tRS.%GetMetadata()
    set tFields = ","
    for i=1:1:tMeta.columnCount {
        set tFields = tFields _ $ZConvert(tMeta.columns.GetAt(i).colName, "U") _ ","
    }
    Quit tFields
}

/// A serial class's storage entries, in order.
ClassMethod StorageValues(pClassName As %String) As %List [ Private ]
{
    set tList = ""
    set tVals = ##class(%Dictionary.CompiledClass).%OpenId(pClassName).Storages.GetAt(1).Data.GetAt(1).Values
    for i=1:1:tVals.Count() { set tList = tList _ $LB(tVals.GetAt(i).Value) }
    Quit tList
}

// ==================== fixtures ====================

/// Generate a schema through the real wizard path, so the test exercises
/// OPCUA.REST.SchemaService rather than a hand-built approximation.
/// pFlat 1 = three flat columns; 0 = one flat column plus a two-leaf folder;
/// 2 = the flat set with a LocalizedText column (a two-field payload) as Gamma.
ClassMethod BuildGeneratedSchema(pClassName As %String, pDSName As %String, pFlat As %Integer, pIncludeServerTS As %Boolean = 1) As %Status [ Private ]
{
    #dim tSC As %Status = $$$OK
    Try {
        do ..DropSchema(pClassName)

        set tCols = []
        if pFlat {
            do tCols.%Push(..Column("Alpha", "OPCUA.Types.DoubleDataValue", $LB("Alpha")))
            do tCols.%Push(..Column("Beta", "OPCUA.Types.IntegerDataValue", $LB("Beta")))
            do tCols.%Push(..Column("Gamma", $Select(pFlat = 2:"OPCUA.Types.LocalizedTextDataValue", 1:"OPCUA.Types.StringDataValue"), $LB("Gamma")))
        } else {
            do tCols.%Push(..Column("Humidity", "OPCUA.Types.IntegerDataValue", $LB("Humidity")))
            do tCols.%Push(..Column("Temperature", "OPCUA.Types.DoubleDataValue", $LB("Motor", "Temperature")))
            do tCols.%Push(..Column("Speed", "OPCUA.Types.IntegerDataValue", $LB("Motor", "Speed")))
        }

        kill tColNS
        set tSC = ##class(OPCUA.REST.SchemaService).GenerateSchemaClass(pClassName, pDSName, tCols, 1, .tColNS, .tSerial, pIncludeServerTS)
        $$$ThrowOnError(tSC)
        Try { do $classmethod(pClassName, "%KillExtent") } Catch (eKill) {}
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

/// A schema whose columns are node names the plc mock server really exposes.
ClassMethod BuildLiveSchema(pClassName As %String, pDSName As %String = "TmpLiveMetaSchema", pIncludeServerTS As %Boolean = 1) As %Status [ Private ]
{
    #dim tSC As %Status = $$$OK
    Try {
        do ..DropSchema(pClassName)

        set tCols = []
        for tName = "SA1", "SA2", "VT5" {
            do tCols.%Push(..Column(tName, "OPCUA.Types.IntegerDataValue", $LB(tName)))
        }

        kill tColNS
        set tSC = ##class(OPCUA.REST.SchemaService).GenerateSchemaClass(pClassName, pDSName, tCols, 1, .tColNS, .tSerial, pIncludeServerTS)
        $$$ThrowOnError(tSC)
        Try { do $classmethod(pClassName, "%KillExtent") } Catch (eKill) {}
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

/// A schema in the old shape: plain columns plus one row-level timestamp pair.
/// Written by hand because the generator deliberately cannot produce it any more.
ClassMethod BuildLegacyPlainSchema(pClassName As %String) As %Status [ Private ]
{
    #dim tSC As %Status = $$$OK
    Try {
        do ..DropSchema(pClassName)

        set tDef = ##class(%Dictionary.ClassDefinition).%New(pClassName)
        set tDef.Description = "Throwaway pre-metadata schema for OPCUA.Tests.MeasurementMetadataTest."
        set tDef.Super = "%Persistent,OPCUA.DataSource.DeviceSchema"

        for tSpec = "OPCUADATASOURCE:TmpLegacySchema", "OPCUDEFAULTANAMESPACE:1", "OPCUAPIPELINEVERSION:2" {
            set tParam = ##class(%Dictionary.ParameterDefinition).%New()
            set tParam.Name = $Piece(tSpec, ":", 1)
            set tParam.Default = $Piece(tSpec, ":", 2)
            do tDef.Parameters.Insert(tParam)
        }

        set tProp = ##class(%Dictionary.PropertyDefinition).%New()
        set tProp.Name = "NodePath"
        set tProp.Type = "%String"
        do tProp.Parameters.SetAt(500, "MAXLEN")
        do tDef.Properties.Insert(tProp)

        for tName = "ServerTimeStamp", "SourceTimeStamp" {
            set tProp = ##class(%Dictionary.PropertyDefinition).%New()
            set tProp.Name = tName
            set tProp.Type = "%TimeStamp"
            do tDef.Properties.Insert(tProp)
        }

        for tSpec = "Alpha:%Double", "Beta:%Integer" {
            set tProp = ##class(%Dictionary.PropertyDefinition).%New()
            set tProp.Name = $Piece(tSpec, ":", 1)
            set tProp.Type = $Piece(tSpec, ":", 2)
            do tProp.Parameters.SetAt($Piece(tSpec, ":", 1), "OPCUANODENAME")
            do tDef.Properties.Insert(tProp)
        }

        set tSC = tDef.%Save()
        $$$ThrowOnError(tSC)
        set tSC = $System.OBJ.Compile(pClassName, "ck-d")
        $$$ThrowOnError(tSC)
        Try { do $classmethod(pClassName, "%KillExtent") } Catch (eKill) {}
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

/// One column description in the shape the frontend posts to /schemas.
ClassMethod Column(pDisplayName As %String, pInferredType As %String, pRelPath As %List) As %DynamicObject [ Private ]
{
    set tCol = {}
    set tCol.displayName = pDisplayName
    set tCol.inferredType = pInferredType
    set tPath = []
    for i=1:1:$LL(pRelPath) {
        do tPath.%Push($LI(pRelPath, i))
    }
    set tCol.relativePath = tPath
    Quit tCol
}

/// Map column index → $LB(nodeName, folderName), in the order the masks use.
ClassMethod ColumnIndex(pClassName As %String, Output pIndex, Output pCount) As %Status [ Private ]
{
    kill pIndex
    set pCount = 0
    set tSC = ##class(OPCUA.DataSource.Resolver).GetSchemaColumns(pClassName, .tColumns, .tFolders)
    Quit:$$$ISERR(tSC) tSC
    set pCount = tColumns
    for i=1:1:tColumns {
        set pIndex(i) = $LB($LI(tColumns(i), 3), $LI(tColumns(i), 5))
    }
    Quit $$$OK
}

/// SQL table name for a class.
ClassMethod TableName(pClassName As %String) As %String [ Private ]
{
    Quit $Translate($Piece(pClassName, ".", 1, *-1), ".", "_")_"."_$Piece(pClassName, ".", *)
}

/// Delete a throwaway schema and any serial classes generated beneath it.
ClassMethod DropSchema(pClassName As %String) [ Private ]
{
    Try { do $classmethod(pClassName, "%KillExtent") } Catch (e) {}
    Try { do $System.OBJ.Delete(pClassName_".*", "-d") } Catch (e) {}
    Try { do $System.OBJ.Delete(pClassName, "-d") } Catch (e) {}
    kill ^OPCUA.DataSource(pClassName)
}

}
