#!/bin/sh

set -eu

REPO_ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
ORIGINAL_PATH=$PATH
ORIGINAL_GIT=$(command -v git || true)
PODMAN_SMOKE_NAMES=
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sd-vpnc-dotfiles.XXXXXX")
cleanup() {
	for container_name in $PODMAN_SMOKE_NAMES; do
		PATH="$ORIGINAL_PATH" podman rm --force "$container_name" >/dev/null 2>&1 || true
	done
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
	case $1 in
		*"$2"*) ;;
		*) fail "expected text to contain: $2" ;;
	esac
}

assert_not_contains() {
	case $1 in
		*"$2"*) fail "expected text not to contain: $2" ;;
		*) ;;
	esac
}

file_mode() {
	stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

assert_file_contains() {
	file=$1
	text=$2
	grep -F "$text" "$file" >/dev/null || fail "$file does not contain: $text"
}

assert_no_configured_contexts() {
	for context in "$CASE_CACHE"/sd-vpnc/build.*; do
		[ ! -e "$context" ] || fail "configured build context was not removed: $context"
	done
}

assert_logged_context_removed() {
	context=$(cat "$CONTAINER_LOG")
	[ ! -e "$context" ] || fail "configured build context was not removed: $context"
}

prepare_case() {
	case_name=$1
	CASE_DIR="$TMP_ROOT/$case_name"
	FAKE_BIN="$CASE_DIR/bin"
	CASE_CACHE="$CASE_DIR/cache"
	CASE_HOME="$CASE_DIR/home"
	CAPTURE_DIR="$CASE_DIR/captured"
	CONTAINERFILE_CAPTURE="$CASE_DIR/Containerfile"
	GIT_LOG="$CASE_DIR/git.log"
	CONTAINER_LOG="$CASE_DIR/container.log"
	ENGINE_LOG="$CASE_DIR/engine.log"
	mkdir -p "$FAKE_BIN" "$CASE_CACHE" "$CASE_HOME"
	GIT_MODE=success
	CONTAINER_MODE=success
	REPO_INSTALLER=yes
	DOTFILES_TEST_URL=
	SD_VPNC_DOTFILES=
	SD_VPNC_DOTFILES_REF=
	GIT_SSH_COMMAND=
	GIT_SSH=
	FAKE_CORE_SSH_COMMAND=
	FAKE_SYSTEM_SSH_COMMAND=
	FAKE_CALLER_SSH_COMMAND=
	EXPECT_DOTFILES=no
	EXPECT_SOURCE=
	SENTINEL=
	CONTAINER_DELAY=0
	export CASE_DIR FAKE_BIN CASE_CACHE CASE_HOME CAPTURE_DIR
	export CONTAINERFILE_CAPTURE GIT_LOG CONTAINER_LOG ENGINE_LOG GIT_MODE CONTAINER_MODE
	export REPO_INSTALLER DOTFILES_TEST_URL SD_VPNC_DOTFILES SD_VPNC_DOTFILES_REF
	export GIT_SSH_COMMAND GIT_SSH FAKE_CORE_SSH_COMMAND FAKE_SYSTEM_SSH_COMMAND FAKE_CALLER_SSH_COMMAND
	export EXPECT_DOTFILES EXPECT_SOURCE SENTINEL CONTAINER_DELAY
}

run_sd() {
	PATH="$RUN_PATH" \
	HOME="$CASE_HOME" \
	XDG_CACHE_HOME="$CASE_CACHE" \
	SD_VPNC_COLOR=never \
		"$REPO_ROOT/sd-vpnc" image --rebuild
}

cat >"$TMP_ROOT/podman" <<'PODMAN'
#!/bin/sh
set -eu
case ${1:-} in
	container) exit 1 ;;
	info) printf 'false\n'; exit 0 ;;
	build) shift ;;
	*) exit 90 ;;
esac
build_file=
while [ "$#" -gt 0 ]; do
	case $1 in
		-f) build_file=${2:-}; shift ;;
	esac
	build_context=$1
	shift
done
# Docker does not look for a Containerfile by default; both engines must be
# told explicitly which generated file to build.
[ "$build_file" = "$build_context/Containerfile" ] || exit 97
printf '%s %s\n' "${0##*/}" "$build_context" >> "$ENGINE_LOG"
printf '%s\n' "$build_context" >> "$CONTAINER_LOG"
if [ "${CONTAINER_DELAY:-0}" -gt 0 ]; then
	sleep "$CONTAINER_DELAY"
fi
if [ -n "${SENTINEL:-}" ] && grep -rqF -- "$SENTINEL" "$build_context/dotfiles-git" "$build_context/Containerfile"; then
	exit 98
fi
cp "$build_context/Containerfile" "$CONTAINERFILE_CAPTURE"
mkdir -p "$CAPTURE_DIR"
cp "$build_context/home-init.sh" "$CAPTURE_DIR/home-init.sh"
cp "$build_context/sd-vpnc-shell" "$CAPTURE_DIR/sd-vpnc-shell"
cp "$build_context/sd-vpnc-session-registry" "$CAPTURE_DIR/sd-vpnc-session-registry"
cp "$build_context/entrypoint.sh" "$CAPTURE_DIR/entrypoint.sh"
for generated_script in home-init.sh sd-vpnc-shell sd-vpnc-session-registry entrypoint.sh; do
	/bin/bash -n "$CAPTURE_DIR/$generated_script" || exit 99
done
if [ "${EXPECT_DOTFILES:-no}" = yes ]; then
	[ -d "$build_context/dotfiles" ] || exit 91
	[ ! -e "$build_context/dotfiles/.git" ] || exit 92
	[ -d "$build_context/dotfiles-git" ] || exit 96
	if [ -n "${EXPECT_SOURCE:-}" ]; then
		[ "$(cat "$build_context/dotfiles/.source")" = "$EXPECT_SOURCE" ] || exit 95
	fi
	mkdir -p "$CAPTURE_DIR"
	cp -R "$build_context/dotfiles" "$CAPTURE_DIR/dotfiles"
	cp -R "$build_context/dotfiles-git" "$CAPTURE_DIR/dotfiles-git"
else
	[ ! -e "$build_context/dotfiles" ] || exit 93
fi
[ "${CONTAINER_MODE:-success}" = success ] || exit 94
PODMAN
chmod +x "$TMP_ROOT/podman"

cat >"$TMP_ROOT/git" <<'GIT'
#!/bin/sh
set -eu
if [ "${1:-}" = config ]; then
	case ${2:-} in
		--global)
			printf 'config-scope=global\n' >> "$GIT_LOG"
			if [ -n "${FAKE_CORE_SSH_COMMAND:-}" ]; then
				printf '%s\n' "$FAKE_CORE_SSH_COMMAND"
				exit 0
			fi
			exit 1
			;;
		--system)
			printf 'config-scope=system\n' >> "$GIT_LOG"
			if [ -n "${FAKE_SYSTEM_SSH_COMMAND:-}" ]; then
				printf '%s\n' "$FAKE_SYSTEM_SSH_COMMAND"
				exit 0
			fi
			exit 1
			;;
		--get)
			printf 'config-scope=local\n' >> "$GIT_LOG"
			if [ -n "${FAKE_CALLER_SSH_COMMAND:-}" ]; then
				printf '%s\n' "$FAKE_CALLER_SSH_COMMAND"
				exit 0
			fi
			exit 1
			;;
		*) exit 87 ;;
	esac
fi
if read -r prompt_line; then
	stdin_state=open
else
	stdin_state=closed
fi
printf 'GIT_TERMINAL_PROMPT=%s GCM_INTERACTIVE=%s GIT_SSH_COMMAND=%s GIT_ASKPASS=%s SSH_ASKPASS=%s SSH_ASKPASS_REQUIRE=%s stdin=%s cwd=%s argv=' \
	"${GIT_TERMINAL_PROMPT:-}" "${GCM_INTERACTIVE:-}" "${GIT_SSH_COMMAND:-}" "${GIT_ASKPASS:-}" "${SSH_ASKPASS:-}" "${SSH_ASKPASS_REQUIRE:-}" "$stdin_state" "$PWD" >> "$GIT_LOG"
for argument do
	printf '[%s]' "$argument" >> "$GIT_LOG"
done
printf '\n' >> "$GIT_LOG"
if [ "${1:-}" = -c ]; then
	[ "${2:-}" = submodule.recurse=false ] || exit 80
	shift 2
fi
case ${1:-} in
	clone)
		shift
		[ "${1:-}" = -- ] || exit 81
		shift
		repository=${1:-}
		checkout=${2:-}
		[ -n "$repository" ] && [ -n "$checkout" ] || exit 82
		mkdir -p "$checkout/.git"
		printf '[remote "origin"]\n\turl = %s\n' "$repository" > "$checkout/.git/config"
		mkdir -p "$checkout/.git/logs"
		printf 'clone: from %s\n' "$repository" > "$checkout/.git/logs/HEAD"
		printf '%s\n' "$repository" > "$checkout/.source"
		printf 'dotfiles source\n' > "$checkout/.bashrc"
		printf 'restrictive mode test\n' > "$checkout/.private-settings"
		chmod 600 "$checkout/.private-settings"
		if [ "${REPO_INSTALLER:-yes}" = yes ]; then
			printf '#!/bin/sh\nexit 0\n' > "$checkout/install.sh"
			chmod 700 "$checkout/install.sh"
		fi
		if [ "${GIT_MODE:-success}" = clone-fail ]; then
			printf 'simulated remote error for %s\n' "$repository" >&2
			exit 83
		fi
		;;
	-C)
		checkout=${2:-}
		operation=${3:-}
		case $operation in
			rev-parse)
				if [ "${GIT_MODE:-success}" = ref-fail ]; then
					printf 'simulated ref error for %s\n' "${DOTFILES_TEST_URL:-source}" >&2
					exit 85
				fi
				printf 'fake-selected-commit\n'
				;;
			remote)
				if [ "${4:-}" = remove ]; then
					printf '[core]\n\tbare = false\n' > "$checkout/.git/config"
				else
					printf 'origin\n'
				fi
				;;
			checkout)
				ref=${5:-}
				printf 'checked-out-ref=%s\n' "$ref" >> "$GIT_LOG"
				printf 'selected ref: %s\n' "$ref" > "$checkout/selected-ref"
				;;
			*) exit 84 ;;
		esac
		;;
	*) exit 86 ;;
esac
GIT
chmod +x "$TMP_ROOT/git"

make_fake_path() {
	PATH="$FAKE_BIN:$TMP_ROOT:$ORIGINAL_PATH"
	RUN_PATH=$PATH
	export RUN_PATH
}

make_path_without_git() {
	RESTRICTED_BIN="$CASE_DIR/no-git-bin"
	mkdir -p "$RESTRICTED_BIN"
	for utility in cat chmod cp flock id mkdir mktemp rm stat; do
		utility_path=$(command -v "$utility") || fail "missing utility: $utility"
		ln -s "$utility_path" "$RESTRICTED_BIN/$utility"
	done
	cp "$TMP_ROOT/podman" "$RESTRICTED_BIN/podman"
	chmod +x "$RESTRICTED_BIN/podman"
	[ ! -e "$RESTRICTED_BIN/git" ] || fail "restricted PATH unexpectedly contains git"
	RUN_PATH=$RESTRICTED_BIN
	export RUN_PATH
}

# An empty/unset configuration must build without Git being available and
# must not add dotfiles instructions to the existing Containerfile.
prepare_case no-config
make_path_without_git
EXPECT_DOTFILES=no
export EXPECT_DOTFILES
output=$(run_sd 2>&1) || fail "no-config image build failed: $output"
assert_not_contains "$(cat "$CONTAINERFILE_CAPTURE")" 'dotfiles'
[ ! -e "$GIT_LOG" ] || fail "no-config path invoked Git"

