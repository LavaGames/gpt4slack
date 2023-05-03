FROM --platform=linux/arm64 python:3.11

RUN mkdir -p /app
COPY gpt4slack.py requirements.txt /app/
RUN pip install -r /app/requirements.txt

CMD ["python3", "/app/gpt4slack.py"]
