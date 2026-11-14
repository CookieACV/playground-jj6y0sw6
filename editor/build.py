# Builds index.html from template.html + the lesson files.
import json, pathlib
root = pathlib.Path(__file__).resolve().parent
L = root.parent / "lessons"
lessons = [
    {"id": "l1", "name": "1 · Basics", "file": "lesson01.py", "code": (L/"lesson01.py").read_text()},
    {"id": "l2", "name": "2 · Lists & functions", "file": "lesson02.py", "code": (L/"lesson02.py").read_text()},
    {"id": "l3", "name": "3 · Guessing game", "file": "lesson03_guessing_game.py", "code": (L/"lesson03_guessing_game.py").read_text()},
    {"id": "my", "name": "My code", "file": "my_code.py", "code": "# This is your space. Write anything you like!\n\nprint(\"Hello from me!\")\n"},
]
data = json.dumps(lessons).replace("</", "<\\/")
(root/"index.html").write_text((root/"template.html").read_text().replace("__LESSONS__", data))
