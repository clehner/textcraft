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
COLOR_BG_BLACK="\e[40m"
COLOR_RESET="\e[0m"

parent_pid=$$

# game info
server_version=
chunk_width=
chunk_height=

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
	#do printf "$COLOR_BG_BLACK%${chunk_width}s$COLOR_RESET\n"
	do printf "%${chunk_width}s\n"
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

# Get initial player info from server
handle_player_info() {
	player_id="$1"
	player_x="$2"
	player_y="$3"
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

print_chunk_files() {
	# ensure the chunks exist
	for file
	do if ! [[ -s $file ]]
	then
	echo $file >> /tmp/empty-chunk
	echo "$empty_chunk" > $file
	fi done
	# paste the chunks
	paste -d '' $*
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
	local chunk_left chunk_right chunk_top chunk_bottom
	local viewport_left viewport_right viewport_top viewport_bottom
	local files
	local header_height=2
	((height -= header_height))

	# get viewport map rect
	((viewport_left=player_x-(width/2)))
	((viewport_right=player_x+(width/2)))
	((viewport_top=player_y-(height/2)))
	((viewport_bottom=player_y+(height/2)))

	#echo height $height $((viewport_bottom-viewport_top))

	#echo player: $player_x $player_y

	#echo viewport x: $viewport_left $viewport_right
	#echo viewport y: $viewport_top $viewport_bottom
	#((chunks_width=width/chunk_width))
	#((chunks_height=height/chunk_height))

	((chunk_left=viewport_left/chunk_width))
	((chunk_top=viewport_top/chunk_height))
	((chunk_right=chunk_left + width/chunk_width))
	((chunk_bottom=chunk_top + height/chunk_height))

	echo $player_x,$player_y
	#echo viewport: $viewport_left,$viewport_top .. $viewport_right,$viewport_bottom
	#echo viewport x $viewport_left $viewport_right
	#echo viewport y $viewport_top $viewport_bottom
	#echo chunk height: $((chunk_bottom-chunk_top))
	#echo chunk width: $((chunk_right-chunk_left))
	#echo height: $(((chunk_bottom-chunk_top)*chunk_height))
	#echo width: $(((chunk_right-chunk_left)*chunk_width))
	#echo chunk x: $chunk_left $chunk_right
	#echo chunk y: $chunk_top $chunk_bottom
	#echo chunks: $chunk_left,$chunk_top .. $chunk_right,$chunk_bottom
	#echo chunk width: $(((chunk_right-chunk_left)*chunk_width)) $width
	((chunks_height=(chunk_bottom-chunk_top)*chunk_height))
	#echo chunk height: $chunks_height $height

	#echo chunk y: $chunk_top $chunk_bottom
	x_range="{$chunk_left..$chunk_right}"
	for ((y=chunk_top; y<chunk_bottom; y++))
	do
		#eval "echo '<(cat '{$chunk_left..$chunk_right}' $y)'"
		eval "print_chunk_files 'data/chunks/'$x_range',$y.txt'"
		#print_chunk $chunk_left $y
	done

	#echo chunk x: {$chunk_left..$chunk_right}
	#echo chunk y: {$chunk_top..$chunk_bottom}
	return $((height-chunks_height))
}

repeat_str() {
	printf "$1"'%.s' $(eval "echo {1.."$(($2))"}")
}

# Draw the interface
redraw() {
	cols=$(tput cols)
	lines=$(tput lines)
	local log_height=4

	# erase display
	echo -ne "\e[2J"
	#echo -ne "\e[2J\ec"
	pos_cursor 0 0

	draw_map 0 0 $((cols-1)) $((lines-log_height-1))
	extra_lines=$?
	((log_height+=extra_lines))

	echo -ne '\e(0'
	repeat_str q $cols
	echo -e '\e(B'
	tail -n $log_height "$log"
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
			j) echo move 0 1;;
			k) echo move 0 -1;;
			h) echo move -1 0;;
			l) echo move 1 0;;
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
		s_player_info) handle_player_info $@;;
		s_chat) handle_chat $@;;
		s_conn) handle_connection_status "$1";;
		s_join) handle_join "$@";;
		s_quit) handle_quit "$@";;
		s_pos) handle_position $@;;
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

	# buffer redraw
	redraw | sed 'H;$!d;x'
done
}

# restart
#exec "$0" $client_args
