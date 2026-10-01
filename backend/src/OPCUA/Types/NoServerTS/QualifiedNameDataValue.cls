/// <class>OPCUA.Types.QualifiedNameDataValue</class> without a server timestamp. See
/// <class>OPCUA.Types.NoServerTS.AbstractDataValue</class>.
Class OPCUA.Types.NoServerTS.QualifiedNameDataValue Extends OPCUA.Types.NoServerTS.AbstractDataValue
{

Property Name As %String;

Property Namespace As %Integer;

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
<Value>Name</Value>
</Value>
<Value name="4">
<Value>Namespace</Value>
</Value>
</Data>
<Type>%Storage.Serial</Type>
}

}
