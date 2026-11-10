#!/bin/bash
#
# End-to-end test of managed Sign & Encrypt against the demo certified-server,
# including the step only the server's administrator can do: approving IRIS.
#
# Approval stays external. The IRIS stack never writes into certified-server's trust
# folder; this host script does, with docker cp, exactly as an administrator would.
#
#   1. reset certified-server (--force-recreate: trust folder = the image's myCA only)
#   2. Runner.Run TestPhase1   identity, trust, /test = clientNotApproved, managed
#                              pipeline logs the diagnosis once, client.der exported
#   3. docker cp client.der -> certified-server:/app/trustdir (restart only if the
#                              server shows no trust-list reload within 5 s)
#   4. Runner.Run TestPhase2   /test connects, pipeline recovers and writes rows,
#                              a swapped pin is refused (serverChanged)
#      HTTP checks (curl)      certificate download, bad key -> 400, role-only -> 403
#   5. Runner.Run TestPhase3   an expired identity is refused before any connect
#   6. cleanup                 overrides, test pipeline and schema removed,
#                              certified-server recreated to its image contents
#
# Exits non-zero on any failure and still cleans up. Runs from any cwd.
# Containers default to the docker compose project "iris-opcua"; override with
# IRIS_CONTAINER / COMPOSE_PROJECT_NAME / API_URL.

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
cd "$repo_root"

IRIS_CONTAINER="${IRIS_CONTAINER:-iris-opcua-iris-1}"
SERVER_SERVICE=certified-server
API_URL="${API_URL:-http://localhost:52783/csp/opcua/api}"
API_AUTH="${API_AUTH:-SuperUser:SYS}"
TRUSTDIR=/app/trustdir
host_tmp=$(mktemp -d "${TMPDIR:-/tmp}/opcua-e2e.XXXXXX")
failures=0

