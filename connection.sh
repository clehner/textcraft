#!/bin/bash
# client.sh - Play the game

test -n "$1" || {
	echo "Usage: ./connection.sh <server_sock>"
	exit 1
}

test -p "$1" || {
	echo "'$1' is not a named pipe"
	exit 1
}

player_id=p$$

echo conn connecting
exec 3>"$1"

# Read commands from server
client_sock=$(mktemp -u)
mkfifo "$client_sock"
# Notify server that we are here
echo $player_id new $client_sock >&3
# Read responses from server
{
	while exec 4<"$client_sock"
	do sed -u '/^conn shutdown/q' <&4
	done
	echo conn disconnected
	rm "$client_sock"
} &
trap "echo ok; rm $client_sock; kill -9 $!; exit" 0 INT

# Transfer user commands to server
{
	while read cmd
	do echo $player_id $cmd
	done
	echo $player_id quit
	echo done >>/tmp/blahasdf
} >&3
