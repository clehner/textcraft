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

declare -a client_socks

# Send data to a client
write_client() {
	local client_id="$1"
	shift
	echo $@ >> "${client_socks[$client_id]}"
}

# Read from server socket
while exec <"$1"
do
	# Read commands from clients
	while read -r client_id cmd arg1 arg2 args
	do
		case "$cmd" in
			new)
				echo new player $client_id: $arg1
				client_socks[$client_id]=$arg1
				write_client $client_id welcome
				;;
			move)
				echo move player $client_id: $arg1 $arg2
				write_client $client_id moved $args
				;;
			*)
				echo player $client_id: $cmd
				write_client $client_id unknown $cmd $arg1 $args
				;;
		esac
	done
done
