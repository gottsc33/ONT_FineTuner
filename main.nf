nextflow.enable.dsl = 2

/*
 * ONT FineTuner Nextflow implementation
 *
 * Workflow:
 *   reference FASTA
 *       |
 *       v
 *   minimap2 index
 *       |
 *       v
 *   Bonito basecaller --save-ctc  [one task per samplesheet row]
 *       |
 *       v
 *   CTC_merger.py
 *       |
 *       v
 *   bonito train
 *       |
 *       v
 *   bonito export
 */

params.samplesheet       = null
params.reference         = null
params.outdir            = 'results'

params.pretrained_model  = 'dna_r10.4.1_e8.2_400bps_hac@v5.0.0'
params.epochs            = 5
params.learning_rate     = '5e-4'
params.batch_size        = 96

/*
 * Additional arguments can be supplied without editing the workflow.
 *
 * Examples:
 *   --basecaller_args '--chunksize 10000'
 *   --train_args '--device cuda'
 *   --export_args '--format dorado'
 */
params.basecaller_args   = ''
params.train_args        = ''
params.export_args       = ''

/*
 * Bonito 0.8.x commonly accepts:
 *
 *     bonito export MODEL --output OUTPUT
 *
 * If a specific Bonito release uses another syntax, set:
 *
 *     --export_command 'bonito export {model} {output}'
 *
 * The placeholders {model} and {output} are replaced below.
 */
params.export_command    = 'bonito export {model} --output {output}'


process INDEX_REFERENCE {

    tag "${reference.simpleName}"

    label 'cpu_medium'

    publishDir(
        "${params.outdir}/reference",
        mode: 'copy',
        overwrite: true
    )

    input:
    path reference

    output:
    path 'reference.mmi', emit: index

    script:
    """
    minimap2 -d reference.mmi '${reference}'
    """
}


process GENERATE_CTC {

    tag "${sample_id}"

    label 'gpu'

    publishDir(
        "${params.outdir}/basecalling/${sample_id}",
        mode: 'copy',
        pattern: "${sample_id}.sam",
        overwrite: true
    )

    input:
    tuple val(sample_id), path(reads), path(reference_index)

    output:
    tuple val(sample_id),
          path("ctc_${sample_id}"),
          emit: ctc

    tuple val(sample_id),
          path("${sample_id}.sam"),
          emit: alignments

    script:
    /*
     * Running inside the CTC directory ensures that the NumPy arrays
     * created by --save-ctc are isolated for each sample.
     */
    """
    mkdir -p 'ctc_${sample_id}'

    cd 'ctc_${sample_id}'

    bonito basecaller \
        '${params.pretrained_model}' \
        --reference '../${reference_index}' \
        --save-ctc \
        ${params.basecaller_args} \
        '../${reads}' \
        > '../${sample_id}.sam'

    test -s chunks.npy
    test -s references.npy
    test -s reference_lengths.npy
    """
}


process MERGE_CTC {

    tag 'merge-ctc-training-data'

    label 'cpu_highmem'

    publishDir(
        "${params.outdir}/training_data",
        mode: 'copy',
        overwrite: true
    )

    input:
    path ctc_directories
    path merger_script

    output:
    path 'merged_ctc', emit: merged

    script:
    /*
     * Nextflow stages each collected CTC directory into this task.
     * CTC_merger.py is deliberately executed here, after every
     * Bonito --save-ctc task and before model training.
     */
    def inputArguments = ctc_directories
        .collect { "'${it}'" }
        .join(' ')

    """
    python '${merger_script}' \
        --input ${inputArguments} \
        --output merged_ctc

    test -s merged_ctc/chunks.npy
    test -s merged_ctc/references.npy
    test -s merged_ctc/reference_lengths.npy
    """
}


process TRAIN_MODEL {

    tag "${params.pretrained_model}"

    label 'gpu'

    input:
    path training_data

    output:
    path 'fine_tuned_model', emit: model

    script:
    """
    bonito train \
        --epochs '${params.epochs}' \
        --lr '${params.learning_rate}' \
        --batch '${params.batch_size}' \
        --pretrained '${params.pretrained_model}' \
        --directory '${training_data}' \
        ${params.train_args} \
        fine_tuned_model
    """
}


process EXPORT_MODEL {

    tag 'export-fine-tuned-model'

    label 'cpu_medium'

    publishDir(
        "${params.outdir}/model",
        mode: 'copy',
        overwrite: true
    )

    input:
    path trained_model

    output:
    path 'exported_model', emit: exported

    script:
    def command = params.export_command
        .replace('{model}', "'${trained_model}'")
        .replace('{output}', "'exported_model'")

    """
    mkdir -p exported_model

    ${command} ${params.export_args}

    # Preserve training artifacts alongside the exported representation.
    cp -r '${trained_model}' exported_model/bonito_training_model
    """
}


workflow {

    if (!params.samplesheet) {
        error """
        Missing --samplesheet.

        Example:
          --samplesheet samplesheet.csv
        """.stripIndent()
    }

    if (!params.reference) {
        error """
        Missing --reference.

        Example:
          --reference reference.fasta
        """.stripIndent()
    }

    /*
     * Expected samplesheet columns:
     *
     * sample_id,reads
     * apple_01,/data/apple_01/pod5
     * apple_02,/data/apple_02/pod5
     *
     * "reads" may be a directory containing POD5/FAST5 files or another
     * input path accepted by the installed Bonito release.
     */
    samples_ch = Channel
        .fromPath(params.samplesheet, checkIfExists: true)
        .splitCsv(header: true)
        .map { row ->
            if (!row.sample_id) {
                error "A samplesheet row is missing sample_id"
            }

            if (!row.reads) {
                error "Sample '${row.sample_id}' is missing its reads path"
            }

            tuple(
                row.sample_id.toString(),
                file(row.reads.toString(), checkIfExists: true)
            )
        }

    reference_ch = Channel.fromPath(
        params.reference,
        checkIfExists: true
    )

    merger_ch = Channel.fromPath(
        "${projectDir}/scripts/CTC_merger.py",
        checkIfExists: true
    )

    /*
     * 1. Build the Minimap2 reference index.
     */
    INDEX_REFERENCE(reference_ch)

    /*
     * 2. Pair every sample with the single reference index and generate
     *    its CTC training arrays.
     */
    basecaller_inputs_ch = samples_ch.combine(INDEX_REFERENCE.out.index)

    GENERATE_CTC(basecaller_inputs_ch)

    /*
     * 3. Wait for all CTC-producing jobs, collect their directories, and
     *    merge them using CTC_merger.py.
     */
    ctc_directories_ch = GENERATE_CTC.out.ctc
        .map { sample_id, ctc_directory -> ctc_directory }
        .collect()

    MERGE_CTC(ctc_directories_ch, merger_ch)

    /*
     * 4. Fine-tune the pretrained model using the merged CTC arrays.
     */
    TRAIN_MODEL(MERGE_CTC.out.merged)

    /*
     * 5. Export the resulting model.
     */
    EXPORT_MODEL(TRAIN_MODEL.out.model)
}