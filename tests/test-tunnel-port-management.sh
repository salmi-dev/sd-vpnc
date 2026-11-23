#!/bin/sh

set -eu
REPO_ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sd-vpnc-tunnel.XXXXXX")
cleanup() {
	chmod -R u+rwx "$TMP_ROOT" 2>/dev/null || true
	rm -rf "$TMP_ROOT"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected '$1' to equal '$2'"; }
assert_contains() { case $1 in *"$2"*) ;; *) fail "expected text to contain '$2'" ;; esac; }
assert_not_contains() { case $1 in *"$2"*) fail "expected text not to contain '$2'" ;; *) ;; esac; }
file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
fake_id() { printf '%064x' "$1"; }

a_setup() {
	case_dir=$TMP_ROOT/$1
	ENGINE_STATE=$case_dir/engine
	ENGINE_BIN=$case_dir/bin
	CASE_HOME=$case_dir/home
	CASE_CONFIG=$CASE_HOME/.config/sd-vpnc
	CASE_SSH=$CASE_HOME/.ssh
	CASE_WORK=$CASE_HOME/.local/share/sd-vpnc
	CASE_STATE=$CASE_HOME/.local/state
	manifest=$CASE_STATE/sd-vpnc/tunnel.manifest
	pending=$CASE_STATE/sd-vpnc/tunnel.pending
	mkdir -p "$ENGINE_STATE/containers" "$ENGINE_BIN" "$case_dir/docker-bin" "$CASE_CONFIG" "$CASE_SSH" "$CASE_WORK" "$CASE_STATE"
	printf 'client baseline\n' > "$CASE_CONFIG/client.ovpn"
	printf 'username\npassword\n' > "$CASE_CONFIG/credentials"
	chmod 600 "$CASE_CONFIG/credentials"
	printf 'Host fake\n' > "$CASE_SSH/config"
	ENGINE_LOG=$ENGINE_STATE/commands
	ENGINE_EVENTS=$ENGINE_STATE/events
	: > "$ENGINE_LOG"
	: > "$ENGINE_EVENTS"
	cat > "$ENGINE_BIN/podman" <<'ENGINE'
#!/bin/sh
set -eu
printf 'podman' >> "$ENGINE_LOG"
for arg do printf '[%s]' "$arg" >> "$ENGINE_LOG"; done
printf '\n' >> "$ENGINE_LOG"
case ${1:-} in
	info)
		case ${2:-} in
			--format)
				case ${3:-} in
					*Security.Rootless*) printf '%s\n' "${FAKE_ROOTLESS:-false}" ;;
					*RemoteSocket.Path*) printf '%s\n' "${FAKE_CONTEXT:-fake-context}" ;;
					*) printf 'fake-info\n' ;;
				esac
				;;
			*) printf 'false\n' ;;
		esac
		exit 0
		;;
	image) [ "${2:-}" = inspect ] && exit 0 ;;
	container)
		case ${2:-} in
			inspect)
				if [ "${FAKE_FAIL_BARE_INSPECT:-0}" = 1 ] && [ "${3:-}" != --format ]; then
					printf 'bare-inspect-failed\n' >> "$ENGINE_EVENTS"
					exit 1
				fi
				if [ "${FAKE_INSPECT_FAIL_AFTER_EXEC:-0}" = 1 ] && [ -f "$ENGINE_STATE/inspect-failure-armed" ]; then exit 1; fi
				name=${5:-${3:-}}
				dir=$ENGINE_STATE/containers/$name
				[ -d "$dir" ] || exit 1
				if [ "${3:-}" = --format ]; then
					case ${4:-} in
						*State.Running*) [ ! -f "$dir/stopped" ] && printf 'true\n' || printf 'false\n' ;;
						*.Id*) cat "$dir/id" ;;
						*io.sd-vpnc.tunnel*) sed -n 's/^io.sd-vpnc.tunnel=//p' "$dir/labels" ;;
						*) printf '\n' ;;
					esac
				fi
				exit 0
				;;
			ls)
				if [ "${FAKE_FAIL_LIST:-0}" = 1 ]; then
					[ "${FAKE_FAIL_LIST_AFTER_INSPECT:-0}" = 1 ] && [ ! -f "$ENGINE_STATE/inspect-failure-armed" ] || exit 1
				fi
				for dir in "$ENGINE_STATE"/containers/*; do
					[ -d "$dir" ] || continue
					printf '%s|%s\n' "$(cat "$dir/id")" "${dir##*/}"
				done
				;;
			stop)
				name=${3:-}
				[ -d "$ENGINE_STATE/containers/$name" ] || exit 0
				if [ "${FAKE_FAIL_STOP:-0}" = 1 ]; then
					printf 'stop-failed:%s\n' "$name" >> "$ENGINE_EVENTS"
					exit 77
				fi
				: > "$ENGINE_STATE/containers/$name/stopped"
				printf 'stop:%s\n' "$name" >> "$ENGINE_EVENTS"
				;;
			rm)
				name=${3:-}
				if [ "${FAKE_INSPECT_FAIL_AFTER_RM:-0}" = 1 ]; then : > "$ENGINE_STATE/inspect-failure-armed"; fi
				if [ "${FAKE_FAIL_RM:-0}" = 1 ]; then
					printf 'remove-failed:%s\n' "$name" >> "$ENGINE_EVENTS"
					exit 78
				fi
				rm -rf "$ENGINE_STATE/containers/$name"
				printf 'remove:%s\n' "$name" >> "$ENGINE_EVENTS"
				;;
		esac
		exit 0
		;;
	run)
		name=
		while [ "$#" -gt 0 ]; do
			case $1 in --name) name=$2; shift 2 ;; *) shift ;; esac
		done
		[ -n "$name" ] || exit 2
		printf 'run-enter:%s\n' "$name" >> "$ENGINE_EVENTS"
		[ -z "${FAKE_RUN_DELAY:-}" ] || /bin/sleep "$FAKE_RUN_DELAY"
		sequence=0
		[ ! -f "$ENGINE_STATE/sequence" ] || sequence=$(cat "$ENGINE_STATE/sequence")
		sequence=$((sequence + 1))
		printf '%s\n' "$sequence" > "$ENGINE_STATE/sequence"
		dir=$ENGINE_STATE/containers/$name
		mkdir -p "$dir"
		printf '%064x\n' "$sequence" > "$dir/id"
		printf 'io.sd-vpnc.tunnel=sd-vpnc\n' > "$dir/labels"
		printf '%s\n' "$sequence" > "$dir/sequence"
		case ,${FAKE_NO_READY_RUNS:-}, in *,$sequence,*) ;; *)
			if ! grep -qi 'invalid config' "$HOME/.config/sd-vpnc/client.ovpn" 2>/dev/null; then : > "$dir/ready"; fi
			;;
		esac
		printf 'start:%s:%s\n' "$name" "$sequence" >> "$ENGINE_EVENTS"
		# Log the current source contents mounted for this new container.
		for source in "$HOME"/.config/sd-vpnc/client.ovpn "$HOME"/.config/sd-vpnc/credentials "$HOME"/.ssh/config; do
			[ ! -f "$source" ] || { printf 'source:%s:' "${source##*/}" >> "$ENGINE_STATE/sources"; cat "$source" >> "$ENGINE_STATE/sources"; }
		done
		printf '%064x\n' "$sequence"
		exit 0
		;;
	exec)
		name=${2:-}
		cmd=${3:-}
		[ "$cmd" = test ] || exit 1
		[ "${4:-}" = -f ] || exit 1
		if [ "${FAKE_INSPECT_FAIL_AFTER_EXEC:-0}" = 1 ]; then : > "$ENGINE_STATE/inspect-failure-armed"; fi
		if [ "${FAKE_REMOVE_AFTER_EXEC:-0}" = 1 ]; then rm -rf "$ENGINE_STATE/containers/$name"; fi
		if [ -d "$ENGINE_STATE/containers/$name" ]; then
			rename_sequence=$(cat "$ENGINE_STATE/containers/$name/sequence")
			case ,${FAKE_RENAME_RUNS:-}, in
				*,$rename_sequence,*)
					if [ ! -f "$ENGINE_STATE/rename-done-$rename_sequence" ]; then
						mv "$ENGINE_STATE/containers/$name" "$ENGINE_STATE/containers/renamed-tunnel-$rename_sequence"
						: > "$ENGINE_STATE/rename-done-$rename_sequence"
					fi
					;;
			esac
		fi
		[ "${5:-}" = /tmp/sd-vpnc-tun-ready ] && [ -f "$ENGINE_STATE/containers/$name/ready" ]
		;;
	logs) exit 0 ;;
