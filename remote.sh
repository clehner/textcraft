#!/bin/bash
# remote.sh - connect to the remote server
stty -echo
while read -rn1 char
do echo "$char"
done | nc $*
