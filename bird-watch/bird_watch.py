"""
Bird Watch: an AI camera that keeps watch 24/7.

How it works
  1. This program reads your camera non-stop.
  2. When something moves (and every 30 minutes anyway) it sends a photo to Claude.
  3. Claude says which animals it sees, what they're doing and how healthy they look.
  4. Sightings are saved in the "sightings" folder and shown on a website.

The website is only a window into this program. Close the browser and the
program keeps watching. Only stopping the program (Ctrl+C) stops it.

Start it with:   python bird_watch.py
Then open:       http://localhost:8000
"""

import base64
import json
import os
import socket
import sys
import threading
import time
import urllib.request
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit

import anthropic
import cv2


# =====================================================================
# SETTINGS: change these to fit your setup
# =====================================================================

# Which camera to use:
#   0 = the computer's built-in webcam (try 1 for a USB camera)
#   or a phone camera link from an "IP Webcam" style app,
#   for example "http://192.168.1.20:8080/video"
CAMERA = 0

# Tell Claude what the camera is pointed at. It helps it guess better.
WHAT_TO_WATCH = "a backyard bird feeder"

# Which Claude model looks at the photos.
#   "claude-opus-5-5"  = the most capable (roughly 1 to 2 cents per check)
#   "claude-haiku-5-5" = much cheaper (a few hundredths of a cent per check)
MODEL = "claude-opus-5-5"

# Claude looks at most once every this many seconds, even if things keep moving.
SECONDS_BETWEEN_CHECKS = 60

# Look anyway every this many minutes, even if nothing moved.
# (Useful for checking on an animal that is sitting still or sleeping.)
CHECK_IN_MINUTES = 30

# Safety limit: never ask Claude more than this many times in one day.
MAX_CHECKS_PER_DAY = 300

# How much of the picture has to change to count as movement. 0.005 means 0.5%.
# Make it smaller (0.002) for small birds far away, or bigger (0.02) if
# wind, leaves or shadows set it off too often.
MOTION_SENSITIVITY = 0.005

# Optional phone alerts when an animal may need help. Install the free
# "ntfy" app, subscribe to a topic with a hard-to-guess name (anyone who
# knows the name can read it), and put that name here. "" = no alerts.
PHONE_ALERT_TOPIC = ""

# The website's port: the number at the end of http://localhost:8000
WEBSITE_PORT = 8000

# The folder (next to this file) where photos and the log are saved.
SAVE_FOLDER = "sightings"


# =====================================================================
# Shared state
# =====================================================================

FOLDER = os.path.dirname(os.path.abspath(__file__))
SAVE_PATH = os.path.join(FOLDER, SAVE_FOLDER)
LOG_FILE = os.path.join(SAVE_PATH, "log.jsonl")

# The camera loop, the Claude checks and the website all run at the same
# time (in "threads"), so they share this dictionary. The lock makes sure
# only one of them changes it at a time.
lock = threading.Lock()
state = {
    "camera_ok": False,
    "live_photo": None,        # the newest camera picture, as JPEG bytes
    "checking": False,         # True while Claude is looking at a photo
    "check_requested": False,  # True after someone presses "Check now"
    "stopped": False,          # True if Claude can't be used until a restart
    "day": "",                 # today's date, to reset the counter at midnight
    "checks_today": 0,
    "last_check": "",
    "camera_problem": "",
    "claude_problem": "",
    "history": [],             # every check, newest first
}

# Talks to Claude. It reads your key from the ANTHROPIC_API_KEY setting.
client = anthropic.Anthropic()


# =====================================================================
# Photos
# =====================================================================

def shrink(frame, longest_side):
    """Make a camera picture smaller, keeping its shape."""
    height, width = frame.shape[:2]
    scale = longest_side / max(height, width)
    if scale >= 1:
        return frame
    new_size = (int(width * scale), int(height * scale))
    return cv2.resize(frame, new_size, interpolation=cv2.INTER_AREA)


def to_jpeg(frame, quality=85):
    """Turn a camera picture into JPEG bytes, the format we save and send."""
    ok, data = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, quality])
    return data.tobytes() if ok else None


def prepare_for_motion(frame):
    """A small, grey, blurry copy of the picture. Blurring hides camera noise."""
    small = cv2.resize(frame, (320, 240))
    grey = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
    return cv2.GaussianBlur(grey, (21, 21), 0)


# =====================================================================
# Asking Claude
# =====================================================================

