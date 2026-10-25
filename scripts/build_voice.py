"""Records every line Baxi can say on the practice routes with a natural voice, and bundles the recordings.

The voice is Kokoro (82M parameters, Apache 2.0, https://github.com/thewh1teagle/kokoro-onnx), an open-source
text-to-speech model run on this Mac: no account, no API, nothing sent anywhere. Each line is saved as
Baxi/Resources/Voice/<key>.m4a, where key = the first 20 hex digits of the SHA-256 of the exact line
(VoiceLines.key in the app). Lines already recorded are skipped; recordings for lines no longer said are removed.
Anything without a recording is spoken by the iPhone's own voice.

Setup (once):
    python3 -m venv ~/kokoro-env && ~/kokoro-env/bin/pip install kokoro-onnx soundfile
    brew install espeak-ng
    download kokoro-v1.0.onnx and voices-v1.0.bin from
    https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0 into one folder
Run:
    swift run baxi-voicelines > /tmp/lines.json
    ~/kokoro-env/bin/python -I scripts/build_voice.py /tmp/lines.json <model folder>
"""
import json, pathlib, re, subprocess, sys, tempfile

VOICE = "af_heart"      # Kokoro's highest-rated English voice: calm and clear
SPEED = 1.0
OUT = pathlib.Path(__file__).resolve().parent.parent / "Baxi" / "Resources" / "Voice"
ESPEAK_LIB = "/opt/homebrew/lib/libespeak-ng.dylib"


def espeak_data():
    found = sorted(pathlib.Path("/opt/homebrew/Cellar/espeak-ng").glob("*/share/espeak-ng-data"))
    if not found:
        raise SystemExit("espeak-ng not found: brew install espeak-ng")
    return str(found[-1])


def for_speech(text):
    """Spell out what a voice model may misread. Only the audio changes; the key stays the line as written."""
    words = {"1,000": "one thousand", "500 feet": "five hundred feet", "1st": "First", "2nd": "Second", "3rd": "Third"}
    for a, b in words.items():
        text = re.sub(rf"(?<![\w,]){re.escape(a)}(?![\w,])", b, text)
    return text if text.endswith((".", "!", "?")) else text + "."


def main():
    lines = json.loads(pathlib.Path(sys.argv[1]).read_text())
    models = pathlib.Path(sys.argv[2])
    from kokoro_onnx import Kokoro, EspeakConfig
    import soundfile as sf
    kokoro = Kokoro(str(models / "kokoro-v1.0.onnx"), str(models / "voices-v1.0.bin"),
                    espeak_config=EspeakConfig(lib_path=ESPEAK_LIB, data_path=espeak_data()))
    OUT.mkdir(parents=True, exist_ok=True)
    wanted = set(lines)
    for stale in OUT.glob("*.m4a"):
        if stale.stem not in wanted:
            stale.unlink()
    todo = [(k, t) for k, t in sorted(lines.items()) if not (OUT / f"{k}.m4a").exists()]
    with tempfile.TemporaryDirectory() as tmp:
        for i, (key, text) in enumerate(todo, 1):
            samples, rate = kokoro.create(for_speech(text), voice=VOICE, speed=SPEED, lang="en-us")
            wav = pathlib.Path(tmp) / f"{key}.wav"
            sf.write(wav, samples, rate)
            # AAC at 32 kbit/s, mono: clear speech in a few KB a line.
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "32000", str(wav), str(OUT / f"{key}.m4a")], check=True)
            print(f"{i}/{len(todo)} {text}", flush=True)
    total = sum(f.stat().st_size for f in OUT.glob("*.m4a"))
    print(f"{len(wanted)} lines, {len(todo)} recorded now, {total / 1e6:.1f} MB in {OUT}")


if __name__ == "__main__":
    main()
