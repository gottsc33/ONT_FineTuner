#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# ONT FineTuner Conda workflow
#
# Steps:
#   1. Index the reference genome with Minimap2.
#   2. Run Bonito basecaller with --save-ctc for each reads directory.
#   3. Merge chunks.npy, references.npy, and reference_lengths.npy using
#      CTC_merger.py.
#   4. Fine-tune the pretrained Bonito model.
#   5. Export the fine-tuned model for Dorado.
###############################################################################

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"

REFERENCE=""
OUTPUT_DIR=""
READS_DIRS=()

PRETRAINED_MODEL="dna_r10.4.1_e8.2_400bps_hac@v5.0.0"
EPOCHS=5
LEARNING_RATE="5e-4"
BATCH_SIZE=96
MIN_CTC_ACCURACY=""
DEVICE="cuda"

SKIP_EXPORT=false
FORCE=false


usage() {
    cat <<'EOF'
Usage:
  run_ont_finetuner.sh \
      --reference reference.fasta \
      --reads /path/to/sample1/pod5 \
      [--reads /path/to/sample2/pod5 ...] \
      --output results

Required arguments:
  --reference FILE       Reference genome in FASTA format.
  --reads PATH           Directory or input accepted by Bonito. This option
                         may be specified more than once.
  --output DIR           Output directory.

Optional arguments:
  --model NAME           Pretrained Bonito model.
                         Default:
                         dna_r10.4.1_e8.2_400bps_hac@v5.0.0

  --epochs INT           Number of training epochs. Default: 5
  --learning-rate FLOAT  Learning rate. Default: 5e-4
  --batch-size INT       Bonito training batch size. Default: 96
  --device NAME          Bonito device: cuda or cpu. Default: cuda

  --min-ctc-accuracy N   Pass --min-accuracy-save-ctc N to Bonito.
                         If omitted, Bonito's default is used.

  --skip-export          Stop after Bonito training.
  --force                Remove and recreate existing step outputs.
  -h, --help             Display this message.

Example:
  ./run_ont_finetuner.sh \
      --reference /data/genomes/apple.fasta \
      --reads /data/apple/run01/pod5 \
      --reads /data/apple/run02/pod5 \
      --output results/apple \
      --epochs 5 \
      --batch-size 96
EOF
}


log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}


die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}


absolute_path() {
    python - "$1" <<'PY'
import os
import sys

print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
}


command_exists() {
    command -v "$1" >/dev/null 2>&1
}


