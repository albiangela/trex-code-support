#!/usr/bin/env bash

set -uo pipefail

usage() {
    cat <<'EOF'
Usage:
  run_trex_batch.sh -d DIRECTORY [-p PATTERN] [-s SETTINGS]
  run_trex_batch.sh -v VIDEO_OR_PATTERN [-s SETTINGS]

Modes:
  -d DIRECTORY
      Search recursively for numbered MP4 subclips.
      Derive one TRex sequence input such as:
      video_000001.mp4 -> video_%06d.mp4

  -v VIDEO_OR_PATTERN
      Process actual MP4 files individually.
      No %Nd sequence pattern is generated.

Options:
  -p PATTERN
      Filename search pattern used with -d.
      Default: y*.mp4

  -s SETTINGS
      TRex settings file.
      Default: default.settings

  -h
      Show this help.

Examples:
  ./run_trex_batch.sh \
      -d "/path/to/videos" \
      -p "y*" \
      -s "/path/to/default.settings"

  ./run_trex_batch.sh \
      -v "/path/to/videos/y*.mp4" \
      -s "/path/to/default.settings"

  ./run_trex_batch.sh \
      -v "/path/to/video.mp4" \
      -s "/path/to/default.settings"
EOF
}

DIRECTORY=""
VIDEO_PATTERN=""
FILE_PATTERN="y*.mp4"
SETTINGS="default.settings"

while getopts ":d:v:p:s:h" option; do
    case "$option" in
        d)
            DIRECTORY="$OPTARG"
            ;;
        v)
            VIDEO_PATTERN="$OPTARG"
            ;;
        p)
            FILE_PATTERN="$OPTARG"
            ;;
        s)
            SETTINGS="$OPTARG"
            ;;
        h)
            usage
            exit 0
            ;;
        :)
            echo "Option -$OPTARG requires a value." >&2
            usage >&2
            exit 2
            ;;
        \?)
            echo "Unknown option: -$OPTARG" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -n "$DIRECTORY" && -n "$VIDEO_PATTERN" ]]; then
    echo "Use either -d or -v, not both." >&2
    exit 2
fi

if [[ -z "$DIRECTORY" && -z "$VIDEO_PATTERN" ]]; then
    echo "Either -d DIRECTORY or -v VIDEO_OR_PATTERN is required." >&2
    usage >&2
    exit 2
fi

if [[ ! -f "$SETTINGS" ]]; then
    echo "Settings file does not exist: $SETTINGS" >&2
    exit 1
fi

if ! command -v trex >/dev/null 2>&1; then
    echo "Could not find 'trex' in PATH." >&2
    exit 1
fi

run_trex() {
    local input="$1"

    echo
    echo "Starting TRex"
    echo "Input:    $input"
    echo "Settings: $SETTINGS"

    if trex \
        -i "$input" \
        -s "$SETTINGS" \
        -task convert
    then
        echo "Finished: $input"
        return 0
    else
        echo "TRex failed: $input" >&2
        return 1
    fi
}

process_individual_videos() {
    local search_directory
    local search_pattern
    local video
    local found
    local failures

    # If -v points to an existing file, process it directly.
    if [[ -f "$VIDEO_PATTERN" ]]; then
        case "$VIDEO_PATTERN" in
            *.[mM][pP]4)
                run_trex "$VIDEO_PATTERN"
                return $?
                ;;
            *)
                echo "The input file is not an MP4: $VIDEO_PATTERN" >&2
                return 1
                ;;
        esac
    fi

    # Otherwise, interpret -v as a filename pattern.
    search_directory="$(dirname "$VIDEO_PATTERN")"
    search_pattern="$(basename "$VIDEO_PATTERN")"

    if [[ ! -d "$search_directory" ]]; then
        echo "Video directory does not exist: $search_directory" >&2
        return 1
    fi

    found=false
    failures=0

    while IFS= read -r -d '' video; do
        found=true

        if ! run_trex "$video"; then
            failures=$((failures + 1))
        fi
    done < <(
        find "$search_directory" \
            -maxdepth 1 \
            -type f \
            -iname "$search_pattern" \
            -iname '*.mp4' \
            -print0 |
        sort -z
    )

    if [[ "$found" == false ]]; then
        echo "No MP4 files matched: $VIDEO_PATTERN" >&2
        return 1
    fi

    if ((failures > 0)); then
        echo "$failures video(s) failed." >&2
        return 1
    fi

    return 0
}

process_directory() {
    local video
    local found=false
    local failures=0

    if [[ ! -d "$DIRECTORY" ]]; then
        echo "Directory does not exist: $DIRECTORY" >&2
        return 1
    fi

    while IFS= read -r -d '' video; do
        found=true

        if ! run_trex "$video"; then
            failures=$((failures + 1))
        fi
    done < <(
        find "$DIRECTORY" \
            -type d -iname clips -prune -o \
            -type f \
            -iname "$FILE_PATTERN" \
            -iname '*.mp4' \
            -print0 |
        sort -z
    )

    if [[ "$found" == false ]]; then
        echo "No MP4 files matching '$FILE_PATTERN' found under:" >&2
        echo "$DIRECTORY" >&2
        return 1
    fi

    if ((failures > 0)); then
        echo "$failures video(s) failed." >&2
        return 1
    fi
}

if [[ -n "$VIDEO_PATTERN" ]]; then
    process_individual_videos
else
    process_directory
fi