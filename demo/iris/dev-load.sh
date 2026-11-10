#!/bin/bash
#
# Loads backend/src, backend/tests and backend/examples into the running IRIS
# container (namespace OPCUA) without rebuilding the image. Runs from any cwd.
# Exits non-zero if any copy step fails, docker exec fails, or IRIS reports a
# load/compile error.
#
# Container defaults to iris-opcua-iris-1; override with IRIS_CONTAINER.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
IRIS_CONTAINER="${IRIS_CONTAINER:-iris-opcua-iris-1}"
dev=/tmp/opcua-dev

echo "Loading OPCUA sources into $IRIS_CONTAINER..."

# Start from an empty staging dir so files deleted from the repo are not reloaded.
docker exec --user root "$IRIS_CONTAINER" rm -rf "$dev"
docker exec "$IRIS_CONTAINER" mkdir -p "$dev"
for d in src tests examples; do
    echo "Copying backend/$d..."
    docker cp "$repo_root/backend/$d/." "$IRIS_CONTAINER:$dev/$d/"
done
docker exec --user root "$IRIS_CONTAINER" chmod -R a+rX "$dev"

# %UnitTest.Manager discovers test classes from files under ^UnitTestRoot (/tmp),
# even with /noload. Mirror the Unit and Live test files there. A package with
# no .cls files is skipped; any other failure (e.g. cp) fails the script.
for pkg in Unit Live; do
    docker exec --user root "$IRIS_CONTAINER" bash -c "
        set -e; shopt -s nullglob
        rm -rf /tmp/OPCUA/Tests/$pkg; mkdir -p /tmp/OPCUA/Tests/$pkg
        files=($dev/tests/OPCUA/Tests/$pkg/*.cls)
        if [ \${#files[@]} -gt 0 ]; then cp \"\${files[@]}\" /tmp/OPCUA/Tests/$pkg/; fi"
done

# One session, one trivial line per step. The exit code of an interactive
# iris session is not reliable, so success is judged from the output.
# LoadDir skips .inc files, hence the explicit Load of Constants.inc first.
script='zn "OPCUA"
set sc=$System.OBJ.Load("'$dev'/src/OPCUA/Constants.inc","ck") write !,"Constants.inc: ",$select($System.Status.IsOK(sc):"loaded",1:"FAILED"),! do:$System.Status.IsError(sc) $System.OBJ.DisplayError(sc)
do $System.OBJ.LoadDir("'$dev'/src","ck",.e1,1) write !,"src: ",+$get(e1)," errors",!
do $System.OBJ.LoadDir("'$dev'/tests","ck",.e2,1) write !,"tests: ",+$get(e2)," errors",!
do $System.OBJ.LoadDir("'$dev'/examples","ck",.e3,1) write !,"examples: ",+$get(e3)," errors",!
halt
'

if ! output=$(printf '%s' "$script" | docker exec -i "$IRIS_CONTAINER" iris session iris 2>&1); then
    printf '%s\n' "$output"
    echo "FAILED: docker exec / iris session failed"
    exit 1
fi
printf '%s\n' "$output"

if grep -Eq 'ERROR #|ERROR:|Detected [0-9]+ errors|Constants\.inc: FAILED|: [1-9][0-9]* errors' <<<"$output"; then
    echo
    echo "FAILED: load/compile errors (see ERROR lines above)"
    exit 1
fi
if ! grep -q 'Constants.inc: loaded' <<<"$output" || ! grep -q 'examples: 0 errors' <<<"$output"; then
    echo
    echo "FAILED: load did not run to completion"
    exit 1
fi

echo
echo "Load complete: no errors."
