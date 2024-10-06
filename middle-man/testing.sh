#!/bin/bash

# Store data with PUT
# device123 is the identifier
# Response should be "message": "Data received"
curl -X PUT http://localhost:5000/data/device123 -H "Content-Type: application/json" -d '{"temperature": 25}'

# Add command with POST
# Response should be "message": "Command "water-now" added for device123"
curl -X POST http://localhost:5000/command/device123 -H "Content-Type: application/json" -d '{"type": "water-now"}'

# Store data with PUT
# Since commands are stored for the device, commands should be returned
# {
# 	"message": "Data received",
# 	"commands": [{"type": "water-now"}]
# }
# The "commands" for the identifier will be empty after this
curl -X PUT http://localhost:5000/data/device123 -H "Content-Type: application/json" -d '{"temperature": 30}'

# Add two commands
# Response should be "message": "Command "water-now" added for device123"
curl -X POST http://localhost:5000/command/device123 -H "Content-Type: application/json" -d '{"type": "water-now"}'
# Response should be "message": "Command "water-schedule" added for device123"
curl -X POST http://localhost:5000/command/device123 -H "Content-Type: application/json" -d '{"type": "water-schedule", "time": "2023-10-04T08:00:00", "repeat": "daily", "stop-repeat": "2023-12-04-T08:00:00"}'

# Put request should return both commands
# Since commands are stored for the device, commands should be returned
# {
# 	"message": "Data received",
# 	"commands": [{"type": "water-now"}, {"type": "water-schedule", ...}]
# }
# The "commands" for the identifier will be empty after this
curl -X PUT http://localhost:5000/data/device123 -H "Content-Type: application/json" -d '{"temperature": 31}'

# Get data
# {"temperature": 31}
curl -X GET http://localhost:5000/data/device123
