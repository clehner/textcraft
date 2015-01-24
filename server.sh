#!/bin/bash
# Game server

test -n "$1" || {
	echo "Usage: ./client.sh <server_sock>"
	exit 1
}

test -p "$1" || {
	echo "'$1' is not a named pipe"
	exit 1
}

declare -A client_socks

# Send data to a client
write_client() {
	local client_id="$1"
	shift
	echo $@ >> ${client_socks[$client_id]}
}

# Send data to all clients
write_clients() {
	local client_sock
	for client_sock in "${client_socks[@]}"
	do echo "$@" >> "$client_sock"
	done
}

# Handle command sent by client
handle_user_command() {
	local client_id="$1"; shift
	local cmd="$1"; shift
	echo $client_id $cmd $@
	case "$cmd" in
		new)
			client_socks[$client_id]=$1
			write_client $client_id welcome
			;;
		move)
			write_client $client_id moved $@
			;;
		chat)
			write_clients chat $client_id $@
			;;
		*)
			write_client $client_id unknown $cmd
			;;
	esac
}

# Read from server socket
while exec <"$1"
do
	# Read commands from clients
	while read -r args
	do handle_user_command $args
	done
done
