from flask import Flask, request, jsonify
import numpy as np
from sklearn.linear_model import LogisticRegression  # Or any simple model

app = Flask(__name__)

# Example: Train a very simple logistic regression on synthetic data
# (In reality, collect or use a small dataset with HR, temp, and risk labels)
# For demo: High risk if HR high and temp high
X_train = np.array([[60, 36.5], [80, 37.0], [120, 39.0], [100, 38.5], [90, 37.8]])
y_train = np.array([0, 0, 1, 1, 0])  # 0 = low, 1 = high
model = LogisticRegression()
model.fit(X_train, y_train)

@app.route('/predict', methods=['POST'])
def predict():
    data = request.json
    hr = data.get('hr', 0)
    temp = data.get('temp', 0)
    
    # Simple improved rule-based (or use model)
    if hr > 110 or temp > 38.5:
        risk = "High"
        prob = 90
    elif hr > 95 or temp > 37.8:
        risk = "Medium"
        prob = 60
    else:
        risk = "Low"
        prob = 10
    
    # Or use ML model for probability (uncomment to use)
    # features = np.array([[hr, temp]])
    # prob = int(model.predict_proba(features)[0][1] * 100)
    # risk = "High" if prob > 70 else "Medium" if prob > 40 else "Low"
    
    return jsonify({
        'risk_level': risk,
        'risk_probability': prob,
        'message': f"Risk: {risk} ({prob}%)"
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)