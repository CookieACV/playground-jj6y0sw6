# Lesson 3: Your first game - Guess the Number!
# New ideas: import, input(), int(), and the while loop.

import random   # borrow Python's ready-made tools for random numbers

secret = random.randint(1, 20)   # a random whole number from 1 to 20
guesses = 0

print("I'm thinking of a number between 1 and 20.")

# `while` keeps looping as long as its condition is True.
while True:
    text = input("Your guess: ")   # input() waits for you to type
    guess = int(text)               # turn the typed text into a number
    guesses = guesses + 1

    if guess < secret:
        print("Too low!")
    elif guess > secret:            # elif = "else if"
        print("Too high!")
    else:
        print("You got it in", guesses, "guesses!")
        break                       # break = leave the loop

# ---------------------------------------------------------------
# YOUR TURN (run: python3 lessons/lesson03_guessing_game.py)
#  a) Play it a few times. What's the smartest way to guess?
#  b) Change it to 1-100.
#  c) Give the player only 5 tries. Hint: change `while True:` to
#     `while guesses < 5:` and print the secret if they run out.
#  d) What happens if you type "hello" instead of a number? (We'll fix
#     that crash in a later lesson!)
# ---------------------------------------------------------------
