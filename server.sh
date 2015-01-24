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

cleanup() {
	echo Closing client pipes
	write_clients conn shutdown
}
trap cleanup 0

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

# New client connected
handle_new() {
	local client_id="$1"
	local sock="$2"

	# Tell other players about new client
	write_clients join $client_id

	client_socks[$client_id]=$sock
	write_client $client_id conn connected
}

# Client quit
handle_quit() {
	local client_id="$1"
	unset client_socks[$client_id]
	write_clients quit $client_id
}

# Player wants to move
handle_move() {
	local client_id="$1"
	local dx="$2"
	local dy="$3"
	write_client $client_id moved $@
}

# Player sent chat
handle_chat() {
	write_clients chat $@
}

# Client sent unknown command
handle_unknown() {
	local client_id="$1"; shift
	echo "Unknown command from $client_id: $@"
}

# Handle command sent by client
handle_user_command() {
	# command format: client_id cmd args...
	local client_id="$1"
	local cmd="$2"
	set -- "$client_id" "${@:3}"
	case "$cmd" in
		new) handle_new "$@";;
		move) handle_move "$@";;
		chat) handle_chat "$@";;
		quit) handle_quit "$@";;
		*) handle_unknown "$@";;
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
