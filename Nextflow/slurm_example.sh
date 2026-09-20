process {
    executor = 'slurm'

    withLabel: gpu {
        cpus = 8
        memory = '64 GB'
        time = '7d'
        accelerator = 1

        // Replace with site-specific Slurm options.
        clusterOptions = '--partition=gpu --gres=gpu:1'
    }

    withLabel: cpu_medium {
        cpus = 4
        memory = '16 GB'
        time = '8h'
        clusterOptions = '--partition=compute'
    }

    withLabel: cpu_highmem {
        cpus = 4
        memory = '64 GB'
        time = '24h'
        clusterOptions = '--partition=compute'
    }
}