"""
Bird Watch: an AI video scanner that keeps watch 24/7, with any camera.

How it works
  1. This program reads your camera's video non-stop. Any camera works:
     a webcam, a GoPro in webcam mode, a security camera, or an old phone.
  2. When something moves (and every 30 minutes anyway) it records a short clip.
  3. Claude watches frames from the clip and says which animals it sees, what
     they're doing, and whether anything doesn't look right.
  4. If something doesn't look right, it sends you a phone notification and an
     email with a photo and the clip.
  5. Every sighting is saved in the "sightings" folder and shown on a website.

The website is only a window into this program. Close the browser and the
program keeps watching. Only stopping the program (Ctrl+C) stops it.

Start it with:      python bird_watch.py
Find your camera:   python bird_watch.py --find-cameras
Then open:          http://localhost:8000
"""

import base64
import io
import json
import os
import smtplib
import socket
import sys
import threading
import time
import urllib.parse
import urllib.request
from collections import deque
from datetime import datetime
from email.message import EmailMessage
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import anthropic
import cv2
from PIL import Image


# =====================================================================
# SETTINGS: change these to fit your setup
# =====================================================================

# ---------- Camera ----------

# Which camera to use. Any camera works:
#   0, 1, 2 ...   a webcam, a GoPro in webcam mode, or an HDMI capture adapter.
#                 Run "python bird_watch.py --find-cameras" to see the numbers.
#   "rtsp://..."  a Wi-Fi security camera's video link (look in its app or manual)
#   "http://..."  a phone camera app's video link
CAMERA = 0

# Tell Claude what the camera is pointed at. It helps it guess better.
WHAT_TO_WATCH = "a backyard bird feeder"

# ---------- Claude ----------

# Which Claude model watches the clips.
#   "claude-opus-5-5"  = the most capable (roughly 2 to 3 cents per check)
#   "claude-haiku-5-5" = much cheaper (well under a tenth of a cent per check)
MODEL = "claude-opus-5-5"

# How many frames from each clip Claude looks at. More frames show movement
# better (like a limp); fewer frames cost less.
FRAMES_FOR_CLAUDE = 4

# Claude checks at most once every this many seconds, even if things keep moving.
SECONDS_BETWEEN_CHECKS = 60

# Check anyway every this many minutes, even if nothing moved.
# (Useful for an animal that is sitting still or sleeping.)
CHECK_IN_MINUTES = 30

# Safety limit: never ask Claude more than this many times in one day.
MAX_CHECKS_PER_DAY = 200

# How much of the picture has to change to count as movement. 0.005 means 0.5%.
# Make it smaller (0.002) for small animals far away, or bigger (0.02) if
# wind, leaves or shadows set it off too often.
MOTION_SENSITIVITY = 0.005

# ---------- Clips ----------

CLIP_SECONDS_BEFORE = 3  # video kept from just before the movement
CLIP_SECONDS_AFTER = 3   # video recorded after it
KEEP_DAYS = 14           # saved photos and clips older than this are deleted

# ---------- Alerts when something doesn't look right ----------

# Phone notifications: install the free "ntfy" app, subscribe to a topic with
# a hard-to-guess name (anyone who knows the name can read it), and put that
# name here. "" = no phone notifications.
PHONE_ALERT_TOPIC = ""

# Email: the address alerts go to, and the address that sends them.
# The sending account's password is NOT written here: put it in the
# EMAIL_APP_PASSWORD setting instead (see README.md). "" = no emails.
EMAIL_TO = ""
EMAIL_FROM = ""
EMAIL_SERVER = "smtp.gmail.com"  # Gmail. Other email services have their own.
EMAIL_PORT = 465

# At most one animal alert this often, so one hurt bird doesn't send fifty.
ALERT_EVERY_MINUTES = 15

# ---------- Website ----------

WEBSITE_PORT = 8000         # the number at the end of http://localhost:8000
SAVE_FOLDER = "sightings"   # where photos, clips and the log are saved


# =====================================================================
# Things you normally don't need to change
# =====================================================================

CLIP_FRAMES_PER_SECOND = 4    # how many frames per second clips keep
CAMERA_ALERT_MINUTES = 5      # warn you if the camera is gone this long
NTFY_SERVER = "https://ntfy.sh"

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
    "busy": False,             # True while a clip is recorded or checked
    "activity": "",            # "recording" or "looking" while busy
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
# Pictures and clips
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


