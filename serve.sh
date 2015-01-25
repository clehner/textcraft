#!/bin/sh
# Start the server and let clients connect

server_sock=$(mktemp -u)
mkfifo "$server_sock"

cleanup() {
	kill -9 $NC_PID 2>&-
	rm -f "$server_sock"
	exit
}

echo Starting network server on port ${PORT:=9000}
{
	nc --continuous -lp $PORT -e "./connection.sh $server_sock"
	cleanup
} &
NC_PID=$!
trap cleanup INT

echo Starting game server at $server_sock.
./server.sh "$server_sock"
echo "Server exited"
cleanup