# The legacy fixed context is retained for unconfigured builds, but any stale
# checkout left by an interrupted earlier run is removed before the build.
prepare_case stale-no-config
mkdir -p "$CASE_CACHE/sd-vpnc/build/dotfiles/.git"
printf 'stale checkout\n' > "$CASE_CACHE/sd-vpnc/build/dotfiles/.source"
make_path_without_git
EXPECT_DOTFILES=no
export EXPECT_DOTFILES
output=$(run_sd 2>&1) || fail "no-config build with stale checkout failed: $output"
[ ! -e "$CASE_CACHE/sd-vpnc/build/dotfiles" ] || fail "no-config build retained stale dotfiles checkout"
[ -d "$CASE_CACHE/sd-vpnc/build" ] || fail "no-config build did not retain the legacy build context"

prepare_case empty-values
make_path_without_git
SD_VPNC_DOTFILES=
SD_VPNC_DOTFILES_REF=
EXPECT_DOTFILES=no
export SD_VPNC_DOTFILES SD_VPNC_DOTFILES_REF EXPECT_DOTFILES
output=$(run_sd 2>&1) || fail "empty-value image build failed: $output"
[ ! -e "$GIT_LOG" ] || fail "empty-value path invoked Git"

# A ref without a repository fails before Git is needed.
prepare_case ref-without-url
make_path_without_git
SD_VPNC_DOTFILES=
SD_VPNC_DOTFILES_REF=main
export SD_VPNC_DOTFILES SD_VPNC_DOTFILES_REF
if output=$(run_sd 2>&1); then
	fail "ref without repository unexpectedly succeeded"
fi
assert_contains "$output" 'SD_VPNC_DOTFILES_REF requires SD_VPNC_DOTFILES'
[ ! -e "$GIT_LOG" ] || fail "ref-without-url path invoked Git"

# Refs beginning with a dash are rejected before Git can parse them as options.
prepare_case leading-dash-ref
make_path_without_git
SD_VPNC_DOTFILES=https://token@example.invalid/dotfiles.git
SD_VPNC_DOTFILES_REF=--help
export SD_VPNC_DOTFILES SD_VPNC_DOTFILES_REF
if output=$(run_sd 2>&1); then
	fail "leading-dash ref unexpectedly succeeded"
fi
assert_contains "$output" "SD_VPNC_DOTFILES_REF must not start with '-'."
assert_not_contains "$output" "$SD_VPNC_DOTFILES"
[ ! -e "$GIT_LOG" ] || fail "leading-dash ref was passed to Git"

# The host Git receives the URL/ref noninteractively, and the engine sees a
# checkout without .git plus its Git metadata staged separately for a temporary
# build-time mount. The checkout is removed after the build completes.
prepare_case configured
make_fake_path
SENTINEL=sentinel-secret-token
SD_VPNC_DOTFILES=https://$SENTINEL@example.invalid/dotfiles.git
SD_VPNC_DOTFILES_REF=release-tag
DOTFILES_TEST_URL=$SD_VPNC_DOTFILES
EXPECT_DOTFILES=yes
export SD_VPNC_DOTFILES SD_VPNC_DOTFILES_REF DOTFILES_TEST_URL EXPECT_DOTFILES SENTINEL
output=$(run_sd 2>&1) || fail "configured image build failed: $output"
assert_contains "$(cat "$GIT_LOG")" "[https://sentinel-secret-token@example.invalid/dotfiles.git]"
assert_contains "$(cat "$GIT_LOG")" '[remote][remove][origin]'
assert_contains "$(cat "$ENGINE_LOG")" 'podman '
# Host clone credentials must not reach the builder: the sentinel token is absent
# from the staged Git metadata and the generated Containerfile (the fake engine
# also checks the live build context). The fake clone writes its URL to a plain
# worktree file, so only the Git metadata is scanned.
if grep -rF -- "$SENTINEL" "$CAPTURE_DIR/dotfiles-git" "$CONTAINERFILE_CAPTURE" >/dev/null 2>&1; then
	fail "host clone credentials reached the builder context"
fi
[ ! -e "$CAPTURE_DIR/dotfiles-git/logs" ] || fail "clone reflog reached the builder context"
assert_contains "$(cat "$GIT_LOG")" 'release-tag'
assert_contains "$(cat "$GIT_LOG")" 'GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never GIT_SSH_COMMAND=ssh -o BatchMode=yes GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false SSH_ASKPASS_REQUIRE=never stdin=closed'
assert_not_contains "$(cat "$GIT_LOG")" '--recurse-submodules'
[ -f "$CAPTURE_DIR/dotfiles/.bashrc" ] || fail "repository source was not available to the image build"
[ ! -e "$CAPTURE_DIR/dotfiles/.git" ] || fail ".git metadata reached the copied source tree"
[ -f "$CAPTURE_DIR/dotfiles-git/config" ] || fail "Git metadata was not staged for the installer mount"
[ -x "$CAPTURE_DIR/dotfiles/install.sh" ] || fail "installer file mode was not preserved"
[ "$(file_mode "$CAPTURE_DIR/dotfiles/.private-settings")" = 600 ] || fail "restrictive file mode was not preserved"
assert_file_contains "$CONTAINERFILE_CAPTURE" 'COPY dotfiles /home/dev/.dotfiles'
assert_file_contains "$CONTAINERFILE_CAPTURE" 'WORKDIR /home/dev/.dotfiles'
assert_file_contains "$CONTAINERFILE_CAPTURE" 'RUN --mount=type=bind,source=dotfiles-git,target=/home/dev/.dotfiles/.git,z if [ -f ./install.sh ]; then HOME=/home/dev bash ./install.sh </dev/null; fi'
assert_file_contains "$CONTAINERFILE_CAPTURE" 'RUN rm -rf /home/dev/.dotfiles/.git'
assert_file_contains "$CONTAINERFILE_CAPTURE" 'RUN mkdir -p /usr/share/sd-vpnc/home-template && cp -a /home/dev/. /usr/share/sd-vpnc/home-template/ && rm -rf /usr/share/sd-vpnc/home-template/.ssh'
cleanup_line=$(grep -nF 'RUN rm -rf /home/dev/.dotfiles/.git' "$CONTAINERFILE_CAPTURE" | cut -d: -f1)
template_line=$(grep -nF 'RUN mkdir -p /usr/share/sd-vpnc/home-template' "$CONTAINERFILE_CAPTURE" | cut -d: -f1)
[ "$template_line" -gt "$cleanup_line" ] || fail "runtime home template was copied before Git metadata cleanup"
assert_file_contains "$CONTAINERFILE_CAPTURE" 'COPY home-init.sh /usr/local/lib/sd-vpnc-home-init.sh'
assert_file_contains "$CONTAINERFILE_CAPTURE" 'COPY sd-vpnc-shell /usr/local/bin/sd-vpnc-shell'
assert_file_contains "$CONTAINERFILE_CAPTURE" 'COPY sd-vpnc-session-registry /usr/local/bin/sd-vpnc-session-registry'
assert_file_contains "$CONTAINERFILE_CAPTURE" 'util-linux'
assert_file_contains "$CAPTURE_DIR/entrypoint.sh" 'sd-vpnc-session-registry launch'
assert_file_contains "$CAPTURE_DIR/entrypoint.sh" 'sd-vpnc-session-registry watch'
BASE_PACKAGES=$(sed -n '/^RUN dnf -y install/,/dnf clean all/p' "$CONTAINERFILE_CAPTURE")
assert_not_contains "$BASE_PACKAGES" 'zsh'
assert_file_contains "$CONTAINERFILE_CAPTURE" 'XDG_STATE_HOME=/home/dev/.local/state'
assert_file_contains "$CONTAINERFILE_CAPTURE" 'ATUIN_HOME=/home/dev/.atuin'
assert_file_contains "$CONTAINERFILE_CAPTURE" 'WORKDIR /work'
assert_file_contains "$CAPTURE_DIR/entrypoint.sh" 'sd_vpnc_seed_home /usr/share/sd-vpnc/home-template'
assert_file_contains "$CAPTURE_DIR/entrypoint.sh" '/usr/local/bin/sd-vpnc-shell'
assert_file_contains "$CAPTURE_DIR/entrypoint.sh" "openvpn --config \"\$vpn_config\""
assert_file_contains "$CAPTURE_DIR/sd-vpnc-session-registry" 'proc_identity()'
assert_file_contains "$CAPTURE_DIR/sd-vpnc-session-registry" 'elapsed -ge 30'
assert_file_contains "$CAPTURE_DIR/sd-vpnc-session-registry" 'acknowledge)'
entry_session_line=$(grep -nF 'exec /usr/local/bin/sd-vpnc-session-registry launch' "$CAPTURE_DIR/entrypoint.sh" | cut -d: -f1)
entry_initialize_line=$(grep -nF '/usr/local/bin/sd-vpnc-session-registry initialize' "$CAPTURE_DIR/entrypoint.sh" | cut -d: -f1)
entry_openvpn_line=$(grep -nF 'openvpn --config' "$CAPTURE_DIR/entrypoint.sh" | cut -d: -f1)
entry_ready_line=$(grep -nF '/usr/local/bin/sd-vpnc-session-registry mark-ready' "$CAPTURE_DIR/entrypoint.sh" | cut -d: -f1)
[ "$entry_session_line" -lt "$entry_openvpn_line" ] || fail "engine exec session path appears after OpenVPN startup"
[ "$entry_initialize_line" -lt "$entry_openvpn_line" ] || fail "manager registry is not made fresh before VPN startup"
[ "$entry_openvpn_line" -lt "$entry_ready_line" ] || fail "manager readiness is reported before OpenVPN startup"
assert_file_contains "$CAPTURE_DIR/entrypoint.sh" "ssh \"\${ssh_args[@]}\" \"\$@\""
ssh_forward_line=$(grep -nF "ssh \"\${ssh_args[@]}\" \"\$@\"" "$CAPTURE_DIR/entrypoint.sh" | cut -d: -f1)
local_shell_line=$(grep -nF '/usr/local/bin/sd-vpnc-shell' "$CAPTURE_DIR/entrypoint.sh" | cut -d: -f1)
[ "$ssh_forward_line" -lt "$local_shell_line" ] || fail "remote SSH forwarding was replaced by the local shell selector"
# The metadata is only ever bind-mounted; no instruction may copy it into a layer.
assert_not_contains "$(grep -E '^(COPY|ADD) ' "$CONTAINERFILE_CAPTURE")" 'dotfiles-git'
assert_not_contains "$(grep -E '^(COPY|ADD) ' "$CONTAINERFILE_CAPTURE")" '.git'
[ "$(grep -c '^FROM ' "$CONTAINERFILE_CAPTURE")" -eq 1 ] || fail "dotfiles setup unexpectedly uses a disposable image stage"
DOTFILES_CONTAINERFILE=$(sed -n '/^COPY dotfiles /,$p' "$CONTAINERFILE_CAPTURE")
assert_not_contains "$DOTFILES_CONTAINERFILE" 'chmod'
assert_not_contains "$DOTFILES_CONTAINERFILE" 'chown'
INSTALLER_RUN_LINE=$(sed -n 's/^RUN //p' "$CONTAINERFILE_CAPTURE" | grep -F 'bash ./install.sh' | tail -n 1 | sed 's/^--mount=[^ ]* //')
[ -n "$INSTALLER_RUN_LINE" ] || fail "could not locate generated installer command"
INSTALLER_DIR="$CASE_DIR/installer-success"
INSTALLER_RESULT="$CASE_DIR/installer-result"
EXPECTED_CWD=$INSTALLER_DIR
export INSTALLER_DIR INSTALLER_RESULT EXPECTED_CWD INSTALLER_RUN_LINE
mkdir -p "$INSTALLER_DIR"
cat >"$INSTALLER_DIR/install.sh" <<'INSTALLER'
[ "$HOME" = /home/dev ] || exit 31
[ "$PWD" = "$EXPECTED_CWD" ] || exit 32
if read -r input; then exit 33; fi
printf 'installer ran noninteractively\n' > "$INSTALLER_RESULT"
INSTALLER
(cd "$INSTALLER_DIR" && sh -c "$INSTALLER_RUN_LINE") || fail "successful installer command failed"
[ -f "$INSTALLER_RESULT" ] || fail "installer did not receive expected HOME/cwd/closed stdin"
# Regression (#5): an installer that requires a Git checkout succeeds when the
# staged metadata is mounted at .git, as the generated RUN --mount does, and the
# mount point is gone afterward. Without the metadata the same installer fails.
INSTALLER_DIR="$CASE_DIR/installer-git-checkout"
INSTALLER_RESULT="$CASE_DIR/installer-git-result"
export INSTALLER_DIR INSTALLER_RESULT
mkdir -p "$INSTALLER_DIR"
cat >"$INSTALLER_DIR/install.sh" <<'INSTALLER'
[ -f .git/config ] || { echo "$PWD is not a git checkout of the dotfiles." >&2; exit 41; }
printf 'installer saw checkout\n' > "$INSTALLER_RESULT"
INSTALLER
if (cd "$INSTALLER_DIR" && sh -c "$INSTALLER_RUN_LINE") 2>/dev/null; then
	fail "git-checkout installer unexpectedly succeeded without Git metadata"
