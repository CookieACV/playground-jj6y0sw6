# Lesson 1: Variables, printing, and making decisions
# Lines starting with # are comments: Python ignores them.

# 1. A variable is a named box that holds a value.
name = "Ada"          # text (a "string") goes in quotes
age = 12              # a whole number (an "int")

# 2. print() shows things on the screen.
print("Hello,", name)
print("Next year you will be", age + 1)

# 3. if / else lets the program make decisions.
#    Notice the colon (:) and the indented lines underneath.
if age >= 13:
    print("You're a teenager!")
else:
    print("Not a teenager yet.")

# 4. A loop repeats work. range(1, 4) gives 1, 2, 3.
for number in range(1, 4):
    print(number, "squared is", number * number)

# ---------------------------------------------------------------
# YOUR TURN (edit this file, then run: python3 lessons/lesson01.py)
#  a) Change name and age to your own and run it again.
#  b) Make the loop go up to 10 instead of 3.
#  c) Add a new variable `city` and print "I live in <city>".
# ---------------------------------------------------------------