esac
exit 0
ENGINE
	chmod +x "$ENGINE_BIN/podman"
	cat > "$ENGINE_BIN/sleep" <<'SLEEP'
#!/bin/sh
[ "${FAKE_REAL_SLEEP:-0}" != 0 ] && exec /bin/sleep "$@"
exit 0
SLEEP
	chmod +x "$ENGINE_BIN/sleep"
	cat > "$ENGINE_BIN/mv" <<'MOVE'
#!/bin/sh
last=
for arg do last=$arg; done
if [ "${FAKE_FAIL_MANIFEST_ONCE:-0}" = 1 ] && [ "$last" = "$XDG_STATE_HOME/sd-vpnc/tunnel.manifest" ] && [ ! -e "$ENGINE_STATE/manifest-failure-used" ]; then
	: > "$ENGINE_STATE/manifest-failure-used"
	exit 1
fi
exec /bin/mv "$@"
MOVE
	chmod +x "$ENGINE_BIN/mv"
	cat > "$case_dir/docker-bin/docker" <<'DOCKER'
#!/bin/sh
[ "${1:-}" = context ] && [ "${2:-}" = show ] && { printf 'other-context\n'; exit 0; }
exit 1
DOCKER
	chmod +x "$case_dir/docker-bin/docker"
	export HOME="$CASE_HOME" XDG_CONFIG_HOME="$CASE_HOME"/.config XDG_DATA_HOME="$CASE_HOME"/.local/share XDG_STATE_HOME="$CASE_STATE"
	export ENGINE_STATE ENGINE_LOG ENGINE_EVENTS
	unset SD_VPNC_CONFIG SD_VPNC_CREDENTIALS SD_VPNC_SSH_CONFIG CONTAINER_CONNECTION DEVPOD_WORKSPACE_ID FAKE_NO_READY_RUNS FAKE_ROOTLESS FAKE_CONTEXT FAKE_REAL_SLEEP FAKE_RUN_DELAY FAKE_FAIL_MANIFEST_ONCE FAKE_FAIL_STOP FAKE_FAIL_RM FAKE_FAIL_LIST FAKE_FAIL_LIST_AFTER_INSPECT FAKE_FAIL_BARE_INSPECT FAKE_INSPECT_FAIL_AFTER_EXEC FAKE_INSPECT_FAIL_AFTER_RM FAKE_REMOVE_AFTER_EXEC FAKE_RENAME_RUNS 2>/dev/null || true
	PATH=$ENGINE_BIN:/usr/bin:/bin
	export PATH
}

run_cli() { "$REPO_ROOT/sd-vpnc" "$@"; }

write_pending_record() {
	test_pending_operation=$1
	test_pending_old_id=$2
	test_pending_replacement_id=$3
	test_pending_mappings=$4
	set -f
	test_pending_saved_ifs=$IFS
	IFS=' '
	# shellcheck disable=SC2086
	set -- $test_pending_mappings
	IFS=$test_pending_saved_ifs
	{
		printf '%s\n' SDVPNC-TUN-PENDING
		printf 'version=%s\n' "$(printf 1 | base64 | tr -d '\n')"
		printf 'operation=%s\n' "$(printf '%s' "$test_pending_operation" | base64 | tr -d '\n')"
		printf 'old_container_id=%s\n' "$(printf '%s' "$test_pending_old_id" | base64 | tr -d '\n')"
		printf 'replacement_container_id=%s\n' "$(printf '%s' "$test_pending_replacement_id" | base64 | tr -d '\n')"
		printf 'mapping_count=%s\n' "$(printf '%s' "$#" | base64 | tr -d '\n')"
		test_pending_index=1
		for test_pending_mapping do
			printf 'mapping.%s=%s\n' "$test_pending_index" "$(printf '%s' "$test_pending_mapping" | base64 | tr -d '\n')"
			test_pending_index=$((test_pending_index + 1))
		done
	} > "$pending"
	chmod 600 "$pending"
}

