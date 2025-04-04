################################################################################
#                         Training_read_counter.py                             #
#                                                                              #
#       This is code to combine basecalls_summary.tsv files and to             #
#       report the number of unique reads by their ID used in the training.    #
#                                                                              #
#       Note: basecalls_summary.tsv output are in several subdirectories of    #
#       "base_data_dir"     						       #
#                                                                              #
#       Usage python3 Training_read_counter.py ./base_data_dir                 #
#                                                                              #
#       Edited and integrated into ARS fine tuning pipeline by                 #
#       Chris Gottschalk 4/4/25  v1                                            #
################################################################################
#!/usr/bin/env python3

import os
import pandas as pd
import glob
import sys

def find_and_merge_tsv_files(root_dir):
    # Ensure we're searching from the root directory for any subdirectories named 'dir_*'
    search_pattern = os.path.join(root_dir, 'dir_*', 'basecalls_summary.tsv')
    
    # Find all basecalls_summary.tsv files in subdirectories
    tsv_files = glob.glob(search_pattern)
    
    if not tsv_files:
        print(f"No 'basecalls_summary.tsv' files found in {root_dir}.")
        return None

    # List to store DataFrames
    dfs = []
    
    # Read all the tsv files into pandas DataFrames
    for file in tsv_files:
        try:
            df = pd.read_csv(file, sep='\t', header=0)
            dfs.append(df)
        except Exception as e:
            print(f"Error reading {file}: {e}")
    
    if not dfs:
        print("No valid dataframes to merge.")
        return None

    # Concatenate all the dataframes along rows (axis=0) preserving the header
    merged_df = pd.concat(dfs, axis=0, ignore_index=True)
    
    # Ensure 'read_id' column exists
    if 'read_id' not in merged_df.columns:
        print("'read_id' column not found in the merged dataframe.")
        return None
    
    # Calculate the number of unique entries in the 'read_id' column
    unique_read_ids = merged_df['read_id'].nunique()

    print(f"Number of unique 'read_id' entries: {unique_read_ids}")
    
    # Optionally, return the merged DataFrame
    return merged_df

def main():
    # Ensure the user has provided the directory argument
    if len(sys.argv) != 2:
        print("Usage: python script.py <directory_path>")
        sys.exit(1)
    
    root_directory = sys.argv[1]

    # Check if the provided path is a valid directory
    if not os.path.isdir(root_directory):
        print(f"The specified path {root_directory} is not a valid directory.")
        sys.exit(1)

    # Run the function
    merged_df = find_and_merge_tsv_files(root_directory)

    # Optionally, save the merged dataframe to a new file (uncomment below if needed)
    # if merged_df is not None:
    #     merged_df.to_csv('merged_basecalls_summary.tsv', sep='\t', index=False)

if __name__ == "__main__":
    main()

