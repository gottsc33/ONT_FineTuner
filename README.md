# Development of a Fine Tuned Oxford Nanopore Tech Basecalling model for Malus domestica

##Requirements:

1) shuf
 https://en.wikipedia.org/wiki/Shuf
2) ONT_FineTuner_v2.1.sh
This is a module shell script to run the model fine tuning pipeline from this repository.
``` sh
git clone XXXXX
chmod u+x ONT_FineTuner_v2.1.sh
```
3) CTC_merger.py
This is a required accessory script that needs to be save in the working directory.
``` sh
chmod u+x CTC_merger.py
```
4) ONT bonito and other requirements
https://github.com/nanoporetech/bonito
``` sh
conda create -n bonito minimap2
pip install --upgrade pip
pip install ont-bonito
```
5) Fuji Diploid genome
The resulting two haplomes were edited to differentiate sequence headers [e.g. Chr01A = hap_A] and to remove any redunancy in the naming of unanchored scaffolds/contigs.

``` sh
wget https://www.rosaceae.org/rosaceae_downloads/Malus_x_domestica/Fuji_cau_v1.0.a2/assembly/Fuji_hap_A.Chr.fa.gz
wget https://www.rosaceae.org/rosaceae_downloads/Malus_x_domestica/Fuji_cau_v1.0.a2/assembly/Fuji_hap_B.Chr.fa.gz
```
Processed diploid fasta has been made available at this link:
``` sh
wget https://www.rosaceae.org/rosaceae_downloads/Malus_x_domestica/drMalDom_FujiDip.fa.fa.gz
```

##Usage
``` sh
conda activate bonito

ONT_FineTuner_v2.1.sh reference_genome ./Pod5_directory ONT_model_name threads
```
##Example
``` sh
#randomly split sequencing run in half for training and validation
cd ./Pod5
shuf -n 307 -e * | xargs -i mv {} ../validation/
cd ..
conda activate bonito
ONT_FineTuner_v2.1.sh drMalDom_FujiDip ./Pod5/ dna_r10.4.1_e8.2_400bps_hac@v5.0.0 30 >> log_file 2>> err_file
```

##Dorado comparisons
``` sh
dorado basecaller -x cuda:0 ./drMalDom_FujiDip_dna_r10.4.1_e8.2_400bps_hac@v5.0.0 ./evaluation > ./finetuned_basecalls_dorado.sam
dorado basecaller -x cuda:1 dna_r10.4.1_e8.2_400bps_hac@v5.0.0 ./evaluation > ./basecalls_dorado.sam

samtools view -bS -@ 30 finetuned_basecalls_dorado.sam > finetuned_basecalls_dorado.bam
samtools fastq finetuned_basecalls_dorado.bam > finetuned_basecalls_dorado.fastq

samtools view -bS -@ 30 basecalls_dorado.sam > basecalls_dorado.bam
samtools fastq basecalls_dorado.bam > basecalls_dorado.fastq

NanoPlot -t 30 -o finetuned_basecalls_dorado --fastq finetuned_basecalls_dorado.fastq
NanoPlot -t 30 -o basecalls_dorado --fastq basecalls_dorado.fastq
```

#Citation
##Gottschalk, C. 2025. Pipeline for fine tuned Oxford Nanopore Technologies Basecalling models for fruit crops.
##Fuji genome:
Li, W., Chu, C., Li, H. et al. Near-gapless and haplotype-resolved apple genomes provide insights into the genetic basis of rootstock-induced dwarfing. Nat Genet (2024) https://doi.org/10.1038/s41588-024-01657-2
##CTC_merger.py:
@rainwala https://github.com/nanoporetech/bonito/issues/386#issuecomment-2100938965
