#!/bin/sh

set -eu

REPO_ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
ORIGINAL_PATH=$PATH
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sd-vpnc-sessions.XXXXXX")
cleanup() {
	[ -z "${FUNCTIONAL_MANAGER_PID:-}" ] || kill "$FUNCTIONAL_MANAGER_PID" 2>/dev/null || true
	[ -z "${FUNCTIONAL_MANAGER_PID:-}" ] || wait "$FUNCTIONAL_MANAGER_PID" 2>/dev/null || true
	[ -z "${DELAYED_EXEC_PID:-}" ] || kill "$DELAYED_EXEC_PID" 2>/dev/null || true
	if [ -n "${ENGINE_STATE:-}" ] && [ -d "$ENGINE_STATE/containers" ]; then
		for state_dir in "$ENGINE_STATE"/containers/*; do
			[ ! -d "$state_dir" ] || rm -rf "$state_dir"
		done
	fi
	chmod -R u+rwx "$TMP_ROOT" 2>/dev/null || true
	rm -rf "$TMP_ROOT"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

assert_contains() {
	case $1 in *"$2"*) ;; *) fail "expected text to contain: $2" ;; esac
}

assert_not_contains() {
	case $1 in *"$2"*) fail "expected text not to contain: $2" ;; *) ;; esac
}

assert_eq() {
	[ "$1" = "$2" ] || fail "expected '$1' to equal '$2'"
}

file_mode() {
	stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

setup_case() {
	case_name=$1
	CASE_DIR=$TMP_ROOT/$case_name
	ENGINE_STATE=$CASE_DIR/engine-state
	ENGINE_BIN=$CASE_DIR/bin
	CASE_HOME=$CASE_DIR/home
	CASE_CONFIG=$CASE_HOME/.config/sd-vpnc
	CASE_SSH=$CASE_HOME/.ssh
	CASE_WORK=$CASE_HOME/.local/share/sd-vpnc
	CASE_CACHE=$CASE_DIR/cache
	CASE_STATE=$CASE_DIR/state
	mkdir -p "$ENGINE_STATE/containers" "$ENGINE_BIN" "$CASE_CONFIG" "$CASE_SSH" "$CASE_WORK" "$CASE_CACHE" "$CASE_STATE"
	: > "$CASE_CONFIG/client.ovpn"
	: > "$CASE_CONFIG/credentials"
	chmod 600 "$CASE_CONFIG/credentials"
	printf 'Host fake\n' > "$CASE_SSH/config"
	RUNTIME_LOG=$ENGINE_STATE/engine.log
	: > "$RUNTIME_LOG"
	: > "$ENGINE_STATE/events"
	TEST_REGISTRY=$CASE_DIR/generated-registry
	TEST_ENTRYPOINT=$CASE_DIR/generated-entrypoint
	FAKE_FAIL_REGISTER=0
	FAKE_KEEP_IDLE=0
	FAKE_DISABLE_SESSION_WATCHER=0
	FAKE_RACE_STOPPING=0
	FAKE_BLOCK_BUILD=0
	FAKE_FAIL_BUILD=0
	FAKE_DELAY_FIRST_SESSION=0
	FAKE_INDETERMINATE=0
	export ENGINE_STATE RUNTIME_LOG TEST_REGISTRY TEST_ENTRYPOINT FAKE_FAIL_REGISTER FAKE_KEEP_IDLE FAKE_DISABLE_SESSION_WATCHER FAKE_RACE_STOPPING FAKE_BLOCK_BUILD FAKE_FAIL_BUILD FAKE_DELAY_FIRST_SESSION FAKE_INDETERMINATE
}

cat > "$TMP_ROOT/fake-podman" <<'ENGINE'
#!/bin/sh
set -eu
printf '%s' "${0##*/}" >> "$RUNTIME_LOG"
for argument do printf '[%s]' "$argument" >> "$RUNTIME_LOG"; done
printf '\n' >> "$RUNTIME_LOG"
state_dir="$ENGINE_STATE/containers/sd-vpnc-$(id -u)"
count_leases() {
	count=0
	for lease in "$state_dir"/lease.*; do
		[ -f "$lease" ] || continue
		count=$((count + 1))
	done
	printf '%s' "$count"
}
status_line() {
	live=$(count_leases)
	state=WAITING_FIRST_SESSION
	[ ! -f "$state_dir/state" ] || state=$(cat "$state_dir/state")
	[ "$live" -eq 0 ] || state=ACTIVE
	if [ "${FAKE_RACE_STOPPING:-0}" = 1 ] && [ ! -f "$ENGINE_STATE/race-triggered" ] && [ "$state" = ACTIVE ]; then live=1; fi
	printf 'ownership=sd-vpnc protocol=1 state=%s generation=fake live=%s stale=0 indeterminate=%s\n' "$state" "$live" "${FAKE_INDETERMINATE:-0}"
}
case ${1:-} in
	info)
		printf '%s\n' "${FAKE_ROOTLESS_STATUS:-false}"
		exit 0
		;;
	image)
		case ${2:-} in inspect) exit 0 ;; esac
		;;
	build)
		shift
		while [ "$#" -gt 0 ]; do
			if [ "$1" = -f ]; then shift; fi
			build_context=$1
			shift
		done
		cp "$build_context/sd-vpnc-session-registry" "$TEST_REGISTRY"
		cp "$build_context/entrypoint.sh" "$TEST_ENTRYPOINT"
		if [ "${FAKE_BLOCK_BUILD:-0}" = 1 ]; then
			: > "$ENGINE_STATE/build-started"
			while [ ! -f "$ENGINE_STATE/build-release" ]; do sleep 0.02; done
		fi
		if [ "${FAKE_FAIL_BUILD:-0}" = 1 ]; then
			printf 'build-failed\n' >> "$ENGINE_STATE/events"
			exit 77
		fi
		printf 'build\n' >> "$ENGINE_STATE/events"
		[ ! -f "$ENGINE_STATE/build-started" ] || printf 'build-complete\n' >> "$ENGINE_STATE/events"
		exit 0
		;;
	container)
		case ${2:-} in
			inspect)
				name=${5:-${3:-}}
				inspect_dir="$ENGINE_STATE/containers/$name"
				[ -d "$inspect_dir" ] || exit 1
				if [ "${3:-}" = --format ]; then
					case ${4:-} in
						*State.Running*) [ ! -f "$inspect_dir/stopped" ] && printf 'true\n' || printf 'false\n' ;;
						*.Id*) cat "$inspect_dir/id" 2>/dev/null || printf 'fake-container-id\n' ;;
						*io.sd-vpnc.tunnel*) grep '^io.sd-vpnc.tunnel=' "$inspect_dir/labels" 2>/dev/null | cut -d= -f2- || printf '\n' ;;
						*io.sd-vpnc.manager*) cat "$inspect_dir/labels" 2>/dev/null || printf '\n' ;;
						*) printf 'true\n' ;;
					esac
				fi
				exit 0
				;;
			ls)
				for container_dir in "$ENGINE_STATE"/containers/*; do
					[ -d "$container_dir" ] || continue
					printf '%s|%s\n' "$(cat "$container_dir/id")" "${container_dir##*/}"
				done
				exit 0
				;;
			rm|stop)
				name=${3:-sd-vpnc-$(id -u)}
				if [ -d "$ENGINE_STATE/containers/$name" ]; then
					if [ "${2:-}" = stop ]; then
						: > "$ENGINE_STATE/containers/$name/stopped"
					else
						rm -rf "$ENGINE_STATE/containers/$name"
					fi
					printf '%s\n' "${2}-container" >> "$ENGINE_STATE/events"
				fi
				exit 0
				;;
		esac
		;;
	run)
		name=
		while [ "$#" -gt 0 ]; do
			case $1 in
				--name) name=$2; shift 2 ;;
				*) shift ;;
			esac
		done
		[ -n "$name" ] || name=sd-vpnc-$(id -u)
		mkdir -p "$ENGINE_STATE/containers/$name"
		sequence=0
		[ ! -f "$ENGINE_STATE/id-sequence" ] || sequence=$(cat "$ENGINE_STATE/id-sequence")
		sequence=$((sequence + 1))
		printf '%s\n' "$sequence" > "$ENGINE_STATE/id-sequence"
		printf 'fake-container-id-%s\n' "$sequence" > "$ENGINE_STATE/containers/$name/id"
		if [ "$name" = "sd-vpnc-tun-$(id -u)" ]; then
			printf 'io.sd-vpnc.tunnel=sd-vpnc\n' > "$ENGINE_STATE/containers/$name/labels"
			[ "${FAKE_TUN_NOT_READY:-0}" = 1 ] || : > "$ENGINE_STATE/containers/$name/tun-ready"
			printf 'tunnel-start\n' >> "$ENGINE_STATE/events"
		else
			printf 'sd-vpnc|1\n' > "$ENGINE_STATE/containers/$name/labels"
			printf 'WAITING_FIRST_SESSION\n' > "$ENGINE_STATE/containers/$name/state"
			: > "$ENGINE_STATE/containers/$name/ready"
			printf 'manager-start\n' >> "$ENGINE_STATE/events"
		fi
		printf 'fake-container-id-%s\n' "$sequence"
		exit 0
		;;
	exec)
		shift
		exec_workdir=
		while :; do
			case ${1:-} in
				-i|-t|-it) shift ;;
				--workdir|-w) exec_workdir=$2; shift 2 ;;
				--user) shift 2 ;;
				*) break ;;
			esac
		done
		name=${1:-}; shift || true
		command=${1:-}; shift || true
		state_dir="$ENGINE_STATE/containers/$name"
		case $command in
			test)
				path=${2:-}
				case $path in
					/tmp/sd-vpnc-manager-ready) [ -f "$state_dir/ready" ] ;;
					/tmp/sd-vpnc-tun-ready) [ -f "$state_dir/tun-ready" ] ;;
					/tmp/sd-vpnc-session-registry/registered/*)
						id=${path##*/}; printf 'poll %s %s %s\n' "$path" "$state_dir" "$([ -f "$state_dir/registered.$id" ] && echo yes || echo no)" >> "$ENGINE_STATE/events"; [ -f "$state_dir/registered.$id" ] ;;
					*) exit 1 ;;
				esac
				exit $?
				;;
			/usr/local/bin/sd-vpnc-entrypoint)
				mode=${1:-}; shift || true
				case $mode in
					status)
						if [ "${FAKE_RACE_STOPPING:-0}" = 1 ] && [ ! -f "$ENGINE_STATE/race-triggered" ]; then
							printf 'host-status-before-watcher\n' >> "$ENGINE_STATE/events"
						fi
						status_line
						exit 0
						;;
					session)
						id=${1:-}; session_mode=${2:-}; shift 2 || true
						[ "${FAKE_FAIL_REGISTER:-0}" != 1 ] || exit 42
						[ -d "$state_dir" ] || exit 43
						if [ "${FAKE_DELAY_FIRST_SESSION:-0}" = 1 ] && [ ! -f "$ENGINE_STATE/delayed-exec-started" ]; then
							: > "$ENGINE_STATE/delayed-exec-started"
							printf '%s\n' "$id" > "$ENGINE_STATE/delayed-exec-id"
							printf '%s\n' "$$" > "$ENGINE_STATE/delayed-exec-pid"
							while [ ! -f "$ENGINE_STATE/delayed-exec-release" ]; do sleep 0.05; done
							[ ! -f "$state_dir/ack.$id" ] || printf 'session-command %s\n' "$id" >> "$ENGINE_STATE/events"
							exit 0
						fi
						if [ "${FAKE_RACE_STOPPING:-0}" = 1 ] && [ ! -f "$ENGINE_STATE/race-triggered" ]; then
							: > "$ENGINE_STATE/race-triggered"
							printf 'STOPPING\n' > "$state_dir/state"
							printf 'watcher-registration-reject\n' >> "$ENGINE_STATE/events"
							(sleep 0.2; rm -rf "$state_dir") &
							exit 44
						fi
						[ "$(cat "$state_dir/state")" != STOPPING ] || exit 44
						: > "$state_dir/lease.$id"
						: > "$state_dir/registered.$id"
						printf 'session-register %s %s\n' "$id" "$state_dir" >> "$ENGINE_STATE/events"
						printf '%s %s\n' "$id" "$session_mode" >> "$ENGINE_STATE/sessions"
						printf '%s %s\n' "$id" "$exec_workdir" >> "$ENGINE_STATE/session-workdirs"
						printf 'ACTIVE\n' > "$state_dir/state"
						while [ ! -f "$state_dir/ack.$id" ]; do sleep 0.05; done
						printf 'session-command %s\n' "$id" >> "$ENGINE_STATE/events"
						while [ ! -f "$state_dir/finish.$id" ]; do sleep 0.05; done
						rm -f "$state_dir/lease.$id"
						if [ "$(count_leases)" -eq 0 ] && [ "${FAKE_KEEP_IDLE:-0}" != 1 ] && [ "${FAKE_DISABLE_SESSION_WATCHER:-0}" != 1 ]; then
							printf 'watcher-stop\n' >> "$ENGINE_STATE/events"
							rm -rf "$state_dir"
						fi
						exit 0
						;;
					esac
					;;
			/usr/local/bin/sd-vpnc-session-registry)
					action=${1:-}; id=${2:-}
					case $action in
						status|reconcile) status_line; exit 0 ;;
						acknowledge) [ -f "$state_dir/lease.$id" ] || exit 1; : > "$state_dir/ack.$id"; printf 'host-ack %s\n' "$id" >> "$ENGINE_STATE/events"; exit 0 ;;
						release|stop-if-idle)
							[ "$action" != release ] || rm -f "$state_dir/lease.$id"
							live=$(count_leases)
							printf 'registry-%s live=%s dir=%s\n' "$action" "$live" "$state_dir" >> "$ENGINE_STATE/events"
							if [ "$live" -eq 0 ] && [ "$action" = release ] && [ "${FAKE_KEEP_IDLE:-0}" = 1 ]; then
								status_line
							elif [ "$live" -eq 0 ]; then
								printf 'watcher-stop\n' >> "$ENGINE_STATE/events"
								rm -rf "$state_dir"
								printf 'ownership=sd-vpnc protocol=1 state=STOPPING generation=fake live=0 stale=0 indeterminate=0\n'
							else
								status_line
							fi
							exit 0
							;;
					esac
					;;
		esac
		exit 0
		;;
	logs) exit 0 ;;
