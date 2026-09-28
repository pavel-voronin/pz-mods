"""Read native PZ LOTHEADER v0/v1 room/building metadata without launching a world.

Coordinates are PZ tiles, floor z (not renderer metres). Room rectangles do not
prove that furniture, doors or random world objects leave a route passable.
"""
import argparse
import hashlib
import json
import pathlib
import struct


def read_header(path):
    cx, cy = map(int, path.stem.split("_"))
    with path.open("rb") as f:
        def integer():
            b = f.read(4)
            if len(b) != 4:
                raise ValueError("truncated integer")
            return struct.unpack("<i", b)[0]

        def count(limit):
            n = integer()
            if not 0 <= n <= limit:
                raise ValueError(f"invalid count {n}")
            return n

        def line():
            b = f.readline(16384)
            if not b.endswith(b"\n"):
                raise ValueError("truncated/oversized string")
            return b.rstrip(b"\r\n").decode("utf-8")

        if f.read(4) != b"LOTH":
            f.seek(0)
        version = integer()
        if version not in (0, 1):
            raise ValueError(f"unsupported LOTHEADER version {version}")
        tiles = [line() for _ in range(count(100000))]
        if version == 0:
            f.read(1)
        width, height = integer(), integer()
        if (width, height) != (8, 8):
            raise ValueError(f"unsupported chunk dimensions {width}x{height}")
        levels = (0, integer() - 1) if version == 0 else (integer(), integer())
        rooms = []
        for index in range(count(100000)):
            name, z = line(), integer()
            rectangles = []
            for _ in range(count(10000)):
                x, y, w, h = integer(), integer(), integer(), integer()
                rectangles.append({"x": x + cx * 256, "y": y + cy * 256, "w": w, "h": h})
            objects = []
            for _ in range(count(100000)):
                kind, x, y = integer(), integer(), integer()
                objects.append({"type": kind, "x": x + cx * 256, "y": y + cy * 256})
            rooms.append({"index": index, "name": name, "z": z, "rectangles": rectangles, "metaObjects": objects})
        buildings = []
        for _ in range(count(100000)):
            buildings.append([integer() for _ in range(count(10000))])
    return {"source": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "version": version, "cell": [cx, cy], "levels": levels, "rooms": rooms,
            "buildings": buildings, "treePaletteEntries": [t for t in tiles if "tree" in t.lower()]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("map_directory", type=pathlib.Path)
    parser.add_argument("--x", type=int, required=True)
    parser.add_argument("--y", type=int, required=True)
    parser.add_argument("--radius", type=int, default=128)
    args = parser.parse_args()
    result = []
    for cx in range((args.x - args.radius) // 256, (args.x + args.radius) // 256 + 1):
        for cy in range((args.y - args.radius) // 256, (args.y + args.radius) // 256 + 1):
            path = args.map_directory / f"{cx}_{cy}.lotheader"
            if path.exists():
                header = read_header(path)
                header["nearbyRooms"] = [r for r in header.pop("rooms") if any(
                    box["x"] <= args.x + args.radius and box["x"] + box["w"] >= args.x - args.radius
                    and box["y"] <= args.y + args.radius and box["y"] + box["h"] >= args.y - args.radius
                    for box in r["rectangles"])]
                result.append(header)
    print(json.dumps({"schema": 1, "coordinateSystem": "PZ tiles/native floor", "headers": result,
                      "validation": "metadata only; native loading, light power and route accessibility require runtime checks"}, indent=2))
