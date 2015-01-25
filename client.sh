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

chunks_dir=$(mktemp -d)

YELLOW="\e[1;33m"
COLOR_BG_BLACK="\e[40m"
COLOR_BG_GREEN="\e[42m"
COLOR_BG_CYAN="\e[46m"
COLOR_FG_BLUE="\e[34m"
COLOR_FG_BLACK_BOLD="\e[1;30m"
COLOR_RESET="\e[0m"

parent_pid=$$

# game info
server_version=0
chunk_width=
chunk_height=

# local player info
player_id=
player_x=
player_y=
player_direction=

# player positions
declare -A players_x
declare -A players_y
declare -A players_direction

declare -A dir_icons
dir_icons=([up]='^' [down]='v' [left]='<' [right]='>')

# viewer info
cols=
lines=
empty_chunk=
paused=

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
	handle_position $*
}

# A user quit
handle_quit() {
	local sender_id="$1"
	unset players_x[$sender_id]
	unset players_y[$sender_id]
	unset players_direction[$sender_id]
	echo "$sender_id left the game"
}

# A user moved
handle_position() {
	local sender_id="$1"
	local x="$2"
	local y="$3"
	local direction="$4"

	players_x[$sender_id]=$x
	players_y[$sender_id]=$y
	players_direction[$sender_id]=$direction

	if [[ $sender_id == $player_id ]]
	then
		player_x=$x
		player_y=$y
		player_direction=$direction
	fi
}

# The server is sending us a chunk
handle_chunk() {
	local chunk=$1; shift
	# save chunk to file
	echo -n $* | tr '%$' '\n ' > "$chunks_dir/$chunk.txt"
}

server_write() {
	echo $@ >&3
}

player_move() {
	server_write move "$*"
}

player_send_chat() {
	[[ -n "$@" ]] &&
		server_write chat $@
}

request_chunks() {
	server_write req_chunks "$@"
}

user_chat() {
	read -rep '> ' msg
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

print_chunks() {
	local file chunk_files missing_chunks

	# ensure the chunks exist
	for chunk
	do
		file="$chunks_dir/$chunk.txt"
		if [[ ! -f "$file" ]]
		then
			# use blank chunk temporarily
			echo "$empty_chunk" > "$file"
			# ask server for chunk
			missing_chunks+=" $chunk"
		fi
		chunk_files+=" $file"
	done

	request_chunks "$missing_chunks"

	# paste the chunks
	paste -d '' $chunk_files
}

# Position cursor on screen
pos_cursor() {
	echo -ne "\e[$2;$1H"
}

# Superimpose players onto map
draw_players() {
	local width="$1"
	local height="$2"
	local left="$3"
	local top="$4"
	local right="$5"
	local bottom="$6"
	local x y direction icon color

	for id in "${!players_x[@]}"
	do
		# get position of player relative to viewport
		((x=players_x[$id]-left))
		((y=players_y[$id]-top))

		# check bounds
		((x < 0 || x > width || y < 0 || y > height)) && continue

		if [[ $id == $player_id ]]
		then color=$COLOR_FG_BLACK_BOLD$COLOR_BG_GREEN
		else color=$COLOR_FG_BLACK_BOLD$COLOR_BG_CYAN
		fi

		direction="${players_direction[$id]}"
		icon="$color${dir_icons[$direction]}$COLOR_RESET"

		# save cursor, move to point, plot character, restore cursor
		
		echo -ne "\e7\e[${y};${x}H${icon}\e8"
	done
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
	local header_height=1
	local status
	((height -= header_height))

	if ((chunk_height==0))
	then
		for ((i=0; i<height; i++))
		do echo
		done
		return
	fi

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

	((full_left=chunk_left*chunk_width))
	((full_top=chunk_top*chunk_height))
	((full_right=chunk_right*chunk_width))
	((full_bottom=chunk_bottom*chunk_height))

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
		eval "print_chunks $x_range,$y"
	done

	status="$player_x,$player_y"
	# draw the status in a half-box at the top-right corner
	status+="\e(0x\n$(repeat_str q ${#status})j\e(B\n"
	echo -ne "\e7\e[1;1H$status\e8"

	draw_players $width $height \
		$full_left $full_top $full_right $full_bottom

	# return unused space
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

	draw_map 0 0 $((cols-2)) $((lines-log_height-1))
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
	rm -rf "$log" "$chunks_dir"
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
			j) echo move down;;
			k) echo move up;;
			h) echo move left;;
			l) echo move right;;
			c) echo chunk;;
			t) user_chat;;
			#w) echo dir 0;;
			#a) echo dir 1;;
			#s) echo dir 2;;
			#d) echo dir 3;;
			#r) user_restart;;
			#q) user_quit;;
		esac
	done

# Multiplex server and user input so that all state is handled in one subshell.
} | {
	trap "kill -TERM $parent_pid; exec 3>&-" 0
while read -r cmd args
do
	set -- $args
	case "$cmd" in 
		# server commands
		s_info) handle_info $@;;
		s_player_info) handle_player_info $@;;
		s_chat) handle_chat $@;;
		s_conn) handle_connection_status "$1";;
		s_join) handle_join "$@";;
		s_quit) handle_quit "$@";;
		s_pos) handle_position $@;;
		s_chunk) handle_chunk $@;;
		s_pause) paused=1;;
		s_resume) paused=;;
		s_*) echo "<server> $cmd $@";;

		# client commands
		move) player_move "$@";;
		chat_send) echo -en '\r'; player_send_chat $@;;
		confirm) echo -n $@;;
		echo) echo $$ $@;;
		quit) echo exiting $parent_pid
			#kill -INT $parent_pid
			#kill -TERM $parent_pid
			#exec 3>&-
			break;;
		restart) echo restarting;;
		chunk) echo requesting chunk; request_chunks 0,0;;
		*) echo unknown $cmd $args
	esac >&5

	# buffered redraw
	[[ -z "$paused" ]] && redraw | sed 'H;$!d;x'
done
}

# restart
#exec "$0" $client_args