esac
exit 90
ENGINE
chmod +x "$TMP_ROOT/fake-podman"

make_engine_path() {
	cp "$TMP_ROOT/fake-podman" "$ENGINE_BIN/podman"
	chmod +x "$ENGINE_BIN/podman"
	RUN_PATH=$ENGINE_BIN:$ORIGINAL_PATH
	export RUN_PATH
}

run_cli() {
	PATH=$RUN_PATH HOME=$CASE_HOME \
		XDG_CONFIG_HOME=$CASE_HOME/.config XDG_DATA_HOME=$CASE_HOME/.local/share \
		XDG_STATE_HOME=$CASE_STATE SD_VPNC_COLOR=never \
		"$REPO_ROOT/sd-vpnc" "$@"
}

lease_count() {
	count=0
	for lease in "$ENGINE_STATE/containers/sd-vpnc-$(id -u)"/lease.*; do
		[ -f "$lease" ] || continue
		count=$((count + 1))
	done
	printf '%s\n' "$count"
}

wait_for_lease_count() {
	expected=$1
	attempt=0
	while [ "$attempt" -lt 100 ]; do
		[ "$(lease_count)" -eq "$expected" ] && return 0
		sleep 0.05
		attempt=$((attempt + 1))
	done
	fail "timed out waiting for $expected fake session leases"
}

wait_for_host_ack() {
	id=$1
	attempt=0
	while [ "$attempt" -lt 100 ]; do
		[ -f "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/ack.$id" ] && return 0
		sleep 0.05
		attempt=$((attempt + 1))
	done
	fail "host did not acknowledge registered session $id"
}

wait_for_session_count() {
	expected=$1
	attempt=0
	while [ "$attempt" -lt 100 ]; do
		actual=$(wc -l < "$ENGINE_STATE/sessions" 2>/dev/null || printf 0)
		[ "$(printf '%s' "$actual" | tr -d ' ')" -ge "$expected" ] && return 0
		sleep 0.05
		attempt=$((attempt + 1))
	done
	fail "timed out waiting for $expected registered sessions"
}

