#!/bin/sh
# Start the server and let clients connect

server_sock=$(mktemp -u)
mkfifo "$server_sock"

echo Starting network server on port ${PORT:=9000}
nc --continuous -lp $PORT -e "./connection.sh $server_sock" &
NC_PID=$!
trap cleanup INT

cleanup() {
	echo killing $NC_PID
	kill -9 $NC_PID
	echo removing $server_sock
	rm "$server_sock"
	exit
}

echo Starting game server at $server_sock.
./server.sh "$server_sock"
echo "Server exited"
cleanup
