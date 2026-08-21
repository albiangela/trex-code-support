# trex-code-support

Support scripts for working with [`TRex`](https://trex.run) animal-tracking exports: converting annotation exports into a YOLO training dataset, and batch-running `TRex`'s video conversion over many clips.

## Contents

- [`annotations-to-dataset.ipynb`](annotations-to-dataset.ipynb) — merges `TRex` and Roboflow annotation exports into a single, validated YOLO `train`/`val` dataset.
- [`run_trex_batch.sh`](run_trex_batch.sh) — batch-runs the `TRex` CLI's video conversion over multiple clips.

---

## 1. `annotations-to-dataset.ipynb`

### What it does

The notebook finds one or more `TRex` `videoname_annotations_yolo` export folders and optional Roboflow exports (detected via the `roboflow:` block in their `data.yaml`, so the folder itself can have any name) under an input directory. It:

1. Renames `TRex` frames to `videoname_frame_number` so every file stays unique once pooled (Roboflow files already have unique names and are kept as-is).
2. Pools every export together into one staging area.
3. Uses [`dataset-fixer`](https://github.com/mooch443/dataset-fixer) to validate the pooled data and split it into a new `train`/`val` YOLO dataset, writing `train/images`, `train/labels`, `val/images`, `val/labels`, and `data.yaml`, plus validation, lineage, and split-audit reports.

Class names are read automatically from a `data.yaml`/`dataset.yaml` found under the input directory (a Roboflow project's YAML takes priority, since it holds the complete class schema), or can be set manually. See the notebook's own markdown cells for the full details on folder layout requirements.

### Running it in VS Code

1. Install [VS Code](https://code.visualstudio.com/) and, from the Extensions panel, the **Python** and **Jupyter** extensions (both from Microsoft).
2. Make sure a **Python 3.12+** interpreter is available (the notebook checks this itself and stops if it isn't) — e.g. via `python3 --version`, [pyenv](https://github.com/pyenv/pyenv), or conda.
3. Open this folder in VS Code, then open `annotations-to-dataset.ipynb`.
4. In the top-right of the notebook, click **Select Kernel** and choose your Python 3.12+ environment.
5. Run the cells top to bottom (`Run All`, or step through with `Shift+Enter`). The first cell installs the `dataset-fixer` dependency directly from GitHub, since it isn't published on PyPI.

### Configuring the input/output and the split ratio

Before running, edit the configuration cell (section "2. Configure the conversion"):

```python
INPUT_ROOT = Path("/path/to/annotation-exports/")   # folder to search for exports
OUTPUT_DATASET = Path("/path/to/training-data/")     # where the new dataset is written
CLASS_NAMES = None            # auto-detect from data.yaml, or set ["shark", "ray", "turtle"]
TASK = "detect"                # detect, segment, pose, or polo

VALIDATION_FRACTION = 0.20     # share of frames reserved for validation
RANDOM_SEED = 42                # makes the split reproducible
SPLIT_BY_VIDEO = True           # keep each video's frames in a single split

DEEP_DUPLICATE_CHECK = False
OVERWRITE_OUTPUT = True         # True replaces an existing OUTPUT_DATASET folder
```

The split ratio and grouping are controlled by three settings:

- **`VALIDATION_FRACTION`** — the fraction of frames set aside for validation, strictly between `0` and `1`. `0.20` means an 80% train / 20% validation split. A common range is `0.10`–`0.30`; use a smaller fraction if you have very little data and want to keep more of it for training.
- **`SPLIT_BY_VIDEO`** — when `True` (recommended), every frame from the same source video stays in the same split, so no video appears in both `train` and `val`. This avoids temporal leakage between near-identical consecutive frames, but requires at least two distinct videos/exports. Set it to `False` to split individual frames randomly instead (e.g. if you only have one video).
- **`RANDOM_SEED`** — a fixed seed so the split is reproducible: rerunning the notebook with the same inputs and seed always produces the same train/val assignment. Change it to get a different random split.

Once configured, run section "4. Build the dataset" to perform the conversion.

---

## 2. `run_trex_batch.sh`

### What it does

`run_trex_batch.sh` batch-runs `TRex`'s own `trex` command-line tool (`trex -i <video> -s <settings> -task convert`) over multiple video files, so you don't have to invoke it by hand for every clip. It has two modes:

- **`-d DIRECTORY`** — recursively searches `DIRECTORY` for MP4 files matching a filename pattern (any subfolder literally named `clips` is skipped), and runs the conversion on each match in sorted order.
- **`-v VIDEO_OR_PATTERN`** — either a single existing MP4 file (processed directly), or a filename glob pattern (e.g. `/path/to/videos/y*.mp4`), matched non-recursively within that one directory.

The script stops and reports an error if the settings file is missing, if `trex` isn't on the `PATH`, or if any matched video fails to convert. Each video's `TRex` stdout/stderr is also saved next to it as `<video>.trex.log`, so a failure can be diagnosed later without rerunning.

### Prerequisites

- `TRex` installed, with the `trex` binary available on your `PATH`.
- A `TRex` `.settings` file for the conversion.

### How to use it

```bash
chmod +x run_trex_batch.sh   # first time only

# Recursively convert every "y*.mp4" clip under a directory
./run_trex_batch.sh \
    -d "/path/to/videos" \
    -p "y*" \
    -s "/path/to/default.settings"

# Convert every MP4 matching a pattern in one directory
./run_trex_batch.sh \
    -v "/path/to/videos/y*.mp4" \
    -s "/path/to/default.settings"

# Convert a single video
./run_trex_batch.sh \
    -v "/path/to/video.mp4" \
    -s "/path/to/default.settings"
```

Options:

| Flag | Description | Default |
| --- | --- | --- |
| `-d DIRECTORY` | Recursively search a directory for MP4s (mode 1) | — |
| `-v VIDEO_OR_PATTERN` | Process a single video or glob pattern (mode 2) | — |
| `-p PATTERN` | Filename pattern used with `-d` | `y*.mp4` |
| `-s SETTINGS` | Path to the `TRex` `.settings` file | `default.settings` |
| `-h` | Show help | — |

Use either `-d` or `-v`, not both. Run `./run_trex_batch.sh -h` at any time to see this usage summary.