wait_for_file() {
	wanted_file=$1
	attempt=0
	while [ ! -f "$wanted_file" ] && [ "$attempt" -lt 200 ]; do
		sleep 0.05
		attempt=$((attempt + 1))
	done
	[ -f "$wanted_file" ] || fail "timed out waiting for $wanted_file"
}

lease_id_at() {
	wanted=$1
	index=0
	for lease in "$ENGINE_STATE/containers/sd-vpnc-$(id -u)"/lease.*; do
		[ -f "$lease" ] || continue
		if [ "$index" -eq "$wanted" ]; then printf '%s\n' "${lease##*.}"; return 0; fi
		index=$((index + 1))
	done
	return 1
}

# Two concurrent first requests serialize manager creation, register distinct exec sessions,
# and only the final session may cause watcher-driven cleanup.
setup_case concurrent-first-start
make_engine_path
run_cli ssh remote-one > "$CASE_DIR/one.log" 2>&1 &
first_pid=$!
wait_for_lease_count 1
run_cli ssh-tmux remote-two tmux-one > "$CASE_DIR/two.log" 2>&1 &
second_pid=$!
wait_for_lease_count 2
first_concurrent_id=$(lease_id_at 0)
second_concurrent_id=$(lease_id_at 1)
wait_for_host_ack "$first_concurrent_id"
wait_for_host_ack "$second_concurrent_id"
assert_eq "$(grep -c '^manager-start$' "$ENGINE_STATE/events")" 1
assert_eq "$(file_mode "$CASE_STATE/sd-vpnc")" 700
assert_eq "$(file_mode "$CASE_STATE/sd-vpnc/manager.manifest")" 600
assert_eq "$(wc -l < "$ENGINE_STATE/sessions" | tr -d ' ')" 2
sessions=$(cat "$ENGINE_STATE/sessions")
assert_contains "$sessions" 'ssh'
assert_contains "$sessions" 'ssh-tmux'
status_output=$(run_cli status 2>&1) || fail "status failed for live manager: $status_output"
assert_contains "$status_output" 'live=2'
assert_contains "$status_output" 'stale=0'
first_id=$(lease_id_at 0)
second_id=$(lease_id_at 1)
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$first_id"
wait "$first_pid" || fail "first fake session failed"
assert_eq "$(lease_count)" 1
assert_eq "$(grep -c '^manager-start$' "$ENGINE_STATE/events")" 1
assert_eq "$(grep -c '^watcher-stop$' "$ENGINE_STATE/events" || true)" 0
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$second_id"
wait "$second_pid" || fail "second fake session failed"
[ ! -d "$ENGINE_STATE/containers/sd-vpnc-$(id -u)" ] || fail 'last session left manager running'
assert_eq "$(grep -c '^watcher-stop$' "$ENGINE_STATE/events")" 1

