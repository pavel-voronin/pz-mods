"""Compare local benchmark artifacts. Python standard library only."""
import argparse
import csv
import json
import pathlib
import statistics


def read_run(folder):
    path = pathlib.Path(folder)
    manifest = json.loads((path / "manifest.json").read_text(encoding="utf-8"))
    hardware = next((p / "hardware.json" for p in path.parents if (p / "hardware.json").exists()), None)
    manifest["hardware"] = json.loads(hardware.read_text(encoding="utf-8-sig")) if hardware else "unknown"
    return path, manifest, json.loads((path / "summary.json").read_text(encoding="utf-8"))


def compare(folders):
    paths = []
    for folder in folders:
        path = pathlib.Path(folder)
        matches = [path] if (path / "summary.json").exists() else sorted(p.parent for p in path.rglob("summary.json") if (p.parent / "manifest.json").exists())
        if not matches:
            raise ValueError(f"No completed metric artifacts in {path}")
        paths.extend(matches)
    runs = [read_run(p) for p in paths]
    warnings = []
    reference = runs[0][1]
    for path, manifest, _ in runs:
        if manifest.get("status") != "complete" or manifest.get("droppedRecords", 0):
            warnings.append(f"{path.name}: incomplete/invalid run")
        for key in ("scenarioHash", "width", "height", "variant", "gpuSampleRate", "fixturePolicy", "cacheMode", "overlay", "hardware", "frameCap", "vsync", "clientSettings"):
            if manifest.get(key) != reference.get(key):
                warnings.append(f"{path.name}: different {key}")
    rows = []
    # Preserve repeat identity. Never compute percentiles of window maxima or repeat percentiles.
    keys = sorted(set().union(*(summary["groups"] for _, _, summary in runs)))
    for key in keys:
        base = runs[0][2]["groups"].get(key, {})
        values = []
        for path, _, summary in runs:
            metrics = summary["groups"].get(key)
            if metrics is None:
                values.append({"run": path.name, "missing": True})
                continue
            mean = metrics["mean_ms"]
            delta = mean - base.get("mean_ms", mean)
            values.append({"run": path.name, **metrics, "delta_ms": delta,
                           "delta_percent": 100 * delta / base["mean_ms"] if base.get("mean_ms") else None})
        rows.append({"group": key, "runs": values})
    repeat_rows = []
    for path, _, summary in runs:
        groups = {}
        for key, metrics in summary["groups"].items():
            parts = next(csv.reader([key]))
            if len(parts) != 6:
                continue
            group = tuple(parts[:1] + parts[2:])
            groups.setdefault(group, []).append(metrics["mean_ms"])
        for group, means in groups.items():
            repeat_rows.append({"run": path.name, "group": group, "repeats": len(means),
                                "median_of_repeat_means_ms": statistics.median(means),
                                "min_repeat_mean_ms": min(means), "max_repeat_mean_ms": max(means)})
    return {"schema": 1, "warnings": warnings, "rows": rows, "repeat_summary": repeat_rows,
            "limits": "Native fresh-world RNG/population are not reset. GPU percentiles are sampled. No claim of statistical significance. Check events and visual evidence."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runs", nargs="+")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    args = parser.parse_args()
    result = compare(args.runs)
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        for warning in result["warnings"]:
            print("WARNING:", warning)
        print("group | run | n | mean ms | p95 ms | delta ms | delta %")
        for row in result["rows"]:
            for v in row["runs"]:
                if v.get("missing"):
                    print(row["group"], v["run"], "MISSING", sep=" | ")
                else:
                    percent = v["delta_percent"]
                    print(f'{row["group"]} | {v["run"]} | {v["n"]} | {v["mean_ms"]:.3f} | {v["p95_ms"]:.3f} | {v["delta_ms"]:+.3f} | {percent if percent is not None else "n/a"}')
        print(result["limits"])
        for group in result["repeat_summary"]:
            if group["repeats"] > 1:
                print(f'Repeats {group["run"]} {group["group"]}: n={group["repeats"]}, median mean={group["median_of_repeat_means_ms"]:.3f} ms, range={group["min_repeat_mean_ms"]:.3f}..{group["max_repeat_mean_ms"]:.3f} ms')
