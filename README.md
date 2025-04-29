# Development of a Fine Tuned Oxford Nanopore Tech Basecalling model for Rosaceae Crops
 ## Requirements:
 
 1) shuf
  https://en.wikipedia.org/wiki/Shuf
 2) ONT_FineTuner.sh
 This is a module shell script to run the model fine tuning pipeline from this repository. Add this directory to your $PATH.
 ``` sh
 git clone https://github.com/gottsc33/ONT_FineTuner.git
 cd ONT_FineTuner
 chmod u+x ONT_FineTuner.sh
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
 5) For this example let's use the Fuji Diploid genome
 The resulting two haplomes were edited to differentiate sequence headers [e.g. Chr01A = hap_A] and to remove any redunancy in the naming of unanchored scaffolds/contigs.
 
 ``` sh
 wget https://www.rosaceae.org/rosaceae_downloads/Malus_x_domestica/Fuji_cau_v1.0.a2/assembly/Fuji_hap_A.Chr.fa.gz
 wget https://www.rosaceae.org/rosaceae_downloads/Malus_x_domestica/Fuji_cau_v1.0.a2/assembly/Fuji_hap_B.Chr.fa.gz
 ```
 Processed diploid fasta has been made available at this link:
 ``` sh
 wget https://www.rosaceae.org/rosaceae_downloads/Malus_x_domestica/drMalDom_FujiDip.fa.fa.gz
 ```
 
 6) Processing and QC programs
https://github.com/wdecoster/NanoPlot
https://github.com/wdecoster/NanoComp
https://github.com/wdecoster/chopper
  ``` sh
 conda install -c bioconda chopper samtools Nanoplot Nanocomp
 ```

 
 ## Usage
 ``` sh
 conda activate bonito
 
 ONT_FineTuner.sh reference_genome ./Pod5_directory ONT_model_name threads
 ```
 ## Example
 ``` sh
 #Randomly split sequencing run in half for training and validation. You will need to change the number following the -n flag in shuf to split your dataset accordingly (pod5 file size and total number are important)
 #Note for our RTX6000 and RTX4500 (both are 24 GB models) we can input a max pod5 file size around 16 GB (or a total of 16 GB between multiple pod5s), so plan accordingly.

 cd ./Pod5
 shuf -n 307 -e * | xargs -i mv {} ../validation/
 cd ..
 conda activate bonito

 #here we will fine-tune using the latest available HAC model dna_r10.4.1_e8.2_400bps_hac@v5.0.0
 ONT_FineTuner.sh drMalDom_FujiDip ./Pod5/ dna_r10.4.1_e8.2_400bps_hac@v5.0.0 30 >> log_file 2>> err_file
 ```
 
 ## Example run of using new fine-tuned model with Dorado and comparing with the standard ONT model dna_r10.4.1_e8.2_400bps_hac@v5.0.0
 ``` sh
 #running simultaneously on a two GPU system
 dorado basecaller -x cuda:0 ./drMalDom_FujiDip_dna_r10.4.1_e8.2_400bps_hac@v5.0.0 ./evaluation > ./finetuned_basecalls_dorado.bam #running on GPU 0
 dorado basecaller -x cuda:1 dna_r10.4.1_e8.2_400bps_hac@v5.0.0 ./evaluation > ./basecalls_dorado.bam #running on GPU 1
 
 samtools fastq finetuned_basecalls_dorado.bam > finetuned_basecalls_dorado.fq
 samtools fastq basecalls_dorado.bam > basecalls_dorado.fq

 chopper -q 9 -i finetuned_basecalls_dorado.fq | gzip > finetuned_basecalls_dorado_filt.fq.gz
 chopper -q 9 -i basecalls_dorado.fq | gzip > basecalls_dorado_filt.fq.gz
 
 NanoPlot -t 30 -o finetuned_basecalls_dorado --fastq finetuned_basecalls_dorado_filt.fq.gz
 NanoPlot -t 30 -o basecalls_dorado --fastq basecalls_dorado_filt.fq.gz

 NanoComp -t 30 -o comparison --fastq basecalls_dorado_filt.fq.gz finetuned_basecalls_dorado_filt.fq.gz --names ONT_std_model finetuned_model
 ```

 ## Utilities scripts
 ``` sh
 #The Training_read_counter.py script is a quick utility tool to search within the subdirectory structure created by ONT_FineTuner.sh to count the number of reads used in the training dataset. The 
 #Its usage is as follows:
 python3 Training_read_counter.py ./subdirectories > reads_used_4_training.txt
 ```
 
 # Citations
 ## Gottschalk et al., 2025. Development of Rosaceae Crop-Specific Nanopore Models for Community Use Through the Genome Database for Rosaceae.
 ## Software used:
 Wouter De Coster, Rosa Rademakers, NanoPack2: population-scale evaluation of long-read sequencing data, Bioinformatics, Volume 39, Issue 5, May 2023, btad311, https://doi.org/10.1093/bioinformatics/btad311
 
 Petr Danecek, James K Bonfield, Jennifer Liddle, John Marshall, Valeriu Ohan, Martin O Pollard, Andrew Whitwham, Thomas Keane, Shane A McCarthy, Robert M Davies, Heng Li, Twelve years of SAMtools and BCFtools, GigaScience, Volume 10, Issue 2, February 2021, giab008, https://doi.org/10.1093/gigascience/giab008
 ## Fuji genome:
 Li, W., Chu, C., Li, H. et al. Near-gapless and haplotype-resolved apple genomes provide insights into the genetic basis of rootstock-induced dwarfing. Nat Genet (2024) https://doi.org/10.1038/s41588-024-01657-2
 ## CTC_merger.py was modified from:
 @rainwala https://github.com/nanoporetech/bonito/issues/386#issuecomment-2100938965
