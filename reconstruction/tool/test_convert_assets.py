"""Synthetic controls for every PNG filter and every Adam7 pass."""

import struct
import unittest
import zlib

from convert_assets import (ADAM7, PNG_SIGNATURE, chunk, chunks, convert_png,
                            decode_pixels, paeth, unpremultiply_bgra, decode_ima4)


def cgbi_fixture(width: int, height: int, interlace: int, bgra: bytes) -> bytes:
    passes = ADAM7 if interlace else ((0, 0, 1, 1),)
    raw = bytearray()
    row_number = 0
    for x_start, y_start, x_step, y_step in passes:
        xs = range(x_start, width, x_step)
        ys = range(y_start, height, y_step)
        if not xs or not ys:
            continue
        previous = bytes(len(xs) * 4)
        for y in ys:
            row = b"".join(bgra[(y * width + x) * 4:(y * width + x + 1) * 4] for x in xs)
            kind = row_number % 5
            row_number += 1
            raw.append(kind)
            for index, value in enumerate(row):
                left = row[index - 4] if index >= 4 else 0
                above = previous[index]
                upper_left = previous[index - 4] if index >= 4 else 0
                if kind == 0:
                    predictor = 0
                elif kind == 1:
                    predictor = left
                elif kind == 2:
                    predictor = above
                elif kind == 3:
                    predictor = (left + above) // 2
                else:
                    estimate = left + above - upper_left
                    predictor = min((left, above, upper_left), key=lambda value: abs(estimate - value))
                raw.append((value - predictor) & 255)
            previous = row
    deflater = zlib.compressobj(wbits=-15)
    compressed = deflater.compress(bytes(raw)) + deflater.flush()
    return (PNG_SIGNATURE + chunk(b"CgBI", b"\x50\x00\x20\x02")
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, interlace))
            + chunk(b"IDAT", compressed) + chunk(b"IEND", b""))


class ConversionTests(unittest.TestCase):
    def test_filters_and_adam7_reconstruct_each_pixel(self):
        for width, height in ((1, 1), (1, 17), (17, 1), (2, 3), (15, 15), (19, 17), (32, 25)):
            expected = bytes((index * 41 + 13) & 255 for index in range(width * height * 4))
            for interlace in (0, 1):
                with self.subTest(width=width, height=height, interlace=interlace):
                    fixture = cgbi_fixture(width, height, interlace, expected)
                    self.assertEqual(decode_pixels(fixture, True), (width, height, interlace, expected))

    def test_alpha_and_color_channels_known_answers(self):
        pixels = bytes((0, 0, 0, 0, 11, 22, 33, 255, 25, 50, 100, 128,
                        0, 1, 1, 1, 25, 25, 25, 25))
        self.assertEqual(unpremultiply_bgra(pixels),
                         bytes((0, 0, 0, 0, 33, 22, 11, 255, 199, 100, 50, 128,
                                255, 255, 0, 1, 255, 255, 255, 25)))

    def test_output_has_standard_zlib_and_no_cgbi(self):
        bgra = bytes((12, 34, 56, 255)) * 65
        result, details = convert_png(cgbi_fixture(13, 5, 1, bgra))
        self.assertEqual(decode_pixels(result, False), (13, 5, 0, bytes((56, 34, 12, 255)) * 65))
        self.assertEqual([kind for kind, _ in chunks(result)], [b"IHDR", b"IDAT", b"IEND"])
        compressed = b"".join(payload for kind, payload in chunks(result) if kind == b"IDAT")
        self.assertEqual(len(zlib.decompress(compressed)), 13 * 5 * 4 + 5)
        self.assertEqual(details["source_interlace"], "Adam7")

    def test_standard_rgba16_quantization(self):
        source_values = (0, 257, 32768, 65535, 128, 129, 65406, 65535)
        raw = struct.pack(">8H", *source_values)
        source = (PNG_SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 1, 16, 6, 0, 0, 0))
                  + chunk(b"IDAT", zlib.compress(b"\0" + raw)) + chunk(b"IEND", b""))
        output, details = convert_png(source)
        self.assertEqual(decode_pixels(output, False)[3], bytes((0, 1, 128, 255, 0, 1, 254, 255)))
        self.assertEqual(details["source_depth_bits"], 16)

    def test_ima4_known_packet_and_continuity(self):
        packet = bytes.fromhex("00009f9990123b99") + bytes(26)
        first = struct.unpack("<64h", decode_ima4(packet))
        self.assertEqual(first[:12], (-11, -17, -21, -25, -24, -27, -21, -18,
                                     -25, -21, -22, -23))
        following = struct.pack(">H", first[-1] & 0xFF80) + bytes(32)
        second = struct.unpack("<128h", decode_ima4(packet + following))[64:]
        self.assertEqual(second, (first[-1],) * 64)

    def test_invalid_ima4_packet_rejected(self):
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            decode_ima4(bytes(33))
        with self.assertRaisesRegex(ValueError, "step index"):
            decode_ima4(bytes((0, 89)) + bytes(32))

    def test_corrupt_crc_rejected(self):
        fixture = bytearray(cgbi_fixture(1, 1, 0, bytes((0, 0, 0, 0))))
        fixture[20] ^= 1
        with self.assertRaisesRegex(ValueError, "CRC"):
            chunks(fixture)

    def test_paeth_ties_follow_png_rule(self):
        self.assertEqual(paeth(1, 1, 0), 1)
        self.assertEqual(paeth(100, 120, 110), 110)


if __name__ == "__main__":
    unittest.main()
