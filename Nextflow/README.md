#Running the workflow
    ##Validate the workflow first

    nextflow run main.nf \
        --samplesheet samplesheet.csv \
        --reference /data/genomes/apple.fasta \
        -stub-run

    ##Because commands that create expected files cannot always be meaningfully stubbed without 
    ##explicit stub: blocks, a practical initial check is:

    nextflow run main.nf \
        --samplesheet samplesheet.csv \
        --reference /data/genomes/apple.fasta \
        -preview
    
    
    ##Run locally

    nextflow run main.nf \
        --samplesheet samplesheet.csv \
        --reference /data/genomes/apple.fasta \
        --outdir results \
        -resume
    
    ##Run with Conda
    ##After confirming CUDA compatibility:

    nextflow run main.nf \
        --samplesheet samplesheet.csv \
        --reference /data/genomes/apple.fasta \
        --outdir results \
        -with-conda \
        -resume
    
    ##Override training settings

    nextflow run main.nf \
        --samplesheet samplesheet.csv \
        --reference /data/genomes/apple.fasta \
        --pretrained_model 'dna_r10.4.1_e8.2_400bps_hac@v5.0.0' \
        --epochs 10 \
        --learning_rate '5e-4' \
        --batch_size 64 \
        --train_args '--device cuda' \
        --outdir results \
        -resume
    
    
    ##Expected outputs

    results/
    ├── reference/
    │   └── reference.mmi
    ├── basecalling/
    │   ├── apple_01/
    │   │   └── apple_01.sam
    │   ├── apple_02/
    │   │   └── apple_02.sam
    │   └── apple_03/
    │       └── apple_03.sam
    ├── training_data/
    │   └── merged_ctc/
    │       ├── chunks.npy
    │       ├── references.npy
    │       └── reference_lengths.npy
    ├── model/
    │   └── exported_model/
    ├── execution-report.html
    ├── execution-timeline.html
    ├── execution-trace.tsv
    └── pipeline-dag.html