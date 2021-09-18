#!/usr/bin/env nextflow

/*
 *
 *  Pipeline            MGAP
 *  Version             v2.0
 *  Description         Antimicrobial resistance detection and prediction from WGS
 *  Authors             Derek Sarovich, Erin Price, Danielle Madden, Eike Steinig
 *
 */

log.info """
================================================================================
                                    NF-MGAP
                                     v2.0
================================================================================

Optional Parameters:

    --fastq      Input PE read file wildcard (default: *_{1,2}.fastq.gz)

                 Currently this is set to $params.fastq

    --ref        Reference file used for reference assisted assembly using
                 ABACAS. For best results please set this to a closely related
                 reference (i.e. same species and sequence type is ideal)

                 Currently ref is set to $params.reference

    --executor   Change this flag for running in a HPC scheduler environment.
                 Default behavior is to run without a scheduler but a
                 wide range of schedulers are supported with nextflow.
                 Some of the supported schedulers include sge, pbs, pbspro,
                 slurm, lsf, moab, nqsii. For a full list please visit the
                 nextflow documentation

                 Currently executor is set to $params.executor



If you want to make changes to the default `nextflow.config` file
clone the workflow into a local directory and change parameters
in `nextflow.config`:

    nextflow clone dsarov/mgap outdir/

Update to the local cache of this workflow:

    nextflow pull dsarov/mgap

==================================================================
==================================================================
"""

fastq = Channel
  .fromFilePairs("${params.fastq}", flat: true)
	.ifEmpty { exit 1, """ Input read files could not be found.
Have you included the read files in the current directory and do they have the correct naming?
With the parameters specified, MGAP is looking for reads named ${params.fastq}.
To fix this error either rename your reads to match this formatting or specify the desired format
when initializing MGAP e.g. --fastq "*_{1,2}_sequence.fastq.gz"

"""
}

reference_file = file(params.ref)
if( !reference_file.exists() ) {
  exit 1, """
ARDaP can't find the reference file.
It is currently looking for this file --> ${params.ref}
If this file doesn't exist, please download and copy to the analysis dirrectory
"""
}

/*
======================================================================
      Part 1: create reference indices, dict files and bed files
======================================================================
*/

process IndexReference {

        label "index"

        input:
        file reference from reference_file

        output:
        file "ref.*" into ref_index_ch
        file "${reference}.fai" into ref_fai_ch1
        file "${reference.baseName}.dict" into ref_dict_ch1
        file "${reference}.bed" into refcov_ch

        script:
        if (ref!="none")
        """
        contig_count=`grep -c '>' ${ref}.fasta`
        echo -e "Joining contigs for ABACAS\n"
        if [ $contig_count == 1 ]; then
          mv ${ref}.fasta ${ref}ABACAS.fasta
        else
          perl $baseDir/bin/joinMultifasta.pl ${ref}.fasta ${ref}ABACAS.fasta"
        fi
        """
}



/*
=======================================================================
   Part 2A: Trim reads with light quality filter and remove adapters
=======================================================================
*/

process Trimmomatic {

    label "trimmomatic"
    tag {"$id"}

    input:
    set id, file(forward), file(reverse) from fastq

    output:
    set id, "${id}_1.fq.gz", "${id}_2.fq.gz" into downsample

    """
    trimmomatic PE -threads $task.cpus ${forward} ${reverse} \
    ${id}_1.fq.gz ${id}_1_u.fq.gz ${id}_2.fq.gz ${id}_2_u.fq.gz \
    ILLUMINACLIP:${baseDir}/resources/trimmomatic/all_adapters.fa:2:30:10: \
    LEADING:10 TRAILING:10 SLIDINGWINDOW:4:15 MINLEN:36
    rm ${id}_1_u.fq.gz ${id}_2_u.fq.gz
    """
}

/*
=======================================================================
   Part 2A: Trim reads with light quality filter and remove adapters
=======================================================================
*/

process Assembly {

  label "Assembly"
  tag { "$id" }
  publishDir "./Outputs/", mode: 'copy', pattern: "*final.fasta", overwrite: true


      input:
      file reference from reference_file
      set id, "${id}_1.fq.gz", "${id}_2.fq.gz" from downsample

      output:
      set id, file("${id}_final.fasta")


      script:
      """
      bash assemble.sh ${id} ${reference} ${baseDir}

      """

}

workflow.onComplete {
	println ( workflow.success ? "\nDone! Result files are in --> ./Outputs\n \
  Antibiotic resistance reports are in --> ./Outputs/AbR_reports\n \
  If further analysis is required, bam alignments are in --> ./Outputs/bams\n \
  Phylogenetic tree and annotated merged variants are in --> ./Outputs/Phylogeny_and_annotation\n \
  Individual variant files are in --> ./Outputs/Variants/VCFs\n" \
  : "Oops .. something went wrong" )
}