interactive_mutation() {
	python3 - "$REPO_ROOT/sd-vpnc" "$@" <<'PY'
import os, pty, select, subprocess, sys, time
cli, mode, first = sys.argv[1:4]
second = sys.argv[4] if len(sys.argv) > 4 else None
pid, fd = pty.fork()
if pid == 0:
    os.execv('/bin/sh', ['/bin/sh', '-c', '"$1" tun-add-port "$2"; result=$?; printf "\\nCLI_STATUS=%s\\n" "$result"; exit 0', 'pty-wrapper', cli, first])
output = bytearray()
deadline = time.time() + 10
while b'Continue? [y/N]' not in output and time.time() < deadline:
    ready, _, _ = select.select([fd], [], [], 0.2)
    if ready:
        try: output.extend(os.read(fd, 4096))
        except OSError: break
if b'Continue? [y/N]' not in output:
    os.kill(pid, 9)
    os.waitpid(pid, 0)
    print(output.decode(errors='replace'))
    print('PROMPT_MISSING=1')
    raise SystemExit(0)
if mode == 'race':
    result = subprocess.run([cli, 'tun-add-port', second, '--yes'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print('SECOND_STATUS=%d' % result.returncode)
    print(result.stdout)
    response = b'y\n'
else:
    response = (b'y\n' if mode == 'yes' else b'n\n')
os.write(fd, response)
while True:
    ready, _, _ = select.select([fd], [], [], 0.2)
    if ready:
        try: output.extend(os.read(fd, 4096))
        except OSError: break
    finished, status = os.waitpid(pid, os.WNOHANG)
    if finished:
        break
    if time.time() > deadline + 30:
        os.kill(pid, 9)
        _, status = os.waitpid(pid, 0)
        break
print(output.decode(errors='replace'))
print('FIRST_STATUS=%d' % os.waitstatus_to_exitcode(status))
PY
}

# Initial start writes verifiable private state, and add/remove recreate only the named managed tunnel.
a_setup initial-and-mutations
run_cli tun host.example 08080:80 8443:db.internal:443 > "$TMP_ROOT/start.out" || fail 'initial tunnel start failed'
manifest=$CASE_STATE/sd-vpnc/tunnel.manifest
pending=$CASE_STATE/sd-vpnc/tunnel.pending
[ -f "$manifest" ] || fail 'initial start did not write a tunnel manifest'
[ ! -e "$pending" ] || fail 'successful initial start retained pending state'
assert_eq "$(file_mode "$CASE_STATE/sd-vpnc")" 700
assert_eq "$(file_mode "$manifest")" 600
assert_eq "$(grep -c '^mapping\.' "$manifest")" 2
id_value=$(sed -n 's/^container_id=//p' "$manifest" | base64 -d)
assert_eq "$id_value" "$(fake_id 1)"
assert_not_contains "$(cat "$manifest")" 'password'
[ -z "$(find "$CASE_STATE/sd-vpnc" -type f -name '.tunnel.manifest.*' -print)" ] || fail 'atomic manifest temporary file was left behind'
if run_cli tun-add-port 9443:443 9444:444 --yes > "$TMP_ROOT/multiple-add.out" 2>&1; then fail 'tun-add-port accepted multiple mappings'; fi
if run_cli tun-rm-port 8080:80 --yes > "$TMP_ROOT/endpoint-remove.out" 2>&1; then fail 'tun-rm-port accepted an endpoint mapping'; fi
if run_cli tun-add-port '9443:bad_host!:80' --yes > "$TMP_ROOT/invalid-host.out" 2>&1; then fail 'tun-add-port accepted an invalid host'; fi
if run_cli tun-add-port 8080:80 --yes > "$TMP_ROOT/duplicate.out" 2>&1; then fail 'numeric duplicate add unexpectedly succeeded'; fi
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 1
if run_cli tun-add-port 9443:443 > "$TMP_ROOT/noninteractive.out" 2>&1; then fail 'non-interactive mutation unexpectedly succeeded without --yes'; fi
assert_contains "$(cat "$TMP_ROOT/noninteractive.out")" --yes
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 1
run_cli tun-add-port 9443:443 --yes > "$TMP_ROOT/add.out" || fail 'confirmed port add failed'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 2
assert_contains "$(cat "$TMP_ROOT/add.out")" 'Tunnel mappings updated'
# Changed source contents are read from saved paths on recreation.
printf 'client changed\n' > "$CASE_CONFIG/client.ovpn"
printf 'updated-user\nupdated-secret\n' > "$CASE_CONFIG/credentials"
printf 'Host current-source\n' > "$CASE_SSH/config"
run_cli tun-rm-port 8080 --yes > "$TMP_ROOT/remove.out" || fail 'normalized local-port removal failed'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 3
assert_contains "$(cat "$ENGINE_STATE/sources")" 'client changed'
assert_contains "$(cat "$ENGINE_STATE/sources")" 'updated-secret'
assert_contains "$(cat "$ENGINE_STATE/sources")" 'current-source'
manifest_maps=$(grep -c '^mapping\.' "$manifest")
assert_eq "$manifest_maps" 2
run_cli tun-rm-port 8443 --yes >/dev/null || fail 'non-final mapping removal failed'
assert_eq "$(grep -c '^mapping\.' "$manifest")" 1
# The final removal shares confirmation policy and stops instead of creating a zero-port tunnel.
run_cli tun-rm-port 9443 --yes > "$TMP_ROOT/final.out" 2>&1 || fail 'final mapping removal failed'
assert_contains "$(cat "$TMP_ROOT/final.out")" 'No mappings will remain; the tunnel will be stopped.'
[ ! -e "$manifest" ] || fail 'final mapping removal kept an active manifest'
[ ! -e "$pending" ] || fail 'final mapping removal kept pending state'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 4
[ ! -d "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" ] || fail 'final mapping removal left the named container'

# Failed inspect cannot make final-port removal treat a still-listed exact target as absent.
a_setup final-remove-inspect-listed
run_cli tun host 8080:80 >/dev/null || fail 'final-remove inspect setup failed'
FAKE_FAIL_RM=1
FAKE_INSPECT_FAIL_AFTER_RM=1
export FAKE_FAIL_RM FAKE_INSPECT_FAIL_AFTER_RM
if run_cli tun-rm-port 8080 --yes > "$TMP_ROOT/final-remove-inspect-listed.out" 2>&1; then fail 'final-port removal accepted a listed target after inspect failure'; fi
final_inspect_output=$(cat "$TMP_ROOT/final-remove-inspect-listed.out")
assert_contains "$final_inspect_output" 'manifest and pending recovery state were retained'
assert_contains "$final_inspect_output" 'tun --stop'
assert_not_contains "$final_inspect_output" 'Removed the final tunnel mapping'
[ -e "$manifest" ] && [ -e "$pending" ] || fail 'final-port removal cleared state while the exact target remained listed'
[ -d "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" ] || fail 'final-port failure unexpectedly removed its listed target'
unset FAKE_FAIL_RM FAKE_INSPECT_FAIL_AFTER_RM
rm -f "$ENGINE_STATE/inspect-failure-armed"
run_cli tun --stop >/dev/null || fail 'final-port inspect failure recovery failed'
[ ! -e "$manifest" ] && [ ! -e "$pending" ] || fail 'final-port explicit recovery retained state'

# Interactive confirmation accepts an explicit yes, rejects no, and ignores redirected yes input.
a_setup confirmation
run_cli tun host 8080:80 >/dev/null || fail 'confirmation setup start failed'
interactive_output=$(interactive_mutation no 9000:90)
assert_contains "$interactive_output" 'cancelled'
assert_contains "$interactive_output" 'CLI_STATUS=1'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 1
interactive_output=$(interactive_mutation yes 9000:90)
assert_contains "$interactive_output" 'Warning: container port publications are immutable'
assert_contains "$interactive_output" 'CLI_STATUS=0'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 2
if printf 'y\\n' | run_cli tun-add-port 9001:91 > "$TMP_ROOT/redirected.out" 2>&1; then fail 'redirected affirmative input was treated as confirmation'; fi
assert_contains "$(cat "$TMP_ROOT/redirected.out")" 'Non-interactive'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 2
run_cli tun-add-port 9001:91 --yes >/dev/null || fail '--yes automation mutation failed'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 3

# A reviewed confirmation cannot authorize a different manifest after a concurrent mutation.
a_setup stale-confirmation
run_cli tun host 8080:80 >/dev/null || fail 'stale-confirmation setup start failed'
interactive_output=$(interactive_mutation race 9000:90 9001:91)
assert_contains "$interactive_output" 'SECOND_STATUS=0'
assert_contains "$interactive_output" 'changed during confirmation'
assert_contains "$interactive_output" 'CLI_STATUS=1'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 2
assert_eq "$(grep -c '^mapping\.' "$manifest")" 2

a_setup lifecycle-lock
run_cli tun host 8080:80 >/dev/null || fail 'lifecycle-lock setup start failed'
FAKE_RUN_DELAY=0.5
export FAKE_RUN_DELAY
run_cli tun-add-port 8443:443 --yes > "$TMP_ROOT/locked-add.out" 2>&1 &
locked_add_pid=$!
wait_count=0
while [ "$(grep -c '^run-enter:' "$ENGINE_EVENTS" || true)" -lt 2 ] && [ "$wait_count" -lt 100 ]; do /bin/sleep 0.02; wait_count=$((wait_count + 1)); done
[ "$wait_count" -lt 100 ] || fail 'add did not enter replacement while holding the lifecycle lock'
run_cli tun --stop > "$TMP_ROOT/locked-stop.out" 2>&1 &
locked_stop_pid=$!
/bin/sleep 0.1
kill -0 "$locked_stop_pid" 2>/dev/null || fail 'tun --stop did not wait for the in-flight replacement lock'
wait "$locked_add_pid" || fail 'locked add failed'
wait "$locked_stop_pid" || fail 'serialized stop failed'
[ ! -e "$manifest" ] || fail 'serialized stop left active tunnel state'
[ ! -e "$pending" ] || fail 'serialized stop left pending tunnel state'
[ ! -d "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" ] || fail 'serialized stop left the named tunnel'

# Add/remove fail closed for absent, unrecognized, insecure, malformed, and mismatched state.
a_setup invalid-preconditions
if run_cli tun-add-port 1234:80 --yes > "$TMP_ROOT/inactive.out" 2>&1; then fail 'add started an inactive tunnel'; fi
assert_contains "$(cat "$TMP_ROOT/inactive.out")" 'tun --stop'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS" || true)" 0
a_setup stopped-precondition
run_cli tun host 8080:80 >/dev/null || fail 'stopped precondition setup start failed'
: > "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)/stopped"
if run_cli tun-rm-port 8080 --yes > "$TMP_ROOT/stopped.out" 2>&1; then fail 'stopped tunnel was accepted for removal'; fi
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 1
assert_eq "$(grep -c '^stop:' "$ENGINE_EVENTS" || true)" 0
run_cli tun --stop >/dev/null || fail 'stopped target cleanup failed'

a_setup invalid-preconditions
mkdir -p "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)"
printf 'other=owner\n' > "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)/labels"
printf 'true\n' > "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)/ready"
printf '%s\n' "$(fake_id 81)" > "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)/id"
if run_cli tun-rm-port 80 --yes > "$TMP_ROOT/unmanaged.out" 2>&1; then fail 'remove accepted an unmanaged tunnel'; fi
assert_eq "$(grep -c '^remove:' "$ENGINE_EVENTS" || true)" 0
# Explicit stop removes only the exact named legacy/unrecognized target even when inspect fails.
: > "$ENGINE_STATE/inspect-failure-armed"
run_cli tun --stop </dev/null > "$TMP_ROOT/legacy-stop.out" || fail 'legacy explicit stop failed'
[ ! -d "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" ] || fail 'legacy stop left its exact named target'
assert_eq "$(grep -c '^stop:sd-vpnc-tun-' "$ENGINE_EVENTS")" 1
assert_eq "$(grep -c '^remove:sd-vpnc-tun-' "$ENGINE_EVENTS")" 1

# Initial start trusts only an authoritative full-ID/name listing, never failed inspection as absence.
a_setup initial-target-occupied
initial_target_name=sd-vpnc-tun-$(id -u)
mkdir -p "$ENGINE_STATE/containers/$initial_target_name"
printf '%s\n' "$(fake_id 80)" > "$ENGINE_STATE/containers/$initial_target_name/id"
if run_cli tun host 8080:80 > "$TMP_ROOT/initial-target-occupied.out" 2>&1; then fail 'initial start accepted an occupied exact TUN name without a manifest'; fi
assert_contains "$(cat "$TMP_ROOT/initial-target-occupied.out")" 'tun --stop'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS" || true)" 0
[ -d "$ENGINE_STATE/containers/$initial_target_name" ] || fail 'initial start touched the occupied exact target'

a_setup stale-manifest-start
run_cli tun old-host 8080:80 >/dev/null || fail 'stale-manifest setup failed'
stale_manifest_id=$(sed -n 's/^container_id=//p' "$manifest" | base64 -d)
assert_eq "$stale_manifest_id" "$(fake_id 1)"
rm -rf "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)"
FAKE_FAIL_BARE_INSPECT=1
export FAKE_FAIL_BARE_INSPECT
if "$ENGINE_BIN/podman" container inspect "sd-vpnc-tun-$(id -u)" >/dev/null 2>&1; then fail 'fake bare inspect failure hook did not fail'; fi
run_cli tun fresh-host 9000:90 > "$TMP_ROOT/stale-manifest-start.out" || fail 'listing-proven stale manifest did not permit a fresh start'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 2
assert_eq "$(sed -n 's/^container_id=//p' "$manifest" | base64 -d)" "$(fake_id 2)"
[ ! -e "$pending" ] || fail 'fresh start retained pending state after stale-manifest cleanup'
assert_contains "$(cat "$ENGINE_LOG")" '[ls]'
unset FAKE_FAIL_BARE_INSPECT

a_setup renamed-initial-manifest
run_cli tun old-host 8080:80 >/dev/null || fail 'renamed initial-manifest setup failed'
renamed_initial_id=$(sed -n 's/^container_id=//p' "$manifest" | base64 -d)
cp "$manifest" "$TMP_ROOT/renamed-initial-manifest.saved"
mv "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" "$ENGINE_STATE/containers/renamed-initial-tunnel"
FAKE_FAIL_BARE_INSPECT=1
export FAKE_FAIL_BARE_INSPECT
if run_cli tun fresh-host 9000:90 > "$TMP_ROOT/renamed-initial-start.out" 2>&1; then fail 'initial start ignored a saved ID surviving under another name'; fi
renamed_initial_output=$(cat "$TMP_ROOT/renamed-initial-start.out")
assert_contains "$renamed_initial_output" 'tun --stop'
assert_contains "$renamed_initial_output" 'under another name'
cmp "$TMP_ROOT/renamed-initial-manifest.saved" "$manifest" || fail 'renamed-ID refusal changed the saved manifest'
[ ! -e "$pending" ] || fail 'renamed-ID refusal created or changed pending state'
[ -d "$ENGINE_STATE/containers/renamed-initial-tunnel" ] || fail 'renamed-ID refusal touched the renamed container'
assert_eq "$(cat "$ENGINE_STATE/containers/renamed-initial-tunnel/id")" "$renamed_initial_id"
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 1
assert_eq "$(grep -c '^stop:' "$ENGINE_EVENTS" || true)" 0
assert_eq "$(grep -c '^remove:' "$ENGINE_EVENTS" || true)" 0
unset FAKE_FAIL_BARE_INSPECT

a_setup renamed-malformed-manifest-id
run_cli tun old-host 8080:80 >/dev/null || fail 'malformed-ID manifest setup failed'
renamed_malformed_id=$(sed -n 's/^container_id=//p' "$manifest" | base64 -d)
mv "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" "$ENGINE_STATE/containers/renamed-malformed-id-tunnel"
sed "s/^container_id=.*/container_id=$(printf x | base64 | tr -d '\\n')/" "$manifest" > "$TMP_ROOT/renamed-malformed-id.manifest"
chmod 600 "$TMP_ROOT/renamed-malformed-id.manifest"
mv "$TMP_ROOT/renamed-malformed-id.manifest" "$manifest"
cp "$manifest" "$TMP_ROOT/renamed-malformed-id.saved"
assert_eq "$(file_mode "$manifest")" 600
if run_cli tun fresh-host 9000:90 > "$TMP_ROOT/renamed-malformed-id.out" 2>&1; then fail 'initial start accepted a malformed saved container ID'; fi
assert_contains "$(cat "$TMP_ROOT/renamed-malformed-id.out")" 'invalid or insecure'
cmp "$TMP_ROOT/renamed-malformed-id.saved" "$manifest" || fail 'malformed-ID refusal changed the manifest'
assert_eq "$(file_mode "$manifest")" 600
[ ! -e "$pending" ] || fail 'malformed-ID refusal created pending state'
[ -d "$ENGINE_STATE/containers/renamed-malformed-id-tunnel" ] || fail 'malformed-ID refusal touched the renamed container'
assert_eq "$(cat "$ENGINE_STATE/containers/renamed-malformed-id-tunnel/id")" "$renamed_malformed_id"
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 1
assert_eq "$(grep -c '^stop:' "$ENGINE_EVENTS" || true)" 0
assert_eq "$(grep -c '^remove:' "$ENGINE_EVENTS" || true)" 0
assert_eq "$(grep -Fc 'podman[run]' "$ENGINE_LOG")" 1

a_setup uncertain-initial-list
run_cli tun old-host 8080:80 >/dev/null || fail 'uncertain-list setup failed'
cp "$manifest" "$TMP_ROOT/uncertain-initial-manifest.saved"
rm -rf "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)"
FAKE_FAIL_LIST=1
export FAKE_FAIL_LIST
if run_cli tun fresh-host 9000:90 > "$TMP_ROOT/uncertain-initial-list.out" 2>&1; then fail 'initial start accepted uncertain container listing'; fi
assert_contains "$(cat "$TMP_ROOT/uncertain-initial-list.out")" 'state was retained'
cmp "$TMP_ROOT/uncertain-initial-manifest.saved" "$manifest" || fail 'uncertain listing changed stale manifest state'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 1
[ ! -e "$pending" ] || fail 'uncertain listing created pending state'
unset FAKE_FAIL_LIST

a_setup insecure-initial-manifest
run_cli tun old-host 8080:80 >/dev/null || fail 'insecure-manifest setup failed'
chmod 644 "$manifest"
cp "$manifest" "$TMP_ROOT/insecure-initial-manifest.saved"
if run_cli tun fresh-host 9000:90 > "$TMP_ROOT/insecure-initial-start.out" 2>&1; then fail 'initial start accepted an insecure stale manifest'; fi
assert_contains "$(cat "$TMP_ROOT/insecure-initial-start.out")" 'invalid or insecure'
cmp "$TMP_ROOT/insecure-initial-manifest.saved" "$manifest" || fail 'insecure-manifest refusal changed saved state'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 1
[ ! -e "$pending" ] || fail 'insecure-manifest refusal created pending state'

# A valid manifest ID renamed away from the target name must keep its state and only get manual-cleanup guidance.
a_setup renamed-manifest-target
run_cli tun host 8080:80 >/dev/null || fail 'renamed-manifest setup start failed'
renamed_manifest_id=$(sed -n 's/^container_id=//p' "$manifest" | base64 -d)
mv "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" "$ENGINE_STATE/containers/renamed-manifest-target"
if run_cli tun --stop > "$TMP_ROOT/renamed-manifest-stop.out" 2>&1; then fail 'tun --stop cleared state for a renamed saved ID'; fi
renamed_manifest_output=$(cat "$TMP_ROOT/renamed-manifest-stop.out")
assert_contains "$renamed_manifest_output" 'manually clean up'
[ -e "$manifest" ] || fail 'renamed manifest ID state was cleared'
[ -d "$ENGINE_STATE/containers/renamed-manifest-target" ] || fail 'explicit stop removed a renamed container'
assert_eq "$(grep -c '^stop:' "$ENGINE_EVENTS" || true)" 0
assert_eq "$(grep -c '^remove:' "$ENGINE_EVENTS" || true)" 0
assert_eq "$renamed_manifest_id" "$(cat "$ENGINE_STATE/containers/renamed-manifest-target/id")"

# If inspect fails while the exact ID/name remains listed, stop must not clear state or claim success.
a_setup stop-inspect-listed
run_cli tun host 8080:80 >/dev/null || fail 'inspect-listed stop setup failed'
write_pending_record add "$(sed -n 's/^container_id=//p' "$manifest" | base64 -d)" none 8080:80
FAKE_FAIL_LIST=1
export FAKE_FAIL_LIST
if run_cli tun --stop > "$TMP_ROOT/stop-list-failure.out" 2>&1; then fail 'tun --stop accepted a failed authoritative listing'; fi
stop_list_output=$(cat "$TMP_ROOT/stop-list-failure.out")
assert_contains "$stop_list_output" 'tunnel state was retained'
assert_contains "$stop_list_output" 'tun --stop'
assert_not_contains "$stop_list_output" 'Stopped tunnel'
[ -e "$manifest" ] && [ -e "$pending" ] || fail 'failed authoritative listing cleared explicit-stop state'
unset FAKE_FAIL_LIST
: > "$ENGINE_STATE/inspect-failure-armed"
FAKE_FAIL_RM=1
export FAKE_FAIL_RM
if run_cli tun --stop > "$TMP_ROOT/stop-inspect-listed.out" 2>&1; then fail 'inspect failure with a listed target was treated as absence'; fi
stop_inspect_output=$(cat "$TMP_ROOT/stop-inspect-listed.out")
assert_contains "$stop_inspect_output" 'tunnel state was retained'
assert_contains "$stop_inspect_output" 'tun --stop'
assert_not_contains "$stop_inspect_output" 'Stopped tunnel'
assert_not_contains "$stop_inspect_output" 'No tunnel container is running'
[ -e "$manifest" ] && [ -e "$pending" ] || fail 'failed explicit stop cleared manifest or pending state'
[ -d "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" ] || fail 'failed explicit stop removed a listed target despite injected failure'
unset FAKE_FAIL_RM
rm -f "$ENGINE_STATE/inspect-failure-armed"
run_cli tun --stop >/dev/null || fail 'inspect-listed stop recovery failed'
[ ! -e "$manifest" ] && [ ! -e "$pending" ] || fail 'recovered explicit stop retained state'

a_setup manifest-security
run_cli tun host 8080:80 >/dev/null || fail 'manifest security setup start failed'
chmod 644 "$manifest"
if run_cli tun-add-port 8443:443 --yes > "$TMP_ROOT/insecure-manifest.out" 2>&1; then fail 'insecure manifest was accepted'; fi
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 1
assert_eq "$(grep -c '^stop:' "$ENGINE_EVENTS" || true)" 0
chmod 600 "$manifest"
printf 'unknown=Zm9v\\n' >> "$manifest"
if run_cli tun-rm-port 8080 --yes > "$TMP_ROOT/malformed-manifest.out" 2>&1; then fail 'unrecognized manifest field was accepted'; fi
assert_eq "$(grep -c '^stop:' "$ENGINE_EVENTS" || true)" 0
run_cli tun --stop >/dev/null || fail 'manifest cleanup stop failed'

a_setup identity-mismatch
run_cli tun host 8080:80 >/dev/null || fail 'identity mismatch setup start failed'
printf '%s\n' "$(fake_id 82)" > "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)/id"
if run_cli tun-add-port 8443:443 --yes > "$TMP_ROOT/id-mismatch.out" 2>&1; then fail 'container ID mismatch was accepted'; fi
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 1
assert_eq "$(grep -c '^stop:' "$ENGINE_EVENTS" || true)" 0

# Invalid initial mappings and config/engine path mismatches cause no engine mutation.
a_setup invalid-inputs
if run_cli tun host 0:80 > "$TMP_ROOT/range.out" 2>&1; then fail 'out-of-range initial mapping succeeded'; fi
if run_cli tun host 8080:80 08080:81 > "$TMP_ROOT/dupe.out" 2>&1; then fail 'normalized duplicate initial mapping succeeded'; fi
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS" || true)" 0
run_cli tun host 8080:80 >/dev/null || fail 'setup tunnel for mismatch check failed'
printf 'other config\n' > "$CASE_CONFIG/other.ovpn"
if SD_VPNC_CONFIG=$CASE_CONFIG/other.ovpn run_cli tun-add-port 8443:443 --yes > "$TMP_ROOT/config-mismatch.out" 2>&1; then fail 'config path mismatch unexpectedly succeeded'; fi
assert_contains "$(cat "$TMP_ROOT/config-mismatch.out")" 'differ'
if PATH="$case_dir/docker-bin:/usr/bin:/bin" run_cli tun-add-port 8443:443 --yes > "$TMP_ROOT/engine-mismatch.out" 2>&1; then fail 'engine mismatch unexpectedly succeeded'; fi
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 1

# A malformed pending record is not treated as an empty transaction during explicit stop.
a_setup malformed-pending-stop
run_cli tun host 8080:80 >/dev/null || fail 'malformed-pending setup start failed'
printf 'SDVPNC-TUN-PENDING\n' > "$pending"
chmod 600 "$pending"
if run_cli tun --stop > "$TMP_ROOT/malformed-pending-stop.out" 2>&1; then fail 'tun --stop accepted a malformed pending record'; fi
assert_contains "$(cat "$TMP_ROOT/malformed-pending-stop.out")" 'pending tunnel record is invalid'
[ -e "$manifest" ] && [ -e "$pending" ] || fail 'malformed pending cleanup cleared recovery state'
pending_test_valid_id=$(sed -n 's/^container_id=//p' "$manifest" | base64 -d)
write_pending_record add x none 8080:80
if run_cli tun --stop > "$TMP_ROOT/malformed-pending-old-id.out" 2>&1; then fail 'pending record accepted a malformed old container ID'; fi
assert_contains "$(cat "$TMP_ROOT/malformed-pending-old-id.out")" 'pending tunnel record is invalid'
[ -e "$manifest" ] && [ -e "$pending" ] || fail 'malformed pending old ID cleared recovery state'
write_pending_record add "$pending_test_valid_id" x 8080:80
if run_cli tun --stop > "$TMP_ROOT/malformed-pending-replacement-id.out" 2>&1; then fail 'pending record accepted a malformed replacement container ID'; fi
assert_contains "$(cat "$TMP_ROOT/malformed-pending-replacement-id.out")" 'pending tunnel record is invalid'
[ -e "$manifest" ] && [ -e "$pending" ] || fail 'malformed pending replacement ID cleared recovery state'
write_pending_record add "$pending_test_valid_id" none 8080:80
run_cli tun --stop >/dev/null || fail 'strict pending recovery failed after fixing its record'

# A pending record blocks start and mutation until the explicit prompt-free stop.
a_setup pending-recovery
run_cli tun host 8080:80 >/dev/null || fail 'pending recovery setup failed'
write_pending_record initial none none 8080:80
if run_cli tun-add-port 8443:443 --yes > "$TMP_ROOT/pending-add.out" 2>&1; then fail 'pending transaction did not block mutation'; fi
if run_cli tun host 9000:90 > "$TMP_ROOT/pending-start.out" 2>&1; then fail 'pending transaction did not block start'; fi
if run_cli tun-rm-port 8080 --yes > "$TMP_ROOT/pending-remove.out" 2>&1; then fail 'pending transaction did not block removal'; fi
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 1
run_cli tun --stop >/dev/null || fail 'tun --stop failed to clear pending state'
[ ! -e "$pending" ] || fail 'tun --stop left pending state'

# Initial readiness timeout removes the partial container and all claimed state.
a_setup initial-timeout
FAKE_NO_READY_RUNS=1
export FAKE_NO_READY_RUNS
if run_cli tun host 8080:80 > "$TMP_ROOT/timeout.out" 2>&1; then fail 'initial readiness timeout succeeded'; fi
assert_contains "$(cat "$TMP_ROOT/timeout.out")" 'retry'
[ ! -d "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" ] || fail 'timeout left a partial tunnel'
[ ! -e "$CASE_STATE/sd-vpnc/tunnel.manifest" ] || fail 'timeout retained active state'
[ ! -e "$CASE_STATE/sd-vpnc/tunnel.pending" ] || fail 'timeout retained pending state'

# A ready initial container is removed if its manifest cannot be atomically committed.
a_setup initial-manifest-failure
FAKE_FAIL_MANIFEST_ONCE=1
export FAKE_FAIL_MANIFEST_ONCE
if run_cli tun host 8080:80 > "$TMP_ROOT/initial-manifest-failure.out" 2>&1; then fail 'initial manifest commit failure unexpectedly succeeded'; fi
assert_contains "$(cat "$TMP_ROOT/initial-manifest-failure.out")" 'tunnel was removed'
[ ! -d "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" ] || fail 'manifest failure left initial tunnel running'
[ ! -e "$manifest" ] && [ ! -e "$pending" ] || fail 'initial manifest failure retained state'

initial_cleanup_failure_case() {
	case_name=$1
	failure=$2
	stage=$3
	a_setup "$case_name"
	case $failure in
		stop) FAKE_FAIL_STOP=1; export FAKE_FAIL_STOP ;;
		rm) FAKE_FAIL_RM=1; export FAKE_FAIL_RM ;;
		inspect) FAKE_INSPECT_FAIL_AFTER_EXEC=1; export FAKE_INSPECT_FAIL_AFTER_EXEC ;;
		list) FAKE_INSPECT_FAIL_AFTER_EXEC=1; FAKE_FAIL_LIST=1; FAKE_FAIL_LIST_AFTER_INSPECT=1; export FAKE_INSPECT_FAIL_AFTER_EXEC FAKE_FAIL_LIST FAKE_FAIL_LIST_AFTER_INSPECT ;;
		*) fail "unknown fake cleanup failure: $failure" ;;
	esac
	case $stage in
		readiness) FAKE_NO_READY_RUNS=1; export FAKE_NO_READY_RUNS ;;
		manifest) FAKE_FAIL_MANIFEST_ONCE=1; export FAKE_FAIL_MANIFEST_ONCE ;;
		*) fail "unknown initial failure stage: $stage" ;;
	esac
	output_file=$TMP_ROOT/$case_name.out
	if run_cli tun host 8080:80 > "$output_file" 2>&1; then fail "$case_name unexpectedly succeeded"; fi
	output=$(cat "$output_file")
	assert_contains "$output" 'may remain'
	assert_contains "$output" 'tun --stop'
	assert_not_contains "$output" 'removed'
	[ -e "$pending" ] || fail "$case_name cleared pending state without verified removal"
	[ ! -e "$manifest" ] || fail "$case_name retained an uncommitted active manifest"
	[ -d "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" ] || fail "$case_name unexpectedly removed the fake tunnel"
	unset FAKE_FAIL_STOP FAKE_FAIL_RM FAKE_FAIL_LIST FAKE_FAIL_LIST_AFTER_INSPECT FAKE_INSPECT_FAIL_AFTER_EXEC FAKE_NO_READY_RUNS FAKE_FAIL_MANIFEST_ONCE
	run_cli tun --stop > "$TMP_ROOT/$case_name-recovery.out" 2>&1 || fail "$case_name explicit recovery failed"
	[ ! -e "$pending" ] || fail "$case_name explicit recovery retained pending state"
	[ ! -e "$manifest" ] || fail "$case_name explicit recovery retained manifest state"
	[ ! -d "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" ] || fail "$case_name explicit recovery left the tunnel container"
}

