/// Comes with OPCUA Adapter
/// https://docs.intersystems.com/irislatest/csp/docbook/Doc.View.cls?KEY=GOBJ_projections
Class OPCUA.DataSource.Projection Extends %Projection.AbstractProjection
{

/// This method is invoked when a class is compiled
ClassMethod CreateProjection(cls As %String, ByRef params) As %Status
{
    #Dim oClassDef As %Dictionary.CompiledClass

    Set tSC = $$$OK
    Try 
    {
        // We don't do nothing when the basic OPCUA.DataSourceDef class definition is compiled
        Quit:cls="OPCUA.DataSource.Definition"

        Set oClassDef = ##class(%Dictionary.CompiledClass).%OpenId(cls)
        
        Set tDataSourceName = ..GetParameterValue(oClassDef, "OPCUADATASOURCE")

        If tDataSourceName=""
        {
            Set tSC = $$$ERROR(5001, "OPCUADATASOURCE parameter is not defined in "_cls)
            Quit
        }

        Set tOPCUADefaultNamespace = ..GetParameterValue(oClassDef, "OPCUDEFAULTANAMESPACE")        

        Set tSC = ..ProcessObj(oClassDef, tOPCUADefaultNamespace, "", "["_tDataSourceName_"]", .lConfigSpec)
        Quit:$$$ISERR(tSC)

        Set tStorageGlobal = oClassDef.Storages.GetAt(1).DataLocation

        Do ..CommitOPCUAConfigSpec(tDataSourceName, cls, tStorageGlobal, lConfigSpec)

    }
    Catch (oException)
    {
        Set tSC = oException.AsStatus()
    }
    
    Quit tSC
}

/// Called recursively
ClassMethod ProcessObj(oObj As %CompiledClass, pOPCUADefaultNamespace As %String, pDefaultNodeName As %String, pPropertyPath As %String, Output lConfigSpec) As %Status
{
    Set lConfigSpec=""

    Set oStorageDataEntries = oObj.Storages.GetAt(1).Data.GetAt(1).Values

    // We must respect the storage entries order. We can't rely on the order of properties on the class definition.
    For i=1:1:oStorageDataEntries.Count()
    {
        Set tPropName = oStorageDataEntries.GetAt(i).Value
        Continue:$Extract(tPropName,1)="%"

        // But we still need the property definition for each storage entry...
        Set bPropFound=0
        For iProp=1:1:oObj.Properties.Count()
        {
            Set oProp=oObj.Properties.GetAt(iProp)
            If oProp.Name=tPropName 
            {
                Set bPropFound=1
                Quit
            }
        }    
        
        // Someone may have deleted the property from the class definition and left the old storage definition. 
        // That is ok!!!! So we must tell the OPCUA C layer to "put nothing" in there.
        If 'bPropFound
        {
            Set lConfigSpec=lConfigSpec_$LB("")
            Continue
        }
        
        // Now I have the right propert definition for the storage entry

        Set tOPCUANamespace = oProp.Parameters.GetAt("OPCUANAMESPACE")
        If tOPCUANamespace="" Set tOPCUANamespace=pOPCUADefaultNamespace

        If tOPCUANamespace=""
        {
            Set tSC = $$$ERROR(5001, "OPCUANAMESPACE parameter is not defined for property "_oProp.Name_" from class "_cls_" and there is no OPCUADEFAULTNAMESPACE parameter defined in class "_cls)
            Quit
        }

        if '$System.Version.IsUnicode() {
            set tSC = ##class(OPCUA.Utils).Initialize() // required for GetUStr on 8-bit IRIS
            Quit:$$$ISERR(tSC) // if initialization fails, report the error (GetUStr will not)
        }
        Set tNodeName = ""
        Set tNodeNameRaw = oProp.Parameters.GetAt("OPCUANODENAME")
        Set tNodeName = ##class(OPCUA.Utils).GetUStr(tNodeNameRaw)
        //Write !,"tNodeName for property ",pPropertyPath_"."_tPropName,": ",tNodeName

        // Are we overwriting the previous node name? If after overwriting, we end up with a empty node name, we will be validating it later
        // There are more opportunities to define the node name. This may be a CustomStructure
        If tNodeName="" Set tNodeName=pDefaultNodeName

        // Same here. We will be validating if we have a node attribute ID later
        Set tNodeAttributeId = oProp.Parameters.GetAt("OPCUAATTRIBUTEID")
        if tNodeAttributeId="" Set tNodeAttributeId=13 // Value Attribute

        // We have three types of properties: 
        // - Primitive values (code 1)
        // - Standard OPCUA structures (code 2)
        // - Custom structures (just a list)
        
        // Primitive values are identified when the user defines a simple data type on his/her class
        If $classmethod(oProp.Type, "%Extends", "%DataType")
        {
            // Using code 1 on the first parameter to say this is just a primitive 
            Set tSC = ..CreateConfigSpecEntry(1, pPropertyPath_"."_oProp.Name, tOPCUANamespace, tNodeName, tNodeAttributeId, .lConfigSpecEntry)
            Quit:$$$ISERR(tSC)
        }
        // A custom structure must inherit from OPCUA.Structure.CustomStructure
        ElseIf $classmethod(oProp.Type, "%Extends", "OPCUA.Structure.CustomStructure") 
        {
            Set oPropTypeClass = ##class(%Dictionary.CompiledClass).%OpenId(oProp.Type)
            Set tSC = ..ProcessObj(oPropTypeClass, tOPCUANamespace, tNodeName, pPropertyPath_"."_oProp.Name, .lConfigSpecEntry)
            Quit:$$$ISERR(tSC)
        }
        // A standard OPCUA structure belongs to the package OPCUA.Structure (or OPCUA.Types)
        ElseIf $Extract(oProp.Type,1,16)="OPCUA.Structure."
        {
            // Using code 2 on the first parameter to say this is a standard OPCUA structure
            Set tSC = ..CreateConfigSpecEntry(2, pPropertyPath_"."_oProp.Name, tOPCUANamespace, tNodeName, tNodeAttributeId, .lConfigSpecEntry)
            Quit:$$$ISERR(tSC)
        }
        ElseIf $Extract(oProp.Type,1,12)="OPCUA.Types."
        {
            // Using code 2 on the first parameter to say this is a standard OPCUA structure
            Set tSC = ..CreateConfigSpecEntry(2, pPropertyPath_"."_oProp.Name, tOPCUANamespace, tNodeName, tNodeAttributeId, .lConfigSpecEntry)
            Quit:$$$ISERR(tSC)
        }
        Else 
        {
            Set tSC = $$$ERROR(5001, "Property "_oProp.Name_" has an invalid type for OPCUA: "_oProp.Type)
            Quit    
        }

        Set lConfigSpec=lConfigSpec_$LB(lConfigSpecEntry)

    } //For

    Quit tSC
}

