#!/bin/sh
# Start the server and let clients connect

server_sock=$(mktemp -u)
mkfifo "$server_sock"

trap "rm $server_sock" INT

echo Starting network server on port ${PORT:=9000}
nc --continuous -lp $PORT -e "./client.sh $server_sock" &
NC_PID=$!
trap "kill $NC_PID 2>&-" EXIT

echo Starting game server at $server_sock.
./server.sh "$server_sock"
echo "Server exited"