# Claude must answer in exactly this shape, so the program can read it.
REPORT_SHAPE = {
    "type": "object",
    "properties": {
        "animals_seen": {"type": "boolean"},
        "animals": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "kind": {"type": "string"},
                    "species": {"type": "string"},
                    "count": {"type": "integer"},
                    "doing": {"type": "string"},
                    "condition": {
                        "type": "string",
                        "enum": ["looks healthy", "possibly unwell", "possibly injured", "can't tell"],
                    },
                    "condition_notes": {"type": "string"},
                },
                "required": ["kind", "species", "count", "doing", "condition", "condition_notes"],
                "additionalProperties": False,
            },
        },
        "summary": {"type": "string"},
        "needs_attention": {"type": "boolean"},
        "attention_reason": {"type": "string"},
    },
    "required": ["animals_seen", "animals", "summary", "needs_attention", "attention_reason"],
    "additionalProperties": False,
}


def make_question(when):
    """The instructions Claude gets with every photo."""
    return (
        f"This photo comes from a camera watching {WHAT_TO_WATCH}. "
        f"It was taken on {when:%A %d %B at %H:%M}.\n\n"
        "Look for animals, especially birds. For each kind of animal you can see, give:\n"
        "- kind: a plain word such as bird, squirrel or cat\n"
        "- species: your best guess, for example \"house sparrow\", or \"unknown\"\n"
        "- count: how many of that kind are visible\n"
        "- doing: what it is doing, in a few words\n"
        "- condition and condition_notes: how healthy it looks from what is visible. "
        "Check feathers or fur, posture and movement, and look for wounds, a limp, a drooping wing, "
        "swollen or crusty eyes, or feathers fluffed up on a warm day. "
        "Use \"can't tell\" when the photo is too dark, blurry or far away to judge.\n\n"
        "summary: one or two plain sentences about the scene.\n"
        "needs_attention: true only if an animal looks injured, sick, trapped or in danger "
        "(for example a cat or hawk stalking the birds). Then say why in attention_reason; "
        "otherwise leave attention_reason empty.\n"
        "If no animals are visible, set animals_seen to false and animals to an empty list."
    )


