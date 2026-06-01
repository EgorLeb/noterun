#!/usr/bin/env python3
"""Generate elochka.mid — В лесу родилась ёлочка (20 notes, BPM=80)"""
import struct, os

def var_len(v):
    buf = [v & 0x7F]
    v >>= 7
    while v:
        buf.append((v & 0x7F) | 0x80)
        v >>= 7
    buf.reverse()
    return bytes(buf)

tpb = 480  # ticks per beat
bpm = 80
us_per_beat = int(60_000_000 / bpm)  # 750000

# Notes: (pitch, start_beat_float, duration_beats_float)
# Ёлочка in C major, 20 notes
notes = [
    (64, 0.0,  0.5),   # E4
    (62, 0.5,  0.25),  # D4
    (60, 0.75, 0.25),  # C4
    (62, 1.0,  0.25),  # D4
    (64, 1.25, 0.25),  # E4
    (64, 1.5,  0.25),  # E4
    (64, 1.75, 0.75),  # E4 (dotted quarter)
    (62, 2.5,  0.25),  # D4
    (62, 2.75, 0.25),  # D4
    (62, 3.0,  0.75),  # D4 (dotted quarter)
    (64, 3.75, 0.25),  # E4
    (67, 4.0,  0.5),   # G4
    (67, 4.5,  1.0),   # G4 (half)
    (64, 5.5,  0.5),   # E4
    (62, 6.0,  0.25),  # D4
    (60, 6.25, 0.25),  # C4
    (62, 6.5,  0.25),  # D4
    (64, 6.75, 0.25),  # E4
    (64, 7.0,  0.25),  # E4
    (60, 7.25, 1.5),   # C4 (end)
]

# Build event list: (abs_tick, bytes)
events = []
# Tempo event at tick 0
events.append((0, bytes([0xFF, 0x51, 0x03,
    (us_per_beat >> 16) & 0xFF,
    (us_per_beat >> 8)  & 0xFF,
     us_per_beat        & 0xFF])))

for pitch, start_b, dur_b in notes:
    start_t = int(start_b * tpb)
    end_t   = int((start_b + dur_b) * tpb)
    events.append((start_t, bytes([0x90, pitch, 80])))  # note on
    events.append((end_t,   bytes([0x80, pitch, 0])))   # note off

# Add end-of-track
max_tick = max(t for t, _ in events)
events.append((max_tick + tpb, bytes([0xFF, 0x2F, 0x00])))

events.sort(key=lambda x: x[0])

# Encode as delta-time events
track_data = b''
prev_tick = 0
for abs_tick, data in events:
    delta = abs_tick - prev_tick
    prev_tick = abs_tick
    track_data += var_len(delta) + data

header = b'MThd' + struct.pack('>IHHH', 6, 0, 1, tpb)
track  = b'MTrk' + struct.pack('>I', len(track_data)) + track_data

out = '/Users/egorleb/PycharmProjects/tset_python/fix_alie_model/app/noterun_v3/assets/midi/elochka.mid'
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'wb') as f:
    f.write(header + track)
print(f"Written {len(header+track)} bytes → {out}")
print(f"Notes: {len(notes)}, Duration: ~{notes[-1][1]+notes[-1][2]:.1f} beats @ {bpm}bpm = {(notes[-1][1]+notes[-1][2])*60/bpm:.1f}s")
