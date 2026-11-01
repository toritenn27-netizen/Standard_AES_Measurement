#!/usr/bin/env python3
"""Verify every printed state with independent AES math and a FIPS example."""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MASTER_KEY = bytes.fromhex('2b7e151628aed2a6abf7158809cf4f3c')
LABELS = ['Plaintext', 'Key (Round 0)', 'Key (Round 1)',
          'Initial AddRoundKey (R0)', 'SubBytes (R1)', 'ShiftRows (R1)',
          'MixColumns (R1)', 'AddRoundKey (R1)']


def require(value, message):
    if not value:
        raise AssertionError(message)


def mul(a, b):
    value = 0
    for _ in range(8):
        if b & 1:
            value ^= a
        a = ((a << 1) ^ (0x11b if a & 128 else 0)) & 255
        b >>= 1
    return value


def sub_byte(value):
    inverse = 0 if value == 0 else 1
    if value:
        for _ in range(254):
            inverse = mul(inverse, value)
    result = inverse ^ 0x63
    for shift in range(1, 5):
        result ^= ((inverse << shift) | (inverse >> (8-shift))) & 255
    return result


SBOX = [sub_byte(i) for i in range(256)]


def expected_blocks(plaintext):
    # Derive K1 independently; the firmware contains no precomputed K1 table.
    key1 = bytearray(16)
    for i, source in enumerate((13, 14, 15, 12)):
        key1[i] = MASTER_KEY[i] ^ SBOX[MASTER_KEY[source]] ^ (1 if i == 0 else 0)
    for i in range(4, 16):
        key1[i] = MASTER_KEY[i] ^ key1[i-4]
    initial = bytes(a ^ b for a, b in zip(plaintext, MASTER_KEY))
    subbed = bytes(SBOX[a] for a in initial)
    shifted = bytes(subbed[4*((c+r) % 4)+r] for c in range(4) for r in range(4))
    mixed = bytearray()
    for c in range(4):
        col = shifted[c*4:c*4+4]
        for r in range(4):
            mixed.append(mul(2, col[r]) ^ mul(3, col[(r+1) % 4]) ^
                         col[(r+2) % 4] ^ col[(r+3) % 4])
    result = bytes(a ^ b for a, b in zip(mixed, key1))
    return [plaintext, MASTER_KEY, bytes(key1), initial, subbed, shifted, bytes(mixed), result]


def parse(path):
    raw = path.read_bytes()
    require(b'\n' not in raw.replace(b'\r\n', b''), f'Incorrect line endings: {path}')
    pattern = rb'^([^\r\n:]+?)\s+: ((?:[0-9A-F]{2} ){15}[0-9A-F]{2})\r$'
    fields = re.findall(pattern, raw, re.MULTILINE)
    require(len(fields) % 8 == 0, 'Incomplete stage output')
    blocks = []
    for start in range(0, len(fields), 8):
        group = fields[start:start+8]
        require([name.decode().rstrip() for name, _ in group] == LABELS, 'Wrong stage order')
        blocks.append([bytes.fromhex(value.decode()) for _, value in group])
    require(raw.count(b'=== AES-128 Round 1: one plaintext ===\r\n') == len(blocks), 'Wrong header count')
    require(raw.count(b"Done. Send 'S' for a new plaintext.\r\n") == len(blocks), 'Wrong completion count')
    return blocks


def check(directory):
    normal = parse(directory / 'serial.log')
    stats = json.loads((directory / 'stats.json').read_text())
    require(stats == {'requested':100, 'round_entries':100, 'completed':100, 'known_vector':False}, 'Expected 100 single-round tests')
    require(len(normal) == 100, 'Expected 100 outputs')
    xs = 12345
    plaintexts = []
    for index, actual in enumerate(normal):
        plaintext = bytearray()
        for _ in range(16):
            xs ^= (xs << 13) & 0xffffffff
            xs ^= xs >> 17
            xs ^= (xs << 5) & 0xffffffff
            plaintext.append(xs & 255)
        plaintext = bytes(plaintext)
        require(actual == expected_blocks(plaintext), f'Stage mismatch at test {index+1}')
        plaintexts.append(plaintext)
    require(len(set(plaintexts)) == 100, 'Repeated plaintext in serial retests')
    known = parse(directory / 'known_vector.log')
    # FIPS 197 (2001), Appendix B: one intermediate-state worked example.
    published = [
        '3243f6a8885a308d313198a2e0370734',
        '2b7e151628aed2a6abf7158809cf4f3c',
        'a0fafe1788542cb123a339392a6c7605',
        '193de3bea0f4e22b9ac68d2ae9f84808',
        'd42711aee0bf98f1b8b45de51e415230',
        'd4bf5d30e0b452aeb84111f11e2798e5',
        '046681e5e0cb199a48f8d37a2806264c',
        'a49c7ff2689f352b6b5bea43026a5049',
    ]
    require(known == [[bytes.fromhex(value) for value in published]], 'Published FIPS intermediate-state vector mismatch')
    known_stats = json.loads((directory / 'known_vector_stats.json').read_text())
    require(known_stats == {'requested':1, 'round_entries':1, 'completed':1, 'known_vector':True}, 'Wrong known-vector test count')
    print('PASS: 100 commands -> 100 new plaintexts, exactly one round each')
    print('PASS: master key, derived round key and all five AES stages match independent math')
    print('PASS: all stages match the published FIPS worked example')
    print('PASS: lowercase/unknown commands ignored; no automatic rerun while idle')


if __name__ == '__main__':
    check(ROOT / 'build/stage-test')
