#!/bin/bash
# client - connect to the remote server

test $# -ge 2 || {
	echo "Usage: ./client <host> <port>"
	exit 1
}

# Connect to server
exec 3<> /dev/tcp/$1/$2 || {
	echo "Unable to connect to server"
	exit 1
}

YELLOW="\e[1;33m"
RESET="\e[0m"

player_id=
parent_pid=$$

# player positions
declare -A players_x
declare -A players_y

exit_child() {
	kill -TERM $parent_pid
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
	handle_position $@
	echo "$sender_id joined the game"
}

# A user quit
handle_quit() {
	local sender_id="$1"
	unset players_x[$sender_id]
	unset players_y[$sender_id]
	echo "$sender_id left the game"
}

# A user moved
handle_position() {
	local sender_id="$1"
	local x="$2"
	local y="$3"

	players_x[$sender_id]=$x
	players_y[$sender_id]=$y
	echo $sender_id moved to $x $y
}

server_write() {
	echo $@ >&3
}

player_move() {
	server_write move "$1" "$2"
}

player_send_chat() {
	[[ -n "$@" ]] &&
		server_write chat $@
}

user_chat() {
	echo chat_start
	read -r msg
	echo chat_send $msg
}

user_confirm() {
	echo confirm $@
	read -rn1 resp && case $resp in y|Y|'') return 0; esac
	return 1
}

user_quit() {
	if user_confirm 'Really quit? [Y/n]'
	then
		exec 3>&-
		kill -TERM $child_pid $parent_pid
	fi
}

user_restart() {
	if user_confirm 'Really restart? [Y/n]'
	then
		exec 3>&-
		# close socket
		kill -TERM $child_pid
		# restart the program
		echo restart
	fi
}

#trap 'exit' TERM
#trap "exec 3>&-" 0

{
	# Read commands from server
	{
		sed -u 's/^/s_/' <&3
		exit_child
	} &
	child_pid=$!
	#echo sed pid $child_pid >&2

	# Read from user's keyboard
	while read -srn 1 char
	do
		case "$char" in
			j) echo move 1 0;;
			k) echo move -1 0;;
			h) echo move 0 -1;;
			l) echo move 0 1;;
			t) user_chat;;
			#r) user_restart;;
			#q) user_quit;;
		esac
	done

# Multiplex server and user input so that all state is handled in one subshell.
} | {
	trap "kill -TERM $parent_pid; exec 3>&-" 0
while read -r cmd args
do
	set -- "$args"
	case "$cmd" in 
		# server commands
		s_chat) handle_chat $@;;
		s_conn) handle_connection_status "$1";;
		s_join) handle_join "$@";;
		s_quit) handle_quit "$@";;
		s_pos) handle_position $@;;
		s_id) player_id="$@";;
		s_*) echo "<server> $cmd $@";;

		# client commands
		move) player_move "$@";;
		chat_start) echo -n "<$player_id> ";;
		chat_send) player_send_chat $@;;
		confirm) echo -n $@;;
		echo) echo $$ $@;;
		quit) echo exiting $parent_pid
			#kill -INT $parent_pid
			#kill -TERM $parent_pid
			#exec 3>&-
			break;;
		restart) echo restarting;;
		*) echo unknown $cmd $args
	esac
done
}

# restart
#exec "$0" $client_args
