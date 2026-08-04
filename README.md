# IRIS OPC UA Adapter Demos

This repository holds an example application in which IRIS uses 
OPC UA to access data and subsequently store that data in tables/globals.
A simple method by which small amounts of data can be written to an 
OPC UA server using ObjectScript is also implemented.

## ToC
- [OPC UA Basics](#opc-ua-basics)
- [The IRIS OPC UA Adapter Client](#the-iris-opc-ua-adapter-client)
- [Polling Access vs. OPC UA Subscription](#polling-access-vs-opc-ua-subscription)
- [Security](#security)
- [Running the Demos Importing Data into IRIS](#running-the-demos-importing-data-into-iris)
- [SimpleWrite and SecureWrite Demos](#simplewrite-and-securewrite-demos)
- [Future Work](#future-work)
- [Product Availabilty](#product-availability)

## OPC UA Basics

OPC UA is a client-server protocol by which data and 
information can be transferred between machines.

Data intended for transmission via OPC UA is made available 
by OPC UA servers to which OPC UA clients can connect.
Clients connect to servers with TCP/IP by referencing
special URLs designating the OPC UA protocol (see below), 
and subsequently those clients 
can then request specific data values held on those servers
by referencing the "node" on which each 
data value is stored. 

Each OPC UA "node" on a server is identified by a "node id" and typically 
stores a single data element that might be any one of various data types. 
Often such data elements are simple primitives 
such as strings, integers, booleans, and floats, 
but server nodes can also hold more complex data types as well
such as bytestrings that 
can literally hold data in virtually any format that a developer so chooses,
including code files and PDF documents.

A relatively common situation might involve an industrial machine 
for which data elements such as the temperature of the machine 
and the pressure inside the machine are made accessible by an OPC UA
server to computers on a local area network. 
In such a situation, instantaneous temperature and pressure values 
might be indexed upon the OPC UA server on nodes each named as 
"temperature" and "pressure". OPC UA clients could then connect 
to the server using the server's URL and subsequently request 
current values 
for each of the temperature and pressure nodes. The OPC UA server 
would typically then reply with the most recent values for the data 
along with timestamps indicating when those most recent
values had been posted to the server.

Although the general concepts behind OPC UA are simple, 
the protocol itself has myriad of different features 
that allow it to be used with great flexibility 
in many situations, making its specification quite detailed and complex. 
More information on OPC UA including the protocol's official specification
can be found at http://opcfoundation.org.

## The IRIS OPC UA Adapter Client

The OPC UA adapter for IRIS contained in this repository
serves to allow IRIS to act 
as an OPC UA client in order to access OPC UA servers,
primarily to query those servers for information, allowing the 
construction of data feeds to continuously import data into IRIS.
(The adapter can also be used to write data to servers in 
limited amounts as is described regarding the 
SimpleWrite and SecureWrite demos at bottom).

Users of the adapter can construct "DataSource" classes 
in ObjectScript with properties that reference queryable OPC UA nodes 
upon a desired target server. Such "DataSource" classes are persistent within IRIS, 
and thus, when values are eventually accessed from the desired OPC UA server, 
those values are immediately stored within IRIS and made queryable 
using both ObjectScript as well as SQL.
In order to perform its function, each "DataSource" class must extend not only 
%Persistent but also OPCUA.DataSource.Definition,
and this allows the adapter to set up the necessary framework in order 
to gather and store the relevant data. 

Each property of a "DataSource" class is specified 
indicating both (1)
the node name for the node on which to find the relevant data,
as well as (2)
a special ObjectScript data type that is 
itself reflective of the data type of that target data. 
In the following sample code line below, data is sought from a node called 
"AirConditioner_1.Temperature", 
and placed in a property called "Temperature" 
(notably, allowing the data to subsequently be 
queried within IRIS both as an object property
as well as in a SQL column of the same name). 

```C#
Property Temperature As OPCUA.Types.DoubleDataValue(OPCUANODENAME = "AirConditioner_1.Temperature");
```

Importantly, the data type above is declared as OPCUA.Types.DoubleDataValue, 
which is a special data type that allows access to both 
the double value that is being sought as well as timestamps 
indicating when that double was placed on the server. Currently, this
adapter supports the accessing of primitive strings and integers,
as well as other basic OPC UA data types,
each of which must be accessed using similar 
data type-related ObjectScript classes.
Similar means can be used to obtain arrays of data as well
(see ArrayExample, below).

## Polling Access vs. OPC UA Subscription

This IRIS client adapter can access OPC UA data using two fundamentally 
different methods: (1) a method we term "polling", and 
(2) a method that is most precisely referred to 
in OPC UA terminology as "subscription to monitored items".

The polling method, which is here implemented using an 
ObjectScript class OPCUA.Service.TCPPollingService, involves 
the repeated requesting of data corresponding to a certain 
set of data nodes in bulk. Specifically, using this polling method, 
data for each and every property of a DataSource class is 
requested from a server all at once. The client application 
then expects to receive data from the server for each and 
every node requested along with the relevant timestamps for 
each reported data element, effectively representing a snapshot
of the node values at that point in time. 
The returned results are then 
placed by the connector into a table/global within IRIS.

The second method improves upon the first in some ways by 
using the OPC UA Subscription framework. Using this second method, 
a request is made of an OPC UA server to track the changes made to 
each node corresponding to a property of the relevant DataSource class. 
Periodically, the client then queries the OPC UA server asking 
if there have been any changes since last querying. 
Upon receipt of this information, the IRIS OPC UA adapter 
then arranges any such changes into one or more new rows 
that are then added to a table/global within the database.
If a particular value has not changed, then the previous value is
inserted instead. If no values have changed, then the row is 
typically omitted altogether. (Some settings can be adjusted to
control this behavior.)

## Security

Currently, this version of the IRIS OPC UA Adapter supports (at least)
two security modes: (1) unencrypted data transmission with anonymous login, 
and (2) encrypted data transmission with two-way mutual client/server 
authentication that allows for username/password login. 

It is not uncommon for OPC UA servers to be implemented 
without substantive security requirements and the use of basic, unsecure, 
unencrypted transmission combined with anonymous login may be sufficient in many
cases. Such a security policy can be selected when using the 
IRIS OPC UA client by setting the "SecurityMode" 
setting to "None" for any OPCUA.Service.TCPPollingService or 
OPCUA.Service.TCPSubscriptionService. The SecurityMode setting
appears under the "Security" heading on the settings tab
for the business service in question when 
viewing the service's parent Production in IRIS.

In contrast, encrypted data transmission 
with two-way mutual client/server authentication 
requires not only that the SecurityMode be set to the alternative 
"Sign & Encrypt" setting, but also that each of several 
crytographic files be supplied to the IRIS OPC UA client 
before that software can be used. 
Fundamentally, in establishing a secure 
connection, the client must first sign its request to the server 
with its own private key,
then make available its public certificate to the server as well, 
then the server must then accept that client's certificate as valid, 
and then the same must happen in reverse with the server providing 
its credentials to the client and the client accepting them.
In practice, this requires that the IRIS
OPC UA client be supplied with up to four different
cryptographic files in order to function: 
the client's public certificate, the client's 
private key, the public certificate of a trusted certificate authority
(useful for verifying the server's identity), 
and a valid certificate revocation list for that certificate authority. 
Indeed, a similar set of files may be needed by any relevant target
server as well.

Other security modes besides these two are available for use with 
the OPC UA protocol, but are not necessarily implemented for the 
IRIS OPC UA client at this time. (It is unclear if security 
standards may be automatically reduced if a target server 
does not require them.)

Security features are available for this connector on each of 
Windows, Mac OS, and Docker/Ubuntu platforms.

## Running the Demos Importing Data into IRIS

### Using Docker
The demos in this repository can be run using only a few steps:

* Download the relevant code from GitHub.
* Run "docker-compose up" in order to start the three Docker containers 
used by the demos. 
* Login to the IRIS Management Portal at http://localhost:52783/csp/sys/UtilHome.csp 
with username "SuperUser" and password "sys".
* Navigate to the IRIS Production Examples.OPCUADS.Production. 
* Enable any of the IRIS Business Services found at the left hand side of the screen. 
Each is itself a separate demo, each 
intended to place incoming OPC UA data on a different table/global within IRIS.

### Using native IRIS
- Ensure that your version of IRIS is licensed for Productions.
- Place the [DLLs](./windows/bin/) (Windows) or [SOs](./image-iris/uacbin/) (Unix) in the bin directory for the instance of IRIS.
- Open the Management Portal and add a namespace “APPINT”.
- Open Studio/VS Code and connect to IRIS and the APPINT namespace.
- Import into Studio/VS Code the material in the [IrisOPCUA_prj.xml](./windows/Studio/IrisOPCUA_prj-20251217.xml) project file, and compile it for use with the connected instance of IRIS.
- Return to the Management Portal and navigate to
 <code>Interoperability > Production Configuration > (Examples.OPCUADS.Production)</code>. At this point, you should be able to see the five business service examples.
- Enable the InternetPollingExample and the InternetSubscriptionExample.
- Each of the two enabled business services should deposit incoming data on tables/globals that correspond to their names. View the results at <code>System > SQL</code> using SQL queries: e.g. <code>SELECT * FROM Examples_OPCUADS.InternetPollingExample</code>.

At this time, it is intended that there be six
OPC UA BusinessService demonstrations available 
within this repository now or in the near future:

* Local Polling Example (Examples.OPCUADS.PollingExample.cls) - This 
example shows IRIS use the OPC UA adapter to connect to an 
OPC UA server running locally in a separate container, that server being
here called "mockserver". The "mockserver" application reads data 
from a .csv file and makes that data available on nodes queryable 
by clients connecting to it. 
IRIS then repeatedly requests data from the "mockserver"
using the polling mechanism described above,
and each time receives a response with the requested data snapshot
which is immediately deposited on a table/global "Examples.OPCUADS.PollingExample".
* Local Subscription Example (Examples.OPCUADS.SubscriptionExample.cls) - This 
example also shows IRIS use the OPC UA adapter to connect to "mockserver", 
though here the data is obtained using the Subscription method instead of the Polling method.
The data is deposited on a table/global "Examples.OPCUADS.SubscriptionExample".
* Internet Polling Example (Examples.OPCUADS.InternetPollingExample.cls) - This 
example shows IRIS use the OPC UA adapter to connect to 
a publicly available OPC UA server on the Internet at 
opc.tcp://opcuaserver.com:48010. 
Data is then requested from that server using the polling method and deposited
on a table/global "Examples.OPCUADS.InternetPollingExample". 
* Internet Subscription Example (Examples.OPCUADS.InternetSubscriptionExample.cls) - This 
example again shows IRIS use the OPC UA adapter to connect to 
the publicly available OPC UA server on the Internet at 
opc.tcp://opcuaserver.com:48010. 
Data is requested from that server using the subscription method 
and again stored within IRIS on a table/global.
* Secure Example (Examples.OPCUADS.SecureExample.cls) - This example shows 
IRIS use the OPC UA adapter to connect to and download data from 
an OPC UA server that requires mutual authentication and transmission 
encryption. The example is otherwise similar to the above local subscription example 
in that it uses the subscription method of data retrieval and seeks data from 
a server running locally, here in a separate docker container called "certified-server". 
This example differs from that above, however, in that, in this case, the 
locally running server is one that has been certified by the OPC Foundation
in its use of security, and connecting to that server requires that certain minimum 
security standards are met. More information on the server can be found at 
https://open62541.org/certified-sdk.
* Array Example (Examples.OPCUADS.ArrayExamole.cls) - This example shows 
IRIS use the OPC UA adapter in order to download arrays of data from the
publicly available OPC UA server on the Internet at opc.tcp://opcuaserver.com:48010.
Aside from the array format in which the data is downloaded, this example is 
fundamentally similar to the Internet Polling Example mentioned above.

## SimpleWrite and SecureWrite Demos

Demos showing the the use of the adapter to write small amounts of data
to OPC UA servers are provided for use with an IRIS terminal session.
ObjectScript code constituting the demos is provided in each of the 
Examples.OPCUA.SimpleWrite.Run() procedure and the 
Examples.OPCUA.SecureWrite.Run() procedure.

In order to run these demos, one must follow the same initial steps as before:

* Download the relevant code from GitHub.
* Run "docker-compose up" to start the Docker containers. 

Subsequently, the procedure to access the terminal-based demos differs:

* Start an IRIS terminal session. Such can be accomplished by running
"iris session iris" from within a bash shell running within the IRIS
Docker container. (The procedure to access such a bash shell may differ
on some systems. On Mac OS, with Docker accessible from the command 
prompt, one can run "docker ps" to list information about the running 
Dockeer containers including their "container ids". Select the 
container id for the container named "irisdemo-demo-opcua_iris_1";
it can be used to access a bash shell within that container using the
command "docker exec -it &lt;CONTAINER_IR&gt; /bin/bash".)
* Login using username "SuperUser" and password "sys".
* Select the APPINT namespace using "zn ""APPINT""". (Notice the 
double-quotes around APPINT.)
* Each of the two demos can not be run by invoking the Run() method of 
each of their classes: "w ##class(Examples.OPCUA.SimpleWrite).Run()" 
and "w ##class(Examples.OPCUA.SecureWrite).Run()".

Both of the write demos illustrate the use of a simple feature of the 
adapter by which a single data element can be written to an
OPC UA server. Simple read commands are also included so that the 
values on the server can be diplayed in the terminal before and
after the write procedure call is executed.

* SimpleWrite - This demo writes a simple value to a publicly
accessible OPC UA server located on the Internet at 
opc.tcp://opcuaserver.com:48010. Security features of the 
IRIS OPC UA adapter are not used.
* SecureWrite - This demo writes a simple value to an OPC UA server
running in one of the locally-running Docker containers, the same
OPC Foundation-certified server instance that is used for the 
Secure data feed example (using Examples.OPCUADS.SecureExample.cls),
and does so using a secure connection. If the SecureExample data
feed is running at the time that the Examples.OPCUA.SecureWrite.Run() 
procedure is invoked, then the results of the write will be
visible, not only on the screen within the IRIS terminal session,
but also in the incomcing SecureExample data as well. In order to 
view the results in the data feed, first note the time at which the
Examples.OPCUA.SecureWrite.Run() procedure is invoked; the value 
"57" should be viewable in the column "TheAnswer_Value" for the 
one-second period after the invocation of the procedure. Otherwise,
the values in "TheAnswer_Value" column should be "42" instead. 

## Future Work

TBD

## Product Availability

Versions of this OPC UA code are available for use on Windows and Mac OS,
in addition to the Docker/Ubuntu version used for these demos.
