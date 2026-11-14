# Lesson 2: Lists and functions

# ---------------------------------------------------------------
# PART A: Lists - one variable that holds many values, in order.
# ---------------------------------------------------------------
fruits = ["apple", "banana", "cherry"]

print(fruits)          # the whole list
print(fruits[0])       # the FIRST item. Python counts from 0!
print(fruits[2])       # the third item
print(len(fruits))     # len() = how many items: 3

fruits.append("mango") # add an item to the end
print(fruits)

# Loop over a list: `fruit` becomes each item in turn.
for fruit in fruits:
    print("I like", fruit)

# ---------------------------------------------------------------
# PART B: Functions - give a name to some code so you can reuse it.
# ---------------------------------------------------------------
# `def` creates a function. `person` is a parameter: an input box.
def greet(person):
    print("Hi there,", person + "!")

greet("Sam")       # calling the function runs the code inside it
greet("Priya")

# A function can hand a value back with `return`.
def double(n):
    return n * 2

result = double(21)
print("Double 21 is", result)

# Functions + lists together: add up every number in a list.
def total(numbers):
    running_sum = 0
    for n in numbers:
        running_sum = running_sum + n
    return running_sum

scores = [10, 25, 7]
print("Total score:", total(scores))

# ---------------------------------------------------------------
# YOUR TURN (run: python3 lessons/lesson02.py)
#  a) Make a list of 3 of your favourite foods and print each one.
#  b) Write a function `triple(n)` that returns n * 3. Print triple(5).
#  c) Write a function `biggest(numbers)` that returns the largest number
#     in a list. Hint: start with biggest_so_far = numbers[0], then loop
#     and use `if n > biggest_so_far:`. (Test: biggest([4, 9, 2]) -> 9)
# ---------------------------------------------------------------
