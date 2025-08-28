from flask import Flask, request, render_template, jsonify
from threading import Lock 
from flask_cors import CORS

app = Flask(__name__)
data_lock = Lock()
CORS(app)

# Shared data storage (latest sensor data)
sensor_data = {
    "roll": 0.0,
    "pitch": 0.0,
    "yaw": 0.0,
    "temperature": 0.0,
    "pressure": 0.0,
    "steps": 0
}

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/upload', methods=['POST'])
def upload():
    global sensor_data
    json_data = request.get_json()
    if not json_data:
        return jsonify({"error": "No JSON received"}), 400
    with data_lock:
        sensor_data.update(json_data)
    return jsonify({"status": "success"}), 200

@app.route('/data')
def data():
    with data_lock:
        return jsonify(sensor_data)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
