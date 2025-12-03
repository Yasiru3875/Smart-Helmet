# server_predict.py
from flask import Flask, request, jsonify
import joblib
import numpy as np

app = Flask(__name__)
model = joblib.load('heart_attack_model.pkl')  # confirm path

@app.route('/predict', methods=['POST'])
def predict():
    data = request.get_json(force=True)
    try:
        hr = float(data['heart_rate'])
        temp = float(data['temperature'])
    except Exception as e:
        return jsonify({'error': 'invalid input', 'details': str(e)}), 400

    X = np.array([[hr, temp]])
    prob = None
    try:
        prob = model.predict_proba(X)[0,1]  # probability of class 1
    except Exception:
        # fallback if predict_proba not supported
        pred = int(model.predict(X)[0])
        return jsonify({'risk': int(pred), 'probability': None})

    pred = int(model.predict(X)[0])
    return jsonify({'risk': pred, 'probability': float(prob)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