# The first manager's configuration is fixed; mismatches and rebuild are rejected while live.
setup_case option-mismatch
make_engine_path
run_cli ssh remote-live > "$CASE_DIR/live.log" 2>&1 &
live_pid=$!
wait_for_lease_count 1
live_id=$(lease_id_at 0)
wait_for_host_ack "$live_id"
mkdir -p "$CASE_HOME/other-work" "$CASE_HOME/other-ssh"
: > "$CASE_HOME/other.ovpn"
: > "$CASE_HOME/other-credentials"
if output=$(run_cli -C "$CASE_HOME/other-work" ssh hidden-work 2>&1); then fail 'different workdir unexpectedly attached'; fi
assert_contains "$output" 'different startup options'
assert_not_contains "$(printf '%s\n' "$output" | grep '^error' || true)" "$CASE_HOME/other-work"
if output=$(SD_VPNC_CONFIG="$CASE_HOME/other.ovpn" run_cli ssh hidden-config 2>&1); then fail 'different VPN config unexpectedly attached'; fi
assert_contains "$output" 'different startup options'
assert_not_contains "$(printf '%s\n' "$output" | grep '^error' || true)" "$CASE_HOME/other.ovpn"
if output=$(SD_VPNC_SSH_CONFIG="$CASE_HOME/other-ssh" run_cli ssh hidden-ssh 2>&1); then fail 'different SSH source unexpectedly attached'; fi
assert_contains "$output" 'different startup options'
assert_not_contains "$(printf '%s\n' "$output" | grep '^error' || true)" "$CASE_HOME/other-ssh"
if output=$(SD_VPNC_CREDENTIALS="$CASE_HOME/other-credentials" run_cli ssh hidden-credentials 2>&1); then fail 'different credentials source unexpectedly attached'; fi
assert_contains "$output" 'different startup options'
assert_not_contains "$(printf '%s\n' "$output" | grep '^error' || true)" "$CASE_HOME/other-credentials"
if output=$(CONTAINER_HOST=tcp://different-engine run_cli ssh hidden-engine 2>&1); then fail 'different engine context unexpectedly attached'; fi
assert_contains "$output" 'different startup options'
assert_not_contains "$(printf '%s\n' "$output" | grep '^error' || true)" 'different-engine'
if output=$(DEVPOD_WORKSPACE_ID=private-workspace run_cli ssh hidden-workspace 2>&1); then fail 'different workspace ID unexpectedly attached'; fi
assert_contains "$output" 'different startup options'
assert_not_contains "$(printf '%s\n' "$output" | grep '^error' || true)" 'private-workspace'
if output=$(run_cli --rebuild ssh hidden-rebuild 2>&1); then fail '--rebuild unexpectedly continued with live session'; fi
assert_contains "$output" 'Cannot rebuild the VPN image while managed sessions are live'
if output=$(run_cli image --rebuild 2>&1); then fail 'image --rebuild unexpectedly succeeded with a live session'; fi
assert_contains "$output" 'Cannot rebuild the VPN image while managed sessions are live'
assert_eq "$(grep -c '^manager-start$' "$ENGINE_STATE/events")" 1
assert_eq "$(lease_count)" 1
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$live_id"
wait "$live_pid" || fail "live session failed after mismatch tests"

# A later matching remote SSH and local shell start one separate exec each.
setup_case command-routing
make_engine_path
run_cli ssh remote-host -o BatchMode=yes > "$CASE_DIR/ssh.log" 2>&1 &
ssh_pid=$!
wait_for_lease_count 1
ssh_id=$(lease_id_at 0)
wait_for_host_ack "$ssh_id"
assert_contains "$(cat "$ENGINE_STATE/sessions")" 'ssh'
assert_contains "$(cat "$ENGINE_STATE/engine.log")" '[remote-host]'
assert_contains "$(cat "$ENGINE_STATE/engine.log")" '[BatchMode=yes]'
assert_contains "$(cat "$ENGINE_STATE/session-workdirs")" '/work'
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$ssh_id"
wait "$ssh_pid" || { cat "$CASE_DIR/ssh.log" "$ENGINE_STATE/engine.log" >&2; fail 'remote SSH session failed'; }
run_cli ssh-tmux tmux-host session-name > "$CASE_DIR/tmux.log" 2>&1 &
tmux_pid=$!
wait_for_lease_count 1
tmux_id=$(lease_id_at 0)
wait_for_host_ack "$tmux_id"
assert_contains "$(tail -n 1 "$ENGINE_STATE/sessions")" 'ssh-tmux'
assert_contains "$(cat "$ENGINE_STATE/engine.log")" '[tmux-host]'
assert_contains "$(cat "$ENGINE_STATE/engine.log")" '[session-name]'
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$tmux_id"
wait "$tmux_pid" || { cat "$CASE_DIR/tmux.log" "$ENGINE_STATE/engine.log" >&2; fail 'SSH-tmux session failed'; }
run_cli shell > "$CASE_DIR/shell.log" 2>&1 &
shell_pid=$!
wait_for_lease_count 1
shell_id=$(lease_id_at 0)
wait_for_host_ack "$shell_id"
assert_contains "$(tail -n 1 "$ENGINE_STATE/sessions")" 'ssh'
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$shell_id"
wait "$shell_pid" || fail 'local shell session failed'

# Killing only the host frontend does not release a live in-container session; its exit triggers watcher cleanup.
setup_case dead-host-frontend
make_engine_path
PATH=$RUN_PATH HOME=$CASE_HOME XDG_CONFIG_HOME=$CASE_HOME/.config \
	XDG_DATA_HOME=$CASE_HOME/.local/share XDG_STATE_HOME=$CASE_STATE \
	SD_VPNC_COLOR=never "$REPO_ROOT/sd-vpnc" ssh orphan-host > "$CASE_DIR/host.log" 2>&1 &
frontend_pid=$!
wait_for_lease_count 1
orphan_id=$(lease_id_at 0)
wait_for_host_ack "$orphan_id"
kill -KILL "$frontend_pid" 2>/dev/null || true
wait "$frontend_pid" 2>/dev/null || true
[ -d "$ENGINE_STATE/containers/sd-vpnc-$(id -u)" ] || fail 'host death stopped a manager with a live in-container session'
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$orphan_id"
attempt=0
while [ -d "$ENGINE_STATE/containers/sd-vpnc-$(id -u)" ] && [ "$attempt" -lt 100 ]; do sleep 0.05; attempt=$((attempt + 1)); done
[ ! -d "$ENGINE_STATE/containers/sd-vpnc-$(id -u)" ] || fail 'final orphaned session did not trigger watcher cleanup'
assert_eq "$(grep -c '^watcher-stop$' "$ENGINE_STATE/events")" 1

# Killing the host before registration acknowledgement must not leave its lock
# inherited by the still-running engine exec or permit that exec to run a command.
setup_case host-killed-before-registration-ack
make_engine_path
FAKE_DELAY_FIRST_SESSION=1
export FAKE_DELAY_FIRST_SESSION
PATH=$RUN_PATH HOME=$CASE_HOME XDG_CONFIG_HOME=$CASE_HOME/.config \
	XDG_DATA_HOME=$CASE_HOME/.local/share XDG_STATE_HOME=$CASE_STATE \
	SD_VPNC_COLOR=never "$REPO_ROOT/sd-vpnc" ssh must-not-run-before-ack > "$CASE_DIR/host.log" 2>&1 &
frontend_pid=$!
wait_for_file "$ENGINE_STATE/delayed-exec-started"
sleep 0.2
kill -KILL "$frontend_pid" 2>/dev/null || true
wait "$frontend_pid" 2>/dev/null || true
delayed_exec_pid=$(cat "$ENGINE_STATE/delayed-exec-pid")
DELAYED_EXEC_PID=$delayed_exec_pid
kill -0 "$delayed_exec_pid" 2>/dev/null || fail 'background engine exec did not survive host termination'
attempt=0
while ! "$(command -v flock)" -n "$CASE_STATE/sd-vpnc/lifecycle.lock" -c true 2>/dev/null; do
	[ "$attempt" -lt 60 ] || fail 'surviving engine exec retained the host lifecycle lock'
	sleep 0.05
	attempt=$((attempt + 1))
done
FAKE_DELAY_FIRST_SESSION=0
export FAKE_DELAY_FIRST_SESSION
run_cli ssh replacement-after-host-death > "$CASE_DIR/replacement.log" 2>&1 &
replacement_pid=$!
wait_for_lease_count 1
replacement_id=$(lease_id_at 0)
wait_for_host_ack "$replacement_id"
attempt=0
while ! grep -Fq "session-command $replacement_id" "$ENGINE_STATE/events" && [ "$attempt" -lt 100 ]; do
	sleep 0.05
	attempt=$((attempt + 1))
done
assert_contains "$(cat "$ENGINE_STATE/events")" "session-command $replacement_id"
assert_not_contains "$(cat "$ENGINE_STATE/events")" "session-command $(cat "$ENGINE_STATE/delayed-exec-id")"
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$replacement_id"
wait "$replacement_pid" || fail 'session start after host death did not complete'
touch "$ENGINE_STATE/delayed-exec-release"
attempt=0
while kill -0 "$delayed_exec_pid" 2>/dev/null && [ "$attempt" -lt 100 ]; do sleep 0.05; attempt=$((attempt + 1)); done
kill -0 "$delayed_exec_pid" 2>/dev/null && fail 'unacknowledged engine exec did not exit after release'
DELAYED_EXEC_PID=

# A final-release/attach race is serialized; the new request either registers before STOPPING or starts after removal.
setup_case attach-release-race
make_engine_path
FAKE_DISABLE_SESSION_WATCHER=1
export FAKE_DISABLE_SESSION_WATCHER
run_cli ssh first-racing-session > "$CASE_DIR/first.log" 2>&1 &
first_race_pid=$!
wait_for_lease_count 1
first_race_id=$(lease_id_at 0)
wait_for_host_ack "$first_race_id"
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$first_race_id"
run_cli ssh racing-attach > "$CASE_DIR/attach.log" 2>&1 &
attach_pid=$!
wait_for_session_count 2
attempt=0
attach_id=
while [ -z "$attach_id" ] && [ "$attempt" -lt 100 ]; do
	for lease in "$ENGINE_STATE/containers/sd-vpnc-$(id -u)"/lease.*; do
		[ -f "$lease" ] || continue
		candidate=${lease##*.}
		[ "$candidate" = "$first_race_id" ] || { attach_id=$candidate; break; }
	done
	[ -n "$attach_id" ] || { sleep 0.05; attempt=$((attempt + 1)); }
done
[ -n "$attach_id" ] || fail 'racing attach did not register a distinct lease'
wait_for_host_ack "$attach_id"
wait "$first_race_pid" || { cat "$CASE_DIR/first.log" "$ENGINE_STATE/engine.log" >&2; fail 'racing first session failed'; }
[ -d "$ENGINE_STATE/containers/sd-vpnc-$(id -u)" ] || fail 'attach race stopped the replacement manager'
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$attach_id"
wait "$attach_pid" || fail 'racing attach session failed'

# If the watcher changes a matching manager to STOPPING just before registration,
# the rejected exec never runs its command and the host retries once on a replacement.
setup_case watcher-registration-retry
make_engine_path
FAKE_KEEP_IDLE=1
export FAKE_KEEP_IDLE
run_cli ssh seed-idle-manager > "$CASE_DIR/idle.log" 2>&1 &
seed_pid=$!
wait_for_lease_count 1
seed_id=$(lease_id_at 0)
wait_for_host_ack "$seed_id"
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$seed_id"
wait "$seed_pid" || fail 'idle manager fixture session failed'
[ -d "$ENGINE_STATE/containers/sd-vpnc-$(id -u)" ] || fail 'idle manager fixture was not retained'
FAKE_KEEP_IDLE=0
FAKE_RACE_STOPPING=1
export FAKE_KEEP_IDLE FAKE_RACE_STOPPING
run_cli ssh retry-after-watcher > "$CASE_DIR/retry.log" 2>&1 &
retry_pid=$!
wait_for_lease_count 1
retry_id=$(lease_id_at 0)
wait_for_host_ack "$retry_id"
assert_eq "$(grep -c '^watcher-registration-reject$' "$ENGINE_STATE/events")" 1
status_checked_line=$(grep -n '^host-status-before-watcher$' "$ENGINE_STATE/events" | head -n 1 | cut -d: -f1)
watcher_reject_line=$(grep -n '^watcher-registration-reject$' "$ENGINE_STATE/events" | cut -d: -f1)
[ "$status_checked_line" -lt "$watcher_reject_line" ] || fail 'watcher transition did not follow a matching host status check'
assert_eq "$(grep -c '^manager-start$' "$ENGINE_STATE/events")" 2
assert_eq "$(grep -c '^session-register ' "$ENGINE_STATE/events")" 2
attempt=0
while [ "$(grep -c '^session-command ' "$ENGINE_STATE/events" || true)" -lt 2 ] && [ "$attempt" -lt 100 ]; do
	sleep 0.05
	attempt=$((attempt + 1))
done
assert_eq "$(grep -c '^session-command ' "$ENGINE_STATE/events")" 2
assert_contains "$(cat "$ENGINE_STATE/session-workdirs")" '/work'
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$retry_id"
wait "$retry_pid" || fail 'retried watcher-race session failed'

# Rebuild stops an owned idle manager before rebuilding and starting a fresh request.
setup_case idle-rebuild
make_engine_path
FAKE_KEEP_IDLE=1
export FAKE_KEEP_IDLE
run_cli ssh create-idle-manager > "$CASE_DIR/idle.log" 2>&1 &
idle_pid=$!
wait_for_lease_count 1
idle_id=$(lease_id_at 0)
wait_for_host_ack "$idle_id"
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$idle_id"
wait "$idle_pid" || fail 'idle manager fixture session failed'
[ -d "$ENGINE_STATE/containers/sd-vpnc-$(id -u)" ] || fail 'idle manager fixture was not retained'
FAKE_KEEP_IDLE=0
export FAKE_KEEP_IDLE
run_cli --rebuild ssh rebuilt-session > "$CASE_DIR/rebuild.log" 2>&1 &
rebuild_pid=$!
wait_for_lease_count 1
rebuilt_id=$(lease_id_at 0)
wait_for_host_ack "$rebuilt_id"
assert_eq "$(grep -c '^build$' "$ENGINE_STATE/events")" 1
assert_eq "$(grep -c '^manager-start$' "$ENGINE_STATE/events")" 2
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$rebuilt_id"
wait "$rebuild_pid" || fail 'request after idle rebuild failed'

# tun --rebuild shares the managed-session guard and is safe with live, uncertain,
# idle, and absent regular managers.
setup_case tun-rebuild-guards
make_engine_path
FAKE_KEEP_IDLE=1
export FAKE_KEEP_IDLE
run_cli ssh tun-rebuild-live-session > "$CASE_DIR/live.log" 2>&1 &
tun_live_pid=$!
wait_for_lease_count 1
tun_live_id=$(lease_id_at 0)
wait_for_host_ack "$tun_live_id"
if output=$(run_cli --rebuild tun tunnel-host 18443:443 2>&1); then fail 'tun --rebuild unexpectedly continued with a live managed session'; fi
assert_contains "$output" 'Cannot rebuild the VPN image while managed sessions are live or indeterminate.'
assert_eq "$(grep -c '^build$' "$ENGINE_STATE/events" || true)" 0
assert_eq "$(grep -c '^tunnel-start$' "$ENGINE_STATE/events" || true)" 0
[ -d "$ENGINE_STATE/containers/sd-vpnc-$(id -u)" ] || fail 'live-session rebuild rejection removed the manager'
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$tun_live_id"
wait "$tun_live_pid" || fail 'live-session tun rebuild fixture failed'
[ -d "$ENGINE_STATE/containers/sd-vpnc-$(id -u)" ] || fail 'idle manager fixture was not retained'
FAKE_INDETERMINATE=1
export FAKE_INDETERMINATE
if output=$(run_cli --rebuild tun tunnel-host 18443:443 2>&1); then fail 'tun --rebuild unexpectedly continued with an indeterminate managed session'; fi
assert_contains "$output" 'Cannot rebuild the VPN image while managed sessions are live or indeterminate.'
assert_eq "$(grep -c '^build$' "$ENGINE_STATE/events" || true)" 0
assert_eq "$(grep -c '^tunnel-start$' "$ENGINE_STATE/events" || true)" 0
[ -d "$ENGINE_STATE/containers/sd-vpnc-$(id -u)" ] || fail 'indeterminate-session rebuild rejection removed the manager'
FAKE_INDETERMINATE=0
FAKE_KEEP_IDLE=0
export FAKE_INDETERMINATE FAKE_KEEP_IDLE
run_cli --rebuild tun tunnel-host 18443:443 > "$CASE_DIR/idle-tun.log" 2>&1 || fail 'tun --rebuild failed with an idle owned manager'
assert_eq "$(grep -c '^build$' "$ENGINE_STATE/events")" 1
assert_eq "$(grep -c '^tunnel-start$' "$ENGINE_STATE/events")" 1
[ ! -d "$ENGINE_STATE/containers/sd-vpnc-$(id -u)" ] || fail 'idle owned manager was not stopped before rebuilding'
idle_stop_line=$(grep -n '^watcher-stop$' "$ENGINE_STATE/events" | cut -d: -f1)
idle_build_line=$(grep -n '^build$' "$ENGINE_STATE/events" | cut -d: -f1)
[ "$idle_stop_line" -lt "$idle_build_line" ] || fail 'idle manager was not stopped before tun rebuild'
stop_tun_output=$(run_cli tun --stop 2>&1) || fail "could not clean up idle-manager tunnel: $stop_tun_output"

# No manager is also a safe --rebuild tun case.
setup_case tun-rebuild-no-manager
make_engine_path
run_cli --rebuild tun tunnel-host 18443:443 > "$CASE_DIR/tun.log" 2>&1 || fail 'tun --rebuild failed when no managed manager existed'
assert_eq "$(grep -c '^build$' "$ENGINE_STATE/events")" 1
assert_eq "$(grep -c '^tunnel-start$' "$ENGINE_STATE/events")" 1
assert_eq "$(grep -c '^manager-start$' "$ENGINE_STATE/events" || true)" 0
[ ! -d "$ENGINE_STATE/containers/sd-vpnc-$(id -u)" ] || fail 'tun rebuild unexpectedly created a regular manager'
stop_tun_output=$(run_cli tun --stop 2>&1) || fail "could not clean up tunnel without manager: $stop_tun_output"

# The tun path holds the same lifecycle lock through the build against a concurrent managed start.
setup_case tun-rebuild-start-lock
make_engine_path
LOCK_BIN=$CASE_DIR/flock-bin
mkdir -p "$LOCK_BIN"
REAL_FLOCK=$(command -v flock)
export REAL_FLOCK
cat > "$LOCK_BIN/flock" <<'FLOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$ENGINE_STATE/flock-args"
exec "$REAL_FLOCK" "$@"
FLOCK
chmod +x "$LOCK_BIN/flock"
RUN_PATH=$ENGINE_BIN:$LOCK_BIN:$ORIGINAL_PATH
export RUN_PATH
FAKE_BLOCK_BUILD=1
export FAKE_BLOCK_BUILD
run_cli --rebuild tun tunnel-host 18443:443 > "$CASE_DIR/tun-rebuild.log" 2>&1 &
tun_build_pid=$!
wait_for_file "$ENGINE_STATE/build-started"
FAKE_BLOCK_BUILD=0
export FAKE_BLOCK_BUILD
run_cli ssh waits-for-tun-build > "$CASE_DIR/start.log" 2>&1 &
start_after_tun_build_pid=$!
attempt=0
while [ "$(grep -c '^-x 9$' "$ENGINE_STATE/flock-args" 2>/dev/null || true)" -lt 2 ] && [ "$attempt" -lt 100 ]; do
	sleep 0.05
	attempt=$((attempt + 1))
done
[ "$(grep -c '^-x 9$' "$ENGINE_STATE/flock-args")" -ge 2 ] || fail 'concurrent managed start did not reach the lock during tun rebuild'
assert_eq "$(grep -c '^manager-start$' "$ENGINE_STATE/events" || true)" 0
assert_eq "$(grep -c '^tunnel-start$' "$ENGINE_STATE/events" || true)" 0
touch "$ENGINE_STATE/build-release"
wait "$tun_build_pid" || fail 'locked tun rebuild failed'
wait_for_lease_count 1
tun_lock_id=$(lease_id_at 0)
wait_for_host_ack "$tun_lock_id"
build_complete_line=$(grep -n '^build-complete$' "$ENGINE_STATE/events" | cut -d: -f1)
manager_started_line=$(grep -n '^manager-start$' "$ENGINE_STATE/events" | cut -d: -f1)
tunnel_started_line=$(grep -n '^tunnel-start$' "$ENGINE_STATE/events" | cut -d: -f1)
[ "$build_complete_line" -lt "$manager_started_line" ] || fail 'manager started before tun rebuild completed'
[ "$build_complete_line" -lt "$tunnel_started_line" ] || fail 'tunnel started before its rebuild completed'
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$tun_lock_id"
wait "$start_after_tun_build_pid" || fail 'managed start did not proceed after tun rebuild'
run_cli tun --stop >/dev/null 2>&1 || fail 'could not clean up rebuilt tunnel'

# image --rebuild holds the lifecycle lock until build completion; a concurrent
# start reaches the lock but cannot start a manager until the build is released.
setup_case image-rebuild-start-lock
make_engine_path
LOCK_BIN=$CASE_DIR/flock-bin
mkdir -p "$LOCK_BIN"
REAL_FLOCK=$(command -v flock)
export REAL_FLOCK
cat > "$LOCK_BIN/flock" <<'FLOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$ENGINE_STATE/flock-args"
exec "$REAL_FLOCK" "$@"
FLOCK
chmod +x "$LOCK_BIN/flock"
RUN_PATH=$ENGINE_BIN:$LOCK_BIN:$ORIGINAL_PATH
export RUN_PATH
FAKE_BLOCK_BUILD=1
export FAKE_BLOCK_BUILD
run_cli image --rebuild > "$CASE_DIR/image-rebuild.log" 2>&1 &
build_pid=$!
wait_for_file "$ENGINE_STATE/build-started"
FAKE_BLOCK_BUILD=0
export FAKE_BLOCK_BUILD
run_cli ssh waits-for-build > "$CASE_DIR/start.log" 2>&1 &
start_pid=$!
attempt=0
while [ "$(grep -c '^-x 9$' "$ENGINE_STATE/flock-args" 2>/dev/null || true)" -lt 2 ] && [ "$attempt" -lt 100 ]; do
	sleep 0.05
	attempt=$((attempt + 1))
done
[ "$(grep -c '^-x 9$' "$ENGINE_STATE/flock-args")" -ge 2 ] || fail 'concurrent start did not reach the lifecycle lock'
assert_eq "$(grep -c '^manager-start$' "$ENGINE_STATE/events" || true)" 0
touch "$ENGINE_STATE/build-release"
wait "$build_pid" || fail 'locked image rebuild failed'
wait_for_lease_count 1
locked_build_id=$(lease_id_at 0)
wait_for_host_ack "$locked_build_id"
build_complete_line=$(grep -n '^build-complete$' "$ENGINE_STATE/events" | cut -d: -f1)
manager_started_line=$(grep -n '^manager-start$' "$ENGINE_STATE/events" | cut -d: -f1)
[ "$build_complete_line" -lt "$manager_started_line" ] || fail 'manager started before image rebuild completed'
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$locked_build_id"
wait "$start_pid" || fail 'start serialized behind image rebuild failed'

# A failed build also releases the lifecycle lock when its owning process exits.
setup_case image-rebuild-failure-unlock
make_engine_path
LOCK_BIN=$CASE_DIR/flock-bin
mkdir -p "$LOCK_BIN"
REAL_FLOCK=$(command -v flock)
export REAL_FLOCK
cat > "$LOCK_BIN/flock" <<'FLOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$ENGINE_STATE/flock-args"
exec "$REAL_FLOCK" "$@"
FLOCK
chmod +x "$LOCK_BIN/flock"
RUN_PATH=$ENGINE_BIN:$LOCK_BIN:$ORIGINAL_PATH
export RUN_PATH
FAKE_BLOCK_BUILD=1
FAKE_FAIL_BUILD=1
export FAKE_BLOCK_BUILD FAKE_FAIL_BUILD
run_cli image --rebuild > "$CASE_DIR/image-rebuild.log" 2>&1 &
failed_build_pid=$!
wait_for_file "$ENGINE_STATE/build-started"
FAKE_BLOCK_BUILD=0
export FAKE_BLOCK_BUILD
run_cli ssh after-build-failure > "$CASE_DIR/start.log" 2>&1 &
start_after_failure_pid=$!
attempt=0
while [ "$(grep -c '^-x 9$' "$ENGINE_STATE/flock-args" 2>/dev/null || true)" -lt 2 ] && [ "$attempt" -lt 100 ]; do
	sleep 0.05
	attempt=$((attempt + 1))
done
[ "$(grep -c '^-x 9$' "$ENGINE_STATE/flock-args")" -ge 2 ] || fail 'concurrent start did not reach the lifecycle lock during failed build'
assert_eq "$(grep -c '^manager-start$' "$ENGINE_STATE/events" || true)" 0
touch "$ENGINE_STATE/build-release"
if wait "$failed_build_pid"; then fail 'fake image build failure unexpectedly succeeded'; fi
wait_for_lease_count 1
failure_unlock_id=$(lease_id_at 0)
wait_for_host_ack "$failure_unlock_id"
assert_contains "$(cat "$ENGINE_STATE/events")" 'build-failed'
touch "$ENGINE_STATE/containers/sd-vpnc-$(id -u)/finish.$failure_unlock_id"
wait "$start_after_failure_pid" || fail 'start did not proceed after failed build released the lock'

# Engine name collisions are never removed or attached unless ownership is verified.
setup_case legacy-container
make_engine_path
legacy_dir=$ENGINE_STATE/containers/sd-vpnc-$(id -u)
mkdir -p "$legacy_dir"
printf 'legacy|0\n' > "$legacy_dir/labels"
if output=$(run_cli ssh ignored 2>&1); then fail 'legacy container was accepted'; fi
assert_contains "$output" 'not a verified sd-vpnc manager'
[ -d "$legacy_dir" ] || fail 'legacy container was removed'
assert_eq "$(grep -c '^manager-start$' "$ENGINE_STATE/events" || true)" 0

# Missing host flock fails before the engine is invoked or any runtime state is created.
setup_case no-host-flock
make_engine_path
NO_FLOCK_BIN=$CASE_DIR/no-flock-bin
mkdir -p "$NO_FLOCK_BIN"
cp "$ENGINE_BIN/podman" "$NO_FLOCK_BIN/podman"
ln -s "$(command -v id)" "$NO_FLOCK_BIN/id"
if output=$(PATH=$NO_FLOCK_BIN HOME=$CASE_HOME XDG_CONFIG_HOME=$CASE_HOME/.config \
	XDG_DATA_HOME=$CASE_HOME/.local/share XDG_STATE_HOME=$CASE_STATE \
	SD_VPNC_COLOR=never "$REPO_ROOT/sd-vpnc" ssh 2>&1); then fail 'managed request worked without flock'; fi
assert_contains "$output" "host 'flock' utility is required"
[ ! -s "$RUNTIME_LOG" ] || fail 'engine was invoked before checking for flock'
[ ! -e "$CASE_STATE/sd-vpnc" ] || fail 'lifecycle state was created without flock'

# A failed registration cleans up an empty new manager.
setup_case failed-registration
make_engine_path
FAKE_FAIL_REGISTER=1
export FAKE_FAIL_REGISTER
if output=$(run_cli ssh fail 2>&1); then fail 'failed session registration unexpectedly succeeded'; fi
assert_contains "$output" 'did not register before startup grace expired'
[ ! -d "$ENGINE_STATE/containers/sd-vpnc-$(id -u)" ] || fail 'failed registration left an empty manager running'

# Generate the in-container registry helper through the production image build path.
setup_case registry-helper
make_engine_path
run_cli image --rebuild > "$CASE_DIR/image.log" 2>&1 || fail 'could not build/capture the generated registry helper'
[ -f "$TEST_REGISTRY" ] || fail 'generated session registry was not captured'
chmod +x "$TEST_REGISTRY" "$TEST_ENTRYPOINT"
/bin/bash -n "$TEST_REGISTRY" || fail 'generated registry has invalid Bash syntax'
/bin/bash -n "$TEST_ENTRYPOINT" || fail 'generated entrypoint has invalid Bash syntax'

# Run the generated manager entrypoint with isolated helper paths and stubs for
# OpenVPN/tun readiness. A real generated registry watcher must stop PID 1 and
# the entrypoint's EXIT trap must terminate the observable OpenVPN daemon.
FUNCTIONAL_DIR=$CASE_DIR/generated-entrypoint-functional
mkdir -p "$FUNCTIONAL_DIR/tmp" "$FUNCTIONAL_DIR/config" "$FUNCTIONAL_DIR/work" \
	"$FUNCTIONAL_DIR/home/.ssh" "$FUNCTIONAL_DIR/template/.local/share" "$FUNCTIONAL_DIR/bin"
: > "$FUNCTIONAL_DIR/config/client.ovpn"
FUNCTIONAL_REGISTRY=$FUNCTIONAL_DIR/session-registry
sed "s|/tmp/sd-vpnc-manager-ready|$FUNCTIONAL_DIR/tmp/sd-vpnc-manager-ready|g" \
	"$TEST_REGISTRY" > "$FUNCTIONAL_REGISTRY"
chmod +x "$FUNCTIONAL_REGISTRY"
FUNCTIONAL_ENTRYPOINT=$FUNCTIONAL_DIR/entrypoint.sh
sed \
	-e "s|/tmp|$FUNCTIONAL_DIR/tmp|g" \
	-e "s|/usr/local/lib/sd-vpnc-home-init.sh|$FUNCTIONAL_DIR/home-init.sh|g" \
	-e "s|/usr/local/bin/sd-vpnc-session-registry|$FUNCTIONAL_REGISTRY|g" \
	-e "s|/usr/local/bin/sd-vpnc-shell|$FUNCTIONAL_DIR/sd-vpnc-shell|g" \
	-e "s|/usr/share/sd-vpnc/home-template|$FUNCTIONAL_DIR/template|g" \
	-e "s|/config|$FUNCTIONAL_DIR/config|g" \
	-e "s|cd /work|cd \"$FUNCTIONAL_DIR/work\"|g" \
	"$TEST_ENTRYPOINT" > "$FUNCTIONAL_ENTRYPOINT"
chmod +x "$FUNCTIONAL_ENTRYPOINT"
cat > "$FUNCTIONAL_DIR/home-init.sh" <<'HOME_INIT'
sd_vpnc_copy_entry() { :; }
sd_vpnc_copy_contents() { :; }
sd_vpnc_seed_home() {
	mkdir -p "$HOME/.cache" "$HOME/.local/state" "$HOME/.local/share" "$HOME/.atuin/data"
}
HOME_INIT
cat > "$FUNCTIONAL_DIR/bin/openvpn" <<'OPENVPN'
#!/bin/sh
set -eu
pidfile=
while [ "$#" -gt 0 ]; do
	case $1 in
		--writepid) pidfile=$2; shift 2 ;;
		*) shift ;;
	esac
