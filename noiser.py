#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.13"
# dependencies = [
#   "numpy",
#   "scipy",
#   "sounddevice",
#   "pyobjc-framework-Cocoa",
#   "pyobjc-framework-CoreAudio",
# ]
# ///

import json
import math
import os
import signal
import subprocess
import time
from pathlib import Path

import numpy as np
import objc
import sounddevice as sd
from scipy.signal import butter, sosfilt, tf2sos
from AppKit import (
    NSApp,
    NSApplication,
    NSApplicationActivationPolicyAccessory,
    NSAttributedString,
    NSBackingStoreBuffered,
    NSBezierPath,
    NSButton,
    NSColor,
    NSColorPanel,
    NSColorSpace,
    NSColorWell,
    NSControlStateValueOn,
    NSEvent,
    NSFont,
    NSFontAttributeName,
    NSFontWeightMedium,
    NSForegroundColorAttributeName,
    NSImage,
    NSMutableParagraphStyle,
    NSParagraphStyleAttributeName,
    NSPopover,
    NSPopoverBehaviorTransient,
    NSPopUpButton,
    NSScreen,
    NSScreenSaverWindowLevel,
    NSSlider,
    NSStatusBar,
    NSTextAlignmentCenter,
    NSTextAlignmentRight,
    NSTextField,
    NSVariableStatusItemLength,
    NSView,
    NSViewController,
    NSWindow,
    NSWindowCollectionBehaviorCanJoinAllSpaces,
    NSWindowCollectionBehaviorTransient,
    NSWindowStyleMaskBorderless,
    NSWindowStyleMaskClosable,
    NSWindowStyleMaskTitled,
)
from CoreAudio import (
    AudioObjectAddPropertyListenerBlock,
    AudioObjectPropertyAddress,
    kAudioHardwarePropertyDefaultOutputDevice,
    kAudioObjectPropertyElementMain,
    kAudioObjectPropertyScopeGlobal,
    kAudioObjectSystemObject,
)
from Foundation import NSMakeRect, NSMinYEdge, NSObject, NSRunLoop, NSRunLoopCommonModes, NSTimer

APP_NAME = "noiser"

SAMPLE_RATE = 48000
BLOCK_SIZE = 2048
# One-pole leak keeps brown noise (a random walk) from drifting into DC / clipping.
LEAK = 0.999
# Every noise type is normalized to this RMS so 0 dB sounds equally loud for all of them.
# Brown noise has a crest factor around 4, so 0.22 leaves peaks just under full scale;
# above that a tanh soft limiter takes over instead of hard clipping. Past roughly
# +12 dB it stops adding loudness and only adds distortion, hence the slider ceiling.
TARGET_RMS = 0.22
VOLUME_MIN_DB = -30.0
VOLUME_MAX_DB = 12.0
DEFAULT_VOLUME_DB = 0.0
FADE_IN_SECONDS = 3
FADE_OUT_SECONDS = 5
PAUSE_FADE_SECONDS = 0.5

# Colored noise piles its energy below what speakers reproduce; that inaudible sub-bass
# would otherwise eat all the headroom (and drive the limiter), so it is cut off.
# Raising the cutoff makes brown noise sound louder on small speakers at the cost of rumble.
LOW_CUT_HZ = 42


def _build_filters():
    low_cut = butter(2, LOW_CUT_HZ, btype="highpass", fs=SAMPLE_RATE, output="sos")
    pink = tf2sos(
        [0.049922035, -0.095993537, 0.050612699, -0.004408786],
        [1.0, -2.494956002, 2.017265875, -0.522189400],
    )
    brown = np.array([[1.0, 0.0, 0.0, 1.0, -LEAK, 0.0]])
    return {
        "white": None,
        "pink": np.vstack([pink, low_cut]),
        "brown": np.vstack([brown, low_cut]),
    }


# Second-order sections applied to white noise; None means raw white.
NOISE_FILTERS = _build_filters()
NOISE_LABELS = (("white", "Белый"), ("pink", "Розовый"), ("brown", "Коричневый"))

# Drag distance -> duration. Centimeters are nominal (macOS assumes 72 pt per inch),
# so tune MINUTES_PER_CM against a ruler on your own screen.
MINUTES_PER_CM = 5
POINTS_PER_CM = 72 / 2.54
MIN_DURATION_MINUTES = 1
# (upper bound in minutes, rounding step); None bound = everything above.
ROUNDING_STEPS = ((30, 1), (60, 5), (None, 10))

