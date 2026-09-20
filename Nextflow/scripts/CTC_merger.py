#!/usr/bin/env python3

"""
Merge Bonito CTC training arrays.

Each input directory must contain:

    chunks.npy
    references.npy
    reference_lengths.npy

The merged output directory will contain files with the same names.

Example
-------
python CTC_merger.py \
    --input ctc_sample1 ctc_sample2 ctc_sample3 \
    --output merged_ctc
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Sequence

import numpy as np
from numpy.lib.format import open_memmap


REQUIRED_FILES = (
    "chunks.npy",
    "references.npy",
    "reference_lengths.npy",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Merge one or more Bonito CTC training datasets."
    )

    parser.add_argument(
        "--input",
        nargs="+",
        required=True,
        type=Path,
        dest="input_directories",
        help=(
            "Directories containing chunks.npy, references.npy, and "
            "reference_lengths.npy."
        ),
    )

    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        dest="output_directory",
        help="Directory in which the merged arrays will be written.",
    )

    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Permit replacement of existing output arrays.",
    )

    return parser.parse_args()


def validate_directory(directory: Path) -> None:
    if not directory.is_dir():
        raise FileNotFoundError(
            f"CTC input is not a directory: {directory}"
        )

    missing = [
        filename
        for filename in REQUIRED_FILES
        if not (directory / filename).is_file()
    ]

    if missing:
        raise FileNotFoundError(
            f"CTC directory {directory} is missing: {', '.join(missing)}"
        )


def load_arrays(
    directory: Path,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    chunks = np.load(directory / "chunks.npy", mmap_mode="r")
    references = np.load(directory / "references.npy", mmap_mode="r")
    lengths = np.load(
        directory / "reference_lengths.npy",
        mmap_mode="r",
    )

    if chunks.ndim < 2:
        raise ValueError(
            f"{directory}/chunks.npy must have at least two dimensions; "
            f"found {chunks.shape}"
        )

    if references.ndim != 2:
        raise ValueError(
            f"{directory}/references.npy must be two-dimensional; "
            f"found {references.shape}"
        )

    if lengths.ndim != 1:
        raise ValueError(
            f"{directory}/reference_lengths.npy must be one-dimensional; "
            f"found {lengths.shape}"
        )

    row_counts = {
        int(chunks.shape[0]),
        int(references.shape[0]),
        int(lengths.shape[0]),
    }

    if len(row_counts) != 1:
        raise ValueError(
            f"Mismatched row counts in {directory}: "
            f"chunks={chunks.shape[0]}, "
            f"references={references.shape[0]}, "
            f"reference_lengths={lengths.shape[0]}"
        )

    if lengths.size and int(np.max(lengths)) > references.shape[1]:
        raise ValueError(
            f"A reference length in {directory} exceeds the width of "
            f"references.npy ({references.shape[1]})."
        )

    return chunks, references, lengths


def ensure_compatible(
    datasets: Sequence[tuple[np.ndarray, np.ndarray, np.ndarray]],
) -> None:
    first_chunks, first_references, first_lengths = datasets[0]

    for dataset_number, (chunks, references, lengths) in enumerate(
        datasets[1:],
        start=2,
    ):
        if chunks.shape[1:] != first_chunks.shape[1:]:
            raise ValueError(
                f"Dataset {dataset_number} has chunk shape "
                f"{chunks.shape[1:]}, but the first dataset has "
                f"{first_chunks.shape[1:]}. All Bonito runs must use "
                f"the same chunk configuration."
            )

        if chunks.dtype != first_chunks.dtype:
            raise TypeError(
                f"Dataset {dataset_number} has chunks dtype "
                f"{chunks.dtype}, expected {first_chunks.dtype}."
            )

        if references.dtype != first_references.dtype:
            raise TypeError(
                f"Dataset {dataset_number} has references dtype "
                f"{references.dtype}, expected {first_references.dtype}."
            )

        if lengths.dtype != first_lengths.dtype:
            raise TypeError(
                f"Dataset {dataset_number} has reference-length dtype "
                f"{lengths.dtype}, expected {first_lengths.dtype}."
            )


def check_output(
    output_directory: Path,
    overwrite: bool,
) -> None:
    output_directory.mkdir(parents=True, exist_ok=True)

    existing = [
        output_directory / filename
        for filename in REQUIRED_FILES
        if (output_directory / filename).exists()
    ]

    if existing and not overwrite:
        names = ", ".join(str(path) for path in existing)
        raise FileExistsError(
            f"Output files already exist: {names}. "
            f"Use --overwrite to replace them."
        )

    for path in existing:
        path.unlink()


def merge(
    input_directories: Sequence[Path],
    output_directory: Path,
    overwrite: bool = False,
) -> None:
    if not input_directories:
        raise ValueError("At least one CTC input directory is required.")

    for directory in input_directories:
        validate_directory(directory)

    datasets = [
        load_arrays(directory)
        for directory in input_directories
    ]

    ensure_compatible(datasets)
    check_output(output_directory, overwrite)

    first_chunks, first_references, first_lengths = datasets[0]

    total_rows = sum(chunks.shape[0] for chunks, _, _ in datasets)
    maximum_reference_width = max(
        references.shape[1]
        for _, references, _ in datasets
    )

    if total_rows == 0:
        raise ValueError("The supplied CTC datasets contain no rows.")

    output_chunks = open_memmap(
        output_directory / "chunks.npy",
        mode="w+",
        dtype=first_chunks.dtype,
        shape=(total_rows, *first_chunks.shape[1:]),
    )

    output_references = open_memmap(
        output_directory / "references.npy",
        mode="w+",
        dtype=first_references.dtype,
        shape=(total_rows, maximum_reference_width),
    )

    output_lengths = open_memmap(
        output_directory / "reference_lengths.npy",
        mode="w+",
        dtype=first_lengths.dtype,
        shape=(total_rows,),
    )

    # Zero is Bonito's padding/blank value for encoded references.
    output_references[:] = 0

    offset = 0

    for directory, (chunks, references, lengths) in zip(
        input_directories,
        datasets,
    ):
        rows = chunks.shape[0]
        end = offset + rows

        print(
            f"Merging {directory}: rows={rows}, "
            f"chunk_shape={chunks.shape[1:]}, "
            f"reference_width={references.shape[1]}",
            file=sys.stderr,
        )

        output_chunks[offset:end] = chunks

        output_references[
            offset:end,
            : references.shape[1],
        ] = references

        output_lengths[offset:end] = lengths
        offset = end

    output_chunks.flush()
    output_references.flush()
    output_lengths.flush()

    print(
        f"Merged {len(datasets)} CTC datasets into "
        f"{output_directory}.",
        file=sys.stderr,
    )
    print(
        f"Output rows: {total_rows}; "
        f"reference width: {maximum_reference_width}",
        file=sys.stderr,
    )


def main() -> int:
    args = parse_args()

    try:
        merge(
            input_directories=args.input_directories,
            output_directory=args.output_directory,
            overwrite=args.overwrite,
        )
    except Exception as exc:
        print(f"CTC merger error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())