# Failed stop/remove operations keep pending recovery state for readiness and commit failures.
initial_cleanup_failure_case readiness-stop-failure stop readiness
initial_cleanup_failure_case readiness-remove-failure rm readiness
initial_cleanup_failure_case readiness-inspect-failure inspect readiness
initial_cleanup_failure_case manifest-stop-failure stop manifest
initial_cleanup_failure_case manifest-remove-failure rm manifest
initial_cleanup_failure_case manifest-inspect-failure inspect manifest
initial_cleanup_failure_case manifest-list-failure list manifest

# A failed inspect is not an obstacle to cleanup when a successful full listing proves absence.
a_setup initial-inspect-absent-listed
FAKE_INSPECT_FAIL_AFTER_EXEC=1
FAKE_REMOVE_AFTER_EXEC=1
export FAKE_INSPECT_FAIL_AFTER_EXEC FAKE_REMOVE_AFTER_EXEC
if run_cli tun host 8080:80 > "$TMP_ROOT/initial-inspect-absent-listed.out" 2>&1; then fail 'initial start unexpectedly succeeded after its target disappeared'; fi
assert_contains "$(cat "$TMP_ROOT/initial-inspect-absent-listed.out")" 'retry'
assert_not_contains "$(cat "$TMP_ROOT/initial-inspect-absent-listed.out")" 'may remain'
[ ! -e "$manifest" ] && [ ! -e "$pending" ] || fail 'authoritatively absent initial target retained state'
[ ! -d "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" ] || fail 'initial target absent from listing remained in fake engine'
unset FAKE_INSPECT_FAIL_AFTER_EXEC FAKE_REMOVE_AFTER_EXEC