while [[ $# -gt 0 ]]; do
    case "$1" in
        --reference)
            [[ $# -ge 2 ]] || die "--reference requires a value"
            REFERENCE="$2"
            shift 2
            ;;
        --reads)
            [[ $# -ge 2 ]] || die "--reads requires a value"
            READS_DIRS+=("$2")
            shift 2
            ;;
        --output)
            [[ $# -ge 2 ]] || die "--output requires a value"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --model)
            [[ $# -ge 2 ]] || die "--model requires a value"
            PRETRAINED_MODEL="$2"
            shift 2
            ;;
        --epochs)
            [[ $# -ge 2 ]] || die "--epochs requires a value"
            EPOCHS="$2"
            shift 2
            ;;
        --learning-rate)
            [[ $# -ge 2 ]] || die "--learning-rate requires a value"
            LEARNING_RATE="$2"
            shift 2
            ;;
        --batch-size)
            [[ $# -ge 2 ]] || die "--batch-size requires a value"
            BATCH_SIZE="$2"
            shift 2
            ;;
        --device)
            [[ $# -ge 2 ]] || die "--device requires a value"
            DEVICE="$2"
            shift 2
            ;;
        --min-ctc-accuracy)
            [[ $# -ge 2 ]] || die "--min-ctc-accuracy requires a value"
            MIN_CTC_ACCURACY="$2"
            shift 2
            ;;
        --skip-export)
            SKIP_EXPORT=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done


###############################################################################
# Validate arguments and software
###############################################################################

[[ -n "$REFERENCE" ]] || die "Missing required argument: --reference"
[[ -n "$OUTPUT_DIR" ]] || die "Missing required argument: --output"
[[ ${#READS_DIRS[@]} -gt 0 ]] || die "At least one --reads path is required"

[[ -f "$REFERENCE" ]] || die "Reference FASTA does not exist: $REFERENCE"
[[ -f "$SCRIPT_DIR/scripts/CTC_merger.py" ]] ||
    die "Cannot find $SCRIPT_DIR/scripts/CTC_merger.py"

for reads in "${READS_DIRS[@]}"; do
    [[ -e "$reads" ]] || die "Reads input does not exist: $reads"
done

command_exists python   || die "python is not available"
command_exists minimap2 || die "minimap2 is not available"
command_exists bonito   || die "bonito is not available"

REFERENCE="$(absolute_path "$REFERENCE")"
OUTPUT_DIR="$(absolute_path "$OUTPUT_DIR")"

for index in "${!READS_DIRS[@]}"; do
    READS_DIRS[$index]="$(absolute_path "${READS_DIRS[$index]}")"
done

mkdir -p "$OUTPUT_DIR"

REFERENCE_DIR="$OUTPUT_DIR/reference"
BASECALL_DIR="$OUTPUT_DIR/basecalling"
MERGED_CTC_DIR="$OUTPUT_DIR/merged_ctc"
TRAINED_MODEL_DIR="$OUTPUT_DIR/fine_tuned_model"
EXPORTED_MODEL_DIR="$OUTPUT_DIR/exported_model"

mkdir -p "$REFERENCE_DIR" "$BASECALL_DIR"

REFERENCE_INDEX="$REFERENCE_DIR/reference.mmi"


###############################################################################
# Record the execution environment
###############################################################################

{
    echo "Execution date: $(date --iso-8601=seconds 2>/dev/null || date)"
    echo "Reference: $REFERENCE"
    echo "Reads:"
    printf '  %s\n' "${READS_DIRS[@]}"
    echo "Pretrained model: $PRETRAINED_MODEL"
    echo "Epochs: $EPOCHS"
    echo "Learning rate: $LEARNING_RATE"
    echo "Batch size: $BATCH_SIZE"
    echo "Device: $DEVICE"
    echo
    echo "Conda environment: ${CONDA_DEFAULT_ENV:-not detected}"
    echo
    echo "Minimap2:"
    minimap2 --version 2>&1 || true
    echo
    echo "Bonito:"
    bonito --version 2>&1 || true
    echo
    echo "Python:"
    python --version 2>&1 || true
} > "$OUTPUT_DIR/run_information.txt"


###############################################################################
# Step 1: Index the reference genome
###############################################################################

if [[ "$FORCE" == true ]]; then
    rm -f "$REFERENCE_INDEX"
fi

if [[ -s "$REFERENCE_INDEX" ]]; then
    log "Step 1/5: Reusing existing reference index: $REFERENCE_INDEX"
else
    log "Step 1/5: Indexing reference genome"

    minimap2 \
        -d "$REFERENCE_INDEX" \
        "$REFERENCE"

    [[ -s "$REFERENCE_INDEX" ]] ||
        die "Minimap2 did not create the expected reference index"
fi


###############################################################################
# Step 2: Generate CTC arrays with Bonito
###############################################################################

log "Step 2/5: Generating Bonito CTC training arrays"

CTC_DIRS=()

for index in "${!READS_DIRS[@]}"; do
    reads="${READS_DIRS[$index]}"

    # Prefixing with a number ensures unique output names even when two input
    # paths have the same final directory name.
    input_name="$(basename "$reads")"
    input_name="${input_name//[^A-Za-z0-9._-]/_}"
    sample_id="$(printf '%03d_%s' "$((index + 1))" "$input_name")"

    sample_dir="$BASECALL_DIR/$sample_id"
    ctc_dir="$sample_dir/ctc"
    alignment_file="$sample_dir/${sample_id}.sam"
    log_file="$sample_dir/bonito.log"

    if [[ "$FORCE" == true ]]; then
        rm -rf "$sample_dir"
    fi

    mkdir -p "$ctc_dir"

    if [[ -s "$ctc_dir/chunks.npy" &&
          -s "$ctc_dir/references.npy" &&
          -s "$ctc_dir/reference_lengths.npy" ]]; then

        log "Reusing CTC arrays for $sample_id"
    else
        log "Running Bonito basecaller for $sample_id"

        rm -f \
            "$ctc_dir/chunks.npy" \
            "$ctc_dir/references.npy" \
            "$ctc_dir/reference_lengths.npy"

        bonito_args=(
            basecaller
            "$PRETRAINED_MODEL"
            --device "$DEVICE"
            --save-ctc
            --reference "$REFERENCE_INDEX"
        )

        if [[ -n "$MIN_CTC_ACCURACY" ]]; then
            bonito_args+=(
                --min-accuracy-save-ctc
                "$MIN_CTC_ACCURACY"
            )
        fi

        bonito_args+=("$reads")

        # Bonito writes the CTC NumPy files to the current working directory.
        # Running it from ctc_dir isolates each input's training arrays.
        (
            cd "$ctc_dir"

            bonito "${bonito_args[@]}" \
                > "$alignment_file" \
                2> "$log_file"
        )

        [[ -s "$ctc_dir/chunks.npy" ]] ||
            die "Missing CTC output for $sample_id: chunks.npy"

        [[ -s "$ctc_dir/references.npy" ]] ||
            die "Missing CTC output for $sample_id: references.npy"

        [[ -s "$ctc_dir/reference_lengths.npy" ]] ||
            die "Missing CTC output for $sample_id: reference_lengths.npy"
    fi

    CTC_DIRS+=("$ctc_dir")
done


###############################################################################
# Step 3: Merge CTC arrays
#
# CTC_merger.py belongs here:
#     Bonito basecaller --save-ctc
#                 |
#                 v
#          CTC_merger.py
#                 |
#                 v
#            Bonito train
###############################################################################

log "Step 3/5: Merging CTC training arrays with CTC_merger.py"

if [[ "$FORCE" == true ]]; then
    rm -rf "$MERGED_CTC_DIR"
fi

if [[ -s "$MERGED_CTC_DIR/chunks.npy" &&
      -s "$MERGED_CTC_DIR/references.npy" &&
      -s "$MERGED_CTC_DIR/reference_lengths.npy" ]]; then

    log "Reusing existing merged CTC data: $MERGED_CTC_DIR"
else
    rm -rf "$MERGED_CTC_DIR"

    python "$SCRIPT_DIR/scripts/CTC_merger.py" \
        --input "${CTC_DIRS[@]}" \
        --output "$MERGED_CTC_DIR"

    [[ -s "$MERGED_CTC_DIR/chunks.npy" ]] ||
        die "CTC merger did not create chunks.npy"

    [[ -s "$MERGED_CTC_DIR/references.npy" ]] ||
        die "CTC merger did not create references.npy"

    [[ -s "$MERGED_CTC_DIR/reference_lengths.npy" ]] ||
        die "CTC merger did not create reference_lengths.npy"
fi


###############################################################################
# Step 4: Fine-tune the Bonito model
###############################################################################

log "Step 4/5: Fine-tuning the Bonito model"

if [[ "$FORCE" == true ]]; then
    rm -rf "$TRAINED_MODEL_DIR"
fi

if [[ -d "$TRAINED_MODEL_DIR" &&
      -n "$(find "$TRAINED_MODEL_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]]; then

    log "Reusing existing trained model: $TRAINED_MODEL_DIR"
else
    rm -rf "$TRAINED_MODEL_DIR"

    bonito train \
        --epochs "$EPOCHS" \
        --lr "$LEARNING_RATE" \
        --batch "$BATCH_SIZE" \
        --device "$DEVICE" \
        --pretrained "$PRETRAINED_MODEL" \
        --directory "$MERGED_CTC_DIR" \
        "$TRAINED_MODEL_DIR" \
        2>&1 | tee "$OUTPUT_DIR/bonito_train.log"

    [[ -d "$TRAINED_MODEL_DIR" ]] ||
        die "Bonito did not create the expected trained-model directory"
fi


###############################################################################
# Step 5: Export the trained model
###############################################################################

if [[ "$SKIP_EXPORT" == true ]]; then
    log "Step 5/5: Model export skipped"
else
    log "Step 5/5: Exporting the fine-tuned model"

    if [[ "$FORCE" == true ]]; then
        rm -rf "$EXPORTED_MODEL_DIR"
    fi

    if [[ -d "$EXPORTED_MODEL_DIR" &&
          -n "$(find "$EXPORTED_MODEL_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]]; then

        log "Reusing existing exported model: $EXPORTED_MODEL_DIR"
    else
        rm -rf "$EXPORTED_MODEL_DIR"
        mkdir -p "$EXPORTED_MODEL_DIR"

        # Bonito export behavior changed across releases. Bonito 0.8.1
        # exports the supplied training model for Dorado. Running from the
        # export directory keeps generated files together.
        (
            cd "$EXPORTED_MODEL_DIR"

            bonito export "$TRAINED_MODEL_DIR" \
                2>&1 | tee bonito_export.log
        )
    fi
fi


###############################################################################
# Completion summary
###############################################################################

log "ONT FineTuner workflow completed"
log "Reference index: $REFERENCE_INDEX"
log "Merged CTC data: $MERGED_CTC_DIR"
log "Fine-tuned model: $TRAINED_MODEL_DIR"

if [[ "$SKIP_EXPORT" == false ]]; then
    log "Exported model: $EXPORTED_MODEL_DIR"
fi