#!/usr/bin/env bash

# Collect read-only CRC, libvirt, runner resource, and API connectivity state
# while the GitHub-hosted runner and CRC VM are still available.

set -u

API_HOST="${API_HOST:-api.crc.testing}"
API_PORT="${API_PORT:-6443}"

section() {
	printf '\n=== %s ===\n' "$1"
}

run_diagnostic() {
	printf '\n$'
	printf ' %q' "$@"
	printf '\n'
	if command -v timeout >/dev/null 2>&1; then
		timeout 15s "$@" 2>&1 || printf 'Diagnostic command failed or timed out (exit %s).\n' "$?"
	else
		"$@" 2>&1 || printf 'Diagnostic command failed (exit %s).\n' "$?"
	fi
}

section "CRC status"
if command -v crc >/dev/null 2>&1; then
	run_diagnostic crc status
	run_diagnostic crc version
else
	echo "crc command is not installed or is not on PATH."
fi

section "VM and libvirt status"
if command -v virsh >/dev/null 2>&1; then
	run_diagnostic virsh list --all
	run_diagnostic virsh dominfo crc
else
	echo "virsh command is not installed or is not on PATH."
fi

if command -v systemctl >/dev/null 2>&1; then
	run_diagnostic systemctl status libvirtd --no-pager
	run_diagnostic systemctl status virtqemud --no-pager
fi
if command -v journalctl >/dev/null 2>&1; then
	run_diagnostic journalctl -u libvirtd -u virtqemud --since "-20 minutes" -n 100 --no-pager
fi

section "Runner resources"
run_diagnostic free -h
run_diagnostic swapon --show
run_diagnostic df -hT / /home/runner
run_diagnostic df -i / /home/runner
run_diagnostic uptime

section "API DNS and reachability"
echo "API endpoint: ${API_HOST}:${API_PORT}"
if command -v getent >/dev/null 2>&1; then
	run_diagnostic getent ahosts "$API_HOST"
fi
if command -v curl >/dev/null 2>&1; then
	run_diagnostic curl --silent --show-error --insecure --connect-timeout 5 --max-time 10 \
		--output /dev/null --write-out 'HTTP %{http_code}; remote %{remote_ip}; connect %{time_connect}s\n' \
		"https://${API_HOST}:${API_PORT}/readyz"
fi
if command -v oc >/dev/null 2>&1; then
	run_diagnostic oc get nodes -o wide
fi

section "Kernel OOM messages"
if command -v dmesg >/dev/null 2>&1; then
	oom_messages=$(dmesg --ctime 2>/dev/null | grep -Ei 'out of memory|oom-kill|killed process' | tail -30 || true)
	if [[ -n "$oom_messages" ]]; then
		printf '%s\n' "$oom_messages"
	else
		echo "No readable OOM messages found."
	fi
fi

exit 0