POPOVER_WIDTH = 150
POPOVER_HEIGHT = 130
BALL_RADIUS = 14
BALL_TOP = 26
TEXT_TOP = 62

IDLE, PLAYING, PAUSED = "idle", "playing", "paused"
ICONS = {IDLE: "waveform", PLAYING: "waveform.circle.fill", PAUSED: "pause.circle"}
ICON_FALLBACK = {IDLE: "〰", PLAYING: "🔊", PAUSED: "⏸"}


class Settings:
    def __init__(self):
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        self.path = config_home / APP_NAME / "settings.json"
        self.noise = "brown"
        self.volume_db = DEFAULT_VOLUME_DB
        self.announce = True
        self.ball_color = None  # "#RRGGBB" or None for the system accent color
        self._load()

    def _load(self):
        try:
            data = json.loads(self.path.read_text())
        except (OSError, ValueError):
            return
        if not isinstance(data, dict):
            return
        if data.get("noise") in NOISE_FILTERS:
            self.noise = data["noise"]
        if isinstance(data.get("volume_db"), (int, float)):
            self.volume_db = float(min(VOLUME_MAX_DB, max(VOLUME_MIN_DB, data["volume_db"])))
        if isinstance(data.get("announce"), bool):
            self.announce = data["announce"]
        color = data.get("ball_color")
        if isinstance(color, str) and len(color) == 7 and color.startswith("#"):
            self.ball_color = color

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        data = {
            "noise": self.noise,
            "volume_db": self.volume_db,
            "announce": self.announce,
            "ball_color": self.ball_color,
        }
        self.path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        os.chmod(self.path, 0o600)


