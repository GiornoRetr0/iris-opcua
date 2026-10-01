/// <class>OPCUA.Types.NodeIdDataValue</class> without a server timestamp. See
/// <class>OPCUA.Types.NoServerTS.AbstractDataValue</class>.
Class OPCUA.Types.NoServerTS.NodeIdDataValue Extends OPCUA.Types.NoServerTS.AbstractDataValue
{

Property Namespace As %Integer;

Property Identifier;

Property IdentifierType As %Integer;

Storage Default
{
<Data name="AbstractDataValueState">
<Value name="1">
<Value>SourceTimeStamp</Value>
</Value>
<Value name="2">
<Value>Status</Value>
</Value>
<Value name="3">
<Value>Namespace</Value>
</Value>
<Value name="4">
<Value>Identifier</Value>
</Value>
<Value name="5">
<Value>IdentifierType</Value>
</Value>
</Data>
<Type>%Storage.Serial</Type>
}

}
