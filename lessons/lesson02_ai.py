# Lesson 2: Build your own (tiny) AI chatbot
# Run it with: python3 lessons/lesson02_ai.py
#
# Real AIs like Claude learn from huge amounts of text. Ours is much
# simpler: it looks for keywords in what you type, and when it doesn't
# know an answer, it asks YOU to teach it. That is still a kind of
# "learning", and it uses only a few new Python ideas.

import random

# 1. A dictionary maps a KEY to a VALUE, like a word to its meaning.
#    Here each keyword maps to a list of possible replies.
brain = {
    "hello": ["Hi there!", "Hello, human!", "Hey! Nice to meet you."],
    "how are you": ["I'm just code, but I feel great!", "Running smoothly, thanks!"],
    "your name": ["I'm Byte, a tiny AI you built in Python."],
    "joke": [
        "Why do programmers prefer dark mode? Because light attracts bugs.",
        "I would tell you a UDP joke, but you might not get it.",
    ],
    "python": ["Python is my native language!", "Python is named after Monty Python, not the snake."],
}


# 2. A function is a reusable block of code. You give it input
#    (here, what the user typed) and it gives back ("returns") an answer.
def find_reply(message):
    message = message.lower()          # "HeLLo" becomes "hello"
    for keyword in brain:
        if keyword in message:         # is the keyword inside the message?
            return random.choice(brain[keyword])
    return None                        # None means "I don't know"


def learn(message):
    print("Byte: I don't know how to answer that yet. What should I say?")
    answer = input("You (teaching): ").strip()
    if answer:
        brain[message.lower()] = [answer]   # add a new entry to the dictionary
        print("Byte: Got it! I'll remember that.")
    else:
        print("Byte: No worries, maybe next time.")


# 3. A while loop keeps going until we tell it to stop with `break`.
print("Byte: Hi! I'm Byte, your AI. Type 'bye' to quit.")
while True:
    try:
        message = input("You: ").strip()
    except EOFError:                   # input ran out (e.g. Ctrl+D)
        break
    if message.lower() == "bye":
        print("Byte: Goodbye! Thanks for building me.")
        break
    if message == "":
        continue                       # skip empty lines, go back to the top

    reply = find_reply(message)
    if reply:
        print("Byte:", reply)
    else:
        learn(message)

# ---------------------------------------------------------------
# YOUR TURN
#  a) Rename the AI from "Byte" to a name you like.
#  b) Add a new keyword to `brain`, e.g. "favorite color".
#  c) Teach it something while it runs, then ask the same thing again.
#  d) Challenge: right now Byte forgets everything when it stops.
#     Look up Python's `json` module and save `brain` to a file so it
#     remembers between runs.
# ---------------------------------------------------------------