def ask_claude(photo_jpeg, when):
    """Send one photo to Claude and get its report back as a dictionary."""
    extra_settings = {}
    if not MODEL.startswith("claude-haiku"):
        # If Claude ever declines to answer, a backup model answers instead.
        # (Haiku doesn't have this option, so it's skipped for Haiku.)
        extra_settings = {"betas": ["server-side-fallback-2026-07-01"], "fallbacks": "default"}

    photo_text = base64.standard_b64encode(photo_jpeg).decode("ascii")
    response = client.beta.messages.create(
        model=MODEL,
        max_tokens=16000,
        output_config={
            "effort": "low",  # a quick look is enough, and keeps each check cheap
            "format": {"type": "json_schema", "schema": REPORT_SHAPE},
        },
        messages=[{
            "role": "user",
            "content": [
                {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": photo_text}},
                {"type": "text", "text": make_question(when)},
            ],
        }],
        **extra_settings,  # ** unpacks the dictionary into more settings
    )

    if response.stop_reason == "refusal":
        raise RuntimeError("Claude declined to describe this photo.")
    if response.stop_reason == "max_tokens":
        raise RuntimeError("Claude's answer was cut off.")
    answer = next(block.text for block in response.content if block.type == "text")
    return json.loads(answer)


# =====================================================================
# Phone alerts
# =====================================================================

last_alert_time = 0.0


def send_phone_alert(message):
    """Send a phone notification through ntfy, at most once every 15 minutes."""
    global last_alert_time
    if not PHONE_ALERT_TOPIC or time.time() - last_alert_time < 15 * 60:
        return
    last_alert_time = time.time()
    request = urllib.request.Request(
        "https://ntfy.sh/" + PHONE_ALERT_TOPIC,
        data=message.encode("utf-8"),
        headers={"Title": "Bird Watch: an animal may need help", "Priority": "high", "Tags": "bird"},
    )
    try:
        urllib.request.urlopen(request, timeout=10)
    except OSError as error:
        print("Couldn't send the phone alert:", error)


# =====================================================================
# Checks
# =====================================================================

def try_to_start_check(frame, reason):
    """Start a Claude check in the background, unless one is running or the
    daily limit is reached. Returns True if a check started."""
    with lock:
        today = datetime.now().strftime("%Y-%m-%d")
        if state["day"] != today:  # a new day: reset the counter
            state["day"] = today
            state["checks_today"] = 0
            state["claude_problem"] = ""
        if state["checking"] or state["stopped"]:
            return False
        if state["checks_today"] >= MAX_CHECKS_PER_DAY:
            state["claude_problem"] = (
                f"Reached today's limit of {MAX_CHECKS_PER_DAY} checks. Claude starts looking again tomorrow."
            )
            state["check_requested"] = False
            return False
        state["checks_today"] += 1
        state["checking"] = True

    # A thread runs run_check at the same time as the camera loop, so the
    # live view keeps updating while Claude looks at the photo.
    threading.Thread(target=run_check, args=(frame.copy(), reason), daemon=True).start()
    return True


def run_check(frame, reason):
    """Ask Claude about one photo, save what it says, and alert if needed."""
    now = datetime.now()
    photo = to_jpeg(shrink(frame, 1024))
    entry = {"time": now.strftime("%Y-%m-%d %H:%M:%S"), "reason": reason}
    stop_checking = False

    try:
        report = ask_claude(photo, now)
        entry.update(report)
        if report["animals_seen"]:
            name = now.strftime("%Y-%m-%d_%H-%M-%S") + ".jpg"
            with open(os.path.join(SAVE_PATH, name), "wb") as file:
                file.write(photo)
            entry["photo"] = name
        if report["needs_attention"]:
            send_phone_alert(report["attention_reason"] or report["summary"])
    except (anthropic.AuthenticationError, anthropic.PermissionDeniedError):
        entry["error"] = "Claude didn't accept the API key. Check ANTHROPIC_API_KEY, then restart the program."
        stop_checking = True
    except anthropic.RateLimitError:
        entry["error"] = "Claude is busy, or your API usage limit was reached. It will try again later."
    except anthropic.APIConnectionError:
        entry["error"] = "Couldn't reach Claude. Is the internet working?"
    except anthropic.APIStatusError as error:
        entry["error"] = f"Claude returned an error ({error.status_code}): {error.message}"
    except Exception as error:
        entry["error"] = f"Something went wrong: {error}"

    with lock:
        state["history"].insert(0, entry)
        del state["history"][500:]  # keep the newest 500 in memory
        state["last_check"] = entry["time"]
        state["checking"] = False
        state["claude_problem"] = entry.get("error", "")
        if stop_checking:
            state["stopped"] = True

    with open(LOG_FILE, "a", encoding="utf-8") as file:
        file.write(json.dumps(entry) + "\n")

    clock = now.strftime("%H:%M:%S")
    if "error" in entry:
        print(f"[{clock}] {reason}: {entry['error']}")
    else:
        flag = "  ** NEEDS ATTENTION **" if entry["needs_attention"] else ""
        print(f"[{clock}] {reason}: {entry['summary']}{flag}")


def load_history():
    """Read earlier checks from the log, so the website shows them after a restart."""
    entries = []
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE, encoding="utf-8") as file:
            for line in file:
                try:
                    entries.append(json.loads(line))
                except json.JSONDecodeError:
                    pass  # skip a damaged line
    today = datetime.now().strftime("%Y-%m-%d")
    state["day"] = today
    state["checks_today"] = sum(1 for e in entries if e.get("time", "").startswith(today))
    state["history"] = list(reversed(entries))[:500]
    if entries:
        state["last_check"] = entries[-1].get("time", "")


# =====================================================================
# The camera loop
# =====================================================================

def set_camera(ok, problem=""):
    with lock:
        state["camera_ok"] = ok
        state["camera_problem"] = problem


def watch_camera():
    """Read the camera forever, watch for movement, and start Claude checks."""
    camera = None
    background = None          # what the scene normally looks like
    started = time.time()
    last_check = 0.0
    next_check_in = started + 5  # take a first look 5 seconds after starting
    last_live_update = 0.0

    while True:
        # Connect to the camera (again) if needed.
        if camera is None:
            camera = cv2.VideoCapture(CAMERA)
            if not camera.isOpened():
                camera = None
                set_camera(False, "Can't open the camera. Check CAMERA in the settings, "
                                  "and close other apps that might be using it.")
                time.sleep(5)
                continue
            background = None

        ok, frame = camera.read()
        if not ok:
            # The camera stopped sending pictures (unplugged, or a video file ended).
            camera.release()
            camera = None
            set_camera(False, "Lost the camera. Trying to reconnect...")
            time.sleep(2)
            continue

        now = time.time()

        # About once a second, keep a fresh picture for the website's live view.
        if now - last_live_update >= 1:
            live = to_jpeg(shrink(frame, 800), quality=70)
            with lock:
                state["live_photo"] = live
            set_camera(True)
            last_live_update = now

        # Movement: compare this picture with the usual background.
        picture = prepare_for_motion(frame)
        if background is None:
            background = picture.astype("float")
        difference = cv2.absdiff(picture, cv2.convertScaleAbs(background))
        changed = (difference > 25).mean()  # the share of the picture that changed
        cv2.accumulateWeighted(picture, background, 0.05)  # slowly learn the new normal
        moved = changed > MOTION_SENSITIVITY and now - started > 3  # skip the first seconds

        with lock:
            asked = state["check_requested"]

        reason = None
        if asked:
            reason = "you asked"
        elif moved and now - last_check >= SECONDS_BETWEEN_CHECKS:
            reason = "movement"
        elif now >= next_check_in:
            reason = "check-in"

        if reason and try_to_start_check(frame, reason):
            last_check = now
            next_check_in = now + CHECK_IN_MINUTES * 60
            with lock:
                state["check_requested"] = False

        time.sleep(0.03)


