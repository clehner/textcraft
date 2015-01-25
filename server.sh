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

version=0.0.1
chunk_width=11
chunk_height=5

# pipes to client sockets
declare -A client_socks

# player positions
declare -A players_x
declare -A players_y

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

# Send data to all clients except one
write_clients_except() {
	local client_sock_skip="${client_socks[$1]}"; shift
	local client_sock
	for client_sock in "${client_socks[@]}"
	do [[ "$client_sock" != "$client_sock_skip" ]] &&
		echo "$@" >> "$client_sock"
	done
}

# New client connected
handle_new() {
	local client_id="$1"
	local sock="$2"
	local x=0
	local y=0

	# Tell other players about new client
	write_clients join $client_id

	client_socks[$client_id]=$sock
	players_x[$client_id]=$x
	players_y[$client_id]=$y
	write_client $client_id conn connected
	write_client $client_id id $client_id
	write_client $client_id info $version \
		$chunk_width $chunk_height
	echo join "(${#client_socks[@]})" $client_id $x $y
}

# Client quit
handle_quit() {
	local client_id="$1"
	unset client_socks[$client_id]
	unset players_x[$client_id]
	unset players_y[$client_id]
	write_clients quit $client_id
	echo quit "(${#client_socks[@]})" $client_id
}

# Player wants to move
handle_move() {
	local client_id="$1"
	local dx="$2"
	local dy="$3"

	# update position
	((x=players_x[$client_id]=players_x[$client_id]+dx))
	((y=players_y[$client_id]=players_y[$client_id]+dy))

	# TODO: verify that move is valid
	echo client $client_id moved to $x $y
	write_clients pos $client_id $x $y
}

# Player sent chat
handle_chat() {
	write_clients_except "$1" chat $@
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