say()  { printf '\n==== %s ====\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf 'ok:   %s\n' "$*"; }

server_container() { docker compose ps -q "$SERVER_SERVICE"; }

# Waits for a "listening" line beyond the first $1 ones (default 0). A restarted
# container keeps its old log, so the caller passes the count from before.
wait_server_ready() {
    local id i logs n base=${1:-0}
    id=$(server_container)
    for i in $(seq 1 60); do
        # Capture first: with pipefail, grep -q closing the pipe early fails the test.
        logs=$(docker logs "$id" 2>&1)
        n=$(grep -c 'TCP network layer listening' <<<"$logs")
        if [ "$n" -gt "$base" ]; then return 0; fi
        sleep 0.5
    done
    fail "certified-server did not start listening"
    return 1
}

reset_server() {
    docker compose up -d --force-recreate "$SERVER_SERVICE" >/dev/null 2>&1 || { fail "could not recreate $SERVER_SERVICE"; return 1; }
    wait_server_ready
}

# Runs one ObjectScript line in the OPCUA namespace and prints the output.
iris_cmd() {
    printf 'zn "OPCUA"\n%s\nhalt\n' "$1" | docker exec -i "$IRIS_CONTAINER" iris session iris 2>&1
}

# Runs a Runner.Run phase; its output is shown; the phase passes only if Run returned 1.
run_phase() {
    local spec=$1 out
    say "$spec"
    out=$(iris_cmd "set ok=##class(OPCUA.Tests.Runner).Run(\"$spec\") write \"E2E-RESULT:\",ok,!")
    # Native library log lines are glued to assertion lines; cut them off.
    printf '%s\n' "$out" | sed -E 's/\[20[0-9]{2}-[0-9-]+ .*$//' | grep -v -e '^$' -e 'license will expire' -e '^USER>' -e '^OPCUA>$' -e '^Node: ' -e '^====*$' -e '^Directory:' -e 'Use the following URL' -e '^http://'
    if grep -q '^E2E-RESULT:1' <<<"$out" && grep -q 'Summary: [0-9]* passed' <<<"$out" \
        && ! grep -Eq 'Summary:.*(failed|skipped)|^FAILED|^SKIPPED' <<<"$out"; then
        ok "$spec"
    else
        fail "$spec"
    fi
}

cleanup() {
    local rc=$?
    say "cleanup"
    local cout
    cout=$(iris_cmd 'set ok=##class(OPCUA.Tests.Runner).Run("OPCUA.Tests.Live.SecureE2ETest:TestCleanup") write "E2E-RESULT:",ok,!')
    grep -E 'Summary|FAILED|E2E-RESULT' <<<"$cout" || true
    if grep -q '^E2E-RESULT:1' <<<"$cout" && ! grep -Eq 'Summary:.*(failed|skipped)|^FAILED|^SKIPPED' <<<"$cout"; then
        ok "cleanup phase"
    else
        fail "cleanup phase (leftovers may remain)"
    fi
    iris_cmd 'do ##class(OPCUA.Tests.Live.ApiRoleTest).DropUser()' >/dev/null 2>&1 || true
    docker compose up -d --force-recreate "$SERVER_SERVICE" >/dev/null 2>&1 || echo "WARNING: could not recreate $SERVER_SERVICE"
    docker exec "$IRIS_CONTAINER" rm -rf /tmp/opcua-e2e >/dev/null 2>&1 || true
    rm -rf "$host_tmp"
    local id left
    id=$(server_container)
    left=$(docker exec "$id" ls "$TRUSTDIR" 2>/dev/null | tr '\n' ' ')
    if [ "$left" = "myCA.crt.der " ]; then
        ok "certified-server trust folder is back to its image contents ($left)"
    else
        fail "certified-server trust folder holds: $left"
    fi
    if [ "$failures" -ne 0 ] || [ "$rc" -ne 0 ]; then
        echo; echo "secure-e2e: FAILED ($failures failure(s))"
        exit 1
    fi
    echo; echo "secure-e2e: all phases passed"
}
trap cleanup EXIT

command -v openssl >/dev/null || { echo "openssl is needed on the host"; exit 2; }
command -v python3 >/dev/null || { echo "python3 is needed on the host"; exit 2; }

say "load sources"
"$script_dir/dev-load.sh" >/dev/null 2>&1 && ok "dev-load" || { fail "dev-load.sh failed"; exit 1; }

say "PKI volume"
pki=$(docker exec "$IRIS_CONTAINER" stat -c '%U %a' /usr/irissys/mgr/opcua-pki 2>&1)
[ "$pki" = "irisowner 700" ] && ok "opcua-pki is owned by irisowner, mode 0700" \
    || { fail "opcua-pki is '$pki', want 'irisowner 700': rebuild the image (docker compose build iris) and recreate the volume (docker compose down; docker volume rm <project>_iris-opcua-pki)"; exit 1; }

say "1. reset certified-server (trust folder = image contents)"
reset_server || exit 1
before=$(docker exec "$(server_container)" ls "$TRUSTDIR" | tr '\n' ' ')
[ "$before" = "myCA.crt.der " ] && ok "trust folder holds only myCA" || fail "trust folder holds: $before"

run_phase "OPCUA.Tests.Live.SecureE2ETest:TestPhase1"
[ "$failures" -eq 0 ] || exit 1

say "3. approve IRIS on the server (host-side docker cp, as an administrator would)"
docker cp "$IRIS_CONTAINER:/tmp/opcua-e2e/client.der" "$host_tmp/client.der" || { fail "client.der was not exported"; exit 1; }
openssl x509 -inform der -in "$host_tmp/client.der" -noout -subject -fingerprint -sha256 || { fail "client.der is not a certificate"; exit 1; }
server_id=$(server_container)
marker=$(docker logs "$server_id" 2>&1 | grep -c 'Reloading the trust-list')
docker cp "$host_tmp/client.der" "$server_id:$TRUSTDIR/iris-e2e.der" || { fail "docker cp into $TRUSTDIR failed"; exit 1; }
reloaded=0
for i in $(seq 1 10); do
    sleep 0.5
    now=$(docker logs "$server_id" 2>&1 | grep -c 'Reloading the trust-list')
    if [ "$now" -gt "$marker" ]; then reloaded=1; break; fi
done
if [ "$reloaded" -eq 1 ]; then
    ok "the server reloaded its trust list by itself (no restart)"
else
    echo "no reload seen within 5 s: restarting certified-server"
    listening=$(docker logs "$server_id" 2>&1 | grep -c 'TCP network layer listening')
    if docker restart "$server_id" >/dev/null && wait_server_ready "$listening"; then
        ok "certified-server restarted and listening again"
    else
        fail "certified-server restart did not complete"
        exit 1
    fi
fi

run_phase "OPCUA.Tests.Live.SecureE2ETest:TestPhase2"

say "HTTP checks against $API_URL"
api() { curl -s -u "$API_AUTH" "$@"; }
json() { python3 -I -c 'import json,sys; d=json.load(sys.stdin)
for k in sys.argv[1].split("."): d=d[k]
print(d)' "$1"; }
norm() { tr -d ': \n' | tr 'a-f' 'A-F'; }

idjson=$(api "$API_URL/security/identity")
fp=$(printf '%s' "$idjson" | json data.fingerprint 2>/dev/null)
[ -n "$fp" ] && ok "GET /security/identity: fingerprint $fp" || fail "GET /security/identity returned no fingerprint: $idjson"
printf '%s' "$idjson" | grep -q 'PRIVATE KEY' && fail "identity response carries key text"

for fmt in der pem; do
    case $fmt in der) ctype=application/pkix-cert; inform=DER;; pem) ctype=application/x-pem-file; inform=PEM;; esac
    code=$(api -D "$host_tmp/h.$fmt" -o "$host_tmp/c.$fmt" -w '%{http_code}' "$API_URL/security/identity/certificate?format=$fmt")
    [ "$code" = 200 ] && ok "format=$fmt: HTTP 200" || fail "format=$fmt: HTTP $code"
    grep -qi "^content-type: $ctype" "$host_tmp/h.$fmt" && ok "format=$fmt: Content-Type $ctype" || fail "format=$fmt: Content-Type: $(grep -i '^content-type' "$host_tmp/h.$fmt")"
    grep -qi '^content-disposition: attachment' "$host_tmp/h.$fmt" && ok "format=$fmt: Content-Disposition attachment" || fail "format=$fmt: no attachment disposition"
    got=$(openssl x509 -inform $inform -in "$host_tmp/c.$fmt" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 | norm)
    want=$(printf '%s' "$fp" | norm)
    if [ -n "$got" ] && [ "$got" = "$want" ]; then ok "format=$fmt: openssl parses it, SHA-256 equals the identity fingerprint"; else fail "format=$fmt: SHA-256 '$got' != '$want'"; fi
    grep -q 'PRIVATE' "$host_tmp/c.$fmt" && fail "format=$fmt: download carries a private key"
