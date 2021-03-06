breed [players player]
breed [bullets bullet]

players-own [
  id    ;; the idendity of the player
  lives ;; how much lives does each player have
]

bullets-own [
  master ;; the idendity of the player
         ;; who shoot this bullet
]

globals [
  dead-id ;; a list of dead player
]

to startup
  hubnet-reset
end

;;;;;;;;;;;;;;;;;;;;;;;
;;; SETUP PROCEDURE ;;;
;;;;;;;;;;;;;;;;;;;;;;;

to setup
  ;; clear all, including players
  clear-all
  hubnet-kick-all-clients
  ;; create the battle field
  create-grasses
  create-covers
  set-default-shape bullets "dot"
  reset-ticks
end

to create-grasses
  ask patches [
    ;; randomize the brightness
    ;; of the grass
    set pcolor (green + random-float 0.5)- 0.5
  ]
end

to create-covers
  ;; create borders
  ;; so no player can escape
  ask patches with [
    ;; all the ones along the boarder
    pxcor = max-pxcor or pxcor = min-pxcor or pycor = max-pycor or pycor = min-pycor
  ][
    set pcolor grey - 1
  ]
  ;; create the cover bodies
  ask patches with [
    ;; randome position
    pxcor = random max-pxcor or pycor = random max-pycor
  ][
    set pcolor grey - 1
  ]
end

;;;;;;;;;;;;;;;;;;;;
;;; GO PROCEDURE ;;;
;;;;;;;;;;;;;;;;;;;;

to go
  ;; remove those players that are dead
  remove-dead
  ;; see what players does
  refresh
  every 0.1 [
    move-bullets
    tick
  ]
end

to remove-dead
  ;; see if there even are dead ones
  if any? players with [lives <= 0]
  [
    set dead-id [id] of players with [lives <= 0]
    ;; tells everyone some just died
    hubnet-broadcast-message word dead-id " die"
    ;; remove the dead.
    ;; remove the players
    ask players with [lives <= 0]
    [ die ]
    ;; ask the players to leave hubnet.
    ;; since there can be more than one that
    ;; are dead, we have to deal with each
    while [not empty? dead-id]
    [
      hubnet-kick-client first dead-id
      ;; after we deal with that,
      ;; deal with the next one
      set dead-id but-first dead-id
    ]
  ]
end

to refresh
  ;; see if there is a new message
  while [ hubnet-message-waiting? ]
  [
    ;; fetch message
    hubnet-fetch-message
    ;; if enters?
    ifelse hubnet-enter-message?
    [ create-new-player ]
    [
      ;; if not enter, exit?
      ifelse hubnet-exit-message?
      [ remove-player ]
      ;; if not those, it must be some command.
      ;; then execute it
        [ execute-command hubnet-message-tag ]
    ]
  ]
end

to create-new-player
  ;; tell everyone someone just entered
  hubnet-broadcast-message word hubnet-message-source " join the game"
  ;; create the new player
  create-players 1 [
    ;; let player spawn at a random position
    setxy random max-pxcor random max-pycor
    while [ [pcolor] of patch-here = grey - 1 ]
    ;; if lands on a cover body
    [
      ;; choose another place to spawn
      setxy random max-pxcor random max-pycor
      ;; keep doing this untile the player
      ;; doesn't land on a cover bodie
    ]
    set id hubnet-message-source
    set label id
    set lives 5
    hubnet-send id "lives" lives
    ;; set the color
    while [ 80 > color and color > 50 ]
    ;; if color is green
    [
      ;; set another color
      ;; otherwise the player cannot be seen clearly
      ;; therfore giving it an advantage
      ;; which is unfair for the other players
      set color random-float 139.9
    ]
    set heading 0
    set size 1
  ]
  ;; let the player follow own character
  hubnet-send hubnet-message-source "world size" 0
  hubnet-send-follow hubnet-message-source one-of players with [id = hubnet-message-source] 7
end

to remove-player
  ;; tell everyone someone just exited
  hubnet-broadcast-message word hubnet-message-source  " exit the game"
  ;; delete the new player
  ask players with [ id = hubnet-message-source ]
  [ die ]
end