done
printf 'openvpn-started cwd=%s\n' "$PWD" >> "$OPENVPN_START_LOG"
"$FAKE_OPENVPN_DAEMON" &
printf '%s\n' "$!" > "$pidfile"
OPENVPN
cat > "$FUNCTIONAL_DIR/bin/openvpn-daemon" <<'DAEMON'
#!/bin/sh
trap 'printf "%s\\n" cleanup >> "$OPENVPN_CLEANUP_LOG"; exit 0' TERM INT
while :; do /bin/sleep 0.05; done
DAEMON
cat > "$FUNCTIONAL_DIR/bin/ssh" <<'SSH'
#!/bin/sh
printf '%s\\n' "$*" >> "$FUNCTIONAL_SSH_LOG"
SSH
chmod +x "$FUNCTIONAL_DIR/bin/openvpn" "$FUNCTIONAL_DIR/bin/openvpn-daemon" "$FUNCTIONAL_DIR/bin/ssh"
cat > "$FUNCTIONAL_DIR/bash-env" <<'BASH_ENV'
compgen() {
	if [ "${1:-}" = -G ] && [ "${2:-}" = '/sys/class/net/tun*' ]; then return 0; fi
	builtin compgen "$@"
}
BASH_ENV
FUNCTIONAL_RUNTIME=$FUNCTIONAL_DIR/runtime
FUNCTIONAL_OPENVPN_LOG=$FUNCTIONAL_DIR/openvpn-start.log
FUNCTIONAL_CLEANUP_LOG=$FUNCTIONAL_DIR/openvpn-cleanup.log
FUNCTIONAL_SSH_LOG=$FUNCTIONAL_DIR/ssh.log
PATH=$FUNCTIONAL_DIR/bin:$ORIGINAL_PATH
REGISTRY_PATH=$FUNCTIONAL_DIR/bin:$ORIGINAL_PATH
BASH_ENV=$FUNCTIONAL_DIR/bash-env
FAKE_OPENVPN_DAEMON=$FUNCTIONAL_DIR/bin/openvpn-daemon
OPENVPN_START_LOG=$FUNCTIONAL_OPENVPN_LOG
OPENVPN_CLEANUP_LOG=$FUNCTIONAL_CLEANUP_LOG
export PATH REGISTRY_PATH BASH_ENV FAKE_OPENVPN_DAEMON OPENVPN_START_LOG OPENVPN_CLEANUP_LOG FUNCTIONAL_SSH_LOG
SD_VPNC_SESSION_RUNTIME=$FUNCTIONAL_RUNTIME HOME=$FUNCTIONAL_DIR/home \
	"$FUNCTIONAL_ENTRYPOINT" manager > "$FUNCTIONAL_DIR/entrypoint.log" 2>&1 &
