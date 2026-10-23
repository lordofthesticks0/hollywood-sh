#!/usr/bin/env bash
# Hollywood-style terminal spectacle in one Bash script.
# Inspired by hollywood (https://github.com/dustinkirkland/hollywood)
# Original Hollywood project by Dustin Kirkland, licensed Apache-2.0.

set -u

PROGRAM=${0##*/}
SCRIPT_PATH=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")
SPLITS=6
DELAY=10
MODE=main
WORKER=0
SCENE_WINDOW=
SCENE_SESSION=
ANCHOR_PANE=
ANCHOR_WIDGET=0
DEDICATED=0
ESC=$'\033'

usage() {
	cat <<EOF
Usage: $PROGRAM [-s|--splits COUNT] [-d|--delay SECONDS]

Fill a tmux window with independently scrolling technobabble feeds.

  -s, --splits COUNT    Number of panes to create (1-16, default: 6)
  -d, --delay SECONDS   Seconds between random rebuilds (default: 10)
  -h, --help            Show this help

Press Ctrl-C to quit. Requires Bash and tmux. Optional utilities fall back to
other live system sources. Network graphs use bmon when it is installed.
EOF
}

fail() {
	printf '%s: %s\n' "$PROGRAM" "$1" >&2
	exit 2
}

while (($#)); do
	case $1 in
		-s|--splits)
			(($# >= 2)) || fail "missing value for $1"
			SPLITS=$2
			shift 2
			;;
		-d|--delay)
			(($# >= 2)) || fail "missing value for $1"
			DELAY=$2
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		--bootstrap)
			MODE=bootstrap
			shift
			;;
		--manager)
			MODE=manager
			shift
			;;
		--dedicated)
			DEDICATED=1
			shift
			;;
		--worker)
			(($# >= 2)) || fail "missing worker number"
			MODE=worker
			WORKER=$2
			shift 2
			;;
		--scene-window)
			(($# >= 2)) || fail "missing scene window id"
			SCENE_WINDOW=$2
			shift 2
			;;
		--scene-session)
			(($# >= 2)) || fail "missing scene session id"
			SCENE_SESSION=$2
			shift 2
			;;
		--anchor-pane)
			(($# >= 2)) || fail "missing anchor pane id"
			ANCHOR_PANE=$2
			shift 2
			;;
		--anchor-widget)
			(($# >= 2)) || fail "missing anchor widget number"
			ANCHOR_WIDGET=$2
			shift 2
			;;
		*) fail "unknown option: $1 (try --help)" ;;
	esac
done

if [[ $MODE != worker ]]; then
	[[ $SPLITS =~ ^[0-9]+$ ]] || fail "splits must be an integer from 1 to 16"
	[[ $DELAY =~ ^[0-9]+$ ]] || fail "delay must be a positive integer"
	SPLITS=$((10#$SPLITS))
	DELAY=$((10#$DELAY))
	((SPLITS >= 1 && SPLITS <= 16)) || fail "splits must be an integer from 1 to 16"
	((DELAY > 0)) || fail "delay must be a positive integer"
fi

widgets=("PROCESS VIEW" "KERNEL LOG" "HEX DUMP" "SOURCE CODE" "NET DEV COUNTERS" "SSH KEYS" "ROUTES" "SOCKETS" "DISK I/O" "SERVICES" "CMATRIX" "ATOP" "TREE /" "BMON" "MAN PAGES" "FILE METADATA")

worker_header() {
	local widget=$1
	printf '%s[2J%s[H%s[1;36m' "$ESC" "$ESC" "$ESC"
	printf ' HOLLYWOOD / %s / %s\n' "${widgets[$widget]}" "$(date '+%H:%M:%S')"
	printf '%s[0m' "$ESC"
}

source_file() {
	find /usr /opt -readable -type f -size +0c \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.h' -o -name '*.java' -o -name '*.js' -o -name '*.py' -o -name '*.sh' -o -name '*.rs' \) -print 2>/dev/null | shuf -n 1
}

binary_file() {
	find /usr/bin /usr/sbin -type f -executable -print 2>/dev/null | shuf -n 1
}

run_worker() {
	local widget=$1 delay file iface page
	[[ $widget =~ ^[0-9]+$ ]] && ((widget >= 0 && widget < ${#widgets[@]})) || exit 2
	worker_cleanup() {
		if [[ -n $SCENE_WINDOW ]]; then
			if ((DEDICATED)) && [[ -n $SCENE_SESSION ]]; then
				tmux kill-session -t "$SCENE_SESSION" 2>/dev/null || true
			else
				tmux kill-window -t "$SCENE_WINDOW" 2>/dev/null || true
			fi
		fi
		exit 0
	}
	trap worker_cleanup INT

	case $widget in
		0)
			if command -v htop >/dev/null 2>&1; then htop; fi
			top -d 2
			;;
		1)
			if command -v journalctl >/dev/null 2>&1; then journalctl -kf --no-pager; else dmesg -w; fi
			for file in /var/log/syslog /var/log/kern.log /var/log/messages; do
				if [[ -r $file ]]; then tail -n 100 -F "$file"; exit; fi
			done
			printf 'No readable live system log source found.\n'
			tail -f /dev/null
			;;
		2)
			while :; do
				file=$(binary_file)
				worker_header "$widget"
				if [[ -n $file ]]; then
					printf 'FILE: %s\n\n' "$file"
					if command -v hexdump >/dev/null 2>&1; then head -c 1024 "$file" | hexdump -C; else head -c 1024 "$file" | od -Ax -tx1z; fi
				else
					printf 'No executable files found under /usr/bin or /usr/sbin.\n'
				fi
				sleep 2
			done
			;;
		3)
			while :; do
				file=$(source_file)
				worker_header "$widget"
				if [[ -n $file ]]; then
					printf 'FILE: %s\n\n' "$file"
					if command -v batcat >/dev/null 2>&1; then batcat --color=always --paging=never --style=plain "$file" | head -n 100
					elif command -v bat >/dev/null 2>&1; then bat --color=always --paging=never --style=plain "$file" | head -n 100
					else sed -n '1,100p' "$file"; fi
				else
					printf 'No readable source files found under /usr or /opt.\n'
				fi
				sleep 2
			done
			;;
		4)
			watch -n 1 cat /proc/net/dev
			;;
		5)
			shopt -s nullglob
			while :; do
				worker_header "$widget"
				local keys=("$HOME"/.ssh/*.pub)
				if ((${#keys[@]})); then
					for file in "${keys[@]}"; do ssh-keygen -lvf "$file" 2>&1; done
				else
					printf 'No local SSH public keys in %s/.ssh\n' "$HOME"
					if command -v ssh-add >/dev/null 2>&1; then ssh-add -l 2>&1; fi
				fi
				sleep 3
			done
			;;
		6)
			if command -v ip >/dev/null 2>&1; then watch -n 2 'ip route show; ip -6 route show'
			elif command -v netstat >/dev/null 2>&1; then watch -n 2 'netstat -rn'
			else printf 'Neither ip nor netstat is installed.\n'; tail -f /dev/null; fi
			;;
		7)
			if command -v ss >/dev/null 2>&1; then watch -n 2 ss -tunap
			elif command -v netstat >/dev/null 2>&1; then watch -n 2 netstat -tunap
			else printf 'Neither ss nor netstat is installed.\n'; tail -f /dev/null; fi
			;;
		8)
			if command -v iostat >/dev/null 2>&1; then iostat -xz 2
			elif command -v vmstat >/dev/null 2>&1; then vmstat 2
			else watch -n 2 df -h; fi
			;;
		9)
			if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then watch -n 5 'systemctl --no-pager --type=service --state=running'
			else watch -n 2 'ps -eo pid,stat,%cpu,%mem,comm --sort=-%cpu | head -n 30'; fi
			;;
		10)
			if command -v cmatrix >/dev/null 2>&1; then while cmatrix -b; do sleep 0.2; done; fi
			watch -n 1 cat /proc/interrupts
			;;
		11)
			if command -v atop >/dev/null 2>&1; then while atop; do sleep 0.2; done
			else top -d 2; fi
			;;
		12)
			if command -v tree >/dev/null 2>&1; then
				while :; do worker_header "$widget"; tree -L 3 / 2>/dev/null | head -n 120; sleep 2; done
			else
				while :; do worker_header "$widget"; find / -maxdepth 3 -print 2>/dev/null | head -n 120; sleep 2; done
			fi
			;;
		13)
			if command -v bmon >/dev/null 2>&1; then while bmon --show-all; do sleep 0.2; done; fi
			watch -n 1 cat /proc/net/dev
			;;
		14)
			while :; do
				file=$(find /usr/share/man -type f \( -name '*.1' -o -name '*.1.gz' \) -print 2>/dev/null | shuf -n 1)
				worker_header "$widget"
				if [[ -n $file ]] && command -v man >/dev/null 2>&1; then
					page=${file##*/}; page=${page%.gz}; page=${page%.1}; man "$page" | head -n 100
				else printf 'No readable section 1 manual pages found.\n'; fi
				sleep 2
			done
			;;
		15)
			while :; do
				file=$(find /sys /dev -maxdepth 4 -print 2>/dev/null | shuf -n 1)
				worker_header "$widget"
				if [[ -n $file ]]; then stat "$file"; else printf 'No paths found under /sys or /dev.\n'; fi
				sleep 1
			done
			;;
	esac
}

if [[ $MODE == worker ]]; then
	run_worker "$WORKER"
	exit 0
fi

command -v tmux >/dev/null 2>&1 || fail "tmux is required; install tmux and run again"
if [[ $MODE != manager && ! -t 1 ]]; then
	fail "run this script in an interactive terminal"
fi

if [[ $MODE == main && -z ${TMUX:-} ]]; then
	printf -v quoted_script '%q' "$SCRIPT_PATH"
	bootstrap_command="exec $quoted_script --bootstrap --dedicated --splits $SPLITS --delay $DELAY"
	exec tmux new-session -s hollywood "$bootstrap_command"
fi

if [[ $MODE == main ]]; then
	printf -v quoted_script '%q' "$SCRIPT_PATH"
	bootstrap_command="exec $quoted_script --bootstrap --splits $SPLITS --delay $DELAY"
	tmux new-window -n hollywood "$bootstrap_command" || fail "could not create a tmux window"
	exit 0
fi

if [[ $MODE == bootstrap ]]; then
	SCENE_WINDOW=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}') || fail "could not identify the tmux window"
	SCENE_SESSION=$(tmux display-message -p -t "$TMUX_PANE" '#{session_id}') || fail "could not identify the tmux session"
	ANCHOR_PANE=$TMUX_PANE
	ANCHOR_WIDGET=$((RANDOM % ${#widgets[@]}))
	printf -v quoted_script '%q' "$SCRIPT_PATH"
	manager_command="exec $quoted_script --manager --scene-window $SCENE_WINDOW --scene-session $SCENE_SESSION --anchor-pane $ANCHOR_PANE --anchor-widget $ANCHOR_WIDGET --splits $SPLITS --delay $DELAY"
	if ((DEDICATED)); then manager_command+=" --dedicated"; fi
	tmux run-shell -b "$manager_command" || fail "could not start the pane manager"
	worker_args=(--worker "$ANCHOR_WIDGET" --scene-window "$SCENE_WINDOW" --scene-session "$SCENE_SESSION")
	if ((DEDICATED)); then worker_args+=(--dedicated); fi
	exec nice -n 19 "$SCRIPT_PATH" "${worker_args[@]}"
fi

if [[ $MODE == manager ]]; then
	build_scene() {
		local widget worker_cmd pane direction i target
		widget=$ANCHOR_WIDGET
		printf -v worker_cmd 'exec nice -n 19 %q --worker %d --scene-window %q --scene-session %q' "$SCRIPT_PATH" "$widget" "$SCENE_WINDOW" "$SCENE_SESSION"
		if ((DEDICATED)); then worker_cmd+=' --dedicated'; fi
		if ((initialized)); then
			tmux kill-pane -a -t "$ANCHOR_PANE" 2>/dev/null || true
			widget=$((RANDOM % ${#widgets[@]}))
			printf -v worker_cmd 'exec nice -n 19 %q --worker %d --scene-window %q --scene-session %q' "$SCRIPT_PATH" "$widget" "$SCENE_WINDOW" "$SCENE_SESSION"
			if ((DEDICATED)); then worker_cmd+=' --dedicated'; fi
			tmux respawn-pane -k -t "$ANCHOR_PANE" "$worker_cmd" >/dev/null 2>&1 || return 1
		fi
		initialized=1
		mapfile -t panes < <(tmux list-panes -t "$SCENE_WINDOW" -F '#{pane_id}')
		for ((i=${#panes[@]}; i<SPLITS; i++)); do
			((${#panes[@]})) || break
			target=${panes[$((RANDOM % ${#panes[@]}))]}
			direction='-h'
			((RANDOM % 2)) && direction='-v'
			widget=$((RANDOM % ${#widgets[@]}))
			printf -v worker_cmd 'exec nice -n 19 %q --worker %d --scene-window %q --scene-session %q' "$SCRIPT_PATH" "$widget" "$SCENE_WINDOW" "$SCENE_SESSION"
			if ((DEDICATED)); then worker_cmd+=' --dedicated'; fi
			pane=$(tmux split-window -d "$direction" -P -F '#{pane_id}' -t "$target" "$worker_cmd" 2>/dev/null) || break
			panes+=("$pane")
		done
	}
	initialized=0
	tmux set-option -w -t "$SCENE_WINDOW" automatic-rename off 2>/dev/null || true
	tmux set-option -w -t "$SCENE_WINDOW" pane-border-style 'fg=colour238' 2>/dev/null || true
	tmux set-option -w -t "$SCENE_WINDOW" pane-active-border-style 'fg=colour45' 2>/dev/null || true
	tmux rename-window -t "$SCENE_WINDOW" hollywood 2>/dev/null || true
	while :; do
		tmux display-message -p -t "$SCENE_WINDOW" '#{window_id}' >/dev/null 2>&1 || exit 0
		build_scene || exit 0
		remaining=$DELAY
		while ((remaining > 0)); do
			sleep 1
			tmux display-message -p -t "$SCENE_WINDOW" '#{window_id}' >/dev/null 2>&1 || exit 0
			remaining=$((remaining - 1))
		done
	done
fi
