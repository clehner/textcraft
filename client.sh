#!/bin/bash
# client - connect to the remote server

test $# -ge 2 || {
	echo "Usage: ./client <host> <port>"
	exit 1
}

client_args="$@"

# Connect to server
exec 3<> /dev/tcp/$1/$2 || {
	echo "Unable to connect to server"
	exit 1
}

YELLOW="\e[1;33m"
RESET="\e[0m"

PID=$$

# Handle connection from backend to server
handle_connection_status() {
	case "$1" in
		connecting) echo 'Connecting to server';;
		connected) echo 'Connection established';;
		shutdown) echo 'Server shut down'
			echo
			# kill parent and subshell
			kill $PID
			exit;;
	esac
}

# Handle chat from other user
handle_chat() {
	local sender_id="$1"; shift
	echo "<$sender_id>: $@"
}

# A user joined
handle_join() {
	local sender_id="$1"
	echo "$sender_id joined the game"
}

# A user quit
handle_quit() {
	local sender_id="$1"
	echo "$sender_id left the game"
}

# Handle command sent by server
handle_server_command() {
	local cmd="$1"; shift
	case "$cmd" in
		conn) handle_connection_status "$1";;
		chat) handle_chat "$@";;
		join) handle_join "$@";;
		quit) handle_quit "$@";;
		*) echo from server: $cmd $@;;
	esac
}

# Read commands from server
{
	while read -r args
	do handle_server_command $args
	done <&3
} &

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
}
trap fix_color 0
trap 'exit' TERM

confirm() {
	echo $@
	read -rn1 resp && case $resp in y|Y|'') return 0; esac
	return 1
}

confirm_restart() {
	confirm 'Really restart? [Y/n]' &&
		exec "$0" $client_args
}

confirm_quit() {
	confirm 'Really quit? [Y/n]' && exit
}

# Read from user's keyboard
while read -rn 1 char
do
	case "$char" in
		j) player_move 1 0;;
		k) player_move -1 0;;
		h) player_move 0 -1;;
		l) player_move 0 1;;
		t) player_chat;;
		r) confirm_restart;;
		q) confirm_quit;;
	esac
done
