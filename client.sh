#!/bin/bash
# client - connect to the remote server

test $# -ge 2 || {
	echo "Usage: ./client <host> <port>"
	exit 1
}

stty -echo
YELLOW="\e[1;33m"
RESET="\e[0m"

# Connect to server
exec 3<> /dev/tcp/$1/$2 || {
	echo "Unable to connect to server"
	exit 1
}

# Read commands from server
{
while read -r cmd data
do
	echo from server: $cmd $data
done <&3
echo done reading from server
}&

server_write() {
	echo $player_id $@ >&3
}

player_move() {
	server_write move "$1" "$2"
	echo move! $1 $2
	case "$1 $2" in
		"-1 0")
			#echo -e "\e[<3>Aok"
			;;
	esac
}

player_chat() {
	stty echo
	echo -n 'chat: '
	read -r msg
	server_write chat "$msg"
	stty -echo
}

stty -echo
fix_color() {
	stty echo
	exit
}
trap fix_color 0

# Read from user's keyboard
while read -rn 1 char
do
	case "$char" in
		j) player_move 1 0;;
		k) player_move -1 0;;
		h) player_move 0 -1;;
		l) player_move 0 1;;
		t) player_chat;;
	esac
done
