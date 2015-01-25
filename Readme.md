# textcraft
**a text adventure thing**

made at [Global Game Jam 2015](http://globalgamejam.org/2015/jam-sites/rettner-hall-university-rochester)

![screenshot](http://globalgamejam.org/sites/default/files/styles/game_sidebar__wide/public/game/featured_image/screenshot2.png)

## features
- real-time multiplayer server
- terminal user interface
- chat
- moving around a 2d world
- tile-based game world

## usage

Try connecting to cel's server:
```
./client.sh celehner.com 9010
```

## running locally

requirements:
- bash
- for server: ncat, or netcat with `--exec` and `--continuous` or `-k`
- other command-line utilities (sed, paste, tr, ...)

start the server

```
[PORT=9000] ./server.sh
```

connect to the server

```
./client.sh localhost $PORT
```

## known issues

- connections don't always close cleanly. when restarting the server, you may
  need to kill backgrounded scripts with e.g. `pkill -f $PORT`

## further work

- prevent walking through walls
- make it a game
- add things
- do stuff
- interact with the game map
- modify the game map
- interact with other players
