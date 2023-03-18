import os
import openai
from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler

# Initialize the OpenAI API
openai.api_key = os.getenv("OPENAI_API_KEY")

# Initialize the Slackbot
app = App()

# Function to interact with ChatGPT
def chat_gpt(prompt):
    model_engine = "text-davinci-002"
    completions = openai.Completion.create(
        engine=model_engine,
        prompt=prompt,
        max_tokens=250,
        n=1,
        stop=None,
        temperature=0.5,
    )
    message = completions.choices[0].text.strip()
    return message

# Event listener for messages
@app.event("app_mention")
def handle_app_mentions(body, say):
    print("Received an app_mention event:", body)
    text = body['event'].get('text')
    if text:
        prompt = f"{text}"
        response = chat_gpt(prompt)
        say(response)

# Run the Slackbot
if __name__ == "__main__":
    handler = SocketModeHandler(app, os.environ["SLACK_APP_TOKEN"])
    handler.start()
