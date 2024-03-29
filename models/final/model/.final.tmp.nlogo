; imports

;Imports are used to make the entire more overseeable
;The imported files contain the functions for the following procedures:
;
; utilities:  -general setup tools like debug?
;             -measuring turtles as a stop condition
;             -reassigning the colors to ensure that no patches with the same color have slightly matching color codes
;
; alarm:      -timer to start the alarm at t = 30
;             -measuring statistics for the evacuation duration
;
; move:       -general move function for when alarm is off, focussed on movement and not walking through walls
;             -adapted move function for children. Children with parents follow parents regardless of the alarm
;             -assignment of children to parents to aid in child move function
;
; evacuation: -pathfinding functions based on assigning a "closeness-to-exit" value to each walkable patch in the building.
;              turtles will navigate to the door by heading towards patches with a lower closeness-to-exit.
;             -similar pathfinding function for assigning a "closeness-to-main-exit" value to each walkable patch in the building.
;              Turtles that will head to the main entrance instead of the closest exit will follow patches with a lower "closeness-to-main-exit".
;             -determination of initial response time when the alarm goes on (based on current task)
;             -move function for turtles when the alarm goes on
;             -evacuation aid function for staff members to guide others to the closest exit
;
; tasks:      -functions to determine when a turtle will start studying or asking something at the desk

__includes [ "imports/utilities.nls" "imports/alarm.nls" "imports/move.nls" "imports/evacuation2.nls" "imports/tasks.nls"]

; the two main type of building users
breed [staff-members staff-member]
breed [visitors visitor]

;define variables
globals [
  all-colors
  alarm-start-time
  alarm-timer
  total-event-time
  done?
  total-response-delay
  evacuating-visitors
  preferred-door-Xcor
  preferred-door-Ycor

]

patches-own [
  cyan?                       ; colors are saved initially in these variables before the pathfinding function
  white?                      ; temporarily overwrites them
  green?
  evac-path?
  closeness-to-exit
  closeness-to-preferred-exit
  preferred-exit?
]

staff-members-own[
  stationary-duty?            ; staff members with stationary duty have tasks requiring no movement, like standing by at an information desk
]

visitors-own [
  task
  response-timer
  parent-turtle
  has-parent?
  is-parent?
  studying?
  asking-at-desk?
  response-time-calculated?
  evacuating?
  timer4
  timer5
]

turtles-own[
  knows-all-exits?
  walking-speed
  running-speed
  gender
  child?
]

; we assume that 1 patch = 1.5 x 1.5 m

to setup
  clear-all
  setupMap               ;import the map png
  set alarm? false       ;at the start the alarm is turned off

  ; always create 50 staff members
  create-staff-members 50 [
    set shape "person"
    set color red
    set size 2
    set knows-all-exits? true
    set child? false
    ifelse random 101 < percentage-female [set gender "female"][ set gender "male"]
    ifelse random 101 < percentage-stationary-staff
    [move-to one-of patches with [pcolor = 25.7]                     ;the map was edited with specific locations where stationary staff members will stand
                                                                     ;these patches are changed to white later in the setup
    set stationary-duty? true]
    [move-to one-of patches with [pcolor = white]
    set stationary-duty? false]
  ]

  ask patches with [pcolor = 25.7]
  [
    set pcolor white                                                  ;the patches with 25.7 as color were only necessary to
    set white? true                                                   ;indicate spawn locations for stationary staff
  ]
  ; create the number of visitors
  create-visitors agents-at-start - 50 [
    set shape "person"
    set color green
    set size 2
    set studying? false
    set asking-at-desk? false
    set response-time-calculated? false
    set evacuating? false
    ifelse random 101 < percentage-visitors-go-to-preferred-exit [set knows-all-exits? false][set knows-all-exits? true]
    ifelse random 101 < percentage-female [set gender "female"][set gender "male"]
    ifelse random 101 < percentage-children [set child? true][set child? false]
    move-to one-of patches with [pcolor = white]

  ]
  ask turtles [determine-speeds]
  assign-parents
  set-preferred-exit-door
  determine-closeness-to-exit
  determine-closeness-to-preferred-exit
  reset-ticks
end

