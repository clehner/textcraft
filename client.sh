#!/bin/bash
# client.sh - Play the game

test -n "$1" || {
	echo "Usage: ./client.sh <server_sock>"
	exit 1
}

test -p "$1" || {
	echo "'$1' is not a named pipe"
	exit 1
}

player_id=p$$

echo conn connecting
exec 3>"$1"
echo conn connected

# Read commands from server
{
	client_sock=$(mktemp -u)
	mkfifo "$client_sock"
	trap "rm $client_sock" INT
	# Notify server that we are here
	echo "$player_id" "$client_sock" >&3
	# Read responses from server
	cat "$client_sock"
	echo conn disconnected
	exit
} &
trap "kill -TERM $!" EXIT INT

# Transfer user commands to server
while read cmd
do echo "$player_id" "$cmd"
done >&3