done

code=$(api -X DELETE -o "$host_tmp/del.json" -w '%{http_code}' "$API_URL/security/servers/not-a-server-key")
[ "$code" = 400 ] && ok "DELETE /security/servers/<bad key>: HTTP 400" || fail "DELETE /security/servers/<bad key>: HTTP $code ($(cat "$host_tmp/del.json"))"

pw=$(iris_cmd 'set sc=##class(OPCUA.Tests.Live.ApiRoleTest).CreateUser(.pw) write "E2E-PW:",pw,!' | sed -n 's/^E2E-PW://p' | tr -d '\r')
if [ -n "$pw" ]; then
    role_user=OPCUATestApiRoleUser
    code=$(curl -s -u "$role_user:$pw" -o /dev/null -w '%{http_code}' "$API_URL/ping")
    [ "$code" = 200 ] && ok "role-only user reaches the API (/ping 200)" || fail "role-only user /ping: HTTP $code"
    code=$(curl -s -u "$role_user:$pw" -o "$host_tmp/role.json" -w '%{http_code}' "$API_URL/security/identity")
    [ "$code" = 403 ] && ok "role-only user: GET /security/identity is 403" || fail "role-only user: /security/identity HTTP $code"
    grep -q 'fingerprint' "$host_tmp/role.json" && fail "role-only user was shown the identity"
else
    fail "could not create the role-only user"
fi
iris_cmd 'do ##class(OPCUA.Tests.Live.ApiRoleTest).DropUser()' >/dev/null 2>&1

say "5. expired identity (no native connect expected)"
channels_before=$(docker logs "$(server_container)" 2>&1 | grep -c 'Creating a new SecureChannel')
run_phase "OPCUA.Tests.Live.SecureE2ETest:TestPhase3"
channels_after=$(docker logs "$(server_container)" 2>&1 | grep -c 'Creating a new SecureChannel')
[ "$channels_before" -gt 0 ] && ok "the server logged connections earlier ($channels_before), so the counter works" || fail "no SecureChannel lines in the server log: the no-connect check would prove nothing"
[ "$channels_before" = "$channels_after" ] && ok "the server saw no connection during the expired-identity phase" || fail "the server saw $((channels_after - channels_before)) connection(s) during the expired-identity phase"

exit 0