# Replacement readiness failures roll back to the old mapping set; failed rollback fails closed.
a_setup rollback-success
run_cli tun rollback-host 8080:80 >/dev/null || fail 'rollback setup start failed'
printf 'changed but valid source\n' > "$CASE_CONFIG/client.ovpn"
FAKE_NO_READY_RUNS=2
export FAKE_NO_READY_RUNS
if run_cli tun-add-port 8443:443 --yes > "$TMP_ROOT/rollback-success.out" 2>&1; then fail 'failed replacement unexpectedly returned success'; fi
assert_contains "$(cat "$TMP_ROOT/rollback-success.out")" 'previous tunnel was restored'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 3
[ -f "$manifest" ] || fail 'successful rollback did not commit a manifest'
[ ! -e "$pending" ] || fail 'successful rollback retained pending state'
# The restored container carries exactly the prior host/mapping set and uses current source contents.
assert_eq "$(grep -c '^mapping\.' "$manifest")" 1
assert_eq "$(sed -n 's/^host=//p' "$manifest" | base64 -d)" rollback-host
assert_contains "$(cat "$ENGINE_STATE/sources")" 'changed but valid source'

a_setup manifest-commit-failure
run_cli tun host 8080:80 >/dev/null || fail 'manifest-commit setup start failed'
FAKE_FAIL_MANIFEST_ONCE=1
export FAKE_FAIL_MANIFEST_ONCE
if run_cli tun-add-port 8443:443 --yes > "$TMP_ROOT/manifest-commit-failure.out" 2>&1; then fail 'injected manifest commit failure unexpectedly succeeded'; fi
assert_contains "$(cat "$TMP_ROOT/manifest-commit-failure.out")" 'previous tunnel was restored'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 3
assert_eq "$(grep -c '^mapping\.' "$manifest")" 1
[ ! -e "$pending" ] || fail 'manifest rollback retained pending state'

