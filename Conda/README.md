#CONDA implementation

    ##usage
    conda activate ont-finetuner

    ./run_ont_finetuner.sh \
        --reference /data/genomes/apple.fasta \
        --reads /data/apple/run01/pod5 \
        --output results/apple

    ##usage with multiple input directories

    ./run_ont_finetuner.sh \
    --reference /data/genomes/apple.fasta \
    --reads /data/apple/run01/pod5 \
    --reads /data/apple/run02/pod5 \
    --reads /data/apple/run03/pod5 \
    --output results/apple \
    --model 'dna_r10.4.1_e8.2_400bps_hac@v5.0.0' \
    --epochs 5 \
    --learning-rate 5e-4 \
    --batch-size 96

    ##Optionally apply a minimum CTC alignment accuracy:

    ./run_ont_finetuner.sh \
    --reference /data/genomes/apple.fasta \
    --reads /data/apple/pod5 \
    --output results/apple \
    --min-ctc-accuracy 0.9

    ##expected outcome
    results/apple/
        ├── run_information.txt
        ├── reference/
        │   └── reference.mmi
        ├── basecalling/
        │   ├── 001_pod5/
        │   │   ├── 001_pod5.sam
        │   │   ├── bonito.log
        │   │   └── ctc/
        │   │       ├── chunks.npy
        │   │       ├── references.npy
        │   │       └── reference_lengths.npy
        │   └── 002_pod5/
        │       └── ...
        ├── merged_ctc/
        │   ├── chunks.npy
        │   ├── references.npy
        │   └── reference_lengths.npy
        ├── bonito_train.log
        ├── fine_tuned_model/
        └── exported_model/

    ##Bonito’s export interface has changed across versions. This implementation uses:
    bonito export /path/to/fine_tuned_model