fi
cp -R "$CAPTURE_DIR/dotfiles-git" "$INSTALLER_DIR/.git"
(cd "$INSTALLER_DIR" && sh -c "$INSTALLER_RUN_LINE") || fail "git-checkout installer failed with Git metadata mounted"
[ -f "$INSTALLER_RESULT" ] || fail "git-checkout installer effects were not produced"
RM_LINE=$(sed -n 's/^RUN //p' "$CONTAINERFILE_CAPTURE" | grep -F 'rm -rf /home/dev/.dotfiles/.git')
[ -n "$RM_LINE" ] || fail "could not locate mount point removal command"
[ "$(printf '%s\n' "$RM_LINE" | wc -l)" -eq 1 ] || fail "unexpected mount point removal commands"
INSTALLER_DIR="$CASE_DIR/installer-missing"
export INSTALLER_DIR
mkdir -p "$INSTALLER_DIR"
(cd "$INSTALLER_DIR" && sh -c "$INSTALLER_RUN_LINE") || fail "missing installer was not skipped successfully"
[ ! -e "$INSTALLER_DIR/.bashrc" ] || fail "missing installer unexpectedly created an automatic link"
INSTALLER_DIR="$CASE_DIR/installer-failure"
export INSTALLER_DIR
mkdir -p "$INSTALLER_DIR"
printf 'exit 17\n' > "$INSTALLER_DIR/install.sh"
if (cd "$INSTALLER_DIR" && sh -c "$INSTALLER_RUN_LINE"); then
	fail "nonzero installer result was not propagated"
fi
build_context=$(cat "$CONTAINER_LOG")
case $build_context in
	"$CASE_CACHE"/sd-vpnc/build.*) ;;
	*) fail "configured build did not use a unique context beneath the cache root: $build_context" ;;
esac
assert_logged_context_removed
assert_no_configured_contexts

# Git's SSH command precedence is GIT_SSH_COMMAND, core.sshCommand, then GIT_SSH.
prepare_case ssh-command-precedence
make_fake_path
SD_VPNC_DOTFILES=ssh-precedence-repo
GIT_SSH_COMMAND='explicit ssh command'
FAKE_CORE_SSH_COMMAND='configured ssh command'
GIT_SSH='ignored ssh path'
EXPECT_DOTFILES=yes
export SD_VPNC_DOTFILES GIT_SSH_COMMAND FAKE_CORE_SSH_COMMAND GIT_SSH EXPECT_DOTFILES
output=$(run_sd 2>&1) || fail "GIT_SSH_COMMAND precedence build failed: $output"
assert_contains "$(cat "$GIT_LOG")" 'GIT_SSH_COMMAND=explicit ssh command -o BatchMode=yes'
assert_logged_context_removed

prepare_case core-ssh-command-precedence
make_fake_path
SD_VPNC_DOTFILES=core-ssh-precedence-repo
FAKE_CORE_SSH_COMMAND='configured ssh command'
FAKE_SYSTEM_SSH_COMMAND='lower-priority system ssh'
GIT_SSH="$CASE_DIR/ignored ssh path"
EXPECT_DOTFILES=yes
export SD_VPNC_DOTFILES GIT_SSH_COMMAND FAKE_CORE_SSH_COMMAND GIT_SSH EXPECT_DOTFILES
output=$(run_sd 2>&1) || fail "core.sshCommand precedence build failed: $output"
assert_contains "$(cat "$GIT_LOG")" 'GIT_SSH_COMMAND=configured ssh command -o BatchMode=yes'
assert_contains "$(cat "$GIT_LOG")" 'config-scope=global'
assert_not_contains "$(cat "$GIT_LOG")" 'config-scope=local'
assert_logged_context_removed

prepare_case system-ssh-command
make_fake_path
SD_VPNC_DOTFILES=system-ssh-repo
FAKE_SYSTEM_SSH_COMMAND='system ssh command'
GIT_SSH='ignored-ssh-path'
EXPECT_DOTFILES=yes
export SD_VPNC_DOTFILES FAKE_SYSTEM_SSH_COMMAND GIT_SSH EXPECT_DOTFILES
output=$(run_sd 2>&1) || fail "system core.sshCommand fallback build failed: $output"
assert_contains "$(cat "$GIT_LOG")" 'GIT_SSH_COMMAND=system ssh command -o BatchMode=yes'
assert_contains "$(cat "$GIT_LOG")" 'config-scope=system'
assert_logged_context_removed

# A caller project's local core.sshCommand must not override host global/system
# SSH config because lookup is performed from the isolated build context.
prepare_case caller-core-isolation
make_fake_path
CALLER_DIR="$CASE_DIR/caller-project"
mkdir -p "$CALLER_DIR"
if [ -n "$ORIGINAL_GIT" ]; then
	"$ORIGINAL_GIT" -C "$CALLER_DIR" init -q
	"$ORIGINAL_GIT" -C "$CALLER_DIR" config core.sshCommand 'real caller-local-ssh'
fi
SD_VPNC_DOTFILES=caller-core-isolation-repo
FAKE_CORE_SSH_COMMAND='global-system-ssh'
FAKE_CALLER_SSH_COMMAND='caller-project-ssh'
EXPECT_DOTFILES=yes
export SD_VPNC_DOTFILES FAKE_CORE_SSH_COMMAND FAKE_CALLER_SSH_COMMAND EXPECT_DOTFILES
output=$(cd "$CALLER_DIR" && run_sd 2>&1) || fail "caller core.sshCommand isolation build failed: $output"
assert_contains "$(cat "$GIT_LOG")" 'GIT_SSH_COMMAND=global-system-ssh -o BatchMode=yes'
assert_not_contains "$(cat "$GIT_LOG")" 'GIT_SSH_COMMAND=caller-project-ssh'
assert_contains "$(cat "$GIT_LOG")" 'config-scope=global'
assert_not_contains "$(cat "$GIT_LOG")" 'config-scope=local'
assert_logged_context_removed

# GIT_SSH is an executable path (not a command string); quote spaces before
# appending the OpenSSH BatchMode option and verify the resulting shell command.
prepare_case git-ssh-space-path
make_fake_path
GIT_SSH="$CASE_DIR/custom ssh"
SSH_ARGS_LOG="$CASE_DIR/ssh-args.log"
cat >"$GIT_SSH" <<'SSH'
#!/bin/sh
printf '%s\n' "$@" > "$SSH_ARGS_LOG"
SSH
chmod +x "$GIT_SSH"
SD_VPNC_DOTFILES=git-ssh-space-repo
EXPECT_DOTFILES=yes
export SD_VPNC_DOTFILES GIT_SSH_COMMAND FAKE_CORE_SSH_COMMAND GIT_SSH EXPECT_DOTFILES SSH_ARGS_LOG
output=$(run_sd 2>&1) || fail "GIT_SSH path with spaces build failed: $output"
ssh_command=$(sed -n 's/.*GIT_SSH_COMMAND=\(.*\) GIT_ASKPASS=.*/\1/p' "$GIT_LOG" | sed -n '1p')
assert_contains "$ssh_command" "'$(printf '%s' "$GIT_SSH" | sed "s/'/'\\\\''/g")' -o BatchMode=yes"
sh -c "$ssh_command \"\$@\"" git-host -p 22 example.invalid command
assert_file_contains "$SSH_ARGS_LOG" 'BatchMode=yes'
assert_file_contains "$SSH_ARGS_LOG" 'example.invalid'
assert_logged_context_removed

# Concurrent configured builds sharing one cache root must receive independent
# contexts and cannot replace each other's checkout.
prepare_case concurrent-builds
make_fake_path
(
	PATH="$RUN_PATH" HOME="$CASE_HOME" XDG_CACHE_HOME="$CASE_CACHE" SD_VPNC_COLOR=never \
	SD_VPNC_DOTFILES=concurrent-one SD_VPNC_DOTFILES_REF='' EXPECT_DOTFILES=yes EXPECT_SOURCE=concurrent-one \
	CAPTURE_DIR="$CASE_DIR/one-capture" CONTAINERFILE_CAPTURE="$CASE_DIR/one.Containerfile" \
	GIT_LOG="$CASE_DIR/one.git.log" CONTAINER_LOG="$CASE_DIR/one.container.log" CONTAINER_DELAY=1 \
		"$REPO_ROOT/sd-vpnc" image --rebuild
) >"$CASE_DIR/one.log" 2>&1 &
first_pid=$!
(
	PATH="$RUN_PATH" HOME="$CASE_HOME" XDG_CACHE_HOME="$CASE_CACHE" SD_VPNC_COLOR=never \
	SD_VPNC_DOTFILES=concurrent-two SD_VPNC_DOTFILES_REF='' EXPECT_DOTFILES=yes EXPECT_SOURCE=concurrent-two \
	CAPTURE_DIR="$CASE_DIR/two-capture" CONTAINERFILE_CAPTURE="$CASE_DIR/two.Containerfile" \
	GIT_LOG="$CASE_DIR/two.git.log" CONTAINER_LOG="$CASE_DIR/two.container.log" CONTAINER_DELAY=1 \
		"$REPO_ROOT/sd-vpnc" image --rebuild
) >"$CASE_DIR/two.log" 2>&1 &
second_pid=$!
if ! wait "$first_pid"; then
	cat "$CASE_DIR/one.log" >&2
	fail "first concurrent configured build failed"
fi
if ! wait "$second_pid"; then
	cat "$CASE_DIR/two.log" >&2
	fail "second concurrent configured build failed"
fi
[ "$(cat "$CASE_DIR/one-capture/dotfiles/.source")" = concurrent-one ] || fail "first configured build saw another checkout"
[ "$(cat "$CASE_DIR/two-capture/dotfiles/.source")" = concurrent-two ] || fail "second configured build saw another checkout"
first_context=$(cat "$CASE_DIR/one.container.log")
second_context=$(cat "$CASE_DIR/two.container.log")
[ "$first_context" != "$second_context" ] || fail "concurrent configured builds shared a context"
case $first_context in "$CASE_CACHE"/sd-vpnc/build.*) ;; *) fail "first context was outside cache root" ;; esac
case $second_context in "$CASE_CACHE"/sd-vpnc/build.*) ;; *) fail "second context was outside cache root" ;; esac
[ ! -e "$first_context" ] && [ ! -e "$second_context" ] || fail "concurrent build contexts were not cleaned"
assert_no_configured_contexts

# A local relative path is passed unchanged while Git runs from the caller cwd.
prepare_case relative-path
make_fake_path
CALLER_DIR="$CASE_DIR/caller"
mkdir -p "$CALLER_DIR"
SD_VPNC_DOTFILES=../local-dotfiles
SD_VPNC_DOTFILES_REF=
EXPECT_DOTFILES=yes
export SD_VPNC_DOTFILES SD_VPNC_DOTFILES_REF EXPECT_DOTFILES
output=$(cd "$CALLER_DIR" && run_sd 2>&1) || fail "relative-path build failed: $output"
assert_contains "$(cat "$GIT_LOG")" 'cwd='
assert_contains "$(cat "$GIT_LOG")" '[../local-dotfiles]'
assert_contains "$(cat "$GIT_LOG")" "cwd=$CALLER_DIR"
assert_logged_context_removed
assert_no_configured_contexts

