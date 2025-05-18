

from flask import Flask, request, jsonify
import requests

app = Flask(__name__)

GROQ_API_KEY = "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"
GROQ_MODEL = "llama-3.3-70b-versatile"

@app.route('/chat', methods=['POST'])
def chat():
    user_message = request.json.get("message")
    if not user_message:
        return jsonify({"error": "No message provided"}), 400

    groq_url = "https://api.groq.com/openai/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {GROQ_API_KEY}"
    }
    data = {
        "model": "llama-3.3-70b-versatile",
        "messages": [
            {"role": "system", "content": "You are a helpful and medically knowledgeable assistant. Respond with clear, safe medical advice."},
            {"role": "user", "content": user_message}
        ],
        "temperature": 0.5
    }
    response = requests.post(groq_url, headers=headers, json=data)
    if response.status_code == 200:
        reply = response.json()['choices'][0]['message']['content']
        return jsonify({"reply": reply})
    else:
        return jsonify({"error": "Groq API error", "details": response.text}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5003)
   
