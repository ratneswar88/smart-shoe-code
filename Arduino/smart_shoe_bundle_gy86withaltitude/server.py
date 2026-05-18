from flask import Flask, request, jsonify, render_template

app = Flask(__name__)

latest_data = {
    "roll": 0,
    "pitch": 0,
    "yaw": 0,
    "temperature": 0,
    "pressure": 0,
    "steps": 0
}

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/upload', methods=['POST'])
def upload():
    global latest_data
    latest_data = request.get_json()
    print("Received:", latest_data)
    return 'OK', 200

@app.route('/data')
def data():
    return jsonify(latest_data)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