FUNCTIONAL_MANAGER_PID=$!
wait_for_file "$FUNCTIONAL_DIR/tmp/sd-vpnc-manager-ready"
[ -f "$FUNCTIONAL_DIR/tmp/sd-vpnc-vpn-ready" ] || fail 'generated manager entrypoint did not report VPN readiness'
assert_eq "$(grep -c '^openvpn-started ' "$FUNCTIONAL_OPENVPN_LOG")" 1
assert_contains "$(cat "$FUNCTIONAL_OPENVPN_LOG")" "cwd=$FUNCTIONAL_DIR/work"
REGISTRY_RUNTIME=$FUNCTIONAL_RUNTIME
REGISTRY_HOME=$FUNCTIONAL_DIR/home
registry_cmd() {
	SD_VPNC_SESSION_RUNTIME=$REGISTRY_RUNTIME HOME=$REGISTRY_HOME PATH=$REGISTRY_PATH \
		"$TEST_REGISTRY" "$@"
}
attempt=0
registry_cmd launch functional-entrypoint-session ssh remote-from-entrypoint > "$FUNCTIONAL_DIR/session.log" 2>&1 &
functional_session_pid=$!
while [ ! -f "$FUNCTIONAL_RUNTIME/registered/functional-entrypoint-session" ] && [ "$attempt" -lt 100 ]; do
	sleep 0.05
	attempt=$((attempt + 1))
