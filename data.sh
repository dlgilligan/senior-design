#!/bin/bash

# URL for the PUT request with port embedded (e.g., port 8080)
URL="http://localhost:5000/data/device123"

# Define the range for random numbers (min and max values)
MIN_TEMP=20
MAX_TEMP=30
MIN_MOISTURE=50
MAX_MOISTURE=80
MIN_UV=1
MAX_UV=5

# Infinite loop
while true
do
  # Generate random numbers for each sensor data array
  temp_1=$(( RANDOM % (MAX_TEMP - MIN_TEMP + 1) + MIN_TEMP ))
  temp_2=$(( RANDOM % (MAX_TEMP - MIN_TEMP + 1) + MIN_TEMP ))
  temp_3=$(( RANDOM % (MAX_TEMP - MIN_TEMP + 1) + MIN_TEMP ))

  moisture_1=$(( RANDOM % (MAX_MOISTURE - MIN_MOISTURE + 1) + MIN_MOISTURE ))
  moisture_2=$(( RANDOM % (MAX_MOISTURE - MIN_MOISTURE + 1) + MIN_MOISTURE ))
  moisture_3=$(( RANDOM % (MAX_MOISTURE - MIN_MOISTURE + 1) + MIN_MOISTURE ))

  uv_1=$(( RANDOM % (MAX_UV - MIN_UV + 1) + MIN_UV ))
  uv_2=$(( RANDOM % (MAX_UV - MIN_UV + 1) + MIN_UV ))
  uv_3=$(( RANDOM % (MAX_UV - MIN_UV + 1) + MIN_UV ))

  # Create JSON body with arrays for temperature, moisture, and UV
  json_body=$(cat <<EOF
{
  "temperature": [$temp_1, $temp_2, $temp_3],
  "moisture": [$moisture_1, $moisture_2, $moisture_3],
  "uv": [$uv_1, $uv_2, $uv_3]
}
EOF
)

  # Send the PUT request using curl
  curl -X PUT "$URL" \
       -H "Content-Type: application/json" \
       -d "$json_body"

  # Optional: sleep for 10 seconds to avoid overwhelming the server
  sleep 10
done