a_setup rollback-failure
run_cli tun rollback-host 8080:80 >/dev/null || fail 'rollback-failure setup start failed'
printf 'invalid config for both attempts\n' > "$CASE_CONFIG/client.ovpn"
unset FAKE_NO_READY_RUNS
if run_cli tun-add-port 8443:443 --yes > "$TMP_ROOT/rollback-failure.out" 2>&1; then fail 'failed rollback unexpectedly returned success'; fi
assert_contains "$(cat "$TMP_ROOT/rollback-failure.out")" 'No managed tunnel is claimed'
[ ! -e "$CASE_STATE/sd-vpnc/tunnel.manifest" ] || fail 'failed rollback retained a false active manifest'
[ -e "$pending" ] || fail 'failed rollback did not retain recovery state'
[ ! -d "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" ] || fail 'failed rollback left a partial replacement'
assert_contains "$(cat "$ENGINE_STATE/sources")" 'invalid config for both attempts'

# A renamed failed replacement ID blocks rollback and remains discoverable in pending state.
a_setup rollback-renamed-replacement
run_cli tun rollback-host 8080:80 >/dev/null || fail 'renamed rollback setup start failed'
FAKE_RENAME_RUNS=2
export FAKE_RENAME_RUNS
if run_cli tun-add-port 8443:443 --yes > "$TMP_ROOT/rollback-renamed.out" 2>&1; then fail 'renamed failed replacement unexpectedly succeeded'; fi
renamed_rollback_output=$(cat "$TMP_ROOT/rollback-renamed.out")
assert_contains "$renamed_rollback_output" 'rollback was not started'
assert_contains "$renamed_rollback_output" 'tun --stop'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 2
[ -e "$manifest" ] && [ -e "$pending" ] || fail 'renamed failed replacement cleanup cleared state'
[ -d "$ENGINE_STATE/containers/renamed-tunnel-2" ] || fail 'fake replacement did not get renamed'
if run_cli tun --stop > "$TMP_ROOT/rollback-renamed-stop.out" 2>&1; then fail 'explicit stop ignored renamed pending replacement ID'; fi
assert_contains "$(cat "$TMP_ROOT/rollback-renamed-stop.out")" 'manually clean up'
[ -e "$manifest" ] && [ -e "$pending" ] || fail 'explicit stop cleared renamed replacement recovery state'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 2

