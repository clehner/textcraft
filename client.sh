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

# Open log
log=$(mktemp)
exec 5<> "$log"

YELLOW="\e[1;33m"
RESET="\e[0m"

parent_pid=$$

# game info
server_version=
chunk_width=11
chunk_height=5

# local player info
player_id=
player_x=
player_y=

# player positions
declare -A players_x
declare -A players_y

# viewer info
cols=
lines=
empty_chunk=

gen_empty_chunk() {
	for ((x=0; x<chunk_height; x++))
	do printf "%${chunk_width}s\n" | sed 's/ /./g'
	done
}

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

# Read info about the game
handle_info() {
	server_version=$1
	chunk_width=$2
	chunk_height=$3
	empty_chunk=$(gen_empty_chunk)
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

	if [[ $sender_id == $player_id ]]
	then
		player_x=$x
		player_y=$y
	fi
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

# Print a game chunk
print_chunk() {
	local chunk_x=$1
	local chunk_y=$2
	local file="data/chunks/$chunk_x,$chunk_y.txt"
	if [[ -s $file ]]
	then cat $file
	else echo "$empty_chunk"
	fi
}

# Position cursor on screen
pos_cursor() {
	echo -ne "\e[$1;$2H"
}

# Draw the game map
draw_map() {
	local offset_x="$1"
	local offset_y="$2"
	local width="$3"
	local height="$4"
	local viewport_x viewport_y

	# get viewport map rect
	((viewport_left=player_x-(width/2)))
	((viewport_top=player_y-(height/2)))
	((viewport_right=player_x+(width/2)-1))
	((viewport_bottom=player_y+(height/2)-1))

	#echo player: $player_x $player_y

	#echo viewport x: $viewport_left $viewport_right
	#echo viewport y: $viewport_top $viewport_bottom

	# get viewport chunk rect
	((chunk_left=viewport_left/chunk_width))
	((chunk_top=viewport_top/chunk_height))
	((chunk_right=viewport_right/chunk_width))
	((chunk_bottom=viewport_bottom/chunk_height))

	((clip_top=viewport_top % chunk_height))
	((clip_left=viewport_left % chunk_width))
	((clip_right=viewport_right % chunk_width))
	((clip_bottom=viewport_bottom % chunk_height))

	#echo chunk height: $((chunk_top-chunk_bottom))
	#echo chunk width: $((chunk_right-chunk_left))
	#echo clip x: $clip_left $clip_right
	#echo clip y: $clip_top $clip_bottom
	#echo sums: $((clip_top+clip_bottom)) $((clip_left+clip_right))

	for ((y=chunk_top; y<chunk_bottom; y++))
	do
		:
		#local files
		#eval "files='print_chunk '{$chunk_left..$chunk_right}' $y'"
		print_chunk $chunk_left $y
	done

	#echo chunk x: {$chunk_left..$chunk_right}
	#echo chunk y: {$chunk_top..$chunk_bottom}
}

# Draw the interface
redraw() {
	cols=$(tput cols)
	lines=$(tput lines)
	local log_height=5

	# erase display
	echo -ne "\e[2J"

	draw_map 0 0 $cols $((lines-log_height-1))

	echo =========
	tail -n $log_height "$log"
	pos_cursor 2 0
}

#trap 'exit' TERM
#trap "exec 3>&-" 0
trap cleanup 0

cleanup() {
	rm "$log"
}

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
		s_info) handle_info $@;;
		s_chat) handle_chat $@;;
		s_conn) handle_connection_status "$1";;
		s_join) handle_join "$@";;
		s_quit) handle_quit "$@";;
		s_pos) handle_position $@;;
		s_id) player_id="$@";;
		s_*) echo "<server> $cmd $@";;

		# client commands
		move) player_move "$@";;
		chat_start) echo -n "> ";;
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
	esac >&5
	redraw
done
}

# restart
#exec "$0" $client_args