to execute-command [command]
  ;; player procedure
  ask players with [ id = hubnet-message-source ]
  [
    ;; move procedure
    if command = "up" [
      ;; make sure it isn't blocked by cover bodies
      if [pcolor] of patch-at-heading-and-distance 0 1 != grey - 1 [
        set ycor ycor + 1
      ]
      stop
    ]
    ;; the reset has the same sturcture of the one above
    if command = "down" [
      if [pcolor] of patch-at-heading-and-distance 180 1 != grey - 1 [
        set ycor ycor - 1
      ]
      stop
    ]
    if command = "left" [
      if [pcolor] of patch-at-heading-and-distance 270 1 != grey - 1 [
        set xcor xcor - 1
      ]
      stop
    ]
    if command = "right" [
      if[pcolor] of patch-at-heading-and-distance 90 1 != grey - 1 [
        set xcor xcor + 1
      ]
      stop
    ]
    ;; rotion procedures
    if command = "turn left" [
      set heading heading - 45
      stop
    ]
    if command = "turn right" [
      set heading heading + 45
      stop
    ]
  ]
  ;; fire procedure
  if command = "fire" [
    ;; create a bullet
    create-bullets 1 [
      set master hubnet-message-source
      ;; go to the position of the shooter.
      ;; "players with [id = hubnet-message-source]"
      ;; gives a list. Although there can be only one item,
      ;; it is still a list. So we use "first"
      ;; ("last" can work too. Or "the 1st")
      setxy first [xcor] of players with [id = hubnet-message-source] first [ycor] of players with [id = hubnet-message-source]
      ;; face the same as the shooter
      set heading first [heading] of players with [id = hubnet-message-source]
      ;; if there are cover bodies ahead of the shooter
      ;; there is no need to shoot in the first place
      ifelse [pcolor] of patch-ahead 1 != grey - 1 [
        ;; move forward by 1
        ;; or it will shoot the shooter
        setxy [pxcor] of patch-ahead 1 [pycor] of patch-ahead 1
        set color first [color] of players with [id = hubnet-message-source]
        set size 1
      ][
        die
        stop
      ]
    ]
    stop
  ]
  ;; perspective procedure
  if command = "world size" [
    ifelse (hubnet-message + 7) < 22
    [ hubnet-send-follow hubnet-message-source one-of players with [id = hubnet-message-source] hubnet-message + 7 ]
    [ hubnet-reset-perspective hubnet-message-source ]
  ]
end

to move-bullets
  ;; if bullets hit a player
  ask bullets with [any? players-here]
  [
    ask players-here [
      ;; loose 1 life
      set lives lives - 1
      ;; refresh the "lives" output of the player
      hubnet-send [id] of players-here "lives" lives
    ]
    ;; the bullet must stop too
    die
  ]
  ask bullets with [[pcolor] of patch-here != grey - 1]
  [ setxy [pxcor] of patch-ahead 1 [pycor] of patch-ahead 1 ]
  ask bullets with [[pcolor] of patch-here = grey - 1]
  [ die ]
end

; Copyright 2018 Kevin.Tang
@#$#@#$#@
GRAPHICS-WINDOW
210
10
628
429
-1
-1
10.0
1
6
1
1
1
0
0
0
1
-20
20
-20
20
0
0
1
ticks
30.0

BUTTON
11
37
125
70
setup/restart
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
124
37
187
70
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

TEXTBOX
5
10
198
38
clients must join AFTER pressing go
11
0.0
1

@#$#@#$#@
## WHAT IS IT?

This is a hubnet shooting game.

## HOW IT WORKS

This model uses baisc hubnet commands, while, ask, with, and list operations.

## RULES

 - use "forward", "back", "left", and "right" or IJKL to move

 - use "turn left" and "turn right" or AD to turn

 - "fire" or W to shoot

 - players or bullets are blocked by grey cover bodies

 - if player is hit by a bullet, player lose one life, lose all and you die


## THINGS TO NOTICE

When "SETUP" is clicked, it will remove all the clients. If you join before "GO" is clicked, nothing will happen. So **Please join after "GO" is clicked**.

## EXTENDING THE MODEL

How about limit the number of bullets? Health packs that can recover lives? Experience points that grow when an enemy is killed? Groups? And **saving the game**?

## NETLOGO FEATURES

It uses Hubnet

## RELATED MODELS

3D_battle_field.nlogo3d

## CREDITS AND REFERENCES

Copyright 2018 Kevin.Tang
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

laser
true
0
Line -2674135 false 150 90 150 210

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

player
true
0
Circle -10899396 true false 90 90 120
Line -6459832 false 150 90 150 0
Circle -2064490 true false 150 60 30

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.4
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
VIEW
210
10
639
439
0
0
0
1
1
1
1
1
0
1
1
1
-20
20
-20
20

BUTTON
71
42
136
75
down
NIL
NIL
1
T
OBSERVER
NIL
K

BUTTON
9
42
72
75
left
NIL
NIL
1
T
OBSERVER
NIL
J

BUTTON
135
42
198
75
right
NIL
NIL
1
T
OBSERVER
NIL
L

BUTTON
18
106
99
139
turn left
NIL
NIL
1
T
OBSERVER
NIL
A

BUTTON
98
106
190
139
turn right
NIL
NIL
1
T
OBSERVER
NIL
D

MONITOR
77
138
134
187
lives
NIL
3
1

TEXTBOX
17
231
192
455
Rules:\n\n - use \"forward\", \"back\", \"left\",\n    and \"right\" or IJKL to move\n\n - use \"turn left\" and \"turn right\"\n    or AD to turn\n\n - \"fire\" or W to shoot\n\n - players or bullets are blocked\n    by grey cover bodies\n\n - if player is hit by a bullet,\n    player lose one life, lose\n    all and you die\n
11
0.0
1

BUTTON
71
74
134
107
fire
NIL
NIL
1
T
OBSERVER
NIL
W

BUTTON
72
10
135
43
up
NIL
NIL
1
T
OBSERVER
NIL
I

SLIDER
14
187
186
220
world size
world size
0.0
16.0
0
1.0
1
NIL
HORIZONTAL

@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