# Host Git is required for a configured repository, but its absence is reported
# generically and no container build is attempted.
prepare_case git-unavailable
make_path_without_git
SD_VPNC_DOTFILES=https://token@example.invalid/private.git
export SD_VPNC_DOTFILES
if output=$(run_sd 2>&1); then
	fail "configured build without Git unexpectedly succeeded"
fi
assert_contains "$output" 'Git is required to clone the configured dotfiles repository.'
assert_not_contains "$output" "$SD_VPNC_DOTFILES"
assert_no_configured_contexts
[ ! -e "$CONTAINER_LOG" ] || fail "container build ran without host Git"

# Clone failure after creating a partial checkout is generic in output and is
# cleaned by the exit trap.
prepare_case clone-failure
make_fake_path
SD_VPNC_DOTFILES=https://token@example.invalid/failing.git
DOTFILES_TEST_URL=$SD_VPNC_DOTFILES
GIT_MODE=clone-fail
export SD_VPNC_DOTFILES DOTFILES_TEST_URL GIT_MODE
if output=$(run_sd 2>&1); then
	fail "clone failure unexpectedly succeeded"
fi
assert_contains "$output" 'Failed to clone the configured dotfiles repository.'
assert_not_contains "$output" "$SD_VPNC_DOTFILES"
assert_no_configured_contexts
[ ! -e "$CONTAINER_LOG" ] || fail "container build ran after clone failure"

# Ref-selection failure also cleans the checkout without exposing the URL.
prepare_case ref-failure
make_fake_path
SD_VPNC_DOTFILES=https://token@example.invalid/ref-failing.git
SD_VPNC_DOTFILES_REF=missing-ref
DOTFILES_TEST_URL=$SD_VPNC_DOTFILES
GIT_MODE=ref-fail
export SD_VPNC_DOTFILES SD_VPNC_DOTFILES_REF DOTFILES_TEST_URL GIT_MODE
if output=$(run_sd 2>&1); then
	fail "ref failure unexpectedly succeeded"
fi
assert_contains "$output" 'Failed to select the configured dotfiles ref.'
assert_not_contains "$output" "$SD_VPNC_DOTFILES"
assert_no_configured_contexts
[ ! -e "$CONTAINER_LOG" ] || fail "container build ran after ref failure"

# Container build errors (including installer errors reported by the engine)
# propagate, redact the source URL, and still clean the checkout.
prepare_case container-failure
make_fake_path
SD_VPNC_DOTFILES=https://token@example.invalid/build-failing.git
DOTFILES_TEST_URL=$SD_VPNC_DOTFILES
EXPECT_DOTFILES=yes
CONTAINER_MODE=fail
export SD_VPNC_DOTFILES DOTFILES_TEST_URL EXPECT_DOTFILES CONTAINER_MODE
if output=$(run_sd 2>&1); then
	fail "container build failure unexpectedly succeeded"
fi
assert_not_contains "$output" "$SD_VPNC_DOTFILES"
assert_logged_context_removed
assert_no_configured_contexts

# Exercise real branch, tag, and commit selection against a temporary local
# repository when host Git is available; this never accesses the network.
if [ -n "$ORIGINAL_GIT" ]; then
	prepare_case local-git-refs
	SENTINEL=sentinel-secret-token
	LOCAL_REPO="$CASE_DIR/local $SENTINEL repository"
	mkdir -p "$LOCAL_REPO"
	"$ORIGINAL_GIT" -C "$LOCAL_REPO" init -q
	"$ORIGINAL_GIT" -C "$LOCAL_REPO" config user.name dotfiles-test
	"$ORIGINAL_GIT" -C "$LOCAL_REPO" config user.email dotfiles-test@example.invalid
	printf 'tag-ref\n' > "$LOCAL_REPO/.selection"
	printf 'tag-ref\n' > "$LOCAL_REPO/.source"
	"$ORIGINAL_GIT" -C "$LOCAL_REPO" add .selection .source
	"$ORIGINAL_GIT" -C "$LOCAL_REPO" commit -qm tag-base
	"$ORIGINAL_GIT" -C "$LOCAL_REPO" branch -M main
	"$ORIGINAL_GIT" -C "$LOCAL_REPO" tag selected-tag
	"$ORIGINAL_GIT" -C "$LOCAL_REPO" checkout -q -b feature
	printf 'branch-ref\n' > "$LOCAL_REPO/.selection"
	printf 'branch-ref\n' > "$LOCAL_REPO/.source"
	"$ORIGINAL_GIT" -C "$LOCAL_REPO" commit -qam branch-tip
	"$ORIGINAL_GIT" -C "$LOCAL_REPO" checkout -q main
	printf 'commit-ref\n' > "$LOCAL_REPO/.selection"
	printf 'commit-ref\n' > "$LOCAL_REPO/.source"
	"$ORIGINAL_GIT" -C "$LOCAL_REPO" commit -qam commit-tip
	LOCAL_COMMIT=$("$ORIGINAL_GIT" -C "$LOCAL_REPO" rev-parse HEAD)
	cp "$TMP_ROOT/podman" "$FAKE_BIN/podman"
	chmod +x "$FAKE_BIN/podman"
	RUN_PATH="$FAKE_BIN:$ORIGINAL_PATH"
	export RUN_PATH LOCAL_REPO SENTINEL
	run_local_git_ref() {
		ref_label=$1
		ref_name=$2
		expected_selection=$3
		expected_commit=$("$ORIGINAL_GIT" -C "$LOCAL_REPO" rev-parse "$ref_name^{commit}")
		CASE_CACHE="$CASE_DIR/cache-$ref_label"
		CASE_HOME="$CASE_DIR/home-$ref_label"
		CAPTURE_DIR="$CASE_DIR/capture-$ref_label"
		CONTAINERFILE_CAPTURE="$CASE_DIR/$ref_label.Containerfile"
		GIT_LOG="$CASE_DIR/$ref_label.git.log"
		CONTAINER_LOG="$CASE_DIR/$ref_label.container.log"
		ENGINE_LOG="$CASE_DIR/$ref_label.engine.log"
		SD_VPNC_DOTFILES=$LOCAL_REPO
		SD_VPNC_DOTFILES_REF=$ref_name
		EXPECT_DOTFILES=yes
		EXPECT_SOURCE=$expected_selection
		mkdir -p "$CASE_HOME"
		export CASE_CACHE CASE_HOME CAPTURE_DIR CONTAINERFILE_CAPTURE GIT_LOG CONTAINER_LOG ENGINE_LOG
		export SD_VPNC_DOTFILES SD_VPNC_DOTFILES_REF EXPECT_DOTFILES EXPECT_SOURCE
		output=$(run_sd 2>&1) || fail "real local Git $ref_label build failed: $output"
		[ "$(cat "$CAPTURE_DIR/dotfiles/.selection")" = "$expected_selection" ] || fail "real Git selected the wrong $ref_label state"
		[ ! -e "$CAPTURE_DIR/dotfiles/.git" ] || fail "real Git metadata reached the copied source tree"
		[ -f "$CAPTURE_DIR/dotfiles-git/HEAD" ] || fail "real Git metadata was not staged for the installer mount"
		mounted_checkout="$CASE_DIR/mounted-$ref_label"
		mkdir -p "$mounted_checkout"
		cp -R "$CAPTURE_DIR/dotfiles/." "$mounted_checkout"
		cp -R "$CAPTURE_DIR/dotfiles-git" "$mounted_checkout/.git"
		if grep -rF -- "$SENTINEL" "$CAPTURE_DIR/dotfiles-git" "$CASE_DIR/$ref_label.Containerfile" >/dev/null 2>&1; then
			fail "host clone source reached the builder context for $ref_label"
		fi
		[ ! -e "$CAPTURE_DIR/dotfiles-git/logs" ] || fail "clone reflog reached the builder context for $ref_label"
		[ -z "$("$ORIGINAL_GIT" -C "$mounted_checkout" remote)" ] || fail "remote reached the builder context for $ref_label"
		# Run the generated installer command in the mounted checkout; the installer
		# verifies real Git checkout identity and the selected commit.
		cat >"$mounted_checkout/install.sh" <<'INSTALLER'
[ "$("$TEST_GIT" rev-parse --is-inside-work-tree)" = true ] || exit 51
[ "$("$TEST_GIT" rev-parse HEAD)" = "$EXPECTED_COMMIT" ] || exit 52
printf 'checkout verified\n' > "$INSTALLER_RESULT"
INSTALLER
		ref_run_line=$(sed -n 's/^RUN //p' "$CASE_DIR/$ref_label.Containerfile" | grep -F 'bash ./install.sh' | tail -n 1 | sed 's/^--mount=[^ ]* //')
		INSTALLER_RESULT="$CASE_DIR/$ref_label.installer-result"
		TEST_GIT=$ORIGINAL_GIT
		EXPECTED_COMMIT=$expected_commit
		export INSTALLER_RESULT TEST_GIT EXPECTED_COMMIT
		(cd "$mounted_checkout" && sh -c "$ref_run_line") || fail "installer could not verify the $ref_label Git checkout and selected commit"
		[ -f "$INSTALLER_RESULT" ] || fail "installer checkout verification did not complete for $ref_label"
		assert_logged_context_removed
		assert_no_configured_contexts
	}
	run_local_git_ref branch feature branch-ref
	run_local_git_ref tag selected-tag tag-ref
	run_local_git_ref commit "$LOCAL_COMMIT" commit-ref

	# A source repository that borrows objects through alternates yields a local
	# clone that also depends on the host path. The staged metadata must keep the
	# selected commit and its reachable history once the original objects are
	# unavailable; unreachable objects are intentionally not asserted.
	prepare_case local-git-alternates
	cp "$TMP_ROOT/podman" "$FAKE_BIN/podman"
	chmod +x "$FAKE_BIN/podman"
	RUN_PATH="$FAKE_BIN:$ORIGINAL_PATH"
	ALT_BASE="$CASE_DIR/alternates-base"
	ALT_SOURCE="$CASE_DIR/alternates-source"
	mkdir -p "$ALT_BASE"
	"$ORIGINAL_GIT" -C "$ALT_BASE" init -q
	"$ORIGINAL_GIT" -C "$ALT_BASE" config user.name dotfiles-test
	"$ORIGINAL_GIT" -C "$ALT_BASE" config user.email dotfiles-test@example.invalid
	printf 'base\n' > "$ALT_BASE/.source"
	"$ORIGINAL_GIT" -C "$ALT_BASE" add .source
	"$ORIGINAL_GIT" -C "$ALT_BASE" commit -qm base
	"$ORIGINAL_GIT" clone -q --shared "$ALT_BASE" "$ALT_SOURCE"
	"$ORIGINAL_GIT" -C "$ALT_SOURCE" config user.name dotfiles-test
	"$ORIGINAL_GIT" -C "$ALT_SOURCE" config user.email dotfiles-test@example.invalid
	[ -e "$ALT_SOURCE/.git/objects/info/alternates" ] || fail "alternates fixture was not created"
	"$ORIGINAL_GIT" clone -q -- "$ALT_SOURCE" "$CASE_DIR/alternates-control"
	[ -e "$CASE_DIR/alternates-control/.git/objects/info/alternates" ] || fail "alternates fixture does not reproduce a host-dependent clone"
	printf 'tip\n' > "$ALT_SOURCE/.source"
	"$ORIGINAL_GIT" -C "$ALT_SOURCE" commit -qam tip
	ALT_COMMIT=$("$ORIGINAL_GIT" -C "$ALT_SOURCE" rev-parse HEAD)
	SD_VPNC_DOTFILES=$ALT_SOURCE
	EXPECT_DOTFILES=yes
	export RUN_PATH SD_VPNC_DOTFILES EXPECT_DOTFILES
	output=$(run_sd 2>&1) || fail "alternates-backed local Git build failed: $output"
	[ ! -e "$CAPTURE_DIR/dotfiles-git/objects/info/alternates" ] || fail "staged Git metadata still depends on alternates"
	mv "$ALT_BASE" "$CASE_DIR/alternates-base.gone"
	mv "$ALT_SOURCE" "$CASE_DIR/alternates-source.gone"
	mounted_checkout="$CASE_DIR/mounted-alternates"
	mkdir -p "$mounted_checkout"
	cp -R "$CAPTURE_DIR/dotfiles/." "$mounted_checkout"
	cp -R "$CAPTURE_DIR/dotfiles-git" "$mounted_checkout/.git"
	[ "$("$ORIGINAL_GIT" -C "$mounted_checkout" rev-parse HEAD)" = "$ALT_COMMIT" ] || fail "alternates-backed checkout selected the wrong commit"
	"$ORIGINAL_GIT" -C "$mounted_checkout" fsck --full >/dev/null 2>&1 || fail "staged Git metadata lost reachable history without the original repositories"
	[ "$("$ORIGINAL_GIT" -C "$mounted_checkout" rev-list --count HEAD)" = 2 ] || fail "staged Git history is incomplete"
	"$ORIGINAL_GIT" -C "$mounted_checkout" rev-list --objects --all >/dev/null 2>&1 || fail "staged Git reachable objects are incomplete"
	assert_logged_context_removed
	assert_no_configured_contexts

