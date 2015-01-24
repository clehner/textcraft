#!/bin/bash
# client - connect to the remote server

test $# -ge 2 || {
	echo "Usage: ./client <host> <port>"
	exit 1
}

client_args="$@"
player_id=

# Connect to server
exec 3<> /dev/tcp/$1/$2 || {
	echo "Unable to connect to server"
	exit 1
}

YELLOW="\e[1;33m"
RESET="\e[0m"

parent_pid=$$

exit_child() {
	echo
	kill $parent_pid
	exit
}

# Handle connection from backend to server
handle_connection_status() {
	case "$1" in
		connecting) echo 'Connecting to server';;
		connected) echo 'Connection established';;
		shutdown) echo 'Server shut down'
			exit_child;;
	esac
}

# Handle chat from other user
handle_chat() {
	local sender_id="$1"; shift
	echo "<$sender_id> $@"
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

server_write() {
	echo $@ >&3
}

player_move() {
	server_write move "$1" "$2"
	case "$1 $2" in
		"-1 0")
			#echo -e "\e[<3>Aok"
			;;
	esac
}

player_send_chat() {
	[[ -n "$@" ]] &&
		server_write chat $@
}

user_chat() {
	stty echo
	echo chat_start
	read -r msg
	echo chat_send $msg
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
	if confirm 'Really restart? [Y/n]'
	then
		# close socket
		kill $child_pid
		# restart the program
		exec "$0" $client_args
	fi
}

confirm_quit() {
	if confirm 'Really quit? [Y/n]'
	then
		kill $child_pid
		echo
		exit
	fi
}

{
	# Read commands from server
	{
		sed -u 's/^/s_/' <&3
		exit_child
	} &
	child_pid=$!

	# Read from user's keyboard
	while read -rn 1 char
	do
		case "$char" in
			j) echo move 1 0;;
			k) echo move -1 0;;
			h) echo move 0 -1;;
			l) echo move 0 1;;
			t) user_chat;;
			r) echo restart;;
			q) echo quit;;
		esac
	done

# Multiplex server and user input so that all state is handled in one subshell.
} | while read -r cmd args
do
	set -- "$args"
	case "$cmd" in 
		# server commands
		s_chat) handle_chat $@;;
		s_conn) handle_connection_status "$1";;
		s_join) handle_join "$@";;
		s_quit) handle_quit "$@";;
		s_moved) echo move! $1 $2;;
		s_id) player_id="$@";;
		s_*) echo "<server> $cmd $@";;

		# client commands
		move) player_move "$@";;
		chat_start) echo -n "<$player_id> ";;
		chat_send) player_send_chat $@;;
		quit) confirm_quit;;
		restart) confirm_restart;;
		*) echo unknown $cmd $args
	esac
done