to go
  alarm-start-30
  ifelse alarm? = False
  [                                                                     ;when the alarm is off

    ask staff-members with [stationary-duty? = false]
    [
      move-turtles                                                      ;non-stationary staff members traverse the building normally
    ]

    ask visitors with [child? = false]
    [

      if any? patches in-radius 2 with [pcolor = 125.8] [ask-at-desk]   ;when close to a desk patch, there is a chance a visitor will ask a question
      study                                                             ;in certain parts of the building, there is a chance a visitor will sit down and study
      if studying? = false and asking-at-desk? = false [move-turtles]   ;when turtles are not studying or asking at a desk, they will move normally
    ]

    ask visitors with [child? = true]
    [
      move-children                                                     ;children move depending on if they have a parent:
                                                                        ;if they have a parent, they will follow the parent around the building
                                                                        ;if they do not have a parent, they will move as normal turtles
    ]
  ]

  [                                                                     ;when the alarm goes on
    ask staff-members
    [
      ifelse count visitors in-radius alerting-range > 0 [guide-visitors-to-exit][evacuate]
                                                                        ;when the alarm goes on, staff members will head to the nearest exit.
                                                                        ;however, as soon as a visitors enters their alerting range, they will
                                                                        ;stop, alert visitors of the danger and show them the route to nearest exit
    ]


    ask visitors with [(child? = false) or (child? = true and has-parent? = false)]
    [
      if response-time-calculated? = false [determine-response-time]   ;based on the task the visitor is doing when the alarm goes on, initial response
                                                                       ;time is determined

      ifelse response-timer = 0                                        ;when a turtle's response time runs out, they will evacuate.
                                                                       ;as long as the response time is not 0, visitors will continue the task they were doing.
      [                                                                ;visitors who've had fire training and know the exits will also alert others of the danger
        set evacuating? true                                           ;and point them to the nearest exit.
        evacuate                                                       ;however they will not stop running to the exit to alert others, like staff members do
        if knows-all-exits? = true and child? = false [guide-visitors-to-exit]
      ]
      [
        ifelse studying? = true or asking-at-desk? = true [][move-turtles]
        set response-timer response-timer - 1
        if count visitors in-radius alerting-range with [response-timer = 0] > count visitors in-radius alerting-range with [response-timer > 0]
        [if random 101 < 10 [set response-timer 0]]                    ;when the alarm goes on, visitors also examine each others behaviour to decide what to do
      ]                                                                ;if the majority is evacuating around a visitor, there is a 10% chance a visitor's
    ]                                                                  ;response timer is reduced to 0 and they will consequently evacuate
    if alarm-start-time = 0 [set alarm-start-time ticks]



  ask visitors with [child? = true and has-parent? = true]             ;children with parents will not start evacuating until their parents do too
  [move-children
    if is-turtle? parent-turtle = true
    [if [response-timer] of parent-turtle = 0
        [set evacuating? true]]
  ]

 ]
  ask turtles [exit-building]                                         ;turtles on a red square exit the building
                                                                      ;it is possible that this happens before the alarm goes on, since the doors aren't locked.
  if not any? turtles [ stop ]                                        ;model ends when no more turtles are in the building
  tick ; next time step
end
@#$#@#$#@
GRAPHICS-WINDOW
297
10
930
680
-1
-1
2.44141
1
10
1
1
1
0
0
0
1
0
255
0
270
1
1
1
ticks
30.0

BUTTON
10
10
83
43
NIL
setup
NIL
1
T
OBSERVER
NIL
S
NIL
NIL
1

BUTTON
11
47
74
80
NIL
go
T
1
T
OBSERVER
NIL
G
NIL
NIL
1

SWITCH
6
89
127
122
verbose?
verbose?
0
1
-1000

SWITCH
147
90
257
123
debug?
debug?
1
1
-1000

SLIDER
9
178
236
211
agents-at-start
agents-at-start
50
5000
450.0
1
1
person
HORIZONTAL

SLIDER
9
215
236
248
percentage-female
percentage-female
0
100
40.7
1
1
%
HORIZONTAL

SLIDER
9
254
237
287
percentage-children
percentage-children
0
100
5.5
1
1
%
HORIZONTAL

MONITOR
973
308
1097
353
evacuation duration
evacuation-duration
17
1
11

SWITCH
5
138
108
171
alarm?
alarm?
1
1
-1000

BUTTON
86
49
149
82
NIL
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
973
258
1137
303
NIL
people-in-building
17
1
11

PLOT
970
36
1405
253
people over time
time
people
0.0
500.0
0.0
500.0
true
false
"" ""
PENS
"total" 1.0 0 -16777216 true "" "plot people-in-building"
"staff" 1.0 0 -2674135 true "" "plot staff-members-in-building"
"visitors" 1.0 0 -13840069 true "" "plot visitors-in-building"

MONITOR
1566
243
1716
288
staff members in building
staff-members-in-building
17
1
11

MONITOR
1716
244
1832
289
visistors in building
visitors-in-building
17
1
11

SLIDER
9
294
283
327
percentage-visitors-go-to-preferred-exit
percentage-visitors-go-to-preferred-exit
0
100
96.0
1
1
NIL
HORIZONTAL

SLIDER
11
453
240
486
max-turtles-per-patch
max-turtles-per-patch
1
8
1.0
1
1
NIL
HORIZONTAL

SLIDER
10
373
239
406
alerting-range
alerting-range
0
10
6.6
1
1
NIL
HORIZONTAL

SLIDER
11
417
239
450
average-response-time
average-response-time
0
120
60.0
1
1
NIL
HORIZONTAL

SLIDER
10
333
237
366
percentage-stationary-staff
percentage-stationary-staff
0
100
50.0
1
1
NIL
HORIZONTAL

MONITOR
974
364
1069
409
event duration
event-duration
17
1
11

