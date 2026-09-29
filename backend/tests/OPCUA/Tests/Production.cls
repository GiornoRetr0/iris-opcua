Class OPCUA.Tests.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Examples.OPCUADS.ExampleProduction" LogGeneralTraceEvents="false">
  <Description></Description>
  <ActorPoolSize>2</ActorPoolSize>
  <Item Name="DataTest" Category="" ClassName="OPCUA.Service.TCPPollingService" PoolSize="1"
 Enabled="false" Foreground="false" 
 Comment="DataTest Data" 
 LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="DataSourceClass">OPCUA.Tests.DataTestDS</Setting>
    <Setting Target="Adapter" Name="URL">opc.tcp://opcuaserver.com:48010</Setting>
    <Setting Target="Adapter" Name="CallInterval">5</Setting>
  </Item>
  <Item Name="AttributesTestDS" Category="" ClassName="OPCUA.Service.TCPPollingService" PoolSize="1"
 Enabled="false" Foreground="false" 
 Comment="Attributes Test Data" 
 LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="DataSourceClass">OPCUA.Tests.AttributesTestDS</Setting>
    <Setting Target="Adapter" Name="URL">opc.tcp://opcuaserver.com:48010</Setting>
    <Setting Target="Adapter" Name="CallInterval">5</Setting>
  </Item>
  <Item Name="ScalarTypesTestDS" Category="" ClassName="OPCUA.Service.TCPPollingService" PoolSize="1"
 Enabled="false" Foreground="false" 
 Comment="Scalar Types Test Data"
 LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="DataSourceClass">OPCUA.Tests.ScalarTypesTestDS</Setting>
    <Setting Target="Adapter" Name="URL">opc.tcp://opcuaserver.com:48010</Setting>
    <Setting Target="Adapter" Name="CallInterval">5</Setting>
  </Item>
  <Item Name="PollingExample" Category="" ClassName="OPCUA.Service.TCPPollingService" PoolSize="1"
 Enabled="false" Foreground="false" 
 Comment="This example repeatedly polls a locally-running OPC UA server for input." 
 LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="DataSourceClass">Examples.OPCUADS.PollingExample</Setting>
    <Setting Target="Adapter" Name="URL">opc.tcp://plc</Setting>
    <Setting Target="Adapter" Name="CallInterval">1</Setting>
  </Item>
  <Item Name="SubscriptionExample" Category="" ClassName="OPCUA.Service.TCPSubscriptionService" PoolSize="1"
 Enabled="false" Foreground="false" 
 Comment="This example receives input data from a subscription to monitored items on a locally-running OPC UA server." 
 LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="DataSourceClass">Examples.OPCUADS.SubscriptionExample</Setting>
    <Setting Target="Adapter" Name="URL">opc.tcp://plc</Setting>
    <Setting Target="Adapter" Name="RequestedPublishingInterval">300</Setting>
    <Setting Target="Adapter" Name="RequestedSamplingInterval">0</Setting>
    <Setting Target="Adapter" Name="RequestedQueueSize">5</Setting>
  </Item>
  <Item Name="SecureExample" Category="" ClassName="OPCUA.Service.TCPSubscriptionService" PoolSize="1"
 Enabled="false" Foreground="false" 
 Comment="This example receives input data from a server requiring mutual authentication and transmission encryption." 
 LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="DataSourceClass">Examples.OPCUADS.SecureExample</Setting>
    <Setting Target="Adapter" Name="URL">opc.tcp://certified-server</Setting>
    <Setting Target="Adapter" Name="RequestedPublishingInterval">1000</Setting>
    <Setting Target="Adapter" Name="RequestedSamplingInterval">250</Setting>
    <Setting Target="Adapter" Name="RequestedQueueSize">5</Setting>
    <Setting Target="Adapter" Name="Username">user1</Setting>
    <Setting Target="Adapter" Name="Password">password</Setting>
    <Setting Target="Adapter" Name="SecurityMode">3</Setting>
    <Setting Target="Adapter" Name="ClientURI">urn:secuac</Setting>
    <Setting Target="Adapter" Name="PublicCertificate">/usr/irissys/uac/certs/secuac.crt.der</Setting>
    <Setting Target="Adapter" Name="PrivateKey">/usr/irissys/uac/certs/secuac.key.der</Setting>
    <Setting Target="Adapter" Name="TrustListDir">/usr/irissys/uac/certs/trustdir</Setting>
    <Setting Target="Adapter" Name="RevocationListDir">/usr/irissys/uac/certs/crldir</Setting>
  </Item>
  <Item Name="InternetPollingExample" Category="" ClassName="OPCUA.Service.TCPPollingService" PoolSize="1"
 Enabled="false" Foreground="false" 
 Comment="This example repeatedly polls a public OPC UA server at opcuaserver.com." 
 LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="DataSourceClass">Examples.OPCUADS.InternetPollingExample</Setting>
    <Setting Target="Adapter" Name="URL">opc.tcp://opcuaserver.com:48010</Setting>
    <Setting Target="Adapter" Name="CallInterval">5</Setting>
  </Item>
  <Item Name="InternetSubscriptionExample" Category="" ClassName="OPCUA.Service.TCPSubscriptionService" PoolSize="1"
 Enabled="false" Foreground="false" 
 Comment="This example creates a subscription to monitored items on a pubic OPC UA server at opcuaserver.com."
 LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="DataSourceClass">Examples.OPCUADS.InternetSubscriptionExample</Setting>
    <Setting Target="Adapter" Name="URL">opc.tcp://opcuaserver.com:48010</Setting>
    <Setting Target="Adapter" Name="CallInterval">5</Setting>
    <Setting Target="Adapter" Name="ReestablishOnEmptyResult">3</Setting>
  </Item>
  <Item Name="ArrayExample" Category="" ClassName="OPCUA.Service.TCPPollingService" PoolSize="1"
 Enabled="false" Foreground="false" 
 Comment="Array Example" 
 LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="DataSourceClass">Examples.OPCUADS.ArrayExample</Setting>
    <Setting Target="Adapter" Name="URL">opc.tcp://opcuaserver.com:48010</Setting>
    <Setting Target="Adapter" Name="CallInterval">5</Setting>
  </Item>
</Production>
}

}