else
	printf 'Skipping local Git ref test: host Git is unavailable.\n'
fi

# Docker needs the generated Containerfile named explicitly and the build runs
# through the docker command when podman is absent.
prepare_case docker-engine
DOCKER_BIN="$CASE_DIR/docker-bin"
mkdir -p "$DOCKER_BIN"
for utility in cat chmod cp flock id mkdir mktemp rm mv sed grep stat; do
	utility_path=$(command -v "$utility") || fail "missing utility: $utility"
	ln -s "$utility_path" "$DOCKER_BIN/$utility"
done
cp "$TMP_ROOT/podman" "$DOCKER_BIN/docker"
cp "$TMP_ROOT/git" "$DOCKER_BIN/git"
chmod +x "$DOCKER_BIN/docker" "$DOCKER_BIN/git"
[ ! -e "$DOCKER_BIN/podman" ] || fail "docker path unexpectedly contains podman"
RUN_PATH=$DOCKER_BIN
SD_VPNC_DOTFILES=docker-engine-repo
EXPECT_DOTFILES=yes
export RUN_PATH SD_VPNC_DOTFILES EXPECT_DOTFILES
output=$(run_sd 2>&1) || fail "docker image build failed: $output"
assert_contains "$(cat "$ENGINE_LOG")" 'docker '
assert_file_contains "$CONTAINERFILE_CAPTURE" 'RUN --mount=type=bind,source=dotfiles-git,target=/home/dev/.dotfiles/.git if [ -f ./install.sh ]'
assert_not_contains "$(cat "$CONTAINERFILE_CAPTURE")" ',z'
assert_logged_context_removed
assert_no_configured_contexts

# If no installer is present, the source is still copied and the Containerfile
# conditionally skips the install command rather than auto-linking files.
prepare_case missing-installer
make_fake_path
SD_VPNC_DOTFILES=https://example.invalid/no-installer.git
REPO_INSTALLER=no
EXPECT_DOTFILES=yes
export SD_VPNC_DOTFILES REPO_INSTALLER EXPECT_DOTFILES
output=$(run_sd 2>&1) || fail "missing-installer image build failed: $output"
[ -f "$CAPTURE_DIR/dotfiles/.bashrc" ] || fail "source was not retained without install.sh"
[ ! -e "$CAPTURE_DIR/dotfiles/install.sh" ] || fail "fake repository unexpectedly has install.sh"
assert_file_contains "$CONTAINERFILE_CAPTURE" 'if [ -f ./install.sh ]; then HOME=/home/dev bash ./install.sh </dev/null; fi'
assert_file_contains "$CONTAINERFILE_CAPTURE" 'RUN mkdir -p /usr/share/sd-vpnc/home-template && cp -a /home/dev/. /usr/share/sd-vpnc/home-template/ && rm -rf /usr/share/sd-vpnc/home-template/.ssh'
assert_not_contains "$(cat "$CONTAINERFILE_CAPTURE")" 'ln -s'
assert_logged_context_removed
assert_no_configured_contexts

# Runtime home seeding uses fresh private XDG roots, preserves readable sibling
# content and symlinks, and leaves the image template untouched.
HOME_INIT_FILE=$CAPTURE_DIR/home-init.sh
SHELL_SELECTOR_FILE=$CAPTURE_DIR/sd-vpnc-shell
HOME_TEMPLATE="$CASE_DIR/runtime-home-template"
RUNTIME_HOME="$CASE_DIR/runtime-home"
mkdir -p "$HOME_TEMPLATE/.dotfiles" "$HOME_TEMPLATE/.cache" \
	"$HOME_TEMPLATE/.local/state" "$HOME_TEMPLATE/.local/share/atuin" \
	"$HOME_TEMPLATE/.local/share/tool-data" "$HOME_TEMPLATE/.local/bin" \
	"$HOME_TEMPLATE/.atuin/data" "$HOME_TEMPLATE/.ssh"
printf 'readable config\n' > "$HOME_TEMPLATE/.zshrc"
printf 'dotfiles config\n' > "$HOME_TEMPLATE/.dotfiles/config"
printf 'stale cache\n' > "$HOME_TEMPLATE/.cache/marker"
printf 'stale history\n' > "$HOME_TEMPLATE/.local/state/marker"
printf 'stale legacy Atuin database\n' > "$HOME_TEMPLATE/.local/share/atuin/history.db"
printf 'stale Atuin database\n' > "$HOME_TEMPLATE/.atuin/data/history.db"
printf 'tool\n' > "$HOME_TEMPLATE/.local/bin/tool"
printf 'tool data\n' > "$HOME_TEMPLATE/.local/share/tool-data/config"
printf 'ssh config\n' > "$HOME_TEMPLATE/.ssh/config"
printf 'unreadable\n' > "$HOME_TEMPLATE/.private"
printf 'relative target\n' > "$HOME_TEMPLATE/.dotfiles/target"
chmod 755 "$HOME_TEMPLATE/.dotfiles" "$HOME_TEMPLATE/.local/bin" "$HOME_TEMPLATE/.local/share/tool-data"
chmod 644 "$HOME_TEMPLATE/.zshrc" "$HOME_TEMPLATE/.dotfiles/config" \
	"$HOME_TEMPLATE/.local/share/tool-data/config" "$HOME_TEMPLATE/.ssh/config"
chmod 755 "$HOME_TEMPLATE/.local/bin/tool"
chmod 000 "$HOME_TEMPLATE/.private"
ln -s .dotfiles/target "$HOME_TEMPLATE/.zshrc-link"
chmod 0555 "$HOME_TEMPLATE/.cache" "$HOME_TEMPLATE/.local" \
	"$HOME_TEMPLATE/.local/state" "$HOME_TEMPLATE/.local/share" \
	"$HOME_TEMPLATE/.local/share/atuin" "$HOME_TEMPLATE/.atuin" \
	"$HOME_TEMPLATE/.atuin/data"
mkdir -m 0700 "$RUNTIME_HOME"
HOME_INIT_FILE="$HOME_INIT_FILE" HOME_TEMPLATE="$HOME_TEMPLATE" HOME="$RUNTIME_HOME" \
	/bin/bash -c '
set -euo pipefail
. "$HOME_INIT_FILE"
before_umask=$(umask)
sd_vpnc_seed_home "$HOME_TEMPLATE"
[ "$(umask)" = "$before_umask" ] || { echo "runtime home setup changed umask" >&2; exit 1; }
uid=$(id -u)
gid=$(id -g)
for path in "$HOME/.cache" "$HOME/.local" "$HOME/.local/state" "$HOME/.local/share" "$HOME/.atuin" "$HOME/.atuin/data"; do
	[ "$(stat -c %a "$path")" = 700 ] || { echo "unexpected mode on $path" >&2; exit 1; }
	[ "$(stat -c %u:%g "$path")" = "$uid:$gid" ] || { echo "unexpected owner on $path" >&2; exit 1; }
done
[ "$XDG_CACHE_HOME" = "$HOME/.cache" ]
[ "$XDG_STATE_HOME" = "$HOME/.local/state" ]
[ "$XDG_DATA_HOME" = "$HOME/.local/share" ]
[ "$ATUIN_HOME" = "$HOME/.atuin" ]
[ -f "$HOME/.zshrc" ] && [ -f "$HOME/.dotfiles/config" ]
[ -L "$HOME/.zshrc-link" ] && [ "$(cat "$HOME/.zshrc-link")" = "relative target" ]
[ -f "$HOME/.local/bin/tool" ] && [ "$(stat -c %a "$HOME/.local/bin/tool")" = 755 ]
[ -f "$HOME/.local/share/tool-data/config" ]
[ ! -e "$HOME/.cache/marker" ] && [ ! -e "$HOME/.local/state/marker" ]
[ ! -e "$HOME/.local/share/atuin/history.db" ] && [ ! -e "$HOME/.atuin/data/history.db" ]
[ ! -e "$HOME/.ssh/config" ] && [ ! -e "$HOME/.private" ]
touch "$HOME/.cache/new" "$HOME/.local/state/history" "$HOME/.atuin/data/new-db"
' || fail "runtime home seeding failed"
[ "$(file_mode "$HOME_TEMPLATE/.cache")" = 555 ] || fail "template cache mode changed"
[ "$(file_mode "$HOME_TEMPLATE/.local")" = 555 ] || fail "template .local mode changed"
[ "$(file_mode "$HOME_TEMPLATE/.local/state")" = 555 ] || fail "template state mode changed"
[ "$(file_mode "$HOME_TEMPLATE/.local/share")" = 555 ] || fail "template share mode changed"
[ "$(file_mode "$HOME_TEMPLATE/.local/share/atuin")" = 555 ] || fail "legacy template Atuin mode changed"
[ "$(file_mode "$HOME_TEMPLATE/.atuin")" = 555 ] || fail "template .atuin mode changed"
[ "$(file_mode "$HOME_TEMPLATE/.atuin/data")" = 555 ] || fail "template Atuin data mode changed"
[ "$(file_mode "$HOME_TEMPLATE/.private")" = 0 ] || fail "unreadable template file mode changed"

# Symlink source roots are not traversed, while ordinary template symlinks are
# still preserved by the runtime copy helper.
EXTERNAL_SENTINEL="$CASE_DIR/external-local"
mkdir -p "$EXTERNAL_SENTINEL/share" "$EXTERNAL_SENTINEL/bin"
printf 'outside local child\n' > "$EXTERNAL_SENTINEL/bin/sentinel"
printf 'outside share child\n' > "$EXTERNAL_SENTINEL/share/sentinel"
SYMLINK_LOCAL_TEMPLATE="$CASE_DIR/symlink-local-template"
SYMLINK_LOCAL_HOME="$CASE_DIR/symlink-local-home"
mkdir -p "$SYMLINK_LOCAL_TEMPLATE"
ln -s "$EXTERNAL_SENTINEL" "$SYMLINK_LOCAL_TEMPLATE/.local"
mkdir -m 0700 "$SYMLINK_LOCAL_HOME"
HOME_INIT_FILE="$HOME_INIT_FILE" HOME_TEMPLATE="$SYMLINK_LOCAL_TEMPLATE" HOME="$SYMLINK_LOCAL_HOME" \
	/bin/bash -c '. "$HOME_INIT_FILE"; sd_vpnc_seed_home "$HOME_TEMPLATE"' || fail "symlink .local seed failed"
[ ! -e "$SYMLINK_LOCAL_HOME/.local/bin/sentinel" ] || fail "symlinked .local source was traversed"
SYMLINK_SHARE_TEMPLATE="$CASE_DIR/symlink-share-template"
SYMLINK_SHARE_HOME="$CASE_DIR/symlink-share-home"
mkdir -p "$SYMLINK_SHARE_TEMPLATE/.local"
ln -s "$EXTERNAL_SENTINEL/share" "$SYMLINK_SHARE_TEMPLATE/.local/share"
mkdir -m 0700 "$SYMLINK_SHARE_HOME"
HOME_INIT_FILE="$HOME_INIT_FILE" HOME_TEMPLATE="$SYMLINK_SHARE_TEMPLATE" HOME="$SYMLINK_SHARE_HOME" \
	/bin/bash -c '. "$HOME_INIT_FILE"; sd_vpnc_seed_home "$HOME_TEMPLATE"' || fail "symlink .local/share seed failed"
