#!/bin/bash

# Loads backend/src, backend/tests and backend/examples into the IRIS container
# for development iteration without rebuilding the Docker image.
# Runs from any working directory.

set -e

# Resolve repo root from this script's location
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)

# Allow override of container name for different environments
IRIS_CONTAINER="${IRIS_CONTAINER:-iris-opcua-iris-1}"

echo "Loading OPCUA sources into $IRIS_CONTAINER..."

# Create temporary directory in the container
docker exec "$IRIS_CONTAINER" mkdir -p /tmp/opcua-dev

# Copy source directories
echo "Copying backend/src..."
docker cp "$repo_root/backend/src/." "$IRIS_CONTAINER:/tmp/opcua-dev/src/"

echo "Copying backend/tests..."
docker cp "$repo_root/backend/tests/." "$IRIS_CONTAINER:/tmp/opcua-dev/tests/"

echo "Copying backend/examples..."
docker cp "$repo_root/backend/examples/." "$IRIS_CONTAINER:/tmp/opcua-dev/examples/"

# Fix permissions so IRIS can read the files
docker exec --user root "$IRIS_CONTAINER" chmod -R a+rX /tmp/opcua-dev/

# Copy test files to ^UnitTestRoot location for %UnitTest.Manager
docker exec --user root "$IRIS_CONTAINER" mkdir -p /tmp/OPCUA/Tests/Unit /tmp/OPCUA/Tests/Live
docker exec --user root "$IRIS_CONTAINER" bash -c "cp /tmp/opcua-dev/tests/OPCUA/Tests/Unit/*.cls /tmp/OPCUA/Tests/Unit/ 2>/dev/null || true"
docker exec --user root "$IRIS_CONTAINER" bash -c "cp /tmp/opcua-dev/tests/OPCUA/Tests/Live/*.cls /tmp/OPCUA/Tests/Live/ 2>/dev/null || true"

# Load into IRIS (Constants.inc loads as part of src directory)
echo "Loading into IRIS namespace OPCUA..."

# Load all three directories - Constants.inc is in src and will be loaded first due to dependencies
printf 'zn "OPCUA"\ndo $System.OBJ.LoadDir("/tmp/opcua-dev/src","ck",.err,1)\ndo $System.OBJ.LoadDir("/tmp/opcua-dev/tests","ck",.err,1)\ndo $System.OBJ.LoadDir("/tmp/opcua-dev/examples","ck",.err,1)\nhalt\n' | docker exec -i "$IRIS_CONTAINER" iris session iris

exit_code=$?

if [ $exit_code -ne 0 ]; then
    echo "ERROR: Load failed with exit code $exit_code"
    exit $exit_code
fi

echo "Load complete."
exit 0
