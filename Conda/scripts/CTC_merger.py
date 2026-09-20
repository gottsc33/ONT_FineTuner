#!/usr/bin/env python3

"""
Merge Bonito CTC training datasets.

Each input directory must contain:

    chunks.npy
    references.npy
    reference_lengths.npy

Example
-------
python CTC_merger.py \
    --input run1/ctc run2/ctc run3/ctc \
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


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Merge chunks.npy, references.npy, and reference_lengths.npy "
            "from multiple Bonito --save-ctc runs."
        )
    )

    parser.add_argument(
        "--input",
        nargs="+",
        required=True,
        type=Path,
        dest="input_directories",
        help="One or more directories containing Bonito CTC arrays.",
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
        help="Replace existing output arrays.",
    )

    return parser.parse_args()


def validate_input_directory(directory: Path) -> None:
    if not directory.is_dir():
        raise FileNotFoundError(
            f"Input is not a directory: {directory}"
        )

    missing_files = [
        name
        for name in REQUIRED_FILES
        if not (directory / name).is_file()
    ]

    if missing_files:
        raise FileNotFoundError(
            f"{directory} is missing required files: "
            f"{', '.join(missing_files)}"
        )


def load_dataset(
    directory: Path,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    chunks = np.load(
        directory / "chunks.npy",
        mmap_mode="r",
        allow_pickle=False,
    )

    references = np.load(
        directory / "references.npy",
        mmap_mode="r",
        allow_pickle=False,
    )

    reference_lengths = np.load(
        directory / "reference_lengths.npy",
        mmap_mode="r",
        allow_pickle=False,
    )

    if chunks.ndim < 2:
        raise ValueError(
            f"{directory}/chunks.npy must have at least two dimensions; "
            f"found shape {chunks.shape}"
        )

    if references.ndim != 2:
        raise ValueError(
            f"{directory}/references.npy must have two dimensions; "
            f"found shape {references.shape}"
        )

    if reference_lengths.ndim != 1:
        raise ValueError(
            f"{directory}/reference_lengths.npy must have one dimension; "
            f"found shape {reference_lengths.shape}"
        )

    counts = (
        chunks.shape[0],
        references.shape[0],
        reference_lengths.shape[0],
    )

    if len(set(counts)) != 1:
        raise ValueError(
            f"Row-count mismatch in {directory}: "
            f"chunks={counts[0]}, references={counts[1]}, "
            f"reference_lengths={counts[2]}"
        )

    if reference_lengths.size:
        maximum_length = int(np.max(reference_lengths))

        if maximum_length > references.shape[1]:
            raise ValueError(
                f"{directory} contains a reference length of "
                f"{maximum_length}, but references.npy has a width of "
                f"{references.shape[1]}"
            )

    return chunks, references, reference_lengths


def validate_compatibility(
    datasets: Sequence[
        tuple[np.ndarray, np.ndarray, np.ndarray]
    ],
) -> None:
    first_chunks, first_references, first_lengths = datasets[0]

    for number, (chunks, references, lengths) in enumerate(
        datasets[1:],
        start=2,
    ):
        if chunks.shape[1:] != first_chunks.shape[1:]:
            raise ValueError(
                f"Dataset {number} has a trailing chunks.npy shape of "
                f"{chunks.shape[1:]}; expected {first_chunks.shape[1:]}. "
                f"All basecalling runs must use the same chunk settings."
            )

        if chunks.dtype != first_chunks.dtype:
            raise TypeError(
                f"Dataset {number} has chunks.npy dtype {chunks.dtype}; "
                f"expected {first_chunks.dtype}"
            )

        if references.dtype != first_references.dtype:
            raise TypeError(
                f"Dataset {number} has references.npy dtype "
                f"{references.dtype}; expected {first_references.dtype}"
            )

        if lengths.dtype != first_lengths.dtype:
            raise TypeError(
                f"Dataset {number} has reference_lengths.npy dtype "
                f"{lengths.dtype}; expected {first_lengths.dtype}"
            )


def prepare_output_directory(
    output_directory: Path,
    overwrite: bool,
) -> None:
    output_directory.mkdir(parents=True, exist_ok=True)

    existing_files = [
        output_directory / name
        for name in REQUIRED_FILES
        if (output_directory / name).exists()
    ]

    if existing_files and not overwrite:
        formatted = ", ".join(str(path) for path in existing_files)

        raise FileExistsError(
            f"Output files already exist: {formatted}. "
            f"Use --overwrite to replace them."
        )

    for path in existing_files:
        path.unlink()


def merge_datasets(
    input_directories: Sequence[Path],
    output_directory: Path,
    overwrite: bool = False,
) -> None:
    if not input_directories:
        raise ValueError("At least one input directory is required")

    for directory in input_directories:
        validate_input_directory(directory)

    datasets = [
        load_dataset(directory)
        for directory in input_directories
    ]

    validate_compatibility(datasets)
    prepare_output_directory(output_directory, overwrite)

    first_chunks, first_references, first_lengths = datasets[0]

    total_rows = sum(
        chunks.shape[0]
        for chunks, _, _ in datasets
    )

    if total_rows == 0:
        raise ValueError("The supplied CTC datasets contain no records")

    maximum_reference_width = max(
        references.shape[1]
        for _, references, _ in datasets
    )

    merged_chunks = open_memmap(
        output_directory / "chunks.npy",
        mode="w+",
        dtype=first_chunks.dtype,
        shape=(total_rows, *first_chunks.shape[1:]),
    )

    merged_references = open_memmap(
        output_directory / "references.npy",
        mode="w+",
        dtype=first_references.dtype,
        shape=(total_rows, maximum_reference_width),
    )

    merged_lengths = open_memmap(
        output_directory / "reference_lengths.npy",
        mode="w+",
        dtype=first_lengths.dtype,
        shape=(total_rows,),
    )

    # Initialize padding in case individual references.npy arrays have
    # different second-dimension widths.
    merged_references[:] = 0

    offset = 0

    for directory, dataset in zip(input_directories, datasets):
        chunks, references, lengths = dataset

        row_count = chunks.shape[0]
        end = offset + row_count

        print(
            f"Merging {directory}: "
            f"records={row_count}, "
            f"chunk-shape={chunks.shape[1:]}, "
            f"reference-width={references.shape[1]}",
            file=sys.stderr,
        )

        merged_chunks[offset:end] = chunks

        merged_references[
            offset:end,
            : references.shape[1],
        ] = references

        merged_lengths[offset:end] = lengths

        offset = end

    merged_chunks.flush()
    merged_references.flush()
    merged_lengths.flush()

    print(
        f"Merged {len(datasets)} datasets and {total_rows} records into "
        f"{output_directory}",
        file=sys.stderr,
    )

    print(
        f"Created: {output_directory / 'chunks.npy'}",
        file=sys.stderr,
    )
    print(
        f"Created: {output_directory / 'references.npy'}",
        file=sys.stderr,
    )
    print(
        f"Created: {output_directory / 'reference_lengths.npy'}",
        file=sys.stderr,
    )


def main() -> int:
    arguments = parse_arguments()

    try:
        merge_datasets(
            input_directories=arguments.input_directories,
            output_directory=arguments.output_directory,
            overwrite=arguments.overwrite,
        )
    except Exception as error:
        print(f"CTC merger error: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())