[ ! -e "$SYMLINK_SHARE_HOME/.local/share/sentinel" ] || fail "symlinked .local/share source was traversed"
[ -f "$EXTERNAL_SENTINEL/bin/sentinel" ] && [ -f "$EXTERNAL_SENTINEL/share/sentinel" ] || fail "symlink source sentinel was changed"

# The shared shell selector starts login Zsh when present and chooses the
# explicit interactive login Bash fallback otherwise, with history under state.
mkdir -p "$CASE_DIR/fake-zsh-bin" "$CASE_DIR/fake-bash-bin"
for bin_dir in "$CASE_DIR/fake-zsh-bin" "$CASE_DIR/fake-bash-bin"; do
	ln -s "$(command -v mkdir)" "$bin_dir/mkdir"
done
cat > "$CASE_DIR/fake-zsh-bin/zsh" <<'ZSH'
#!/bin/sh
printf '%s\n' "$@" > "$SHELL_ARGS_LOG"
printf '%s\n' "$HISTFILE" > "$SHELL_HIST_LOG"
printf '%s\n' "$XDG_DATA_HOME" > "$SHELL_DATA_LOG"
ZSH
cat > "$CASE_DIR/fake-bash-bin/bash" <<'BASH'
#!/bin/sh
printf '%s\n' "$@" > "$SHELL_ARGS_LOG"
printf '%s\n' "$HISTFILE" > "$SHELL_HIST_LOG"
BASH
chmod +x "$CASE_DIR/fake-zsh-bin/zsh" "$CASE_DIR/fake-bash-bin/bash"
SHELL_ARGS_LOG="$CASE_DIR/zsh-args" SHELL_HIST_LOG="$CASE_DIR/zsh-hist" \
	SHELL_DATA_LOG="$CASE_DIR/zsh-data" HOME="$RUNTIME_HOME" \
	XDG_STATE_HOME="$RUNTIME_HOME/.local/state" XDG_DATA_HOME="$RUNTIME_HOME/.local/share" \
	PATH="$CASE_DIR/fake-zsh-bin" /bin/bash "$SHELL_SELECTOR_FILE" || fail "Zsh selector failed"
assert_contains "$(cat "$CASE_DIR/zsh-args")" '-l'
assert_contains "$(cat "$CASE_DIR/zsh-args")" '-i'
assert_contains "$(cat "$CASE_DIR/zsh-hist")" '/.local/state/sd-vpnc/zsh_history'
assert_contains "$(cat "$CASE_DIR/zsh-data")" '/.local/share'
SHELL_ARGS_LOG="$CASE_DIR/bash-args" SHELL_HIST_LOG="$CASE_DIR/bash-hist" \
	HOME="$RUNTIME_HOME" XDG_STATE_HOME="$RUNTIME_HOME/.local/state" \
	XDG_DATA_HOME="$RUNTIME_HOME/.local/share" PATH="$CASE_DIR/fake-bash-bin" \
	/bin/bash "$SHELL_SELECTOR_FILE" || fail "Bash fallback selector failed"
assert_contains "$(cat "$CASE_DIR/bash-args")" '--login'
assert_contains "$(cat "$CASE_DIR/bash-args")" '-i'
assert_contains "$(cat "$CASE_DIR/bash-hist")" '/.local/state/sd-vpnc/bash_history'

