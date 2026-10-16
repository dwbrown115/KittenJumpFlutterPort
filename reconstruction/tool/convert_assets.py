#!/usr/bin/env python3
"""Convert the archived iOS resources without modifying the archived app."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
from pathlib import Path
import struct
import subprocess
import wave
import zipfile
import zlib


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
ADAM7 = ((0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8),
         (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2))


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def chunks(data: bytes) -> list[tuple[bytes, bytes]]:
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("Invalid PNG signature")
    result = []
    offset = len(PNG_SIGNATURE)
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError("Truncated PNG chunk")
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        end = offset + 8 + length
        if end + 4 > len(data):
            raise ValueError("Truncated PNG payload")
        payload = data[offset + 8:end]
        crc = struct.unpack_from(">I", data, end)[0]
        if zlib.crc32(kind + payload) & 0xFFFFFFFF != crc:
            raise ValueError(f"Invalid {kind!r} CRC")
        result.append((kind, payload))
        offset = end + 4
        if kind == b"IEND":
            if offset != len(data):
                raise ValueError("Trailing bytes after IEND")
            break
    if not result or result[-1][0] != b"IEND":
        raise ValueError("Missing IEND")
    return result


def chunk(kind: bytes, payload: bytes) -> bytes:
    return (struct.pack(">I", len(payload)) + kind + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))


def paeth(left: int, above: int, upper_left: int) -> int:
    prediction = left + above - upper_left
    distances = (abs(prediction - left), abs(prediction - above),
                 abs(prediction - upper_left))
    if distances[0] <= distances[1] and distances[0] <= distances[2]:
        return left
    if distances[1] <= distances[2]:
        return above
    return upper_left


def unfilter(filtered: bytes, previous: bytes, kind: int, bpp: int = 4) -> bytes:
    if kind not in range(5):
        raise ValueError(f"Invalid PNG filter: {kind}")
    row = bytearray(len(filtered))
    for index, value in enumerate(filtered):
        left = row[index - bpp] if index >= bpp else 0
        above = previous[index]
        upper_left = previous[index - bpp] if index >= bpp else 0
        predictor = (0, left, above, (left + above) // 2,
                     paeth(left, above, upper_left))[kind]
        row[index] = (value + predictor) & 0xFF
    return bytes(row)


def decode_pixels(data: bytes, cgbi: bool) -> tuple[int, int, int, bytes]:
    parts = chunks(data)
    ihdr = [payload for kind, payload in parts if kind == b"IHDR"]
    if len(ihdr) != 1:
        raise ValueError("Expected one IHDR")
    width, height, depth, color, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", ihdr[0])
    if width == 0 or height == 0 or depth not in (8, 16) or (color, compression, filtering) != (6, 0, 0):
        raise ValueError("Only nonempty 8-bit or 16-bit RGBA PNGs are supported")
    if cgbi and depth != 8:
        raise ValueError("CgBI requires 8-bit channels")
    bytes_per_pixel = 4 * (depth // 8)
    if interlace not in (0, 1):
        raise ValueError("Invalid interlace mode")
    is_cgbi = any(kind == b"CgBI" for kind, _ in parts)
    if cgbi != is_cgbi:
        raise ValueError("Unexpected CgBI presence")
    compressed = b"".join(payload for kind, payload in parts if kind == b"IDAT")
    inflater = zlib.decompressobj(-15 if cgbi else 15)
    raw = inflater.decompress(compressed) + inflater.flush()
    if not inflater.eof or inflater.unused_data:
        raise ValueError("Incomplete or trailing deflate stream")
    rgba = bytearray(width * height * bytes_per_pixel)
    offset = 0
    passes = ADAM7 if interlace else ((0, 0, 1, 1),)
    for x_start, y_start, x_step, y_step in passes:
        pass_width = max(0, (width - x_start + x_step - 1) // x_step)
        pass_height = max(0, (height - y_start + y_step - 1) // y_step)
        if not pass_width or not pass_height:
            continue
        row_bytes = pass_width * bytes_per_pixel
        previous = bytes(row_bytes)
        for pass_y in range(pass_height):
            if offset + row_bytes + 1 > len(raw):
                raise ValueError("Truncated scanlines")
            row = unfilter(raw[offset + 1:offset + 1 + row_bytes], previous, raw[offset], bytes_per_pixel)
            previous = row
            offset += row_bytes + 1
            y = y_start + pass_y * y_step
            for pass_x in range(pass_width):
                x = x_start + pass_x * x_step
                source = pass_x * bytes_per_pixel
                pixel = row[source:source + bytes_per_pixel]
                rgba[(y * width + x) * bytes_per_pixel:(y * width + x + 1) * bytes_per_pixel] = pixel
    if offset != len(raw):
        raise ValueError("Unexpected scanline bytes")
    return width, height, interlace, bytes(rgba)


def unpremultiply_bgra(bgra: bytes) -> bytes:
    result = bytearray(len(bgra))
    for offset in range(0, len(bgra), 4):
        blue, green, red, alpha = bgra[offset:offset + 4]
        # CgBI stores premultiplied 8-bit channels; nearest rounding is
        # deterministic, but cannot recover colors lost in that quantization.
        if alpha:
            channels = [min(255, (channel * 255 + alpha // 2) // alpha)
                        for channel in (red, green, blue)]
        else:
            channels = [0, 0, 0]
        result[offset:offset + 4] = bytes((*channels, alpha))
    return bytes(result)


def encode_png(width: int, height: int, rgba: bytes) -> bytes:
    if len(rgba) != width * height * 4:
        raise ValueError("Pixel count mismatch")
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    rows = b"".join(b"\0" + rgba[y * width * 4:(y + 1) * width * 4]
                    for y in range(height))
    return (PNG_SIGNATURE + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def convert_png(source: bytes) -> tuple[bytes, dict]:
    if not any(kind == b"CgBI" for kind, _ in chunks(source)):
        width, height, interlace, raw = decode_pixels(source, cgbi=False)
        depth = struct.unpack(">IIBBBBB", dict(chunks(source))[b"IHDR"])[2]
        rgba = raw if depth == 8 else bytes((sample + 128) // 257
                    for sample in struct.unpack(">" + "H" * (len(raw) // 2), raw))
        return encode_png(width, height, rgba), {
            "width": width, "height": height,
            "source_interlace": "Adam7" if interlace else "none",
            "source_depth_bits": depth, "source_format": "standard straight RGBA",
            "source_straight_rgba_sha256": sha256(raw),
            "output_interlace": "none", "output_color_type": "RGBA8",
            "output_straight_rgba_sha256": sha256(rgba),
            "quantization": "16-bit to 8-bit nearest integer (sample + 128) // 257" if depth == 16 else "none",
        }
    width, height, interlace, bgra = decode_pixels(source, cgbi=True)
    rgba = unpremultiply_bgra(bgra)
    premultiplied_rgba = bytearray(bgra)
    for offset in range(0, len(bgra), 4):
        premultiplied_rgba[offset], premultiplied_rgba[offset + 2] = bgra[offset + 2], bgra[offset]
    output = encode_png(width, height, rgba)
    decoded_width, decoded_height, output_interlace, decoded = decode_pixels(output, cgbi=False)
    if (decoded_width, decoded_height, output_interlace, decoded) != (width, height, 0, rgba):
        raise ValueError("PNG output verification failed")
    premultiply_max_error = 0
    for offset in range(0, len(bgra), 4):
        blue, green, red, alpha = bgra[offset:offset + 4]
        for original, straight in zip((red, green, blue), rgba[offset:offset + 3]):
            restored = (straight * alpha + 127) // 255
            premultiply_max_error = max(premultiply_max_error, abs(original - restored))
    return output, {
        "width": width, "height": height,
        "source_depth_bits": 8, "source_format": "CgBI premultiplied BGRA",
        "source_interlace": "Adam7" if interlace else "none",
        "output_interlace": "none", "output_color_type": "RGBA8",
        "source_premultiplied_bgra_sha256": sha256(bgra),
        "source_premultiplied_rgba_sha256": sha256(premultiplied_rgba),
        "output_straight_rgba_sha256": sha256(rgba),
        "maximum_premultiply_roundtrip_channel_error": premultiply_max_error,
    }


def audio_details(path: Path) -> dict:
    with wave.open(str(path), "rb") as audio:
        if audio.getcomptype() != "NONE" or audio.getsampwidth() != 2:
            raise ValueError(f"Expected 16-bit PCM WAV: {path}")
        pcm = audio.readframes(audio.getnframes())
        expected = audio.getnframes() * audio.getnchannels() * audio.getsampwidth()
        if len(pcm) != expected:
            raise ValueError(f"PCM payload size mismatch: {path}")
        return {
            "encoding": "PCM signed 16-bit little-endian",
            "channels": audio.getnchannels(), "sample_rate_hz": audio.getframerate(),
            "sample_frames": audio.getnframes(),
            "duration_seconds": audio.getnframes() / audio.getframerate(),
            "pcm_bytes": len(pcm), "pcm_sha256": sha256(pcm),
        }


IMA_STEP = (7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
    34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157,
    173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658,
    724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272,
    2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132,
    7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350,
    22385, 24623, 27086, 29794, 32767)
IMA_INDEX = (-1, -1, -1, -1, 2, 4, 6, 8)


def decode_ima4(packets: bytes) -> bytes:
    if len(packets) % 34:
        raise ValueError("Incomplete mono Apple IMA4 packet")
    predictor, step_index = 0, 0
    samples = []
    for offset in range(0, len(packets), 34):
        packet = packets[offset:offset + 34]
        header = struct.unpack(">H", packet[:2])[0]
        packet_index = header & 127
        packet_predictor = header & 0xFF80
        if packet_predictor >= 32768:
            packet_predictor -= 65536
        if packet_index > 88:
            raise ValueError("Invalid Apple IMA4 step index")
        # Consecutive Apple packets retain the low seven predictor bits when
        # the quantized header and step index match the previous decoder state.
        if predictor & ~127 != packet_predictor or step_index != packet_index:
            predictor = packet_predictor
        step_index = packet_index
        for value in packet[2:]:
            for nibble in (value & 15, value >> 4):
                step = IMA_STEP[step_index]
                delta = (step >> 3) + ((step >> 2) if nibble & 1 else 0)
                delta += ((step >> 1) if nibble & 2 else 0) + (step if nibble & 4 else 0)
                predictor = max(-32768, min(32767, predictor + (-delta if nibble & 8 else delta)))
                step_index = max(0, min(88, step_index + IMA_INDEX[nibble & 7]))
                samples.append(predictor)
    return struct.pack("<" + "h" * len(samples), *samples)


def source_audio(source: Path) -> tuple[bytes, dict]:
    original = source.read_bytes()
    if source.suffix.lower() == ".caf":
        if original[:8] != b"caff\x00\x01\x00\x00":
            raise ValueError("Unexpected CAF header")
        offset, parts = 8, {}
        while offset < len(original):
            kind, length = struct.unpack_from(">4sq", original, offset)
            if length < 0 or offset + 12 + length > len(original):
                raise ValueError("Invalid CAF chunk length")
            parts[kind] = original[offset + 12:offset + 12 + length]
            offset += 12 + length
        description = struct.unpack(">d4sIIIII", parts[b"desc"])
        if description != (44100.0, b"ima4", 0, 34, 64, 1, 0):
            raise ValueError("Unexpected CAF encoding")
        _, valid, priming, remainder = struct.unpack(">qqii", parts[b"pakt"])
        packets = parts[b"data"][4:]
        pcm = decode_ima4(packets)
        if len(pcm) // 2 != valid + priming + remainder:
            raise ValueError("CAF packet frame count mismatch")
        pcm = pcm[priming * 2:(priming + valid) * 2]
        return pcm, {"container": "CAF", "source_encoding": "mono Apple IMA4 ADPCM",
                     "source_valid_frames": valid, "source_priming_frames": priming,
                     "source_remainder_frames": remainder, "source_packets": len(packets) // 34}
    if original[:4] != b"FORM" or original[8:12] != b"AIFC":
        raise ValueError("Expected AIFC")
    offset, parts = 12, {}
    while offset < len(original):
        kind, length = struct.unpack_from(">4sI", original, offset)
        parts[kind] = original[offset + 8:offset + 8 + length]
        offset += 8 + length + length % 2
    channels, packet_count, sample_bits = struct.unpack(">HIH", parts[b"COMM"][:8])
    if (channels, sample_bits, parts[b"COMM"][18:22]) != (1, 16, b"ima4"):
        raise ValueError("Unexpected AIFC encoding")
    if parts[b"COMM"][8:18] != bytes.fromhex("400eac44000000000000"):
        raise ValueError("Expected AIFC 44100 Hz")
    sound_offset, blocksize = struct.unpack(">II", parts[b"SSND"][:8])
    if blocksize != 0:
        raise ValueError("Unexpected AIFF block size")
    packets = parts[b"SSND"][8 + sound_offset:]
    if len(packets) != packet_count * 34:
        raise ValueError("AIFC packet count mismatch")
    return decode_ima4(packets), {"container": "AIFC", "source_encoding": "mono Apple IMA4 ADPCM",
                                 "source_packets": packet_count}


def convert_audio(source: Path, destination: Path) -> dict:
    subprocess.run(["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16",
                    str(source), str(destination)], check=True, capture_output=True)
    details = audio_details(destination)
    if (details["channels"], details["sample_rate_hz"]) != (1, 44100):
        raise ValueError("Unexpected channel count or sample rate")
    expected_pcm, source_details = source_audio(source)
    if sha256(expected_pcm) != details["pcm_sha256"]:
        raise ValueError(f"Independent IMA4 samples differ: {source.name}")
    details.update(source_details)
    details["converter"] = "macOS /usr/bin/afconvert -f WAVE -d LEI16"
    details["source_sample_verification"] = "Exact match to independent Apple IMA4 decoder with packet/frame metadata validation"
    return details


def verify_source(app: Path, identity_path: Path, ipa: Path) -> tuple[dict, str]:
    identity = json.loads(identity_path.read_text())
    ipa_hash = sha256(ipa.read_bytes())
    if ipa_hash != identity["sha256"]:
        raise ValueError("Original IPA hash changed")
    with zipfile.ZipFile(ipa) as archive:
        expected = {name.removeprefix("Payload/KJ2.app/"): archive.read(name)
                    for name in archive.namelist() if name.startswith("Payload/KJ2.app/") and not name.endswith("/")}
        actual = {str(path.relative_to(app)) for path in app.rglob("*") if path.is_file()}
        if actual != set(expected):
            raise ValueError("Original app file list differs from IPA")
        for relative, data in expected.items():
            if (app / relative).read_bytes() != data:
                raise ValueError(f"Original differs from IPA: {relative}")
    return {"files": [{"relative_path": relative, "sha256": sha256(data), "bytes": len(data)}
                      for relative, data in sorted(expected.items())]}, ipa_hash


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original-root", type=Path,
                        default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.original_root.resolve()
    reconstruction = Path(__file__).resolve().parents[1]
    app = root / "Extracted/Payload/KJ2.app"
    inventory_path = root / "analysis/artifact-identity.json"
    ipa = root / "KittenJump-Paid-2.1.1-Christmas-bullate.ipa"
    inventory, ipa_hash = verify_source(app, inventory_path, ipa)
    image_dir = reconstruction / "assets/images"
    audio_dir = reconstruction / "assets/audio"
    image_dir.mkdir(parents=True, exist_ok=True)
    audio_dir.mkdir(parents=True, exist_ok=True)
    entries = []
    for source in sorted(app.glob("*.png")):
        original = source.read_bytes()
        converted, details = convert_png(original)
        destination = image_dir / source.name
        destination.write_bytes(converted)
        entries.append({"source": "Extracted/Payload/KJ2.app/" + source.name,
                        "source_sha256": sha256(original), "source_bytes": len(original),
                        "output": "assets/images/" + source.name,
                        "output_sha256": sha256(converted), "output_bytes": len(converted),
                        "image": details})
    if len(entries) != 85:
        raise ValueError("Expected all 85 original images")
    audio_sources = sorted([*app.glob("*.caf"), *app.glob("*.aif")])
    if len(audio_sources) != 34:
        raise ValueError("Expected 31 CAFs and 3 AIFC tracks")
    for audio_source in audio_sources:
        source_name, output_name = audio_source.name, audio_source.stem + ".wav"
        source = app / source_name
        destination = audio_dir / output_name
        details = convert_audio(source, destination)
        converted = destination.read_bytes()
        entries.append({"source": "Extracted/Payload/KJ2.app/" + source_name,
                        "source_sha256": sha256(source.read_bytes()), "source_bytes": source.stat().st_size,
                        "output": "assets/audio/" + output_name,
                        "output_sha256": sha256(converted), "output_bytes": len(converted),
                        "audio": details})
    font_dir = reconstruction / "assets/fonts"
    font_dir.mkdir(parents=True, exist_ok=True)
    for source in sorted(app.glob("*.fnt")):
        data = source.read_bytes()
        (font_dir / source.name).write_bytes(data)
        entries.append({"source": "Extracted/Payload/KJ2.app/" + source.name,
                        "source_sha256": sha256(data), "source_bytes": len(data),
                        "output": "assets/fonts/" + source.name,
                        "output_sha256": sha256(data), "output_bytes": len(data),
                        "font": {"format": "BMFont text", "conversion": "exact byte copy"}})
    verify_source(app, inventory_path, ipa)
    manifest = {
        "schema_version": 1,
        "source": {"artifact": ipa.name, "ipa_sha256": ipa_hash,
                   "inventory": "analysis/artifact-identity.json",
                   "inventory_sha256": sha256(inventory_path.read_bytes()),
                   "verified_original_app_files": len(inventory["files"]),
                   "version": "Kitten Jump Paid Christmas 2.1.1", "bundle_id": "com.marksergienko.KittenApp"},
        "conversion": {
            "images": "Raw-deflate CgBI; PNG filter reversal; Adam7 pass placement; BGRA to RGBA; nearest integer alpha unpremultiplication; PNG zlib encoding",
            "standard_png": "butterfly.png is standard RGBA16; rounded to RGBA8 for consistent runtime decoding",
            "image_limits": "No resampling. Source is premultiplied 8-bit; original straight colors lost during premultiplication cannot be recovered exactly. Alpha-zero RGB is set to zero.",
            "audio": "Decode mono 44100 Hz Apple IMA4 ADPCM to PCM signed 16-bit WAV using macOS afconvert; independently compare every sample",
            "fonts": "Three original BMFont text files copied exactly, with original atlas PNGs converted. No system fonts copied.",
        },
        "assets": entries,
    }
    (reconstruction / "assets/manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Verified {len(inventory['files'])} original app files against IPA and artifact identity.")
    print(f"Converted and verified 85 PNGs, 34 PCM WAVs, and copied 3 bitmap-font metadata files.")
    for entry in entries:
        if "audio" in entry:
            print(entry["output"], entry["audio"]["sample_frames"], "frames",
                  f"{entry['audio']['duration_seconds']:.6f} seconds")


if __name__ == "__main__":
    main()