done
if [ ! -f "$FUNCTIONAL_RUNTIME/registered/functional-entrypoint-session" ]; then
	cat "$FUNCTIONAL_DIR/entrypoint.log" "$FUNCTIONAL_DIR/session.log" >&2
	fail 'generated entrypoint manager did not accept a session'
fi
registry_cmd acknowledge functional-entrypoint-session || fail 'generated entrypoint session acknowledgement failed'
wait "$functional_session_pid" || fail 'generated entrypoint session did not complete'
wait "$FUNCTIONAL_MANAGER_PID" || fail 'generated entrypoint manager did not exit after watcher shutdown'
FUNCTIONAL_MANAGER_PID=
assert_eq "$(sed -n '1p' "$FUNCTIONAL_RUNTIME/state")" STOPPING
wait_for_file "$FUNCTIONAL_CLEANUP_LOG"
assert_eq "$(cat "$FUNCTIONAL_CLEANUP_LOG")" cleanup

REGISTRY_RUNTIME=$CASE_DIR/registry-runtime
REGISTRY_HOME=$CASE_DIR/registry-home
mkdir -p "$REGISTRY_HOME/.ssh"
FAKE_SSH_BIN=$CASE_DIR/fake-ssh-bin
mkdir -p "$FAKE_SSH_BIN"
cat > "$FAKE_SSH_BIN/ssh" <<'SSH'
#!/bin/sh
printf '%s\n' "$*" >> "$SSH_LOG"
case $* in *hold*) exec sleep 300 ;; esac
SSH
chmod +x "$FAKE_SSH_BIN/ssh"
SSH_LOG=$CASE_DIR/ssh-args.log
export SSH_LOG
REGISTRY_PATH=$FAKE_SSH_BIN:$ORIGINAL_PATH

registry_initialize() {
	registry_cmd initialize
	registry_cmd start-grace
}

launch_registry_session() {
	session_id=$1
	session_log=$2
	shift 2
	registry_cmd launch "$session_id" "$@" > "$session_log" 2>&1 &
	launcher_pid=$!
	attempt=0
	while [ ! -f "$REGISTRY_RUNTIME/registered/$session_id" ] && [ "$attempt" -lt 100 ]; do
		sleep 0.05
		attempt=$((attempt + 1))
	done
	[ -f "$REGISTRY_RUNTIME/registered/$session_id" ] || fail "session $session_id did not register"
	registry_cmd acknowledge "$session_id" || fail "session $session_id registration acknowledgement failed"
	wait "$launcher_pid" || fail "session $session_id did not complete"
}

# Registration is disabled before VPN readiness; the 30-second grace begins only after readiness.
REGISTRY_RUNTIME=$CASE_DIR/grace-runtime
registry_cmd initialize || fail 'registry initialization failed'
grace_status=$(registry_cmd status) || fail 'initializing manager status failed'
assert_contains "$grace_status" 'state=STARTING'
if registry_cmd launch too-early ssh must-not-run > "$CASE_DIR/too-early.log" 2>&1; then fail 'session registered before manager readiness'; fi
registry_cmd start-grace || fail 'could not begin first-registration grace'
grace_status=$(registry_cmd status) || fail 'waiting manager status failed'
assert_contains "$grace_status" 'state=WAITING_FIRST_SESSION'
assert_contains "$grace_status" 'live=0'
printf 'WAITING_FIRST_SESSION\n0\n%s\n' "$(($(date +%s) - 31))" > "$REGISTRY_RUNTIME/state"
# A status reconciliation observes the expired grace and makes the same locked transition as the watcher.
registry_cmd status >/dev/null
assert_eq "$(sed -n '1p' "$REGISTRY_RUNTIME/state")" STOPPING