# Uncertain inspection of a failed replacement also prevents rollback or clearing recovery state.
a_setup rollback-inspection-uncertain
run_cli tun rollback-host 8080:80 >/dev/null || fail 'inspection-uncertain rollback setup start failed'
FAKE_NO_READY_RUNS=2
FAKE_INSPECT_FAIL_AFTER_EXEC=1
export FAKE_NO_READY_RUNS FAKE_INSPECT_FAIL_AFTER_EXEC
if run_cli tun-add-port 8443:443 --yes > "$TMP_ROOT/rollback-inspection-uncertain.out" 2>&1; then fail 'inspection-uncertain replacement unexpectedly succeeded'; fi
uncertain_rollback_output=$(cat "$TMP_ROOT/rollback-inspection-uncertain.out")
assert_contains "$uncertain_rollback_output" 'rollback was not started'
assert_contains "$uncertain_rollback_output" 'Manifest and pending state were retained'
assert_eq "$(grep -c '^start:' "$ENGINE_EVENTS")" 2
[ -e "$manifest" ] && [ -e "$pending" ] || fail 'inspection uncertainty cleared manifest or pending state'
[ -d "$ENGINE_STATE/containers/sd-vpnc-tun-$(id -u)" ] || fail 'inspection uncertainty removed the unverified replacement'
unset FAKE_NO_READY_RUNS FAKE_INSPECT_FAIL_AFTER_EXEC
rm -f "$ENGINE_STATE/inspect-failure-armed"
run_cli tun --stop >/dev/null || fail 'inspection-uncertain explicit recovery failed'

printf 'All tunnel port-management fake-engine tests passed.\n'
