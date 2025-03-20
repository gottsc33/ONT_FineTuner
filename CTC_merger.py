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
#       Chris Gottschalk 3/18/25                                               #
################################################################################
#!/bin/bash python3

import numpy as np
import sys
import glob

base_data_dir = sys.argv[1]

## combine the chunk arrays
chunks_filename = 'chunks'
chunks_pattern = f"{base_data_dir}/*/{chunks_filename}.npy"
chunks_array = np.vstack( [np.load(file_path) for file_path in glob.glob(chunks_pattern)] )
np.save(f"{base_data_dir}/{chunks_filename}.npy",chunks_array)

## combine the reference_lengths arrays
ref_len_filename = 'reference_lengths'
ref_len_pattern = f"{base_data_dir}/*/{ref_len_filename}.npy"
ref_len_array = np.concatenate( [np.load(file_path) for file_path in glob.glob(ref_len_pattern)] )
np.save(f"{base_data_dir}/{ref_len_filename}.npy",ref_len_array)

## combine the reference arrays
max_ref_len = int(np.max(ref_len_array))
ref_filename = 'references'
ref_pattern = f"{base_data_dir}/*/{ref_filename}.npy"
old_ref_array = [np.load(file_path) for file_path in glob.glob(ref_pattern)]
max_ref_len = int(np.max([x.shape[1] for x in old_ref_array]))

ref_array = []
for old_array in old_ref_array:
  # zerofill the new array to 'max_ref_len' in the second dimension
  new_array = np.zeros((old_array.shape[0],max_ref_len),dtype=old_array.dtype)
  new_array[:, :old_array.shape[1]] = old_array
  ref_array.append(new_array)
ref_array = np.vstack( ref_array )
np.save(f"{base_data_dir}/{ref_filename}.npy",ref_array)