# =====================================================================
# The website
# =====================================================================

def make_status():
    """Everything the website shows, as a dictionary."""
    with lock:
        recent = [e for e in state["history"] if e.get("animals_seen") or e.get("error")][:100]
        return {
            "watching": WHAT_TO_WATCH,
            "model": MODEL,
            "camera_ok": state["camera_ok"],
            "checking": state["checking"],
            "checks_today": state["checks_today"],
            "max_checks": MAX_CHECKS_PER_DAY,
            "last_check": state["last_check"],
            "problems": [p for p in (state["camera_problem"], state["claude_problem"]) if p],
            "recent": recent,
        }


class Website(BaseHTTPRequestHandler):
    """Answers the browser. Each address (path) gives back something different."""

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/":
            self.send_file(os.path.join(FOLDER, "dashboard.html"), "text/html; charset=utf-8")
        elif path == "/api/status":
            self.send_json(make_status())
        elif path == "/live.jpg":
            with lock:
                photo = state["live_photo"]
            if photo:
                self.send_bytes(photo, "image/jpeg")
            else:
                self.send_error(404, "No camera picture yet")
        elif path.startswith("/photos/"):
            name = os.path.basename(unquote(path[len("/photos/"):]))
            file = os.path.join(SAVE_PATH, name)
            if name.endswith(".jpg") and os.path.isfile(file):
                self.send_file(file, "image/jpeg", cache=True)
            else:
                self.send_error(404)
        else:
            self.send_error(404)

    def do_POST(self):
        if urlsplit(self.path).path != "/api/check-now":
            self.send_error(404)
            return
        with lock:
            if state["stopped"]:
                message = "Claude can't be used until the API key is fixed and the program restarts."
            elif state["checks_today"] >= MAX_CHECKS_PER_DAY:
                message = "Today's check limit is reached."
            else:
                state["check_requested"] = True
                message = "Claude will look in a moment."
        self.send_json({"message": message})

    def send_bytes(self, data, content_type, cache=False):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "max-age=86400" if cache else "no-store")
        self.end_headers()
        self.wfile.write(data)

    def send_file(self, file, content_type, cache=False):
        with open(file, "rb") as f:
            self.send_bytes(f.read(), content_type, cache)

    def send_json(self, data):
        self.send_bytes(json.dumps(data).encode("utf-8"), "application/json")

    def log_message(self, format, *args):
        pass  # don't print every web request in the terminal


class QuietServer(ThreadingHTTPServer):
    def handle_error(self, request, client_address):
        # A browser closing a connection early isn't a real problem; stay quiet about it.
        if not isinstance(sys.exc_info()[1], ConnectionError):
            super().handle_error(request, client_address)


def local_address():
    """This computer's address on the Wi-Fi, so a phone can open the website."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))  # nothing is actually sent
            return s.getsockname()[0]
    except OSError:
        return "localhost"


# =====================================================================
# Start everything
# =====================================================================

def main():
    os.makedirs(SAVE_PATH, exist_ok=True)
    load_history()

    try:
        server = QuietServer(("0.0.0.0", WEBSITE_PORT), Website)
    except OSError:
        print(f"Port {WEBSITE_PORT} is already in use. Is Bird Watch already running? "
              "If not, change WEBSITE_PORT in the settings.")
        return
    threading.Thread(target=server.serve_forever, daemon=True).start()

    print("Bird Watch is running.")
    print(f"  On this computer:          http://localhost:{WEBSITE_PORT}")
    print(f"  On a phone on the same Wi-Fi: http://{local_address()}:{WEBSITE_PORT}")
    print("  Press Ctrl+C to stop.\n")
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("Warning: ANTHROPIC_API_KEY isn't set, so Claude can't look at photos yet. "
              "See step 3 in README.md.\n")

    try:
        watch_camera()
    except KeyboardInterrupt:
        print("\nStopped. Bye!")


if __name__ == "__main__":
    main()
