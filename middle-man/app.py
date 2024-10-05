from flask import Flask, request, jsonify

app = Flask(__name__)

# In-memory storage
# Scalable implementation would be something like mongodb or/and redis
data_store = {}


# data_store = {
#     "device123": {
#         "data": { ... },  # Data sent from the data source
#         "command": "restart"  # Command sent from the data consumer
#     },
#     "device456": {
#         "data": { ... },
#         "command": "status"
#     }
# }

@app.route('/data/<identifier>', methods=['PUT'])
def put_data(identifier):
    data = request.json

    # Check if identifier already exists in the store
    if identifier not in data_store:
        data_store[identifier] = {
            'data': None,
            'commands': []
        }

    # Update the data for the identifier
    data_store[identifier]['data'] = data


    if len(data_store[identifier]['commands']) > 0:
        # Get the commands and clear the array
        commands = data_store[identifier]['commands']
        data_store[identifier]['commands'] = []

        return jsonify({
            'message': 'Data received',
            'command': commands
        }), 200
    else:
        return jsonify({'message': 'Data received'}), 201

@app.route('/data/<identifier>', methods=['GET'])
def get_data(identifier):
    # Check if identifier exists in the store
    if identifier not in data_store or 'data' not in data_store[identifier]:
        return jsonify({'error': 'Data not found'}), 404

    # Return the data for the identifier
    return jsonify(data_store[identifier]['data'])

@app.route('/command/<identifier>', methods=['POST'])
def post_command(identifier):
    # Check if identifier exists in the store
    command_data = request.json.get('command')

    if not command_data:
        return jsonify({'error': 'Missing command'}), 400

    # Check if identifier exists in the store
    if identifier not in data_store:
        data_store[identifier] = {
            'data': None,
            'commands': []
        }

    # Store the command in the "command" key
    data_store[identifier]['commands'].append(command_data)

    return jsonify({
        'message': 'Command added'
    })

