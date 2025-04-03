################################################################################
#                              CTC_merger.py                                   #
#                                                                              #
#       This is code to combine npy files following numerous save-ctc          #
#       runs using the bonito basecaller on a dataset.                         #
#                                                                              #
#       Code is by @rainwala found in this thread:                             #
#       https://github.com/nanoporetech/bonito/issues/386                      #
#                                                                              #
#       Note: save_ctc output are in several subdirectories of                 #
#       "base_data_dir"                                                        #
#                                                                              #
#       Edited and integrated into ARS fine tuning pipeline by                 #
#       Chris Gottschalk 3/18/25   v2.1                                        #
################################################################################
#!/usr/bin/env python3

import numpy as np
import sys
import glob
from concurrent.futures import ThreadPoolExecutor
import os

def load_npy_file(file_path):
    """Helper function to load a numpy array from a file."""
    return np.load(file_path, mmap_mode='r')  # Use memmap to avoid loading into memory fully

def combine_chunks(base_data_dir):
    """Combine all chunk arrays from the given directory."""
    chunks_filename = 'chunks'
    chunks_pattern = f"{base_data_dir}/*/{chunks_filename}.npy"
    with ThreadPoolExecutor(max_workers=8) as executor:  # Limiting max workers to 8
        # Use ThreadPoolExecutor to load chunk files in parallel
        chunks_list = list(executor.map(load_npy_file, glob.glob(chunks_pattern)))
    # Stack all arrays vertically
    chunks_array = np.vstack(chunks_list)
    np.save(f"{base_data_dir}/{chunks_filename}.npy", chunks_array)

def combine_reference_lengths(base_data_dir):
    """Combine all reference_lengths arrays from the given directory."""
    ref_len_filename = 'reference_lengths'
    ref_len_pattern = f"{base_data_dir}/*/{ref_len_filename}.npy"
    with ThreadPoolExecutor(max_workers=8) as executor:  # Limiting max workers to 8
        # Use ThreadPoolExecutor to load reference_length files in parallel
        ref_len_list = list(executor.map(load_npy_file, glob.glob(ref_len_pattern)))
    # Concatenate all reference length arrays
    ref_len_array = np.concatenate(ref_len_list)
    np.save(f"{base_data_dir}/{ref_len_filename}.npy", ref_len_array)
    return ref_len_array

def combine_references(base_data_dir, ref_len_array):
    """Combine all references arrays and zero-pad to max_ref_len."""
    max_ref_len = int(np.max(ref_len_array))
    ref_filename = 'references'
    ref_pattern = f"{base_data_dir}/*/{ref_filename}.npy"
    
    with ThreadPoolExecutor(max_workers=8) as executor:  # Limiting max workers to 8
        # Use ThreadPoolExecutor to load reference files in parallel
        old_ref_array_list = list(executor.map(load_npy_file, glob.glob(ref_pattern)))

    ref_array = []
    for old_array in old_ref_array_list:
        # Zero-fill the new array to 'max_ref_len' in the second dimension
        new_array = np.zeros((old_array.shape[0], max_ref_len), dtype=old_array.dtype)
        new_array[:, :old_array.shape[1]] = old_array
        ref_array.append(new_array)
    # Stack all arrays vertically
    ref_array = np.vstack(ref_array)
    np.save(f"{base_data_dir}/{ref_filename}.npy", ref_array)

def main():
    base_data_dir = sys.argv[1]

    # Combine chunks
    combine_chunks(base_data_dir)

    # Combine reference lengths and get ref_len_array for later use
    ref_len_array = combine_reference_lengths(base_data_dir)

    # Combine references
    combine_references(base_data_dir, ref_len_array)

if __name__ == '__main__':
    main()