/// pEntryType can be:
/// 1 - If if what we will find on this Namespace>NodeName>AttributeId is an atomic value of some type
/// 2 - If if what we will find on this Namespace>NodeName>AttributeId is a standard complex OPCUA structure
/// 
ClassMethod CreateConfigSpecEntry(pEntryType As %Integer, pPropertyPath As %String, pOPCUANamespace As %String, pNodeName As %String, pNodeAttributeId As %String, Output pConfigSpecEntry) As %Status [ Private ]
{
    Set tSC = $$$OK
    Set pConfigSpecEntry=""

    Try 
    {
        If pNodeName=""
        {
            Set tSC = $$$ERROR(5001, "Property "_pPropertyPath_" does not specify an OPCUANODENAME.")
            Quit
        }

        If pNodeAttributeId=""
        {
            Set tSC = $$$ERROR(5001, "Property "_pPropertyPath_" does not specify an OPCUAATTRIBUTEID.")
            Quit
        }

        Set pConfigSpecEntry=$LB(pEntryType, pPropertyPath, pOPCUANamespace, pNodeName, pNodeAttributeId)
    } 
    Catch (oException)
    {
        Set tSC = oException.AsStatus()
    }

    Quit tSC
}

ClassMethod CommitOPCUAConfigSpec(pDataSourceName As %String, pClassName As %String, pStorageGlobal As %String, pConfigSpec As %List) [ Private ]
{
    Set lFullSpec=$LB(pDataSourceName, pStorageGlobal, $LB("")_pConfigSpec)
    Set ^OPCUA.DataSource(pClassName)=lFullSpec
}

ClassMethod GetOPCUAConfigSpec(pClassName As %String) As %List
{
    // Specifications are supplied in the form of %List
    // 1. DataSource name
    // 2. The name of the global on which to save the results
    // 3. A multidimensional %List of property elements.
    //		1. The first element is perhaps usually null (or the name of the class if a subclass?)
    //		2. Property elements take the form of a list with elements:
    //			1. The type of element: 1 = Primitives, 2 = Standard OPCUA, 3 = ?
    //			2. The pPropertyPath_"."_oProp.Name e.g. "[MyDataSource2].Temperature"
    //			3. The namespace
    //			4. The node name, a string NodeId identifier
    //			5. The AttributeId

    return ^OPCUA.DataSource(pClassName)
}

ClassMethod GetParameterValue(pClassDef As %Dictionary.CompiledClass, pParameterName As %String) As %String
{
    #Dim oParam As %Dictionary.CompiledParameter

    For i=1:1:pClassDef.Parameters.Count()
    {
        Set oParam = pClassDef.Parameters.GetAt(i)
        If oParam.Name=pParameterName 
        {
            Return oParam.Default
        }
    }

    Return ""
}

/// This method is invoked when a class is 'uncompiled'
ClassMethod RemoveProjection(cls As %String, ByRef params, recompile As %Boolean) As %Status
{
    Set tSC = $$$OK
    Try 
    {
        Kill ^OPCUA.DataSource(cls)
    } 
    Catch (oException)
    {
        Set tSC = oException.AsStatus()
    }
    
    QUIT tSC
}

}
