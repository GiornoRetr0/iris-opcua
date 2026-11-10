Include (OPCUA.Constants, %occInclude)

/// Live half of the measurement-metadata suite, against the docker plc server:
/// a resolved poll (with and without server timestamps) and a subscription
/// notification both store all four fields per measurement through RowWriter.
Class OPCUA.Tests.Live.MeasurementMetadataTest Extends OPCUA.Tests.MeasurementMetadataBase
{

/// A resolved poll stores real values and all four fields per measurement.
Method TestLiveRow()
{
    do ..LiveRow(..URL(), 1)
}

/// The same poll through a schema without server timestamps.
Method TestLiveRowNoServerTS()
{
    do ..LiveRow(..URL(), 0)
}

// ==================== live poll ====================

/// End-to-end against a real server: generate a schema from node names the mock
/// server exposes, resolve it, poll, and confirm the stored measurements carry
/// real values and real timestamps rather than empty metadata.
///
/// pIncludeServerTS 0 runs the same poll through a schema without server
/// timestamps: real values and source timestamps, and no server-TS column.
Method LiveRow(pURL As %String, pIncludeServerTS As %Boolean = 1)
{
    #dim tClient As OPCUA.Client
    set tClass = ..#TestPackage_".LiveSchema"_$Select(pIncludeServerTS:"", 1:"NoSrv")
    Try {
        set tSC = ..BuildLiveSchema(tClass, "TmpLiveMetaSchema"_$Select(pIncludeServerTS:"", 1:"NoSrv"), pIncludeServerTS)
        if $$$ISERR(tSC) {
            do $$$AssertFailure("could not generate live schema: "_$System.Status.GetOneErrorText(tSC))
            quit
        }

        set tClient = ##class(OPCUA.Client).%New()
        set tSC = tClient.Initialize()
        if $$$ISERR(tSC) {
            do $$$AssertFailure("client initialize: "_$System.Status.GetOneErrorText(tSC))
            quit
        }
        do tClient.SetupClient("", 1, "", "", "", "", "")
        set tSC = tClient.Connect(pURL, "", "")
        if $$$ISERR(tSC) {
            do $$$AssertFailure("connect to "_pURL_": "_$System.Status.GetOneErrorText(tSC))
            quit
        }

        // Two devices both rooted at the Objects folder, where the mock server
        // holds SA1/SA2/VT5 directly.
        do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths("i=85|DevA"_$Char(10)_"i=85|DevB", .tDevices, .tErrors)
        set tSC = ##class(OPCUA.DataSource.Resolver).ResolveSpecification(tClient, tClass, tDevices, .tSpec, .tMasks, .tDiag)
        do $$$AssertEquals($$$ISOK(tSC), 1, "resolution succeeds")
        quit:$$$ISERR(tSC)
        do $$$AssertEquals($LI(tMasks, 1), $LB(1, 1, 1), "all columns resolved on the mock server")

        set tSC = tClient.ReadBulkSetupC(.tHandle, tSpec)
        do $$$AssertEquals($$$ISOK(tSC), 1, "C layer accepts the spec")
        quit:$$$ISERR(tSC)

        set tSC = tClient.ReadBulkPollC(.tList, tHandle)
        do $$$AssertEquals($$$ISOK(tSC), 1, "poll succeeds")
        if $$$ISERR(tSC) {
            do tClient.ReadBulkClear(tHandle)
            quit
        }

        set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
        set tSC = tWriter.Initialize(tClass)
        do $$$AssertEquals($$$ISOK(tSC), 1, "live writer initializes")
        if $$$ISERR(tSC) {
            do tClient.ReadBulkClear(tHandle)
            quit
        }

        // Write both devices from the one flat result, exactly as the services do.
        do $$$AssertEquals($$$ISOK(tWriter.CheckInput(.tList, tMasks)), 1, "CheckInput accepts the live poll result")
        set tResultIdx = 1
        kill tIds
        for iDev=1:1:$LL(tMasks) {
            set tSC = tWriter.BuildRow(.tList, $LI(tMasks, iDev), $LI($LI(tDevices, iDev), 4), .tResultIdx, .tRow)
            $$$ThrowOnError(tSC)
            set tSC = $classmethod(tClass, "SaveSourcedData", .tRow, .tId)
            $$$ThrowOnError(tSC)
            set tIds(iDev) = tId
        }
        do tClient.ReadBulkClear(tHandle)

        do $$$AssertEquals($Get(tIds(2)) '= "", 1, "both devices produced a row")

        set tObj = $classmethod(tClass, "%OpenId", $Get(tIds(1)))
        do $$$AssertEquals($IsObject(tObj), 1, "live row opens")
        quit:'$IsObject(tObj)

        do $$$AssertEquals(tObj.NodePath, "DevA", "device label stored as NodePath")
        do $$$AssertEquals(tObj.SA1.Value '= "", 1, "SA1 has a real value")
        do $$$AssertEquals(tObj.SA1.SourceTimeStamp '= "", 1, "SA1 has a source timestamp")
        if pIncludeServerTS {
            do $$$AssertEquals(tObj.SA1.ServerTimeStamp '= "", 1, "SA1 has a server timestamp")
        } else {
            do $$$AssertEquals(tObj.SA1.%ClassName(1), "OPCUA.Types.NoServerTS.IntegerDataValue", "SA1 is a NoServerTS measurement")
            set tFields = ..SqlFields(tClass)
            do $$$AssertEquals(tFields [ ",SA1_SERVERTS,", 0, "SQL has no SA1_ServerTS")
            do $$$AssertEquals(tFields [ ",SA1_SOURCETS,", 1, "SQL keeps SA1_SourceTS")
        }
        do $$$AssertEquals(tObj.SA1.Status, 0, "SA1 status is good")
        do $$$AssertEquals(tObj.SA2.SourceTimeStamp '= "", 1, "SA2 has its own source timestamp")
        do $$$AssertEquals(tObj.VT5.Value '= "", 1, "VT5 has a real value")

        // Every measurement on the row must be populated — a single shared
        // timestamp pair would leave the others blank.
        set tRS = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT COUNT(*) FROM "_..TableName(tClass)_
            " WHERE SA1_SourceTS IS NOT NULL AND SA2_SourceTS IS NOT NULL AND VT5_SourceTS IS NOT NULL")
        do tRS.%Next()
        do $$$AssertEquals(tRS.%GetData(1), 2, "both rows carry a timestamp for every measurement")
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
    do:$IsObject($Get(tClient)) tClient.Disconnect()
    do ..DropSchema(tClass)
}

/// The subscription transport feeds the same writer, so a change notification
/// must store the same four fields per measurement as a poll does. This is the
/// check that stops the two collection modes drifting apart again.
Method TestLiveSubscription()
{
    set pURL = ..URL()
    #dim tClient As OPCUA.Client
    set tClass = ..#TestPackage_".SubSchema"
    set tHandle = ""
    Try {
        set tSC = ..BuildLiveSchema(tClass, "TmpSubMetaSchema")
        if $$$ISERR(tSC) {
            do $$$AssertFailure("could not generate schema: "_$System.Status.GetOneErrorText(tSC))
            quit
        }

        set tClient = ##class(OPCUA.Client).%New()
        do tClient.Initialize()
        do tClient.SetupClient("", 1, "", "", "", "", "")
        set tSC = tClient.Connect(pURL, "", "")
        if $$$ISERR(tSC) {
            do $$$AssertFailure("connect to "_pURL_": "_$System.Status.GetOneErrorText(tSC))
            quit
        }

        do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths("i=85|SubDev", .tDevices, .tErrors)
        set tSC = ##class(OPCUA.DataSource.Resolver).ResolveSpecification(tClient, tClass, tDevices, .tSpec, .tMasks, .tDiag)
        do $$$AssertEquals($$$ISOK(tSC), 1, "subscription resolution succeeds")
        quit:$$$ISERR(tSC)

        set tPublishing = 200, tLifetime = 10000, tKeepAlive = 10, tSampling = 200
        set tSC = tClient.CreateSubscriptionSetB(.tHandle, tSpec, .tPublishing, .tLifetime, .tKeepAlive, 100, tSampling, 1, 0)
        do $$$AssertEquals($$$ISOK(tSC), 1, "subscription created from the resolved spec")
        quit:$$$ISERR(tSC)

        // The first publish cycle may be empty; give the server a few chances.
        set tBatch = "", tQty = 0
        for i=1:1:10 {
            set tSC = tClient.PollSubscriptionSet(.tList, tHandle, 1000, 0, 1)
            quit:$$$ISERR(tSC)
            set tQty = $LI(tList, 2)
            if tQty > 0 {
                set tBatch = $LI(tList, 3)
                quit
            }
            hang 0.3
        }
        do $$$AssertEquals($$$ISOK(tSC), 1, "subscription poll succeeds")
        do $$$AssertEquals((tQty > 0), 1, "a notification arrived")
        quit:tQty'>0

        set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
        set tSC = tWriter.Initialize(tClass)
        $$$ThrowOnError(tSC)

        // One notification is shaped exactly like one poll result, which is why
        // both services can hand it to the same writer unchanged.
        set tNotification = $LI(tBatch, 1)
        do $$$AssertEquals($$$ISOK(tWriter.CheckInput(.tNotification, $LB($LI(tMasks, 1)))), 1, "CheckInput accepts the live notification")
        set tResultIdx = 1
        set tSC = tWriter.BuildRow(.tNotification, $LI(tMasks, 1), "SubDev", .tResultIdx, .tRow)
        do $$$AssertEquals($$$ISOK(tSC), 1, "notification builds a row")
        if $$$ISERR(tSC) {
            do $$$LogMessage($System.Status.GetOneErrorText(tSC))
            quit
        }

        set tSC = $classmethod(tClass, "SaveSourcedData", .tRow, .tId)
        do $$$AssertEquals($$$ISOK(tSC), 1, "notification row saves")
        quit:$$$ISERR(tSC)

        set tObj = $classmethod(tClass, "%OpenId", tId)
        quit:'$IsObject(tObj)
        do $$$AssertEquals(tObj.SA1.Value '= "", 1, "subscribed SA1 has a value")
        do $$$AssertEquals(tObj.SA1.SourceTimeStamp '= "", 1, "subscribed SA1 has a source timestamp")
        do $$$AssertEquals(tObj.SA1.ServerTimeStamp '= "", 1, "subscribed SA1 has a server timestamp")
        do $$$AssertEquals(tObj.SA2.SourceTimeStamp '= "", 1, "subscribed SA2 has its own source timestamp")
        do $$$AssertEquals(tObj.VT5.Value '= "", 1, "subscribed VT5 has a value")

        // An explicit delete leaves the client usable: a new subscription on it
        // needs no reset. With a native library older than 2026-10-21 the
        // Disconnect() below kills this process (signal 11) instead.
        set tSC = tClient.DeleteSubscriptionSet(tHandle)
        do $$$AssertEquals($$$ISOK(tSC), 1, "DeleteSubscriptionSet succeeds")
        set tPublishing = 200, tLifetime = 10000, tKeepAlive = 10
        set tSC = tClient.CreateSubscriptionSetB(.tHandle, tSpec, .tPublishing, .tLifetime, .tKeepAlive, 100, tSampling, 1, 0)
        do $$$AssertEquals($$$ISOK(tSC), 1, "a new subscription after the delete needs no reset")
        if $$$ISOK(tSC) {
            hang 0.5
            set tSC = tClient.PollSubscriptionSet(.tList, tHandle, 1000, 0, 1)
            do $$$AssertEquals($$$ISOK(tSC), 1, "the new subscription polls")
        }
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
    // Tear down the way the subscription adapter does: Disconnect alone, which
    // deletes the subscription on the server.
    if $IsObject($Get(tClient)) {
        do tClient.Disconnect()
    }
    do ..DropSchema(tClass)
}

}