class NoiseEngine:
    """Endless output stream; UI just moves the gain target around."""

    def __init__(self, settings: Settings):
        self.state = IDLE
        self.deadline = None
        self.paused_remaining = None
        self.finished = False
        self.current = 0.0
        self.target = 0.0
        self.ramp = FADE_IN_SECONDS
        self.rng = np.random.default_rng()
        self.noise_type = settings.noise
        self.active_type = None
        self.zi = None
        self.volume_gain = 1.0
        self.set_volume_db(settings.volume_db)
        self.norm = {kind: self._measure_norm(kind) for kind in NOISE_FILTERS}
        self.stream = None
        self._open_stream()

    def _open_stream(self):
        self.stream = sd.OutputStream(
            samplerate=SAMPLE_RATE,
            blocksize=BLOCK_SIZE,
            channels=1,
            dtype="float32",
            callback=self._callback,
        )
        self.stream.start()

    def close(self):
        try:
            self.stream.stop()
            self.stream.close()
        except sd.PortAudioError:
            pass  # the device may already be gone

    def reopen(self):
        """A PortAudio stream is pinned to the device it was opened on, so following the
        system default output means opening a fresh stream. Playback state lives outside
        the stream and carries over."""
        self.close()
        # PortAudio enumerates devices only at init; re-init so a new default is visible.
        sd._terminate()
        sd._initialize()
        self._open_stream()

    def set_noise(self, kind: str):
        self.noise_type = kind

    def set_volume_db(self, db: float):
        self.volume_gain = 10 ** (db / 20)

    def start(self, seconds: float | None):
        # Also restarts a running timer: the ramp simply continues from the current gain.
        self.deadline = time.monotonic() + seconds if seconds else None
        self.state = PLAYING
        self._ramp_to(1.0, FADE_IN_SECONDS)

    def pause(self):
        if self.state != PLAYING:
            return
        self.paused_remaining = self.deadline - time.monotonic() if self.deadline else None
        self.state = PAUSED
        self._ramp_to(0.0, PAUSE_FADE_SECONDS)

    def resume(self):
        if self.state != PAUSED:
            return
        if self.paused_remaining is not None:
            self.deadline = time.monotonic() + self.paused_remaining
        self.state = PLAYING
        self._ramp_to(1.0, PAUSE_FADE_SECONDS)

    def remaining(self) -> float | None:
        if self.state == PLAYING and self.deadline is not None:
            return max(0.0, self.deadline - time.monotonic())
        if self.state == PAUSED:
            return self.paused_remaining
        return None

    def take_finished(self) -> bool:
        finished, self.finished = self.finished, False
        return finished

    def _ramp_to(self, target: float, seconds: float):
        self.target = target
        self.ramp = seconds

    def _render(self, kind: str, white, zi):
        sos = NOISE_FILTERS[kind]
        if sos is None:
            return white, zi
        if zi is None:
            zi = np.zeros((sos.shape[0], 2))
        return sosfilt(sos, white, zi=zi)

    def _measure_norm(self, kind: str) -> float:
        y, _ = self._render(kind, self.rng.standard_normal(2 * SAMPLE_RATE), None)
        # Skip the filter's settling transient before measuring.
        rms = math.sqrt(float(np.mean(y[SAMPLE_RATE // 2 :] ** 2)))
        return TARGET_RMS / rms

    def _callback(self, out, frames, _time, _status):
        kind = self.noise_type
        if kind != self.active_type:
            self.active_type = kind
            self.zi = None
        signal_block, self.zi = self._render(kind, self.rng.standard_normal(frames), self.zi)

        # Linear ramp towards the target gain, at most `ramp` seconds for a full swing.
        max_change = frames / (self.ramp * SAMPLE_RATE)
        change = np.clip(self.target - self.current, -max_change, max_change)
        env = self.current + change * np.arange(1, frames + 1) / frames
        self.current = env[-1]

        # Snapshot: the UI thread may clear the deadline between the check and the use.
        deadline = self.deadline
        if self.state == PLAYING and deadline is not None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                self.state = IDLE
                self.deadline = None
                self.current = self.target = 0.0
                self.finished = True
                env[:] = 0.0
            else:
                t = np.arange(frames) / SAMPLE_RATE
                env *= np.clip((remaining - t) / FADE_OUT_SECONDS, 0.0, 1.0)

        gain = self.norm[kind] * self.volume_gain
        out[:, 0] = np.tanh(signal_block * gain * env)


def fmt_hms(seconds: float) -> str:
    seconds = max(0, int(seconds))
    return f"{seconds // 3600:02d}:{seconds % 3600 // 60:02d}:{seconds % 60:02d}"


def fmt_minutes(minutes: int) -> str:
    h, m = divmod(minutes, 60)
    return " ".join(p for p in (f"{h}h" if h else "", f"{m}m" if m else "") if p)


def round_minutes(raw: float) -> int:
    for limit, step in ROUNDING_STEPS:
        if limit is None or raw < limit:
            return round(raw / step) * step


def drag_minutes(points: float) -> int:
    """0 means the pull was too short to count as a duration (i.e. a click)."""
    raw = points / POINTS_PER_CM * MINUTES_PER_CM
    if raw < MIN_DURATION_MINUTES:
        return 0
    return max(MIN_DURATION_MINUTES, round_minutes(raw))


def color_from_hex(value: str | None):
    if not value:
        return NSColor.controlAccentColor()
    r, g, b = (int(value[i : i + 2], 16) / 255 for i in (1, 3, 5))
    return NSColor.colorWithSRGBRed_green_blue_alpha_(r, g, b, 1.0)


def color_to_hex(color) -> str:
    c = color.colorUsingColorSpace_(NSColorSpace.sRGBColorSpace())
    return "#{:02X}{:02X}{:02X}".format(
        round(c.redComponent() * 255), round(c.greenComponent() * 255), round(c.blueComponent() * 255)
    )


def draw_centered(text: str, rect, font, color):
    style = NSMutableParagraphStyle.alloc().init()
    style.setAlignment_(NSTextAlignmentCenter)
    attrs = {
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: style,
    }
    NSAttributedString.alloc().initWithString_attributes_(text, attrs).drawInRect_(rect)


def draw_ball_on_string(anchor, center, color):
    NSColor.secondaryLabelColor().setStroke()
    string = NSBezierPath.bezierPath()
    string.moveToPoint_(anchor)
    string.lineToPoint_(center)
    string.setLineWidth_(1.5)
    string.stroke()

    color.setFill()
    cx, cy = center
    ball = NSMakeRect(cx - BALL_RADIUS, cy - BALL_RADIUS, 2 * BALL_RADIUS, 2 * BALL_RADIUS)
    NSBezierPath.bezierPathWithOvalInRect_(ball).fill()


def symbol_image(name: str):
    image = NSImage.imageWithSystemSymbolName_accessibilityDescription_(name, None)
    if image is not None:
        image.setTemplate_(True)
    return image


class AnchoredColorWell(NSColorWell):
    """The shared color panel remembers an arbitrary last position; open it next to our window."""

    def activate_(self, exclusive):
        objc.super(AnchoredColorWell, self).activate_(exclusive)
        window = self.window()
        panel = NSColorPanel.sharedColorPanel()
        if window is None:
            return
        frame = window.frame()
        origin = (frame.origin.x + frame.size.width + 8, frame.origin.y + frame.size.height - panel.frame().size.height)
        panel.setFrameOrigin_(window.constrainFrameRect_toScreen_(
            NSMakeRect(origin[0], origin[1], panel.frame().size.width, panel.frame().size.height), window.screen()
        ).origin)
        panel.orderFront_(None)


class OverlayView(NSView):
    def initWithFrame_(self, frame):
        self = objc.super(OverlayView, self).initWithFrame_(frame)
        if self is None:
            return None
        self.anchor = (0.0, 0.0)
        self.ball = (0.0, 0.0)
        self.color = NSColor.controlAccentColor()
        return self

    def drawRect_(self, _rect):
        draw_ball_on_string(self.anchor, self.ball, self.color)


class DragOverlay:
    """Transparent click-through windows, one per screen: the popover can't draw
    outside its own bounds, and with "Displays have separate Spaces" a single
    window is clipped to whichever display it belongs to."""

    def __init__(self):
        self.windows = []  # (window, view, screen origin)
        self.screen_frames = None

    def _build(self):
        self.hide()
        self.windows = []
        for screen in NSScreen.screens():
            frame = screen.frame()
            window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
                frame, NSWindowStyleMaskBorderless, NSBackingStoreBuffered, False
            )
            window.setOpaque_(False)
            window.setBackgroundColor_(NSColor.clearColor())
            window.setHasShadow_(False)
            window.setIgnoresMouseEvents_(True)
            window.setLevel_(NSScreenSaverWindowLevel)
            window.setReleasedWhenClosed_(False)
            window.setCollectionBehavior_(
                NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorTransient
            )
            view = OverlayView.alloc().initWithFrame_(NSMakeRect(0, 0, frame.size.width, frame.size.height))
            window.setContentView_(view)
            self.windows.append((window, view, frame.origin))

    def show(self):
        frames = tuple(
            (s.frame().origin.x, s.frame().origin.y, s.frame().size.width, s.frame().size.height)
            for s in NSScreen.screens()
        )
        if frames != self.screen_frames:
            self._build()
            self.screen_frames = frames
        for window, _, _ in self.windows:
            window.orderFront_(None)

    def update(self, anchor, ball, color):
        for _, view, origin in self.windows:
            view.anchor = (anchor.x - origin.x, anchor.y - origin.y)
            view.ball = (ball[0] - origin.x, ball[1] - origin.y)
            view.color = color
            view.setNeedsDisplay_(True)

    def hide(self):
        for window, _, _ in self.windows:
            window.orderOut_(None)


class BallView(NSView):
    def initWithFrame_(self, frame):
        self = objc.super(BallView, self).initWithFrame_(frame)
        if self is None:
            return None
        self.engine = None
        self.settings = None
        self.on_release = None  # ball released: seconds, or None for no timer
        self.on_toggle = None  # click on the window outside the ball
        self.dragging = False
        self.window_press = False
        self.returning = False
        self.grab_point = (0.0, 0.0)  # screen coords at mouseDown
        self.delta = (0.0, 0.0)  # ball displacement from rest, screen coords (y up)
        self.overlay = None
        self.return_timer = None
        return self

    def isFlipped(self):
        return True

    def acceptsFirstMouse_(self, event):
        return True

    def rest_center(self):
        return self.bounds().size.width / 2, BALL_TOP

    def to_screen(self, point):
        return self.window().convertPointToScreen_(self.convertPoint_toView_(point, None))

    def drag_distance(self) -> float:
        return math.hypot(*self.delta)

    def labels(self):
        if self.dragging:
            minutes = drag_minutes(self.drag_distance())
            if minutes < MIN_DURATION_MINUTES:
                return "∞", "отпусти — без таймера"
            return fmt_minutes(minutes), "отпусти — старт"
        state = self.engine.state
        if state == IDLE:
            return "", "тяни или кликни"
        remaining = self.engine.remaining()
        main = fmt_hms(remaining) if remaining is not None else "∞"
        return main, "пауза" if state == PAUSED else "шумим"

    def drawRect_(self, _rect):
        size = self.bounds().size
        cx, cy = self.rest_center()
        # While stretched, the ball is drawn on the overlay instead.
        if not (self.dragging or self.returning):
            draw_ball_on_string((cx, 0), (cx, cy), color_from_hex(self.settings.ball_color))

        main, sub = self.labels()
        top = TEXT_TOP
        draw_centered(
            main,
            NSMakeRect(0, top, size.width, 32),
            NSFont.monospacedDigitSystemFontOfSize_weight_(24, NSFontWeightMedium),
            NSColor.labelColor(),
        )
        draw_centered(
            sub,
            NSMakeRect(0, top + 36, size.width, 18),
            NSFont.systemFontOfSize_(11),
            NSColor.secondaryLabelColor(),
        )

    def _hit_ball(self, event) -> bool:
        p = self.convertPoint_fromView_(event.locationInWindow(), None)
        cx, cy = self.rest_center()
        return (p.x - cx) ** 2 + (p.y - cy) ** 2 <= (BALL_RADIUS * 1.6) ** 2

    def mouseDown_(self, event):
        if self.dragging:
            return
        # The ball sets the timer; the rest of the popover is a play/pause button.
        if not self._hit_ball(event):
            self.window_press = True
            return
        self._stop_return()
        self.returning = False
        self.dragging = True
        # Screen coordinates keep counting after the cursor leaves the popover.
        m = NSEvent.mouseLocation()
        self.grab_point = (m.x, m.y)
        self.delta = (0.0, 0.0)
        if self.overlay is None:
            self.overlay = DragOverlay()
        self.overlay.show()
        self._update_overlay()
        self.setNeedsDisplay_(True)

    def mouseDragged_(self, event):
        if not self.dragging:
            return
        m = NSEvent.mouseLocation()
        self.delta = (m.x - self.grab_point[0], m.y - self.grab_point[1])
        self._update_overlay()
        self.setNeedsDisplay_(True)

    def mouseUp_(self, event):
        if self.window_press:
            self.window_press = False
            self.on_toggle()
            return
        if not self.dragging:
            return
        self.dragging = False
        minutes = drag_minutes(self.drag_distance())
        self.on_release(minutes * 60 if minutes >= MIN_DURATION_MINUTES else None)
        self.returning = True
        self._start_return()

    def _update_overlay(self):
        cx, cy = self.rest_center()
        rest = self.to_screen((cx, cy))
        ball = (rest.x + self.delta[0], rest.y + self.delta[1])
        self.overlay.update(self.to_screen((cx, 0)), ball, color_from_hex(self.settings.ball_color))

    def _start_return(self):
        self._stop_return()
        self.return_timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            1 / 60, self, "returnStep:", None, True
        )

    def _stop_return(self):
        if self.return_timer is not None:
            self.return_timer.invalidate()
            self.return_timer = None

    def returnStep_(self, _timer):
        self.delta = (self.delta[0] * 0.6, self.delta[1] * 0.6)
        if self.drag_distance() < 0.5:
            self.delta = (0.0, 0.0)
            self.returning = False
            self._stop_return()
            self.overlay.hide()
        else:
            self._update_overlay()
        self.setNeedsDisplay_(True)


class AppDelegate(NSObject):
    def applicationDidFinishLaunching_(self, _notification):
        self.settings = Settings()
        self.engine = NoiseEngine(self.settings)
        self.icon_name = None
        self.settings_window = None

        self.status_item = NSStatusBar.systemStatusBar().statusItemWithLength_(NSVariableStatusItemLength)
        button = self.status_item.button()
        button.setTarget_(self)
        button.setAction_("togglePopover:")

        self.build_popover()

        self.timer = NSTimer.timerWithTimeInterval_target_selector_userInfo_repeats_(1.0, self, "tick:", None, True)
        NSRunLoop.currentRunLoop().addTimer_forMode_(self.timer, NSRunLoopCommonModes)
        self.watch_default_output()
        self.refresh()

    def watch_default_output(self):
        address = AudioObjectPropertyAddress(
            mSelector=kAudioHardwarePropertyDefaultOutputDevice,
            mScope=kAudioObjectPropertyScopeGlobal,
            mElement=kAudioObjectPropertyElementMain,
        )

        def changed(_count, _addresses):
            # Called on a CoreAudio thread; hop to the main thread before touching the stream.
            self.performSelectorOnMainThread_withObject_waitUntilDone_("audioDeviceChanged:", None, False)

        self.device_listener = changed  # must outlive the registration
        self.reopen_timer = None
        AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, address, None, changed)

    def audioDeviceChanged_(self, _sender):
        # Device switches fire several notifications in a row; reopen once they settle.
        if self.reopen_timer is not None:
            self.reopen_timer.invalidate()
        self.reopen_timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            0.3, self, "reopenAudio:", None, False
        )

    def reopenAudio_(self, _timer):
        self.reopen_timer = None
        self.engine.reopen()

    def applicationWillTerminate_(self, _notification):
        self.engine.close()

    def build_popover(self):
        w, h = POPOVER_WIDTH, POPOVER_HEIGHT
        container = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, w, h))

        self.ball_view = BallView.alloc().initWithFrame_(NSMakeRect(0, 0, w, h))
        self.ball_view.engine = self.engine
        self.ball_view.settings = self.settings
        self.ball_view.on_release = self.start_noise
        self.ball_view.on_toggle = self.toggle_pause
        container.addSubview_(self.ball_view)

        gear = symbol_image("gearshape")
        if gear is not None:
            gear_button = NSButton.buttonWithImage_target_action_(gear, self, "openSettings:")
        else:
            gear_button = NSButton.buttonWithTitle_target_action_("⚙", self, "openSettings:")
        gear_button.setBordered_(False)
        gear_button.setFrame_(NSMakeRect(w - 28, h - 28, 22, 22))
        container.addSubview_(gear_button)

        cross = symbol_image("xmark")
        if cross is not None:
            quit_button = NSButton.buttonWithImage_target_action_(cross, self, "quit:")
        else:
            quit_button = NSButton.buttonWithTitle_target_action_("✕", self, "quit:")
        quit_button.setBordered_(False)
        quit_button.setFrame_(NSMakeRect(6, h - 28, 22, 22))
        container.addSubview_(quit_button)

        controller = NSViewController.alloc().init()
        controller.setView_(container)
        self.popover = NSPopover.alloc().init()
        self.popover.setContentViewController_(controller)
        self.popover.setContentSize_((w, h))
        self.popover.setBehavior_(NSPopoverBehaviorTransient)

    def togglePopover_(self, sender):
        if self.popover.isShown():
            self.popover.performClose_(sender)
            return
        button = self.status_item.button()
        self.popover.showRelativeToRect_ofView_preferredEdge_(button.bounds(), button, NSMinYEdge)
        # An accessory app isn't frontmost, so make the popover key to receive the drag.
        NSApp.activateIgnoringOtherApps_(True)

    # Not `start`: NSObject already has that selector and PyObjC rejects the mismatch.
    def start_noise(self, seconds):
        self.engine.start(seconds)
        self.refresh()

    def toggle_pause(self):
        state = self.engine.state
        if state == PLAYING:
            self.engine.pause()
        elif state == PAUSED:
            self.engine.resume()
        else:
            self.engine.start(None)
        self.refresh()

    def quit_(self, _sender):
        NSApp.terminate_(None)

    def tick_(self, _timer):
        if self.engine.take_finished() and self.settings.announce:
            subprocess.Popen(["say", "time is up"])
        self.refresh()

    def refresh(self):
        self.set_icon(self.engine.state)
        self.ball_view.setNeedsDisplay_(True)

    def set_icon(self, state):
        if self.icon_name == state:
            return
        self.icon_name = state
        button = self.status_item.button()
        image = symbol_image(ICONS[state])
        if image is None:
            button.setImage_(None)
            button.setTitle_(ICON_FALLBACK[state])
            return
        button.setTitle_("")
        button.setImage_(image)

    # --- settings window ---

    def openSettings_(self, _sender):
        if self.settings_window is None:
            self.settings_window = self.build_settings_window()
        self.popover.performClose_(None)
        self.settings_window.makeKeyAndOrderFront_(None)
        NSApp.activateIgnoringOtherApps_(True)

    def build_settings_window(self):
        w, h = 340, 230
        margin, label_w, gap = 20, 90, 12
        control_x = margin + label_w + gap
        control_w = w - control_x - margin
        window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(0, 0, w, h),
            NSWindowStyleMaskTitled | NSWindowStyleMaskClosable,
            NSBackingStoreBuffered,
            False,
        )
        window.setTitle_(APP_NAME)
        window.setReleasedWhenClosed_(False)
        window.setDelegate_(self)
        window.center()
        content = window.contentView()

        def row(text, center_y, control, control_h):
            field = NSTextField.labelWithString_(text)
            field.setAlignment_(NSTextAlignmentRight)
            field.setFrame_(NSMakeRect(margin, center_y - 9, label_w, 18))
            content.addSubview_(field)
            frame = control.frame()
            control.setFrame_(NSMakeRect(control_x, center_y - control_h / 2, frame.size.width or control_w, control_h))
            content.addSubview_(control)

        self.noise_popup = NSPopUpButton.alloc().initWithFrame_pullsDown_(NSMakeRect(0, 0, control_w, 26), False)
        for key, title in NOISE_LABELS:
            self.noise_popup.addItemWithTitle_(title)
            self.noise_popup.lastItem().setRepresentedObject_(key)
        self.noise_popup.selectItemAtIndex_([k for k, _ in NOISE_LABELS].index(self.settings.noise))
        self.noise_popup.setTarget_(self)
        self.noise_popup.setAction_("noiseChanged:")
        row("Шум", 188, self.noise_popup, 26)

        self.volume_slider = NSSlider.sliderWithValue_minValue_maxValue_target_action_(
            self.settings.volume_db, VOLUME_MIN_DB, VOLUME_MAX_DB, self, "volumeChanged:"
        )
        self.volume_slider.setContinuous_(True)
        self.volume_slider.setFrame_(NSMakeRect(0, 0, control_w, 24))
        row("Громкость", 148, self.volume_slider, 24)

        self.color_well = AnchoredColorWell.alloc().initWithFrame_(NSMakeRect(0, 0, 56, 26))
        self.color_well.setColor_(color_from_hex(self.settings.ball_color))
        self.color_well.setTarget_(self)
        self.color_well.setAction_("colorChanged:")
        row("Шарик", 108, self.color_well, 26)

        self.announce_checkbox = NSButton.checkboxWithTitle_target_action_(
            "Объявлять «time is up»", self, "announceChanged:"
        )
        self.announce_checkbox.setFrame_(NSMakeRect(control_x - 2, 66 - 11, control_w, 22))
        self.announce_checkbox.setState_(NSControlStateValueOn if self.settings.announce else 0)
        content.addSubview_(self.announce_checkbox)

        close_button = NSButton.buttonWithTitle_target_action_("Закрыть", self, "closeSettings:")
        close_button.setFrame_(NSMakeRect(w - margin - 96, 14, 96, 30))
        # Escape triggers the button, so the window also closes from the keyboard.
        close_button.setKeyEquivalent_("\x1b")
        content.addSubview_(close_button)
        return window

    def closeSettings_(self, _sender):
        self.settings_window.performClose_(None)

    def windowWillClose_(self, notification):
        # The shared color panel outlives the color well; take it down with the settings.
        if notification.object() is self.settings_window:
            self.color_well.deactivate()
            NSColorPanel.sharedColorPanel().orderOut_(None)

    def noiseChanged_(self, sender):
        self.settings.noise = sender.selectedItem().representedObject()
        self.engine.set_noise(self.settings.noise)
        self.settings.save()

    def volumeChanged_(self, sender):
        self.settings.volume_db = float(sender.doubleValue())
        self.engine.set_volume_db(self.settings.volume_db)
        self.settings.save()

    def colorChanged_(self, sender):
        self.settings.ball_color = color_to_hex(sender.color())
        self.settings.save()
        self.ball_view.setNeedsDisplay_(True)

    def announceChanged_(self, sender):
        self.settings.announce = sender.state() == NSControlStateValueOn
        self.settings.save()


def main():
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
    delegate = AppDelegate.alloc().init()
    app.setDelegate_(delegate)
    # Cocoa's run loop swallows Ctrl+C; the handler runs on the next timer tick.
    signal.signal(signal.SIGINT, lambda *_: app.terminate_(None))
    app.run()


if __name__ == "__main__":
    main()