# Restore a fresh registry, register a stable launcher identity, and verify local shell/SSH dispatch.
REGISTRY_RUNTIME=$CASE_DIR/lease-runtime
registry_initialize
launch_registry_session ssh-one "$CASE_DIR/registry-ssh.log" ssh remote-one
assert_contains "$(cat "$SSH_LOG")" 'remote-one'
lease_status=$(registry_cmd status)
assert_contains "$lease_status" 'state=STOPPING'
assert_contains "$lease_status" 'stale=1'
REGISTRY_RUNTIME=$CASE_DIR/tmux-runtime
registry_initialize
launch_registry_session tmux-one "$CASE_DIR/registry-tmux.log" ssh-tmux tmux-host work-session
assert_contains "$(cat "$SSH_LOG")" "tmux-host -t tmux new -s 'work-session' || tmux attach -t 'work-session'"

# SIGKILL leaves a lease; process identity recovery reaps it, while malformed or uninspectable identity is preserved.
REGISTRY_RUNTIME=$CASE_DIR/kill-runtime
registry_initialize
registry_cmd launch killed-session ssh hold > "$CASE_DIR/registry-hold.log" 2>&1 &
registry_pid=$!
attempt=0
while [ ! -f "$REGISTRY_RUNTIME/sessions/killed-session" ] && [ "$attempt" -lt 100 ]; do sleep 0.05; attempt=$((attempt + 1)); done
[ -f "$REGISTRY_RUNTIME/sessions/killed-session" ] || fail 'held session did not register'
registry_cmd acknowledge killed-session || fail 'held session registration acknowledgement failed'
live_lease_status=$(registry_cmd status)
assert_contains "$live_lease_status" 'live=1'
assert_contains "$live_lease_status" 'indeterminate=0'
killed_pid=$(sed -n '1p' "$REGISTRY_RUNTIME/sessions/killed-session")
kill -KILL "$killed_pid" 2>/dev/null || true
wait "$registry_pid" 2>/dev/null || true
kill_status=$(registry_cmd status)
assert_contains "$kill_status" 'stale=1'
assert_contains "$kill_status" 'state=STOPPING'
REGISTRY_RUNTIME=$CASE_DIR/indeterminate-runtime
registry_initialize
printf 'ACTIVE\n1\n%s\n' "$(date +%s)" > "$REGISTRY_RUNTIME/state"
printf 'not-a-pid\ninvalid\nwrong\n' > "$REGISTRY_RUNTIME/sessions/uncertain"
uncertain_status=$(registry_cmd status)
assert_contains "$uncertain_status" 'state=ACTIVE'
assert_contains "$uncertain_status" 'indeterminate=1'
assert_contains "$uncertain_status" 'indeterminate_ids=uncertain'
[ -f "$REGISTRY_RUNTIME/sessions/uncertain" ] || fail 'indeterminate lease was removed'

# PID reuse and manager-generation changes are stale, not live; indeterminate records never stop a manager.
REGISTRY_RUNTIME=$CASE_DIR/reuse-runtime
registry_initialize
current_start=$(awk '{ print $20 }' "/proc/$$/stat")
generation=$(cat "$REGISTRY_RUNTIME/generation")
printf '%s\n%s\n%s\n' "$$" "$((current_start + 1))" "$generation" > "$REGISTRY_RUNTIME/sessions/reused-pid"
printf '%s\n%s\nold-generation\n' "$$" "$current_start" > "$REGISTRY_RUNTIME/sessions/old-generation"
reuse_status=$(registry_cmd status)
assert_contains "$reuse_status" 'stale=2'
assert_contains "$reuse_status" 'state=WAITING_FIRST_SESSION'
REGISTRY_RUNTIME=$CASE_DIR/restart-runtime
registry_initialize
old_generation=$(cat "$REGISTRY_RUNTIME/generation")
printf '424242\n100\n%s\n' "$old_generation" > "$REGISTRY_RUNTIME/sessions/old-manager"
registry_cmd initialize
new_generation=$(cat "$REGISTRY_RUNTIME/generation")
[ "$new_generation" != "$old_generation" ] || fail 'manager restart reused its generation'
[ ! -e "$REGISTRY_RUNTIME/sessions/old-manager" ] || fail 'manager restart retained an old-generation lease'

# Session registration racing the watcher is ordered by the same flock: no user command starts after STOPPING.
REGISTRY_RUNTIME=$CASE_DIR/race-runtime
: > "$SSH_LOG"
registry_cmd initialize
printf 'ACTIVE\n1\n%s\n' "$(date +%s)" > "$REGISTRY_RUNTIME/state"
registry_cmd launch race-session ssh hold > "$CASE_DIR/race-session.log" 2>&1 &
race_pid=$!
registry_cmd watch > "$CASE_DIR/race-watch.log" 2>&1 &
watch_pid=$!
attempt=0
race_state=
while [ "$attempt" -lt 100 ]; do
	race_state=$(sed -n '1p' "$REGISTRY_RUNTIME/state")
	if [ "$race_state" = STOPPING ] || [ -f "$REGISTRY_RUNTIME/registered/race-session" ]; then break; fi
	sleep 0.05
	attempt=$((attempt + 1))
done
if [ "$race_state" = ACTIVE ]; then
	registry_cmd acknowledge race-session || fail 'raced registration was not acknowledged while ACTIVE'
	[ -f "$REGISTRY_RUNTIME/sessions/race-session" ] || fail 'ACTIVE race result lost the live lease'
	kill -KILL "$(sed -n '1p' "$REGISTRY_RUNTIME/sessions/race-session")" 2>/dev/null || true
	wait "$race_pid" 2>/dev/null || true
	attempt=0
	while [ "$(sed -n '1p' "$REGISTRY_RUNTIME/state")" != STOPPING ] && [ "$attempt" -lt 40 ]; do sleep 0.1; attempt=$((attempt + 1)); done
	wait "$watch_pid" || fail 'watcher did not exit after the final raced lease became stale'
else
	assert_eq "$race_state" STOPPING
	wait "$race_pid" 2>/dev/null || true
	wait "$watch_pid" || true
	[ ! -s "$SSH_LOG" ] || fail 'session command ran after watcher STOPPING won the lock'
fi

# Conditional engine smoke uses only an already-local sd-vpnc image and disables pulls.
PATH=$ORIGINAL_PATH
export PATH
APP_VERSION=$(sed -n 's/^VERSION=//p' "$REPO_ROOT/sd-vpnc" | head -n 1)
APP_IMAGE="localhost/sd-vpnc:$APP_VERSION"
for engine in podman docker; do
	if command -v "$engine" >/dev/null 2>&1 && "$engine" info >/dev/null 2>&1 && \
		"$engine" image inspect "$APP_IMAGE" >/dev/null 2>&1; then
		"$engine" run --rm --pull=never --entrypoint /bin/bash "$APP_IMAGE" -c \
			'set -euo pipefail; command -v flock >/dev/null; test -x /usr/local/bin/sd-vpnc-session-registry; test -x /usr/local/bin/sd-vpnc-entrypoint; /usr/local/bin/sd-vpnc-session-registry initialize; /usr/local/bin/sd-vpnc-session-registry start-grace; /usr/local/bin/sd-vpnc-session-registry mark-ready; /usr/local/bin/sd-vpnc-session-registry ready; /usr/local/bin/sd-vpnc-session-registry status | grep -F "state=WAITING_FIRST_SESSION"' \
			|| fail "$engine local-image session lifecycle smoke failed"
		printf 'Passed %s local-image lifecycle prerequisites smoke (no pull).\n' "$engine"
	else
		printf 'Skipping %s lifecycle smoke: engine/daemon or local image %s unavailable (no pull attempted).\n' "$engine" "$APP_IMAGE"
	fi
done
printf 'All fake VPN manager lifecycle and registry tests passed.\n'
