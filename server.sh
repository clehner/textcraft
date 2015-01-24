#!/bin/sh
# Game server

test -n "$1" || {
	echo "Usage: ./client.sh <server_sock>"
	exit 1
}

test -p "$1" || {
	echo "'$1' is not a named pipe"
	exit 1
}

# Read from server socket
while exec <"$1"
do
	# Read commands from clients
	while read -r client_id cmd args
	do
		case "$cmd" in
			new)
				echo new player $client_id
				;;
			move)
				echo move player $client_id: $args
				;;
			*)
				echo player $client_id: $cmd
				;;
		esac
	done
done
