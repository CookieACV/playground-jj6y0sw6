# Bird Watch

An AI camera that keeps watch all day and night. It notices when something
moves, asks Claude what animal it is and how healthy it looks, and shows
every sighting on a website you can open from your phone.

**Why it's a program and not just a website:** browsers turn the camera off
as soon as you close the page. So a small program on your computer does the
watching, and the website is just a window into it. You can close the website
and the program keeps watching.

## What it does

1. Reads your camera non-stop.
2. When something moves, it sends a photo to Claude (at most once a minute).
   It also checks every 30 minutes even if nothing moved, so it can check on
   an animal that is sitting still or sleeping.
3. Claude names each animal (for example "house sparrow"), counts them, says
   what they're doing, and judges how healthy they look: **looks healthy**,
   **possibly unwell**, **possibly injured** or **can't tell**.
4. If an animal looks hurt, sick or in danger (for example a cat stalking the
   birds), the website shows a red alert. It can also send one to your phone.
5. Photos with animals are saved in the `sightings` folder.

## Setup

You need a computer with a camera that can stay switched on, and Python 3.10
or newer.

**1. Open a terminal in this folder**

```
cd bird-watch
```

**2. Install the two libraries it uses**

```
pip install -r requirements.txt
```

(On a Mac, use `pip3` and `python3` instead of `pip` and `python`.)

**3. Get a Claude API key**

Go to [platform.claude.com](https://platform.claude.com), sign in, add some
credit, and create an API key. The API is paid for separately from a Claude
app subscription. Then put the key in your terminal:

- **Windows:** `setx ANTHROPIC_API_KEY "sk-ant-your-key-here"`, then close the terminal and open a new one.
- **Mac or Linux:** `export ANTHROPIC_API_KEY="sk-ant-your-key-here"` (do this in each new terminal).

Never put your key inside the code or share it.

**4. Start it**

```
python bird_watch.py
```

It prints two web addresses. Open the first one on the same computer, or the
second one on your phone (the phone must be on the same Wi-Fi).

**5. Keep it running 24/7**

- Keep the computer plugged in and the terminal window open.
- Stop the computer from going to sleep:
  - **Windows:** Settings → System → Power → set "sleep" to **Never** when plugged in.
  - **Mac:** start it with `caffeinate -i python3 bird_watch.py` instead.
- Press **Ctrl+C** in the terminal to stop it.

## Settings

Open `bird_watch.py` and change the values at the top:

| Setting | What it does | Default |
| --- | --- | --- |
| `CAMERA` | `0` for the built-in webcam, `1` for a USB camera, or a phone camera link | `0` |
| `WHAT_TO_WATCH` | What the camera is pointed at, so Claude guesses better | `"a backyard bird feeder"` |
| `MODEL` | Which Claude model looks at the photos | `"claude-opus-5-5"` |
| `SECONDS_BETWEEN_CHECKS` | Shortest gap between checks while things keep moving | `60` |
| `CHECK_IN_MINUTES` | Check anyway this often, even with no movement | `30` |
| `MAX_CHECKS_PER_DAY` | Safety limit on how many photos go to Claude each day | `300` |
| `MOTION_SENSITIVITY` | How much must change to count as movement | `0.005` |
| `PHONE_ALERT_TOPIC` | Your ntfy topic for phone alerts (see below) | `""` (off) |

## Cost

Each check sends one photo to Claude. These are rough estimates:

| Model | Per check | At the 300-a-day limit |
| --- | --- | --- |
| `claude-opus-5-5` (most capable) | about 1.5 cents | about $4.50 a day |
| `claude-haiku-5-5` (cheapest) | about 0.04 cents | about 11 cents a day |

A quiet camera that only does the 30-minute check-ins uses 48 checks a day.
A busy feeder can hit the daily limit. Lower `MAX_CHECKS_PER_DAY` or switch
`MODEL` to spend less, and watch your real usage in the Claude Console.

## Phone alerts (optional)

1. Install the free **ntfy** app on your phone.
2. Subscribe to a topic with a name nobody could guess, like `birdwatch-k7q2m9x4`.
   Anyone who knows the name can read the alerts.
3. Put that name in `PHONE_ALERT_TOPIC` and restart the program.

You'll get a notification when an animal may need help (at most one every
15 minutes).

## Use an old phone as the camera

Install an "IP Webcam" style app on an old phone, start its camera server,
and set `CAMERA` to the link it shows, for example
`"http://192.168.1.20:8080/video"`. Then put the phone wherever you like.

## Privacy

- Anyone on your Wi-Fi can open the website and see the camera. It can't be
  opened from outside your home network.
- Photos are saved only on your computer. Each photo that gets checked is sent
  to Claude to be looked at.

## If something goes wrong

- **"Camera off":** try `CAMERA = 1`, and close other apps using the camera
  (Zoom, Teams, FaceTime). On a Mac, allow the terminal in System Settings →
  Privacy & Security → Camera.
- **"Claude didn't accept the API key":** redo step 3, then restart.
- **Too many checks from leaves or shadows:** raise `MOTION_SENSITIVITY` to `0.02`.
- **Small birds far away get missed:** lower it to `0.002`, or move the camera closer.
