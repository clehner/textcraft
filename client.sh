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

echo "Connecting to server"
exec 3>"$1"
echo connected

server_write() {
	echo $player_id $@ >&3
}

# Read commands from server
{
	client_sock=$(mktemp -u)
	mkfifo "$client_sock"
	trap "rm $client_sock" INT
	while read -r cmd data
	do
		echo got server cmd "$cmd" "$data"
	done <"$client_sock"
	echo "Connection to server lost"
	exit
} &
trap "kill -TERM $!" EXIT INT

YELLOW="\e[1;33m"
RESET="\e[0m"
echo -e hi $YELLOW asd $RESET

player_move() {
	server_write move "$1" "$2"
	echo move! $1 $2
	case "$1 $2" in
		"-1 0")
			#echo -e "\e[<3>Aok"
			;;
	esac
}

stty -echo
fix_color() {
	stty echo
	exit
}
trap fix_color INT TERM

while read -rn 1 char
do
	case "$char" in
		j) player_move 1 0;;
		k) player_move -1 0;;
		h) player_move 0 -1;;
		l) player_move 0 1;;
	esac
done