def make_gif(jpeg_frames, width=480):
    """Turn a clip's frames into an animated GIF: a short video that every
    phone, browser and email app can play."""
    images = []
    for data in jpeg_frames:
        image = Image.open(io.BytesIO(data)).convert("RGB")
        image.thumbnail((width, width))
        images.append(image)
    output = io.BytesIO()
    images[0].save(output, format="GIF", save_all=True, append_images=images[1:],
                   duration=1000 // CLIP_FRAMES_PER_SECOND, loop=0, optimize=True)
    return output.getvalue()


def pick_frames(frames, how_many):
    """Pick frames spread evenly through the clip."""
    if len(frames) <= how_many:
        return frames
    if how_many <= 1:
        return [frames[len(frames) // 2]]
    step = (len(frames) - 1) / (how_many - 1)
    return [frames[round(i * step)] for i in range(how_many)]


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


def make_question(when, frame_count, seconds):
    """The instructions Claude gets with every clip."""
    return (
        f"These {frame_count} frames, in order, come from a {seconds:.0f}-second video clip "
        f"recorded by a camera watching {WHAT_TO_WATCH}, on {when:%A %d %B at %H:%M}.\n\n"
        "Look for animals, especially birds. Compare the frames to see how each animal moves. "
        "For each kind of animal you can see, give:\n"
        "- kind: a plain word such as bird, squirrel or cat\n"
        "- species: your best guess, for example \"house sparrow\", or \"unknown\"\n"
        "- count: the most of that kind visible at once\n"
        "- doing: what it is doing, in a few words\n"
        "- condition and condition_notes: how healthy it looks. Check feathers or fur, posture and "
        "movement, and look for wounds, a limp, a drooping or dragging wing, trouble flying or keeping "
        "its balance, swollen or crusty eyes, feathers fluffed up on a warm day, or staying still when "
        "it normally wouldn't. Use \"can't tell\" when the video is too dark, blurry or far away to judge.\n\n"
        "summary: one or two plain sentences about what happens in the clip.\n"
        "needs_attention: true when something doesn't look right: an animal looks injured or sick, is "
        "trapped or tangled, is behaving strangely, or is in danger (for example a cat or hawk stalking "
        "the birds). Then explain what you saw in attention_reason, in one or two sentences; otherwise "
        "leave attention_reason empty.\n"
        "If no animals are visible, set animals_seen to false and animals to an empty list."
    )


def ask_claude(frames, when, seconds):
    """Send frames from one clip to Claude and get its report back as a dictionary."""
    content = []
    for number, frame in enumerate(frames, start=1):
        content.append({"type": "text", "text": f"Frame {number}:"})
        content.append({"type": "image", "source": {
            "type": "base64", "media_type": "image/jpeg",
            "data": base64.standard_b64encode(frame).decode("ascii"),
        }})
    content.append({"type": "text", "text": make_question(when, len(frames), seconds)})

    extra_settings = {}
    if not MODEL.startswith("claude-haiku"):
        # If Claude ever declines to answer, a backup model answers instead.
        # (Haiku doesn't have this option, so it's skipped for Haiku.)
        extra_settings = {"betas": ["server-side-fallback-2026-07-01"], "fallbacks": "default"}

    response = client.beta.messages.create(
        model=MODEL,
        max_tokens=16000,
        output_config={
            "effort": "low",  # a quick look is enough, and keeps each check cheap
            "format": {"type": "json_schema", "schema": REPORT_SHAPE},
        },
        messages=[{"role": "user", "content": content}],
        **extra_settings,  # ** unpacks the dictionary into more settings
    )

    if response.stop_reason == "refusal":
        raise RuntimeError("Claude declined to describe this clip.")
    if response.stop_reason == "max_tokens":
        raise RuntimeError("Claude's answer was cut off.")
    answer = next(block.text for block in response.content if block.type == "text")
    return json.loads(answer)


# =====================================================================
# Alerts: phone notification and email
# =====================================================================

def email_is_set_up():
    return bool(EMAIL_TO and EMAIL_FROM and os.environ.get("EMAIL_APP_PASSWORD"))


def send_phone_alert(title, text, photo=None, clip=None):
    """Send a phone notification through ntfy, with the clip (or photo) attached.
    Returns True if it was sent."""
    if not PHONE_ALERT_TOPIC:
        return False
    options = {"title": title, "message": text, "priority": "high", "tags": "warning"}
    attachment = clip or photo
    if attachment:
        options["filename"] = "clip.gif" if clip else "photo.jpg"
    url = f"{NTFY_SERVER}/{PHONE_ALERT_TOPIC}?{urllib.parse.urlencode(options)}"
    request = urllib.request.Request(url, data=attachment or b"", method="PUT")
    try:
        urllib.request.urlopen(request, timeout=30)
        return True
    except OSError as error:
        print("Couldn't send the phone notification:", error)
        return False


def send_email_alert(title, text, photo=None, clip=None):
    """Send an email with the photo and clip attached. Returns True if it was sent."""
    if not email_is_set_up():
        return False
    message = EmailMessage()
    message["Subject"] = title
    message["From"] = EMAIL_FROM
    message["To"] = EMAIL_TO
    message.set_content(text + "\n\nSent by Bird Watch.")
    if photo:
        message.add_attachment(photo, maintype="image", subtype="jpeg", filename="photo.jpg")
    if clip:
        message.add_attachment(clip, maintype="image", subtype="gif", filename="clip.gif")

    password = os.environ["EMAIL_APP_PASSWORD"]
    try:
        if EMAIL_PORT == 465:
            with smtplib.SMTP_SSL(EMAIL_SERVER, EMAIL_PORT, timeout=30) as server:
                server.login(EMAIL_FROM, password)
                server.send_message(message)
        else:
            with smtplib.SMTP(EMAIL_SERVER, EMAIL_PORT, timeout=30) as server:
                server.starttls()
                server.login(EMAIL_FROM, password)
                server.send_message(message)
        return True
    except smtplib.SMTPAuthenticationError:
        print("The email server didn't accept the password. For Gmail, use an app password "
              "(see README.md), not your normal password.")
    except (OSError, smtplib.SMTPException) as error:
        print("Couldn't send the email:", error)
    return False


def send_alerts(title, text, photo=None, clip=None):
    """Send a phone notification and an email (whichever are set up)."""
    phone = send_phone_alert(title, text, photo, clip)
    email = send_email_alert(title, text, photo, clip)
    return {"phone": phone, "email": email}


last_animal_alert = 0.0


def alert_about_animals(report, photo, clip):
    """Tell you something doesn't look right, at most once every ALERT_EVERY_MINUTES."""
    global last_animal_alert
    if time.time() - last_animal_alert < ALERT_EVERY_MINUTES * 60:
        return
    last_animal_alert = time.time()
    text = report["attention_reason"] or report["summary"]
    send_alerts("Bird Watch: something doesn't look right", text, photo, clip)


# =====================================================================
# Checks
# =====================================================================

def reserve_check():
    """Book the next check, unless one is running or the daily limit is reached.
    Returns True if the check can go ahead."""
    with lock:
        today = datetime.now().strftime("%Y-%m-%d")
        if state["day"] != today:  # a new day: reset the counter
            state["day"] = today
            state["checks_today"] = 0
            state["claude_problem"] = ""
        if state["busy"] or state["stopped"]:
            return False
        if state["checks_today"] >= MAX_CHECKS_PER_DAY:
            state["claude_problem"] = (
                f"Reached today's limit of {MAX_CHECKS_PER_DAY} checks. Claude starts watching again tomorrow."
            )
            state["check_requested"] = False
            return False
        state["checks_today"] += 1
        state["busy"] = True
        state["activity"] = "recording"
        return True


def run_check(frames, trigger_index, reason):
    """Ask Claude about one clip, save what it says, and alert you if needed.
    This runs in its own thread, so the camera keeps going meanwhile."""
    with lock:
        state["activity"] = "looking"
    now = datetime.now()
    seconds = len(frames) / CLIP_FRAMES_PER_SECOND
    entry = {"time": now.strftime("%Y-%m-%d %H:%M:%S"), "reason": reason}
    stop_checking = False

    try:
        report = ask_claude(pick_frames(frames, FRAMES_FOR_CLAUDE), now, seconds)
        entry.update(report)
        if report["animals_seen"] or report["needs_attention"]:
            stamp = now.strftime("%Y-%m-%d_%H-%M-%S")
            photo = frames[min(trigger_index, len(frames) - 1)]
            clip = make_gif(frames)
            with open(os.path.join(SAVE_PATH, stamp + ".jpg"), "wb") as file:
                file.write(photo)
            with open(os.path.join(SAVE_PATH, stamp + ".gif"), "wb") as file:
                file.write(clip)
            entry["photo"] = stamp + ".jpg"
            entry["clip"] = stamp + ".gif"
            if report["needs_attention"]:
                alert_about_animals(report, photo, clip)
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
        state["busy"] = False
        state["activity"] = ""
        state["claude_problem"] = entry.get("error", "")
        if stop_checking:
            state["stopped"] = True

    with open(LOG_FILE, "a", encoding="utf-8") as file:
        file.write(json.dumps(entry) + "\n")

    clock = now.strftime("%H:%M:%S")
    if "error" in entry:
        print(f"[{clock}] {reason}: {entry['error']}")
    else:
        flag = "  ** DOESN'T LOOK RIGHT **" if entry["needs_attention"] else ""
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


def delete_old_files():
    """Delete saved photos and clips older than KEEP_DAYS, so the disk doesn't fill up."""
    cutoff = time.time() - KEEP_DAYS * 24 * 60 * 60
    try:
        for item in os.scandir(SAVE_PATH):
            if item.name.endswith((".jpg", ".gif")) and item.stat().st_mtime < cutoff:
                os.remove(item.path)
    except OSError as error:
        print("Couldn't clean up old files:", error)


# =====================================================================
# The camera loop
# =====================================================================

camera_lost_since = None
camera_alert_sent = False


def camera_status(ok, problem=""):
    """Remember whether the camera works, and send an alert if it's been gone a while."""
    global camera_lost_since, camera_alert_sent
    with lock:
        state["camera_ok"] = ok
        state["camera_problem"] = problem
    if ok:
        camera_lost_since = None
        camera_alert_sent = False
        return
    if camera_lost_since is None:
        camera_lost_since = time.time()
    if not camera_alert_sent and time.time() - camera_lost_since > CAMERA_ALERT_MINUTES * 60:
        camera_alert_sent = True
        text = (f"Bird Watch hasn't had any video for {CAMERA_ALERT_MINUTES} minutes. "
                "Check that the camera is on, plugged in and charged.")
        threading.Thread(target=send_alerts, args=("Bird Watch: the camera stopped", text), daemon=True).start()


def open_camera():
    camera = cv2.VideoCapture(CAMERA)
    if isinstance(CAMERA, int):
        # Ask a webcam for HD video. Cameras that can't do it just ignore this.
        camera.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    return camera


def watch_camera():
    """Read the video forever, watch for movement, record clips and start Claude checks."""
    camera = None
    background = None              # what the scene normally looks like
    started = time.time()
    last_check = 0.0
    next_check_in = started + 5    # take a first look 5 seconds after starting
    last_live_update = 0.0
    next_clip_frame = 0.0
    next_cleanup = 0.0
    recent = deque()               # (time, JPEG) for the last few seconds of video
    recording = None               # the clip being recorded right now, if any

    while True:
        # Connect to the camera (again) if needed.
        if camera is None:
            camera = open_camera()
            if not camera.isOpened():
                camera = None
                camera_status(False, "Can't open the camera. Check CAMERA in the settings, "
                                     "and close other apps that might be using it.")
                time.sleep(5)
                continue
            background = None

        ok, frame = camera.read()
        if not ok:
            # The camera stopped sending video (unplugged, battery, or a video file ended).
            camera.release()
            camera = None
            camera_status(False, "Lost the camera. Trying to reconnect...")
            time.sleep(2)
            continue

        now = time.time()

        # About once a second, keep a fresh picture for the website's live view.
        if now - last_live_update >= 1:
            live = to_jpeg(shrink(frame, 800), quality=70)
            with lock:
                state["live_photo"] = live
            camera_status(True)
            last_live_update = now

        # A few times a second, keep a frame for clips.
        if now >= next_clip_frame:
            next_clip_frame = now + 1 / CLIP_FRAMES_PER_SECOND
            clip_frame = to_jpeg(shrink(frame, 960))
            recent.append((now, clip_frame))
            while recent and recent[0][0] < now - CLIP_SECONDS_BEFORE:
                recent.popleft()
            if recording:
                recording["frames"].append(clip_frame)

        # When a clip is finished, hand it to Claude in the background.
        if recording and now >= recording["until"]:
            threading.Thread(target=run_check, daemon=True,
                             args=(recording["frames"], recording["trigger_index"], recording["reason"])).start()
            recording = None

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

        # Start recording a clip: the last few seconds, plus a few more.
        if reason and recording is None and reserve_check():
            frames = [jpeg for _, jpeg in recent]
            recording = {"reason": reason, "frames": frames, "trigger_index": len(frames),
                         "until": now + CLIP_SECONDS_AFTER}
            last_check = now
            next_check_in = now + CHECK_IN_MINUTES * 60
            with lock:
                state["check_requested"] = False

        if now >= next_cleanup:
            delete_old_files()
            next_cleanup = now + 60 * 60  # once an hour

        time.sleep(0.03)


def find_cameras():
    """Try camera numbers 0 to 5 and say which ones work."""
    try:
        cv2.utils.logging.setLogLevel(cv2.utils.logging.LOG_LEVEL_SILENT)
    except AttributeError:
        pass
    print("Looking for cameras (this takes a few seconds)...")
    found = 0
    for number in range(6):
        camera = cv2.VideoCapture(number)
        ok, frame = camera.read() if camera.isOpened() else (False, None)
        camera.release()
        if ok:
            height, width = frame.shape[:2]
            print(f"  CAMERA = {number}   works ({width} x {height})")
            found += 1
    if found:
        print("Put the number you want in CAMERA at the top of bird_watch.py.")
    else:
        print("No cameras found. Check the camera is plugged in and switched on, and that no other "
              "app (Zoom, Teams, the GoPro app...) is using it.")


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
            "activity": state["activity"],
            "checks_today": state["checks_today"],
            "max_checks": MAX_CHECKS_PER_DAY,
            "last_check": state["last_check"],
            "problems": [p for p in (state["camera_problem"], state["claude_problem"]) if p],
            "alerts": {"phone": bool(PHONE_ALERT_TOPIC), "email": email_is_set_up()},
            "recent": recent,
        }


class Website(BaseHTTPRequestHandler):
    """Answers the browser. Each address (path) gives back something different."""

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
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
        elif path.startswith("/saved/"):
            name = os.path.basename(urllib.parse.unquote(path[len("/saved/"):]))
            file = os.path.join(SAVE_PATH, name)
            kinds = {".jpg": "image/jpeg", ".gif": "image/gif"}
            ending = os.path.splitext(name)[1]
            if ending in kinds and os.path.isfile(file):
                self.send_file(file, kinds[ending], cache=True)
            else:
                self.send_error(404)
        else:
            self.send_error(404)

    def do_POST(self):
        path = urllib.parse.urlsplit(self.path).path
        if path == "/api/check-now":
            with lock:
                if state["stopped"]:
                    message = "Claude can't be used until the API key is fixed and the program restarts."
                elif state["checks_today"] >= MAX_CHECKS_PER_DAY:
                    message = "Today's check limit is reached."
                else:
                    state["check_requested"] = True
                    message = "Recording a clip for Claude..."
            self.send_json({"message": message})
        elif path == "/api/test-alert":
            with lock:
                photo = state["live_photo"]
            sent = send_alerts("Bird Watch: test alert",
                               "This is a test. If you can read it, alerts are working.", photo)
            self.send_json(sent)
        else:
            self.send_error(404)

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
    if "--find-cameras" in sys.argv:
        find_cameras()
        return

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
    print(f"  On this computer:             http://localhost:{WEBSITE_PORT}")
    print(f"  On a phone on the same Wi-Fi: http://{local_address()}:{WEBSITE_PORT}")
    print("  Press Ctrl+C to stop.\n")
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("Warning: ANTHROPIC_API_KEY isn't set, so Claude can't watch the video yet. "
              "See step 3 in README.md.\n")
    alerts = [name for name, on in (("phone", bool(PHONE_ALERT_TOPIC)), ("email", email_is_set_up())) if on]
    print("Alerts: " + (" and ".join(alerts) if alerts else "off (see README.md to turn them on)") + "\n")

    try:
        watch_camera()
    except KeyboardInterrupt:
        print("\nStopped. Bye!")


if __name__ == "__main__":
    main()