# Fake runtime engines record regular/detached launches and engine-specific bind behavior.
RUNTIME_ENGINE_SCRIPT="$TMP_ROOT/runtime-engine"
cat > "$RUNTIME_ENGINE_SCRIPT" <<'ENGINE'
#!/bin/sh
set -eu
printf '%s' "${0##*/}" >> "$RUNTIME_LOG"
for argument do printf '[%s]' "$argument" >> "$RUNTIME_LOG"; done
printf '\n' >> "$RUNTIME_LOG"
case ${1:-} in
	context) printf 'default\n'; exit 0 ;;
	info)
		case ${FAKE_ROOTLESS_STATUS:-false} in
			error) exit 77 ;;
			*) printf '%s\n' "${FAKE_ROOTLESS_STATUS:-false}"; exit 0 ;;
		esac
		;;
	container)
		case ${2:-} in
			inspect)
				[ -f "$RUNTIME_STATE" ] || { [ "${3:-}" = --format ] && printf 'false\n'; exit 1; }
				if [ "${3:-}" = --format ]; then
					case ${4:-} in
						*State.Running*) printf 'true\n' ;;
						*.Id*) cat "$RUNTIME_STATE.id" 2>/dev/null || printf 'fake-container-id\n' ;;
						*io.sd-vpnc.tunnel*) printf 'sd-vpnc\n' ;;
						*io.sd-vpnc.manager*) printf 'sd-vpnc|1\n' ;;
						*) printf 'true\n' ;;
					esac
				fi
				exit 0
				;;
			ls) exit 0 ;;
			rm|stop) rm -f "$RUNTIME_STATE"; exit 0 ;;
		esac
		;;
	image) exit 0 ;;
	run)
		case " $* " in
			*' --detach '*)
				: > "$RUNTIME_STATE"
				case " $* " in *'--name sd-vpnc-tun-'*) printf 'fake-container-id\n' > "$RUNTIME_STATE.id" ;; esac
				printf 'fake-container-id\n'
				;;
		esac
		exit 0
		;;
	exec)
		shift
		while :; do
			case ${1:-} in
				-i|-t|-it) shift ;;
				--workdir|-w|--user) shift 2 ;;
				*) break ;;
			esac
		done
		name=${1:-}; shift || true
		command=${1:-}; shift || true
		case $command in
			test)
				case ${2:-} in
					/tmp/sd-vpnc-manager-ready) exit 0 ;;
					/tmp/sd-vpnc-tun-ready) exit 0 ;;
					/tmp/sd-vpnc-session-registry/registered/*) exit 0 ;;
					esac
				exit 1
				;;
			/usr/local/bin/sd-vpnc-entrypoint)
				case ${1:-} in
					status) printf 'ownership=sd-vpnc protocol=1 state=ACTIVE generation=fake live=0 stale=0 indeterminate=0\n'; exit 0 ;;
					session)
						id=${2:-}
						: > "$RUNTIME_STATE.registered.$id"
						exit 0
						;;
				esac
				;;
			/usr/local/bin/sd-vpnc-session-registry)
				case ${1:-} in
					release|stop-if-idle)
						rm -f "$RUNTIME_STATE"
						printf 'ownership=sd-vpnc protocol=1 state=STOPPING generation=fake live=0 stale=0 indeterminate=0\n'
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
chmod +x "$RUNTIME_ENGINE_SCRIPT"
prepare_runtime_cli_case() {
	prepare_case "$1"
	unset DEVPOD_WORKSPACE_ID DEVPOD_WORKSPACE_ID_OTHER DEVPOD_WORKSPACE SD_VPNC_FORWARD_CANARY
	FAKE_ROOTLESS_STATUS=false
	export FAKE_ROOTLESS_STATUS
	mkdir -p "$CASE_HOME/.config/sd-vpnc" "$CASE_HOME/.ssh" "$CASE_HOME/.local/share/sd-vpnc"
	: > "$CASE_HOME/.config/sd-vpnc/client.ovpn"
	RUNTIME_LOG="$CASE_DIR/runtime.log"
	RUNTIME_STATE="$CASE_DIR/container-state"
	export RUNTIME_LOG RUNTIME_STATE
}
make_runtime_podman_path() {
	RUNTIME_BIN="$CASE_DIR/runtime-podman-bin"
	mkdir -p "$RUNTIME_BIN"
	cp "$RUNTIME_ENGINE_SCRIPT" "$RUNTIME_BIN/podman"
	chmod +x "$RUNTIME_BIN/podman"
	RUN_PATH="$RUNTIME_BIN:$ORIGINAL_PATH"
	export RUN_PATH
}
make_runtime_docker_path() {
	DOCKER_RUNTIME_BIN="$CASE_DIR/runtime-docker-bin"
	mkdir -p "$DOCKER_RUNTIME_BIN"
	for utility in awk base64 cat chmod cmp date flock grep id mkdir mktemp mv od rm sed sleep stat tail tr wc; do
		utility_path=$(command -v "$utility") || fail "missing runtime utility: $utility"
		ln -s "$utility_path" "$DOCKER_RUNTIME_BIN/$utility"
	done
	cp "$RUNTIME_ENGINE_SCRIPT" "$DOCKER_RUNTIME_BIN/docker"
	chmod +x "$DOCKER_RUNTIME_BIN/docker"
	RUN_PATH=$DOCKER_RUNTIME_BIN
	export RUN_PATH
}
run_runtime_cli() {
	PATH="$RUN_PATH" HOME="$CASE_HOME" XDG_CONFIG_HOME="$CASE_HOME/.config" \
		XDG_DATA_HOME="$CASE_HOME/.local/share" SD_VPNC_COLOR=never \
		"$REPO_ROOT/sd-vpnc" "$@"
}
uid=$(id -u)
gid=$(id -g)
prepare_runtime_cli_case runtime-rootless-podman-regular
make_runtime_podman_path
FAKE_ROOTLESS_STATUS=true
output=$(run_runtime_cli ssh 2>&1) || fail "rootless Podman regular runtime argument test failed: $output"
runtime_args=$(cat "$RUNTIME_LOG")
assert_contains "$runtime_args" "[--user][$uid:$gid]"
assert_contains "$runtime_args" '[--userns=keep-id]'
assert_contains "$runtime_args" '[--mount][type=tmpfs,destination=/home/dev,tmpfs-mode=0700,U=true,notmpcopyup]'
assert_contains "$runtime_args" "[$CASE_HOME/.config/sd-vpnc:/config:ro,z]"
assert_contains "$runtime_args" "[$CASE_HOME/.ssh:/home/dev/.ssh:ro,z]"
assert_contains "$runtime_args" "[$CASE_HOME/.local/share/sd-vpnc:/work:z]"
assert_contains "$runtime_args" "[info][--format][{{.Host.Security.Rootless}}]"

prepare_runtime_cli_case runtime-rootless-podman-detached
make_runtime_podman_path
FAKE_ROOTLESS_STATUS=true
output=$(run_runtime_cli tun smoke-host 8080:80 2>&1) || fail "rootless Podman detached runtime argument test failed: $output"
runtime_args=$(cat "$RUNTIME_LOG")
assert_contains "$runtime_args" '[--detach]'
assert_contains "$runtime_args" '[--userns=keep-id]'
assert_contains "$runtime_args" '[--mount][type=tmpfs,destination=/home/dev,tmpfs-mode=0700,U=true,notmpcopyup]'
assert_contains "$runtime_args" "[$CASE_HOME/.config/sd-vpnc:/config:ro,z]"
assert_contains "$runtime_args" "[$CASE_HOME/.ssh:/home/dev/.ssh:ro,z]"
assert_contains "$runtime_args" "[$CASE_HOME/.local/share/sd-vpnc:/work:z]"

prepare_runtime_cli_case runtime-rootful-podman-regular
make_runtime_podman_path
output=$(run_runtime_cli ssh 2>&1) || fail "rootful Podman regular runtime argument test failed: $output"
runtime_args=$(cat "$RUNTIME_LOG")
assert_contains "$runtime_args" "[--user][$uid:$gid]"
assert_not_contains "$runtime_args" '--userns=keep-id'
assert_contains "$runtime_args" "[$CASE_HOME/.config/sd-vpnc:/config:ro]"
assert_contains "$runtime_args" "[$CASE_HOME/.ssh:/home/dev/.ssh:ro]"
assert_contains "$runtime_args" "[$CASE_HOME/.local/share/sd-vpnc:/work]"
assert_not_contains "$runtime_args" ':ro,z'
assert_not_contains "$runtime_args" ':/work:z'

prepare_runtime_cli_case runtime-rootful-podman-detached
make_runtime_podman_path
output=$(run_runtime_cli tun smoke-host 8080:80 2>&1) || fail "rootful Podman detached runtime argument test failed: $output"
runtime_args=$(cat "$RUNTIME_LOG")
assert_contains "$runtime_args" '[--detach]'
assert_not_contains "$runtime_args" '--userns=keep-id'
assert_contains "$runtime_args" "[$CASE_HOME/.config/sd-vpnc:/config:ro]"
assert_contains "$runtime_args" "[$CASE_HOME/.ssh:/home/dev/.ssh:ro]"
assert_contains "$runtime_args" "[$CASE_HOME/.local/share/sd-vpnc:/work]"
assert_not_contains "$runtime_args" ':ro,z'
assert_not_contains "$runtime_args" ':/work:z'

prepare_runtime_cli_case runtime-podman-probe-error
make_runtime_podman_path
FAKE_ROOTLESS_STATUS=error
if output=$(run_runtime_cli ssh 2>&1); then fail "Podman rootless probe error unexpectedly succeeded"; fi
assert_contains "$output" 'Failed to determine whether Podman is rootless.'
assert_not_contains "$(cat "$RUNTIME_LOG")" '[run]'

prepare_runtime_cli_case runtime-podman-probe-invalid
make_runtime_podman_path
FAKE_ROOTLESS_STATUS=unknown
if output=$(run_runtime_cli tun smoke-host 8080:80 2>&1); then fail "invalid Podman rootless probe unexpectedly succeeded"; fi
assert_contains "$output" 'Podman rootless detection returned an invalid result'
assert_not_contains "$(cat "$RUNTIME_LOG")" '[run]'

prepare_runtime_cli_case runtime-podman-host-shell
make_runtime_podman_path
FAKE_ROOTLESS_STATUS=true
output=$(run_runtime_cli ssh remote-host 2>&1) || fail "remote SSH host argument test failed: $output"
assert_contains "$(cat "$RUNTIME_LOG")" '[session]'
assert_contains "$(cat "$RUNTIME_LOG")" '[ssh]'
assert_contains "$(cat "$RUNTIME_LOG")" '[remote-host]'

prepare_runtime_cli_case runtime-docker-regular
make_runtime_docker_path
output=$(run_runtime_cli ssh 2>&1) || fail "Docker regular runtime argument test failed: $output"
runtime_args=$(cat "$RUNTIME_LOG")
assert_contains "$runtime_args" "[--user][$uid:$gid]"
assert_contains "$runtime_args" "[--tmpfs][/home/dev:rw,uid=$uid,gid=$gid,mode=0700]"
assert_contains "$runtime_args" "[$CASE_HOME/.config/sd-vpnc:/config:ro]"
assert_contains "$runtime_args" "[$CASE_HOME/.ssh:/home/dev/.ssh:ro]"
assert_contains "$runtime_args" "[$CASE_HOME/.local/share/sd-vpnc:/work]"
assert_not_contains "$runtime_args" 'info][--format'
assert_not_contains "$runtime_args" ':ro,z'
assert_not_contains "$runtime_args" ':/work:z'

prepare_runtime_cli_case runtime-docker-detached
make_runtime_docker_path
output=$(run_runtime_cli tun smoke-host 8080:80 2>&1) || fail "Docker detached runtime argument test failed: $output"
runtime_args=$(cat "$RUNTIME_LOG")
assert_contains "$runtime_args" '[--detach]'
assert_contains "$runtime_args" "[--tmpfs][/home/dev:rw,uid=$uid,gid=$gid,mode=0700]"
assert_contains "$runtime_args" "[$CASE_HOME/.config/sd-vpnc:/config:ro]"
assert_contains "$runtime_args" "[$CASE_HOME/.ssh:/home/dev/.ssh:ro]"
assert_contains "$runtime_args" "[$CASE_HOME/.local/share/sd-vpnc:/work]"
assert_not_contains "$runtime_args" 'info][--format'
assert_not_contains "$runtime_args" ':ro,z'
assert_not_contains "$runtime_args" ':/work:z'

# DEVPOD_WORKSPACE_ID is the only host variable forwarded, and only when non-empty.
assert_devpod_forwarded() {
	assert_contains "$runtime_args" '[-e][HOME=/home/dev][-e][DEVPOD_WORKSPACE_ID=devpod workspace;id][-v]'
	assert_not_contains "$runtime_args" 'DEVPOD_WORKSPACE_ID_OTHER'
	assert_not_contains "$runtime_args" 'SD_VPNC_FORWARD_CANARY'
	assert_not_contains "$runtime_args" 'canary-value'
	assert_not_contains "$runtime_args" 'other-value'
}
assert_devpod_not_forwarded() {
	assert_contains "$runtime_args" '[-e][HOME=/home/dev]'
	assert_not_contains "$runtime_args" 'DEVPOD_WORKSPACE_ID'
	assert_not_contains "$runtime_args" 'DEVPOD_WORKSPACE'
	assert_not_contains "$runtime_args" 'SD_VPNC_FORWARD_CANARY'
	assert_not_contains "$runtime_args" '[-e][-v]'
	assert_contains "$runtime_args" '[-e][HOME=/home/dev][-v]'
}
set_devpod_environment() {
	DEVPOD_WORKSPACE_ID='devpod workspace;id'
	DEVPOD_WORKSPACE_ID_OTHER=other-value
	SD_VPNC_FORWARD_CANARY=canary-value
	export DEVPOD_WORKSPACE_ID DEVPOD_WORKSPACE_ID_OTHER SD_VPNC_FORWARD_CANARY
}

for engine in podman docker; do
	prepare_runtime_cli_case "runtime-$engine-devpod-regular-set"
	"make_runtime_${engine}_path"
	set_devpod_environment
	output=$(run_runtime_cli ssh 2>&1) || fail "$engine regular DEVPOD_WORKSPACE_ID forwarding failed: $output"
	runtime_args=$(cat "$RUNTIME_LOG")
	assert_devpod_forwarded

	prepare_runtime_cli_case "runtime-$engine-devpod-detached-set"
	"make_runtime_${engine}_path"
	set_devpod_environment
	output=$(run_runtime_cli tun smoke-host 8080:80 2>&1) || fail "$engine detached DEVPOD_WORKSPACE_ID forwarding failed: $output"
	runtime_args=$(cat "$RUNTIME_LOG")
	assert_contains "$runtime_args" '[--detach]'
	assert_devpod_forwarded

	prepare_runtime_cli_case "runtime-$engine-devpod-regular-unset"
	"make_runtime_${engine}_path"
	DEVPOD_WORKSPACE_ID_OTHER=other-value
	SD_VPNC_FORWARD_CANARY=canary-value
	DEVPOD_WORKSPACE=workspace-value
	export DEVPOD_WORKSPACE_ID_OTHER SD_VPNC_FORWARD_CANARY DEVPOD_WORKSPACE
	output=$(run_runtime_cli ssh 2>&1) || fail "$engine regular unset DEVPOD_WORKSPACE_ID failed: $output"
	runtime_args=$(cat "$RUNTIME_LOG")
	assert_devpod_not_forwarded

	prepare_runtime_cli_case "runtime-$engine-devpod-detached-unset"
	"make_runtime_${engine}_path"
	DEVPOD_WORKSPACE_ID_OTHER=other-value
	SD_VPNC_FORWARD_CANARY=canary-value
	DEVPOD_WORKSPACE=workspace-value
	export DEVPOD_WORKSPACE_ID_OTHER SD_VPNC_FORWARD_CANARY DEVPOD_WORKSPACE
	output=$(run_runtime_cli tun smoke-host 8080:80 2>&1) || fail "$engine detached unset DEVPOD_WORKSPACE_ID failed: $output"
	runtime_args=$(cat "$RUNTIME_LOG")
	assert_contains "$runtime_args" '[--detach]'
	assert_devpod_not_forwarded

	prepare_runtime_cli_case "runtime-$engine-devpod-regular-empty"
	"make_runtime_${engine}_path"
	DEVPOD_WORKSPACE_ID=
	export DEVPOD_WORKSPACE_ID
	output=$(run_runtime_cli ssh 2>&1) || fail "$engine regular empty DEVPOD_WORKSPACE_ID failed: $output"
	runtime_args=$(cat "$RUNTIME_LOG")
	assert_devpod_not_forwarded

	prepare_runtime_cli_case "runtime-$engine-devpod-detached-empty"
	"make_runtime_${engine}_path"
	DEVPOD_WORKSPACE_ID=
	export DEVPOD_WORKSPACE_ID
	output=$(run_runtime_cli tun smoke-host 8080:80 2>&1) || fail "$engine detached empty DEVPOD_WORKSPACE_ID failed: $output"
	runtime_args=$(cat "$RUNTIME_LOG")
	assert_contains "$runtime_args" '[--detach]'
	assert_devpod_not_forwarded
done
unset DEVPOD_WORKSPACE_ID DEVPOD_WORKSPACE_ID_OTHER DEVPOD_WORKSPACE SD_VPNC_FORWARD_CANARY

# `shell` starts the persistent manager and opens a registered exec session.
prepare_runtime_cli_case runtime-shell-exec
make_runtime_podman_path
output=$(run_runtime_cli shell 2>&1) || fail "managed shell invocation failed: $output"
assert_contains "$(cat "$RUNTIME_LOG")" '[--detach]'
assert_contains "$(cat "$RUNTIME_LOG")" '[manager]'
assert_contains "$(cat "$RUNTIME_LOG")" '[session]'

# A running separate tunnel remains the preferred shell target.
prepare_runtime_cli_case runtime-shell-prefers-tunnel
make_runtime_podman_path
: > "$RUNTIME_STATE"
output=$(run_runtime_cli shell 2>&1) || fail "tunnel shell target preference failed: $output"
assert_contains "$(cat "$RUNTIME_LOG")" "[exec][-it][sd-vpnc-tun-$(id -u)]"
assert_not_contains "$(cat "$RUNTIME_LOG")" '[run]'

# Use the host engines, not fake commands left at the front of PATH by the
# command-argument tests. Engine smoke checks are conditional and report skips.
PATH=$ORIGINAL_PATH
export PATH
if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
	PODMAN_SMOKE_IMAGE=registry.fedoraproject.org/fedora:42
	if podman image inspect "$PODMAN_SMOKE_IMAGE" >/dev/null 2>&1; then
		HOST_SSH="$CASE_DIR/podman-ssh"
		mkdir -m 0755 "$HOST_SSH"
		printf 'host ssh config\n' > "$HOST_SSH/config"
		chmod 0644 "$HOST_SSH/config"
		podman run --rm --pull=never --user 12345:6789 \
			--mount type=tmpfs,destination=/home/dev,tmpfs-mode=0700,U=true,notmpcopyup \
			-v "$HOME_INIT_FILE:/tmp/home-init.sh:ro,Z" \
			-v "$HOME_TEMPLATE:/tmp/home-template:ro,Z" \
			-v "$HOST_SSH:/home/dev/.ssh:ro,Z" \
			-e HOME=/home/dev --entrypoint /bin/bash "$PODMAN_SMOKE_IMAGE" -c '
				set -euo pipefail
				. /tmp/home-init.sh
				sd_vpnc_seed_home /tmp/home-template
				[ "$(stat -c %u:%g /home/dev)" = 12345:6789 ]
				[ "$(stat -c %a /home/dev)" = 700 ]
				[ "$(stat -c %u:%g /home/dev/.cache)" = 12345:6789 ]
				[ "$(stat -c %a /home/dev/.cache)" = 700 ]
				[ -f /home/dev/.local/bin/tool ]
				[ "${ATUIN_HOME}" = /home/dev/.atuin ]
				[ ! -e /home/dev/.atuin/data/history.db ]
				[ ! -e /home/dev/.local/share/atuin/history.db ]
				[ "$(cat /home/dev/.ssh/config)" = "host ssh config" ]
				if touch /home/dev/.ssh/write-probe 2>/dev/null; then exit 1; fi
				touch /home/dev/.cache/new
				touch /home/dev/.local/state/history /home/dev/.atuin/data/db
			' || fail "rootless Podman home seeding and UID:GID smoke test failed"
		podman run --rm --pull=never --user 12345:6789 \
			--mount type=tmpfs,destination=/home/dev,tmpfs-mode=0700,U=true,notmpcopyup \
			-e HOME=/home/dev --entrypoint /bin/sh "$PODMAN_SMOKE_IMAGE" -c '
				[ ! -e /home/dev/.local/state/history ]
				[ ! -e /home/dev/.atuin/data/db ]
			' || fail "runtime Atuin/state unexpectedly persisted between containers"
		[ "$(file_mode "$HOME_TEMPLATE/.cache")" = 555 ] || fail "Podman smoke changed source cache mode"
		[ "$(file_mode "$HOME_TEMPLATE/.local")" = 555 ] || fail "Podman smoke changed source .local mode"
		[ "$(file_mode "$HOME_TEMPLATE/.local/state")" = 555 ] || fail "Podman smoke changed source state mode"
		[ "$(file_mode "$HOME_TEMPLATE/.local/share")" = 555 ] || fail "Podman smoke changed source share mode"
		APP_VERSION=$(sed -n 's/^VERSION=//p' "$REPO_ROOT/sd-vpnc" | head -n 1)
		APP_IMAGE="localhost/sd-vpnc:$APP_VERSION"
		if podman image inspect "$APP_IMAGE" >/dev/null 2>&1; then
			if podman run --rm --pull=never --user 12345:6789 \
				--mount type=tmpfs,destination=/home/dev,tmpfs-mode=0700,U=true \
				--entrypoint /bin/sh "$APP_IMAGE" -c '
				set -e
				[ -d /home/dev/.config/atuin ]
				[ "$(stat -c %u:%g /home/dev/.config/atuin)" = 0:0 ]
				[ -r /home/dev/.config/atuin ] && [ -x /home/dev/.config/atuin ]
				[ -r /usr/local/lib/sd-vpnc-home-init.sh ]
				[ -d /usr/share/sd-vpnc/home-template/.config/atuin ]
				if touch /home/dev/.config/atuin/.tmpfs-copyup-probe 2>/dev/null; then
					rm -f /home/dev/.config/atuin/.tmpfs-copyup-probe
					exit 1
				fi
			'; then
				podman run --rm --pull=never --user 12345:6789 \
					--mount type=tmpfs,destination=/home/dev,tmpfs-mode=0700,U=true,notmpcopyup \
					-e HOME=/home/dev --entrypoint /bin/bash "$APP_IMAGE" -c '
						set -euo pipefail
						. /usr/local/lib/sd-vpnc-home-init.sh
						sd_vpnc_seed_home /usr/share/sd-vpnc/home-template
						[ "$(stat -c %u:%g /home/dev/.config/atuin)" = 12345:6789 ]
						touch /home/dev/.config/atuin/config.toml
					' || fail "no-copy-up smoke failed to seed writable .config/atuin"
			else
				printf 'Skipping copy-up regression smoke: local app image lacks an unreadable root-owned /home/dev/.config/atuin.\n'
			fi
		else
			printf 'Skipping copy-up regression smoke: local app image %s is unavailable (no pull attempted).\n' "$APP_IMAGE"
		fi
	else
		printf 'Skipping Podman home smoke: Fedora 42 image is not locally available.\n'
	fi
else
	printf 'Skipping Podman home smoke: no accessible Podman engine.\n'
fi

# Exercise the accepted rootless bind strategy against the local application
# image only. These mode-0700 host sources reproduce the private user-owned
# directories reported by the user; the two-container case keeps both mounts
# active together so shared :z labels are tested, not just generated.
if command -v podman >/dev/null 2>&1; then
	if ROOTLESS_STATUS=$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null) && [ "$ROOTLESS_STATUS" = true ]; then
		APP_VERSION=$(sed -n 's/^VERSION=//p' "$REPO_ROOT/sd-vpnc" | head -n 1)
		APP_IMAGE="localhost/sd-vpnc:$APP_VERSION"
		if podman image inspect "$APP_IMAGE" >/dev/null 2>&1; then
			ROOTLESS_SMOKE_ROOT="$TMP_ROOT/rootless-host-mounts"
			ROOTLESS_CONFIG="$ROOTLESS_SMOKE_ROOT/config"
			ROOTLESS_SSH="$ROOTLESS_SMOKE_ROOT/ssh"
			ROOTLESS_WORK="$ROOTLESS_SMOKE_ROOT/work"
			mkdir -p "$ROOTLESS_CONFIG" "$ROOTLESS_SSH" "$ROOTLESS_WORK"
			chmod 700 "$ROOTLESS_SMOKE_ROOT" "$ROOTLESS_CONFIG" "$ROOTLESS_SSH" "$ROOTLESS_WORK"
			printf 'rootless smoke VPN config\n' > "$ROOTLESS_CONFIG/client.ovpn"
			printf 'rootless smoke credentials\n' > "$ROOTLESS_CONFIG/credentials"
			printf 'Host rootless-smoke\n' > "$ROOTLESS_SSH/config"
			chmod 600 "$ROOTLESS_CONFIG/client.ovpn" "$ROOTLESS_CONFIG/credentials" "$ROOTLESS_SSH/config"
			ROOTLESS_UID=$(id -u)
			ROOTLESS_GID=$(id -g)

			podman run --rm --pull=never --userns=keep-id --user "$ROOTLESS_UID:$ROOTLESS_GID" \
				--mount type=tmpfs,destination=/home/dev,tmpfs-mode=0700,U=true,notmpcopyup \
				-v "$ROOTLESS_CONFIG:/config:ro,z" \
				-v "$ROOTLESS_SSH:/home/dev/.ssh:ro,z" \
				-v "$ROOTLESS_WORK:/work:z" \
				-e HOME=/home/dev -e ROOTLESS_UID="$ROOTLESS_UID" -e ROOTLESS_GID="$ROOTLESS_GID" \
				--workdir /home/dev --entrypoint /bin/bash "$APP_IMAGE" -c '
					set -euo pipefail
					. /usr/local/lib/sd-vpnc-home-init.sh
					seed_template="/tmp/sd-vpnc-seed-$$"
					mkdir -m 0700 "$seed_template"
					printf "seeded home entry\\n" > "$seed_template/seed-probe"
					sd_vpnc_seed_home "$seed_template"
					[ "$(stat -c %u:%g /home/dev)" = "$ROOTLESS_UID:$ROOTLESS_GID" ]
					[ "$(stat -c %a /home/dev)" = 700 ]
					[ "$(cat /home/dev/seed-probe)" = "seeded home entry" ]
					[ "$(stat -c %u:%g /home/dev/seed-probe)" = "$ROOTLESS_UID:$ROOTLESS_GID" ]
					[ "$(cat /config/client.ovpn)" = "rootless smoke VPN config" ]
					[ "$(cat /config/credentials)" = "rootless smoke credentials" ]
					[ "$(cat /home/dev/.ssh/config)" = "Host rootless-smoke" ]
					if touch /config/write-probe 2>/dev/null; then exit 1; fi
					if touch /home/dev/.ssh/write-probe 2>/dev/null; then exit 1; fi
					touch /work/single-container-probe
					[ "$(stat -c %u:%g /work/single-container-probe)" = "$ROOTLESS_UID:$ROOTLESS_GID" ]
					rm -rf "$seed_template"
				' || fail "rootless Podman config/SSH/work/home tmpfs smoke failed"
			[ "$(stat -c %u:%g "$ROOTLESS_WORK/single-container-probe")" = "$ROOTLESS_UID:$ROOTLESS_GID" ] || fail "rootless Podman /work file has unexpected host ownership"

			ROOTLESS_OVERLAP_ONE="sd-vpnc-overlap-one-$$"
			ROOTLESS_OVERLAP_TWO="sd-vpnc-overlap-two-$$"
			PODMAN_SMOKE_NAMES="$PODMAN_SMOKE_NAMES $ROOTLESS_OVERLAP_ONE $ROOTLESS_OVERLAP_TWO"
			for container_name in "$ROOTLESS_OVERLAP_ONE" "$ROOTLESS_OVERLAP_TWO"; do
				podman run --pull=never --detach --name "$container_name" \
					--userns=keep-id --user "$ROOTLESS_UID:$ROOTLESS_GID" \
					--mount type=tmpfs,destination=/home/dev,tmpfs-mode=0700,U=true,notmpcopyup \
					-v "$ROOTLESS_CONFIG:/config:ro,z" \
					-v "$ROOTLESS_SSH:/home/dev/.ssh:ro,z" \
					-v "$ROOTLESS_WORK:/work:z" \
					-e HOME=/home/dev --workdir /home/dev --entrypoint /bin/bash "$APP_IMAGE" -c 'sleep 300' \
					>/dev/null || fail "could not start overlapping rootless Podman smoke container"
			done
			check_overlap_container() {
				container_name=$1
				marker=$2
				podman exec --user "$ROOTLESS_UID:$ROOTLESS_GID" "$container_name" /bin/bash -ceu '
					[ "$(cat /config/client.ovpn)" = "rootless smoke VPN config" ]
					[ "$(cat /config/credentials)" = "rootless smoke credentials" ]
					[ "$(cat /home/dev/.ssh/config)" = "Host rootless-smoke" ]
					if touch /config/write-probe 2>/dev/null; then exit 1; fi
					if touch /home/dev/.ssh/write-probe 2>/dev/null; then exit 1; fi
					touch "/work/$1"
					[ "$(stat -c %u:%g "/work/$1")" = "$2:$3" ]
				' overlap-smoke "$marker" "$ROOTLESS_UID" "$ROOTLESS_GID" || fail "overlapping rootless Podman container could not use shared :z mounts"
			}
			check_overlap_container "$ROOTLESS_OVERLAP_ONE" overlap-one
			check_overlap_container "$ROOTLESS_OVERLAP_TWO" overlap-two
			for container_name in "$ROOTLESS_OVERLAP_ONE" "$ROOTLESS_OVERLAP_TWO"; do
				[ "$(podman container inspect --format '{{.State.Running}}' "$container_name")" = true ] || fail "overlapping rootless Podman smoke container exited early"
			done
			[ "$(stat -c %u:%g "$ROOTLESS_WORK/overlap-one")" = "$ROOTLESS_UID:$ROOTLESS_GID" ] || fail "first overlapping /work write has unexpected host ownership"
			[ "$(stat -c %u:%g "$ROOTLESS_WORK/overlap-two")" = "$ROOTLESS_UID:$ROOTLESS_GID" ] || fail "second overlapping /work write has unexpected host ownership"
			if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null || true)" = Enforcing ]; then
				printf 'Rootless Podman overlapping shared-mount smoke passed with SELinux Enforcing.\n'
			else
				printf 'Rootless Podman overlapping shared-mount smoke passed; SELinux Enforcing-specific validation unavailable.\n'
			fi
		else
			printf 'Skipping rootless Podman bind smokes: local app image %s is unavailable (no pull attempted).\n' "$APP_IMAGE"
		fi
	else
		printf 'Skipping rootless Podman bind smokes: no rootless Podman engine.\n'
	fi
else
	printf 'Skipping rootless Podman bind smokes: Podman is unavailable.\n'
fi
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
	DOCKER_SMOKE_IMAGE=${SD_VPNC_DOCKER_SMOKE_IMAGE:-busybox:latest}
	if docker image inspect "$DOCKER_SMOKE_IMAGE" >/dev/null 2>&1; then
		docker run --rm --pull=never --user 12345:6789 \
			--tmpfs /home/dev:rw,uid=12345,gid=6789,mode=0700 \
			--entrypoint sh "$DOCKER_SMOKE_IMAGE" -c '
				[ "$(stat -c %u:%g /home/dev)" = 12345:6789 ]
				[ "$(stat -c %a /home/dev)" = 700 ]
				touch /home/dev/.cache-write
				mkdir -p /home/dev/.local/state /home/dev/.atuin/data
				touch /home/dev/.local/state/history /home/dev/.atuin/data/db
			' || fail "Docker tmpfs UID:GID smoke test failed"
	else
		printf 'Skipping Docker tmpfs smoke: daemon available but image %s is not local (no pull attempted).\n' "$DOCKER_SMOKE_IMAGE"
	fi
else
	printf 'Skipping Docker tmpfs smoke: no accessible Docker daemon.\n'
fi

printf 'All dotfiles image-build and runtime-home/shell tests passed.\n'