MONITOR
973
418
1231
463
percentage visitors currently not evacuating
precision ((count visitors with [evacuating? = false] /\ncount visitors) * 100) 2
17
1
11

CHOOSER
120
128
258
173
Preferred-exit-door
Preferred-exit-door
"main" "lower-left" "upper-right"
0

@#$#@#$#@
## WHAT IS IT?

This model models the evacutaion of the TU Delft library. 

## HOW IT WORKS

The model simulates an evacuation in the TU Delft library. 

- When the simulation starts, the model first start with normal behaviour. Visitors and staff members randomly walk around and perform tasks for about 30 ticks. 
- After 30 ticks, the alarm rings. Some visitors remain busy with their task and evacuate after completing this task. 
- The model stops when all agents have evacuated. 

## HOW TO USE IT
- The model should first be setup with the setup button. 
- After this, the model can be run for just one tick, or the entire simulation using the button 'go'

## Parameters

<table>
    <tr>
        <td>Parameter</td>
        <td>Description</td>
        <td>Range</td>
        <td>Unit</td>
    </tr>
    <tr>
        <td>agents-at-start</td>
        <td>Total numbers of people at the start</td>
        <td>50-5000</td>
        <td>Persons</td>
    </tr>
    <tr>
        <td>percentage-female</td>
        <td>Percentage of people female</td>
        <td>0-100%</td>
        <td>-</td>
    </tr>
    <tr>
        <td>percentage-children</td>
        <td>Percentage of people children</td>
        <td>0-100%</td>
        <td>-</td>
    </tr>
    <tr>
        <td>percentage-stationary-staff</td>
        <td>Percentage of staff that will remain stationary during a non-evacuation situation</td>
        <td>0-100%</td>
        <td>-</td>
    </tr>
    <tr>
        <td>alerting-range</td>
        <td>Range in which staff members can alert visitors during an evacuation</td>
        <td>0-10</td>
        <td>Patches (1,5 m2 )</td>
    </tr>
    <tr>
        <td>average-response-time</td>
        <td>Average time it takes for people to start evacuating</td>
        <td>0-120</td>
        <td>Ticks (seconds)</td>
    </tr>
    <tr>
        <td>max-turtles-per-patch</td>
        <td>Maximum number of turtles allowed on patch during an evacuation</td>
        <td>1-aug</td>
        <td>Persons/patch</td>
    </tr>
    <tr>
        <td>percentage-visitors-go-to-preferred-exit</td>
        <td>Percentage of visitors that will initially go to the selected preferred exit</td>
        <td>0-100%</td>
        <td>-</td>
    </tr>
    <tr>
        <td>Preferred-exit-door</td>
        <td>Enables the model to pick a specific exit that people will take</td>
        <td>“upper-right”, “upper-left”, “main”</td>
        <td>-</td>
    </tr>
</table>

## THINGS TO TRY

- Edit the max-turtles-per-patch parameter while the model is running, to directly see the effect. 

- Try simulating the model with more agents. The model simulates smoothly up to 5000 agents. 


## EXTENDING THE MODEL

- A suggested extension, might be the modelling of  fire. 
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
NetLogo 6.1.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment 1" repetitions="10" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <metric>evacuation-duration</metric>
    <metric>event-duration</metric>
    <metric>people-in-building</metric>
    <metric>staff-members-in-building</metric>
    <metric>visitors-in-building</metric>
    <metric>precision ((count visitors with [evacuating? = false] / count visitors) * 100) 2</metric>
    <steppedValueSet variable="percentage-female" first="0" step="10" last="100"/>
    <enumeratedValueSet variable="percentage-stationary-staff">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alarm?">
      <value value="true"/>
    </enumeratedValueSet>
    <steppedValueSet variable="percentage-children" first="0" step="10" last="100"/>
    <enumeratedValueSet variable="max-turtles-per-patch">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debug?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="average-response-time">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="agents-at-start">
      <value value="450"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verbose?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percentage-visitors-go-to-main-door">
      <value value="96"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alerting-range">
      <value value="6"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment" repetitions="20" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <metric>evacuation-duration</metric>
    <metric>event-duration</metric>
    <metric>people-in-building</metric>
    <metric>staff-members-in-building</metric>
    <metric>visitors-in-building</metric>
    <metric>precision ((count visitors with [evacuating? = false] / count visitors) * 100) 2</metric>
    <enumeratedValueSet variable="percentage-female">
      <value value="33.3"/>
      <value value="37"/>
      <value value="40.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percentage-stationary-staff">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alarm?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percentage-children">
      <value value="4.5"/>
      <value value="5"/>
      <value value="5.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-turtles-per-patch">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debug?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Preferred-exit-door">
      <value value="&quot;main&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="average-response-time">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="agents-at-start">
      <value value="450"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="verbose?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percentage-visitors-go-to-preferred-exit">
      <value value="86.4"/>
      <value value="96"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alerting-range">
      <value value="5.4"/>
      <value value="6"/>
      <value value="6.6"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
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
