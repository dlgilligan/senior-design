#!/bin/bash
# URL for the PUT request
URL="http://localhost:5000/data/device123"

# Define MAC addresses for plants
MAC_ADDRESSES=("AA:BB:CC:DD:EE:01" "AA:BB:CC:DD:EE:02" "AA:BB:CC:DD:EE:03")

# Define the range for random numbers
MIN_TEMP=20
MAX_TEMP=30
MIN_MOISTURE=50
MAX_MOISTURE=80
MIN_UV=1
MAX_UV=5

# Function to process commands
process_commands() {
    response=$1
    if echo "$response" | grep -q "commands"; then
        echo "Processing commands:"
        echo "$response" | jq -r '.commands[]'
    fi
}

# Infinite loop
while true
do
    # Initialize empty JSON arrays for each plant's data
    declare -A plant_data
    
    # Generate data for each plant
    for mac in "${MAC_ADDRESSES[@]}"; do
        temp=$(( RANDOM % (MAX_TEMP - MIN_TEMP + 1) + MIN_TEMP ))
        moisture=$(( RANDOM % (MAX_MOISTURE - MIN_MOISTURE + 1) + MIN_MOISTURE ))
        uv=$(( RANDOM % (MAX_UV - MIN_UV + 1) + MIN_UV ))
        
        plant_data[$mac]=$(cat <<EOF
            {
                "temperature": $temp,
                "moisture": $moisture,
                "uv": $uv
            }
EOF
)
    done
    
    # Create the complete JSON body
    json_body=$(cat <<EOF
{
    "plants": $(printf '%s\n' "${MAC_ADDRESSES[@]}" | jq -R . | jq -s .),
    "data": {
        $(for mac in "${MAC_ADDRESSES[@]}"; do
            echo "\"$mac\": ${plant_data[$mac]}"
            if [ "$mac" != "${MAC_ADDRESSES[-1]}" ]; then
                echo ","
            fi
        done)
    }
}
EOF
)

    # Send the PUT request and capture response
    response=$(curl -X PUT "$URL" \
         -H "Content-Type: application/json" \
         -d "$json_body" \
         -w "\n%{http_code}")

    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | sed '$d')

    # Process any commands if present
    if [ "$http_code" = "200" ]; then
        process_commands "$response_body"
    fi

    # Print the sent data and response
    echo "Sent data:"
    echo "$json_body" | jq '.'
    echo "Response:"
    echo "$response_body" | jq '.'
    echo "HTTP Status: $http_code"
    echo "-------------------"
    
    # Sleep for 10 seconds
    sleep 10
done
