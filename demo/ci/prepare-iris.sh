#!/bin/bash
#
# Readies a stock intersystems/iris-community container for the offline tests:
# waits for IRIS to come up (5-minute cap), then creates the OPCUA namespace
# with interoperability through IRISConfig.Installer's setup() manifest. It
# installs nothing else: no demos, web app, credentials or native library.
# Load the sources afterwards with demo/iris/dev-load.sh. Runs from any cwd.
#
# Container defaults to iris; override with IRIS_CONTAINER.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
IRIS_CONTAINER="${IRIS_CONTAINER:-iris}"

echo "Waiting for IRIS in $IRIS_CONTAINER..."
deadline=$((SECONDS + 300))
until printf 'write "IRIS-READY",!\nhalt\n' \
        | docker exec -i "$IRIS_CONTAINER" iris session IRIS -U %SYS 2>/dev/null \
        | grep -q 'IRIS-READY'; do
    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "FAILED: IRIS did not accept a session within 5 minutes"
        docker logs --tail 50 "$IRIS_CONTAINER" || true
        exit 1
    fi
    sleep 5
done
echo "IRIS is up after ${SECONDS}s."

docker cp "$repo_root/demo/iris/IRISConfig/Installer.cls" "$IRIS_CONTAINER:/tmp/Installer.cls"
docker exec --user root "$IRIS_CONTAINER" chmod a+r /tmp/Installer.cls

# Only the manifest: Install() would also load the native library, demos,
# credentials and the web app.
script='set sc=$System.OBJ.Load("/tmp/Installer.cls","ck") write !,"Installer: ",$select($System.Status.IsOK(sc):"loaded",1:"FAILED"),! do:$System.Status.IsError(sc) $System.Status.DisplayError(sc)
set sc=##class(IRISConfig.Installer).setup() write !,"Namespace: ",$select($System.Status.IsOK(sc):"created",1:"FAILED"),! do:$System.Status.IsError(sc) $System.Status.DisplayError(sc)
write !,"Interoperability: ",$select(##class(%EnsembleMgr).IsEnsembleNamespace("OPCUA"):"enabled",1:"MISSING"),!
halt
'

if ! output=$(printf '%s' "$script" | docker exec -i "$IRIS_CONTAINER" iris session IRIS -U %SYS 2>&1); then
    printf '%s\n' "$output"
    echo "FAILED: docker exec / iris session failed"
    exit 1
fi
printf '%s\n' "$output"

if grep -Eq 'ERROR #|ERROR:|FAILED|MISSING' <<<"$output" \
   || ! grep -q 'Namespace: created' <<<"$output" \
   || ! grep -q 'Interoperability: enabled' <<<"$output"; then
    echo
    echo "FAILED: namespace setup"
    exit 1
fi

echo
echo "Namespace OPCUA ready."
