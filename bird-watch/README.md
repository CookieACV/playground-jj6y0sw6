# Bird Watch

An AI video scanner that keeps watch all day and night, with any camera.
When something moves, it records a short clip, and Claude watches it to say
which animals are there and how they're doing. If something doesn't look
right, you get a phone notification and an email with the photo and the clip.

**Why it's a program and not just a website:** browsers turn the camera off
as soon as you close the page. So a small program on your computer does the
watching, and the website is just a window into it. You can close the website
and the program keeps watching.

## What it does

1. Reads your camera's video non-stop.
2. When something moves, it records a 6-second clip (3 seconds before the
   movement and 3 after). It also records one every 30 minutes even if nothing
   moved, to check on an animal that is sitting still or sleeping.
3. Claude watches 4 frames from the clip. It names each animal (for example
   "house sparrow"), counts them, says what they're doing, and judges how
   healthy they look: **looks healthy**, **possibly unwell**, **possibly
   injured** or **can't tell**. Because it sees several frames, it can notice
   movement problems like a limp or trouble flying.
4. If something doesn't look right (a hurt or sick animal, one that's trapped,
   or a cat stalking the birds), it sends you a **phone notification** with the
   clip and an **email** with the photo and the clip. It also warns you if the
   camera stops sending video for 5 minutes.
5. Every sighting is saved and shown on the website, where you can play the clip.

## Connect a camera

Any camera that sends video to the computer works:

- **Webcam:** built into the laptop, or plugged in by USB.
- **GoPro:** newer GoPros can act as a USB webcam with GoPro's free Webcam app
  (check GoPro's website for your model). Once it works as a webcam, it's like
  any other webcam here. Keep it plugged into power and out of direct sun:
  GoPros get hot when they run for hours.
- **Any camera with an HDMI port** (action cams, camcorders, older GoPros):
  plug it into a cheap USB HDMI capture adapter, and it shows up as a webcam.
- **Wi-Fi security camera:** many give an `rtsp://` video link in their app
  or manual. Put that link in `CAMERA`.
- **Old phone:** install an "IP Webcam" style app and put the `http://` link
  it shows in `CAMERA`.

To see which number your camera has, plug it in and run:

```
python bird_watch.py --find-cameras
```

Then put that number in `CAMERA` at the top of `bird_watch.py`.

## Setup

You need a computer that can stay switched on, and Python 3.10 or newer.

**1. Open a terminal in this folder**

```
cd bird-watch
```

**2. Install the libraries it uses**

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

## Turn on alerts

You can use either one, or both. After setting them up, restart the program
and press **Send test alert** on the website to check they work.

### Phone notifications

1. Install the free **ntfy** app on your phone.
2. Subscribe to a topic with a name nobody could guess, like `birdwatch-k7q2m9x4`.
   Anyone who knows the name can read the alerts.
3. Put that name in `PHONE_ALERT_TOPIC` in `bird_watch.py`.

### Email (Gmail)

1. In your Google Account, turn on **2-Step Verification**.
2. Go to [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
   and create an app password. Google shows a 16-letter password once.
3. Put that password in a setting called `EMAIL_APP_PASSWORD`, the same way as
   the API key in step 3:
   - **Windows:** `setx EMAIL_APP_PASSWORD "abcd efgh ijkl mnop"`, then open a new terminal.
   - **Mac or Linux:** `export EMAIL_APP_PASSWORD="abcd efgh ijkl mnop"`
4. In `bird_watch.py`, set `EMAIL_FROM` to that Gmail address and `EMAIL_TO`
   to where the alerts should go (it can be the same address).

Use the app password, not your normal Gmail password. For another email
service, also change `EMAIL_SERVER` and `EMAIL_PORT` to the ones it gives
for sending mail ("SMTP").

## Settings

Open `bird_watch.py` and change the values at the top:

| Setting | What it does | Default |
| --- | --- | --- |
| `CAMERA` | Camera number, or a camera's video link | `0` |
| `WHAT_TO_WATCH` | What the camera is pointed at, so Claude guesses better | `"a backyard bird feeder"` |
| `MODEL` | Which Claude model watches the clips | `"claude-opus-5-5"` |
| `FRAMES_FOR_CLAUDE` | How many frames of each clip Claude sees | `4` |
| `SECONDS_BETWEEN_CHECKS` | Shortest gap between checks while things keep moving | `60` |
| `CHECK_IN_MINUTES` | Check anyway this often, even with no movement | `30` |
| `MAX_CHECKS_PER_DAY` | Safety limit on checks per day | `200` |
| `MOTION_SENSITIVITY` | How much must change to count as movement | `0.005` |
| `CLIP_SECONDS_BEFORE` / `CLIP_SECONDS_AFTER` | Clip length around the movement | `3` / `3` |
| `KEEP_DAYS` | Delete saved photos and clips older than this | `14` |
| `PHONE_ALERT_TOPIC` | Your ntfy topic | `""` (off) |
| `EMAIL_TO` / `EMAIL_FROM` | Where email alerts go, and the Gmail that sends them | `""` (off) |
| `ALERT_EVERY_MINUTES` | At most one animal alert this often | `15` |

## Cost

Each check sends 4 frames to Claude. These are rough estimates:

| Model | Per check | At the 200-a-day limit |
| --- | --- | --- |
| `claude-opus-5-5` (most capable) | about 2.5 cents | about $5 a day |
| `claude-haiku-5-5` (cheapest) | under 0.1 cents | about 13 cents a day |

A quiet camera that only does the 30-minute check-ins uses 48 checks a day.
A busy feeder can hit the daily limit. To spend less, lower
`MAX_CHECKS_PER_DAY` or `FRAMES_FOR_CLAUDE`, or switch `MODEL`. Watch your
real usage in the Claude Console.

## Privacy

- Anyone on your Wi-Fi can open the website and see the camera. It can't be
  opened from outside your home network.
- Photos and clips are saved on your computer. Frames from each clip are sent
  to Claude to be checked. When an alert goes out, the clip goes through the
  ntfy service and your email.

## If something goes wrong

- **"Camera off":** run `python bird_watch.py --find-cameras`, and close other
  apps using the camera (Zoom, Teams, the GoPro app's preview). On a Mac,
  allow the terminal in System Settings → Privacy & Security → Camera.
- **"Claude didn't accept the API key":** redo step 3, then restart.
- **Test email fails:** check the app password and both email addresses, then
  restart. The terminal shows the exact error.
- **Too many checks from leaves or shadows:** raise `MOTION_SENSITIVITY` to `0.02`.
- **Small animals far away get missed:** lower it to `0.002`, or move the camera closer.
