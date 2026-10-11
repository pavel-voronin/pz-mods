"""Validate native baseline artifacts and print comparable window summaries."""
import argparse
import json
import pathlib
import csv
import math


def percentile(values, fraction):
    values = sorted(values)
    return values[max(0, math.ceil(len(values) * fraction) - 1)] if values else None


def summarize(directory):
    launch = json.loads((directory / "launch.json").read_text(encoding="utf-8-sig"))
    result = json.loads((directory / "scenario-result.json").read_text(encoding="utf-8-sig"))
    if launch.get("status") != "complete" or result.get("status") != "complete":
        raise ValueError(f"Incomplete run: {directory}")
    if not launch.get("nativeOnly") or not launch.get("exited") or launch.get("forcedExit"):
        raise ValueError("Not a normally exited native-only session")
    preset = (pathlib.Path(launch["nativeProfile"]) / "mods/default.txt").read_text()
    if "pz3d" in preset.lower():
        raise ValueError("pz3d enabled in baseline profile")
    with (directory / "native-events.csv").open(newline="") as stream:
        records = [row for row in csv.reader(stream) if len(row) >= 3][1:]
    windows = []
    for path in sorted(directory.glob("native-*.json")):
        window = json.loads(path.read_text())
        if window.get("dropped") or window["updateCost"]["count"] < 1 or window["presents"]["count"] < 1:
            raise ValueError(f"Lost or missing measurements: {path}")
        samples = [r for r in records if r[0] == "sample" and r[2] == window["name"]]
        forward = [r for r in samples if len(r) >= 14]
        if forward:
            window["requiredAheadRange"] = [min(int(r[12]) for r in forward), max(int(r[12]) for r in forward)]
            window["missingAheadP95"] = percentile([int(r[13]) for r in forward], .95)
        window["squareMismatchSamples"] = sum(r[10] != "true" for r in samples)
        window["sampleCount"] = len(samples)
        window["stages"] = {}
        for phase in range(5):
            values = [float(r[5]) for r in records if r[0] == f"chunk{phase}" and r[2] == window["name"]]
            window["stages"][str(phase)] = {"count": len(values), "p95Ms": percentile(values, .95),
                                            "p99Ms": percentile(values, .99), "maxMs": max(values, default=0)}
        window["queueLast"] = int(samples[-1][8]) if samples else None
        window["queueFirst"] = int(samples[0][8]) if samples else None
        window["sampleStartNs"] = int(samples[0][1]) if samples else None
        window["sampleEndNs"] = int(samples[-1][1]) if samples else None
        window["artifact"] = str(directory)
        monitor = directory / "system.jsonl"
        if monitor.exists() and samples:
            window["system"] = system_summary(window, monitor)
        if "dx" in window and (not window.get("god") or not window.get("invisible")):
            raise ValueError("Baseline player was not protected")
        windows.append(window)
    return windows


def system_summary(window, monitor):
    samples = [json.loads(line) for line in monitor.read_text(encoding="utf-8-sig").splitlines()]
    samples = [s for s in samples if window["sampleStartNs"] <= s["monotonic_ns"] <= window["sampleEndNs"]]
    own, foreign, gpus = [], [], []
    for sample in samples:
        for process in sample["java"]:
            if window["artifact"].replace("/", "\\") in (process.get("command") or ""):
                own.append(process)
            else:
                foreign.append({"utc": sample["utc"], **process})
        try:
            gpus.append([float(v.strip()) for v in sample["gpu"].split(",")])
        except ValueError:
            pass
    return {"samples": len(samples), "foreignProcesses": foreign,
            "maxWorkingSetMiB": max((p["working_set"] / 1048576 for p in own), default=0),
            "maxPrivateMiB": max((p["private_bytes"] / 1048576 for p in own), default=0),
            "gpuTemperatureRange": [min((g[0] for g in gpus), default=0), max((g[0] for g in gpus), default=0)],
            "gpuUtilizationRange": [min((g[1] for g in gpus), default=0), max((g[1] for g in gpus), default=0)],
            "cpuCoreEquivalent": (own[-1]["cpu_seconds"] - own[0]["cpu_seconds"]) / window["seconds"] if len(own)>1 else None}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifacts", nargs="+", type=pathlib.Path)
    parser.add_argument("--json", type=pathlib.Path)
    args = parser.parse_args()
    windows = [w for directory in args.artifacts for w in summarize(directory)]
    if args.json:
        args.json.write_text(json.dumps(windows, indent=2))
    print("grid | window | km/h | minimum ready lead tiles / seconds | minimum ready ahead | maximum missing ahead | object attachments/s | low-reserve episodes")
    for w in windows:
        lead_seconds = w["minLead"] / (w["kmh"] / 3.6) if w["minLead"] >= 0 and w["kmh"] > 0 else -1
        flow = w.get("attachedChunksPerSecond", w["contentChunks"] / w["seconds"])
        print(f'{w["grid"]} | {w["name"]} | {w["kmh"]:.2f} | {w["minLead"]:.1f} / {lead_seconds:.2f} | '
              f'{w.get("minReadyAhead", "N/A")} | {w.get("maxMissingAhead", "N/A")} | {flow:.1f} | {w["lateCount"]}')
