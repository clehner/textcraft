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
chunk_width=10
chunk_height=5
chunks_dir=data/chunks

# pipes to client sockets
declare -A client_socks

# player positions
declare -A players_x
declare -A players_y
declare -A players_direction

cleanup() {
	echo Closing client pipes
	write_clients conn shutdown
}
trap cleanup 0

# Send data to a client
write_client() {
	local client_id="$1"
	shift
	echo "$@" >> ${client_socks[$client_id]}
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

# Send a client a chunk
send_chunk() {
	# TODO: make sure client can see chunk
	local chunk_file="$chunks_dir/$2.txt"
	if [[ -s "$chunk_file" ]]
	then
		local chunk="$(tr '\n ' '%$' <$chunk_file)"
		write_client $1 chunk $2 "$chunk"
	fi
}

# New client connected
handle_new() {
	local client_id="$1"
	local sock="$2"
	local x=0
	local y=0
	local direction=up

	# Tell other players about new client
	write_clients join $client_id

	client_socks[$client_id]=$sock
	players_x[$client_id]=$x
	players_y[$client_id]=$y
	players_direction[$client_id]=$direction

	write_client $client_id conn connected
	write_client $client_id player_info $client_id $x $y $direction
	write_client $client_id info $version \
		$chunk_width $chunk_height
	
	# tell player about other players
	for player in "${!client_socks[@]}"
	do write_client $client_id pos $player ${players_x[$player]} ${players_y[$player]} ${players_direction[$player]}
		#${players_{x,y,direction}[$player]}
	done

	echo join "(${#client_socks[@]})" $client_id $x $y
}

# Client quit
handle_quit() {
	local client_id="$1"
	unset client_socks[$client_id]
	unset players_x[$client_id]
	unset players_y[$client_id]
	unset players_direction[$client_id]
	write_clients quit $client_id
	echo quit "(${#client_socks[@]})" $client_id
}

# Player wants to move in a direction
handle_move() {
	local client_id="$1"
	local direction="$2"
	local dx=
	local dy=0

	# TODO: verify that move is valid

	if [[ "$direction" == "${players_direction[$client_id]}" ]]
	then
		# move in same direction
		case $direction in
			up) ((players_y[$client_id]--));;
			down) ((players_y[$client_id]++));;
			left) ((players_x[$client_id]--));;
			right) ((players_x[$client_id]++));;
		esac
	else
		# change direction
		players_direction[$client_id]=$direction
	fi

	write_clients pos $client_id \
		${players_x[$client_id]} ${players_y[$client_id]} $direction
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

# Client asked for chunks
handle_req_chunks() {
	local client_id="$1"; shift
	# If there are multiple chunks, tell the client
	# not to redraw until we send them all.
	[[ $# -gt 1 ]] && write_client $client_id pause
	for chunk
	do send_chunk "$client_id" "$chunk"
	done
	[[ $# -gt 1 ]] && write_client $client_id resume
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
		req_chunks) handle_req_chunks $@;;
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
