################################################################################
#          __  _________  ___      ___   ___  ____                             #
#         / / / / __/ _ \/ _ |____/ _ | / _ \/ __/                             #
#        / /_/ /\ \/ // / __ /___/ __ |/ , _/\ \                               #
#        \____/___/____/_/ |_|  /_/ |_/_/|_/___/                               #
#        ____  _  ________  _____            ______                            #
#       / __ \/ |/ /_  __/ / __(_)__  ___   /_  __/_ _____  ___ ____           #
#      / /_/ /    / / /   / _// / _ \/ -_)   / / / // / _ \/ -_) __/           #
#      \____/_/|_/ /_/   /_/ /_/_//_/\__/   /_/  \_,_/_//_/\__/_/              #
#                                                                              #
#          USDA-ARS Oxford Nanopore Technologies Model FineTuner               #
#                                                                              #
#       This is pipeling is used to fine tune ONT basecaller models            #
#       using internally produced resequence data.                             #
#       Pipeline by                                                            #
#       Chris Gottschalk 3/18/25      version: 2.1                             #
#                                                                              #
#Usage: ONT_FineTuner.sh reference_genome ./pod5_directory ONT_model_name threads#
#   Requirements: shuf, bonito, CTC_merger.py and minimap2                     #
################################################################################

#!/bin/bash

echo -e "\nWelcome! USDA-ARS ONT FineTuner is beginning to run to generate a fine-tune base calling model for your use.\n"

# Check if at least four arguments are passed; reference genome, directory of POD5 files, ONT model, and CPU threads
if [ $# -lt 4 ]; then
    echo -e  "\nPlease provide at least four arguments.\n"
    exit 1
fi

# Check if reference genome file exists
if [ ! -f "$1.fa" ]; then
  echo -e "\nReference genome file $1.fa not found.\n"
  exit 1
fi

# Build reference genome index
echo -e  "\nStep 1: Building reference genome index...\n"
mkdir -p "$1_genome_index"
minimap2 -d ./$1_genome_index/$1.mmi $1.fa

ref_index="./$1_genome_index/$1.mmi"

# Directory to store subdirectories (use the current directory or specify a path)
TARGET_DIR="./subdirectories"

# Create the target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Get a list of all .pod5 files in the current directory
POD5_FILES=($2/*.pod5)

# Check if there are any .pod5 files
if [ ${#POD5_FILES[@]} -eq 0 ]; then
    echo -e  "\nNo .pod5 files found in the current directory.\n"
    exit 1
fi

# Shuffle the list of files
shuf_files=$(printf "%s\n" "${POD5_FILES[@]}" | shuf)

# Initialize variables for subdirectory creation
counter=0
dir_counter=1
total_files=${#POD5_FILES[@]}

# Function to show progress bar
show_progress() {
    local current=$1
    local total=$2
    local progress=$(( 100 * current / total ))
    local filled=$(( progress / 2 ))  # 50 '=' characters for 100%
    local empty=$(( 50 - filled ))
    printf "\rProgress: [${filled// /=}${empty// /-}] $progress%%"
}

# Loop through shuffled files and move them into subdirectories
for file in $shuf_files; do
  if [ -f "$file" ]; then
    # Create a new subdirectory if necessary
    # Change the number to correspond to number of pod5 files to split into each subdirectory. For example, if your pod5's are >16 Gb, set the value to 1. If your pod5s are 200 Mb, keep at 25.
    if (( counter % 25 == 0 )); then
      sub_dir="$TARGET_DIR/dir_$dir_counter"
      mkdir -p "$sub_dir"
      (( dir_counter++ ))
    fi

    # Move the file to the current subdirectory
    mv "$file" "$sub_dir/"

    # Increment the file counter
    ((counter++))

    # Show progress bar
    show_progress $counter $total_files
  fi
done

echo -e "\n\nIndex is built and files are being assigned to subdirectories."

# Step 2; Basecalling to obtain CTC information for training (loop)
total_subdirs=$(find "$TARGET_DIR" -type d | wc -l)
counter=0

echo -e "\nFiles have been assigned to subdirectories. Step 1 is now complete!\n"

echo -e "\nStep 2: Basecalling to obtain CTC data for training is starting...!\n"

# Loop through subdirectories and basecall
for sub_dir in "$TARGET_DIR"/*; do
  if [ -d "$sub_dir" ]; then
    echo -e "\nRunning bonito basecaller on $sub_dir"
    bonito basecaller $3 --save-ctc --alignment-threads $4 --reference $ref_index $sub_dir > $sub_dir/basecalls.bam

    # Increment the counter and show progress
    ((counter++))
    show_progress $counter $total_subdirs
  fi
done

echo -e "\nBasecalling completed for all subdirectories. Now moving onto step 3: the merging of npy outputs...\n"
python3 CTC_merger.py $TARGET_DIR
echo -e "\nMerging complete!\n\nStep 4: fine tuning base caller is now starting...\n"

# Step 4: Training the new model
echo -e "\nStarting model training...\n"
bonito train --epochs 5 --lr 5e-4 --pretrained $3 --directory $TARGET_DIR ./fine_tuned_model/

# Optional: Show progress for training epochs
for ((i=1; i<=5; i++)); do
    show_progress $i 5
    sleep 1  # Simulate the epoch duration (remove or adjust as needed)
done

echo -e "\nStep 4: Training complete!\n"

echo -e "\nStep 5: The export or a Dorado model is beginning now...\n"

# Step 5: Exporting the new model for Dorado usage
bonito export --output "${1}_${3}" ./fine_tuned_model/

echo -e "\nPipeline is now finished! Thank you for using the USDA-ARS ONT Training Pipelline!\n"
