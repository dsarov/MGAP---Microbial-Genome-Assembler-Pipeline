#!/bin/bash


seq=$1
ref=$2
baseDir=$3
NCPUS=$4
long=$5


#testing
baseDir=~/bin/mgap/
NCPUS=23
ref=Pa_PA01.fasta



VelvOpt="${baseDir}/bin/velvet_1.2.10/contrib/VelvetOptimiser-2.2.4/VelvetOptimiser.pl"
SHUFFLE="${baseDir}/bin/velvet_1.2.10/contrib/shuffleSequences_fasta/shuffleSequences_fasta.pl"
IMAGE="${baseDir}/bin/IMAGE_version2.4"
GAPFILLER="${baseDir}/bin/GapFiller_v1-10_linux-x86_64/GapFiller.pl"
ABACAS="${baseDir}/bin/abacas.1.3.1.pl"
SSPACE="${baseDir}/bin/SSPACE-BASIC-2.0_linux-x86_64/SSPACE_Basic_v2.0.pl";
CONVERT_PROJECT="${baseDir}/bin/convert_project";
PILON="java -jar ${baseDir}/bin/pilon/pilon-1.24.jar"

export PERL5LIB=/home/dsarovich/.cpan/build/Perl4-CoreLibs-0.004-0/lib/
##starting and ending kmer for velvet optimiser
START_KMER=53	
END_KMER=75

#need to add chmod +x -r ./mgap/

##########################################################################
###                                                                    ###
###                          VELVET + OPTIMISER                        ###  
###                             WITH TRIMMED                           ###
###                                                                    ###
##########################################################################

gunzip -c ${seq}_1.fastq.gz > ${seq}_1.fastq
gunzip -c ${seq}_2.fastq.gz > ${seq}_2.fastq
perl ${SHUFFLE} ${seq}_1.fastq ${seq}_2.fastq ${seq}_merged.fastq

echo -e "now running velvet optimiser with the following parameters\n"
echo -e "starting kmer = $START_KMER\n"
echo -e "ending kmer = $END_KMER\n"
perl ${VelvOpt} -o "-scaffolding yes -min_contig_lgth 1000" -s ${START_KMER} -e ${END_KMER} -f "-shortPaired -fastq.gz ${seq}_merged.fastq" -t $NCPUS
mv auto_data_*/contigs.fa ${seq}_velvet.scaff.fasta

perl $baseDir/bin/joinMultifasta.pl ${ref}.fasta ${ref}ABACAS.fasta
##########################################################################
###                                                                    ###
###                            GAPFILLER                               ###
###                                                                    ###
##########################################################################

#echo -e "${seq}_Gapfiller\tbwa\t${seq}_1.fastq\t${seq}_2.fastq\t500\t0.25\tFR" > Gapfiller.txt
#GapFiller -seed1 ${seq}_1.fastq -seed2 ${seq}_1.fastq --seed-ins 500 -query ${seq}_velvet.scaff.fasta --output-prefix output_test
perl $GAPFILLER -l Gapfiller.txt -s ${seq}_velvet.scaff.fasta -m 20 -o 2 -r 0.7 -n 10 -d 50 -t 10 -T ${NCPUS} -i 3 -b Velv_scaff
mv Velv_scaff/Velv_scaff.gapfilled.final.fa ${seq}_velvet.fasta
rm -rf ${seq}/Velv_scaff/
#TO DO need filecheck here for gapfiller

##########################################################################
###                                                                    ###
###                             ABACAS                                 ###
###                                                                    ###
##########################################################################

if [ "$contig_count" != 1 -a "$ref" != "none" ]; then	
  perl "$ABACAS" -m -b -r ${ref}ABACAS.fasta -q ${seq}_velvet.fasta -p nucmer -o ${seq}mapped
  echo -e "Velvet assembly has been mapped against the reference using ABACAS\n\n"
  cat ${seq}mapped.fasta ${seq}mapped.contigsInbin.fas > ${seq}mapnunmap.fasta
fi

if [ "$contig_count" == 1 -a "$ref" != "none" ]; then
  perl $ABACAS -m -b -r ${ref}ABACAS.fasta -q ${seq}_velvet.fasta -p nucmer -o ${seq}mapped
  echo -e "Velvet assembly has been mapped against the reference using ABACAS\n\n"
  cat ${seq}mapped.fasta ${seq}mapped.contigsInbin.fas > ${seq}mapnunmap.fasta
fi

if [ "$ref" == "none" ]; then
  mv ${seq}/${seq}_velvet.fasta ${seq}/${seq}mapnunmap.fasta
fi


##########################################################################
###                                                                    ###
###                             IMAGE                                  ###
###                                                                    ###
##########################################################################

## include test for PAGIT assembly
if [ ! -s ${seq}/${seq}_IMAGE2_out.fasta -a ! -s ${PBS_O_WORKDIR}/Assemblies/${seq}_final.fasta -a ! -s ${seq}/${seq}_icorn.fasta ]; then
   perl $IMAGE/image.pl -scaffolds ${seq}mapnunmap.fasta -prefix ${seq} -iteration 1 -all_iteration 3 -dir_prefix ite -kmer 81
   perl $IMAGE/restartIMAGE.pl ite3 71 3 partitioned
   perl $IMAGE/restartIMAGE.pl ite6 61 3 partitioned
   perl $IMAGE/restartIMAGE.pl ite9 51 3 partitioned
   perl $IMAGE/restartIMAGE.pl ite12 41 3 partitioned
   perl $IMAGE/restartIMAGE.pl ite15 31 3 partitioned
   perl $IMAGE/restartIMAGE.pl ite18 21 3 partitioned
   mv ite21/new.fa ${seq}_IMAGE2_out.fasta

  perl $IMAGE/image_run_summary.pl ite > IMAGE2.summary

 rm -r ite*
 rm partitioned_1.fastq
 rm partitioned_2.fastq
fi  

##########################################################################
###                                                                    ###
###                             SSPACE                                 ###
###                                                                    ###
##########################################################################

  #TODO need to write SSPACE version check for different library file. The below is for SSPACEv3.0
  
  #echo -e "${seq}SSPACE\tbowtie\t${seq}_1.fastq\t${seq}_2.fastq\t200\t0.25\tFR" > ${seq}/library.txt
  
  #For SSPACE v2.0 basic
  echo -e "${seq}SSPACE\t${seq}_1.fastq\t${seq}_2.fastq\t200\t0.25\tFR" > library.txt
  
  perl $SSPACE -l library.txt -s ${seq}_IMAGE2_out.fasta
  mv standard_output.final.scaffolds.fasta ${seq}SSPACE.fasta
  rm -r pairinfo
  rm -r intermediate_results
  rm -r bowtieoutput
  rm -r reads
  rm standard_output.final.evidence
  rm standard_output.logfile.txt
  #mv ${seq}/standard_output.summary.txt ${seq}/SSPACE.summary.txt ##standard_output.summaryfile.txt is the correct name for this output


### SSPACE test ############
## This will skip the next step if SSPACE doesn't find anything to scaffold in your assembly, which caused a gapfiller crash



if [ -s standard_output.summaryfile.txt ]; then
  SSPACE_test=`grep 'Total number of N' standard_output.summaryfile.txt |tail -n1 |awk '{print $6}'`
  if [ "$SSPACE_test" == 0 ]; then
   cp ${seq}SSPACE.fasta ${seq}_gap2.fasta
  fi
fi


##########################################################################
###                                                                    ###
###                            GAPFILLER 2                             ###
###  This step is skipped is SSPACE doesn't find anything to scaffold  ###
###                                                                    ###
##########################################################################
if [ ! -s ${seq}_gap2.fasta ]; then
  perl $GAPFILLER -l Gapfiller.txt -s ${seq}SSPACE.fasta -m 20 -o 2 -r 0.7 -n 10 -d 50 -t 10 -T ${NCPUS} -i 3 -b SSPACE_scaff
    mv SSPACE_scaff/SSPACE_scaff.gapfilled.final.fa ${seq}_gap2.fasta
	rm -r SSPACE_scaff/
fi

##########################################################################
###                                                                    ###
###                Remove contigs <1kb and image cleanup               ###
###                                                                    ###
##########################################################################
if [ "$long" == "no" ]; then
  $CONVERT_PROJECT -f fasta -t fasta -x 1000 -R Contig ${seq}_gap2.fasta ${seq}_pilon
  echo -e "Project has been filtered to remove contigs less than 1kb in size \n" 
else 
  mv ${seq}_gap2.fasta ${seq}_pilon.fasta
  echo -e "Project includes all contigs including <1kb in size\n" 
fi

##########################################################################
###                                                                    ###
###                                PILON                               ###
###                                                                    ###
##########################################################################

#create bam file before running pilon
if [ ! -s ${seq}_pilon.fasta.bwt ]; then
  bwa index ${seq}_pilon.fasta
  else
  echo "Found ref index for Pilon"
fi
if [ ! -s ${seq}.sam ]; then
    bwa mem -R '@RG\tID:Assembly\tSM:${seq}\tPL:ILLUMINA' -a -t $NCPUS ${seq}_pilon.fasta ${seq}_1.fastq ${seq}_2.fastq > ${seq}.sam
  else
    echo "Found bam file for pilon"  
fi
if [ ! -s ${seq}.bam ]; then
  	    samtools view -h -b -@ 1 -q 1 -o ${seq}.bam.tmp ${seq}.sam && samtools sort -@ 1 -o ${seq}.bam ${seq}.bam.tmp
		rm ${seq}.bam.tmp ${seq}.sam
fi
if [ ! -s ${seq}.bam.bai ]; then
    samtools index ${seq}.bam
fi

if [ ! -s pilon.fasta ]; then
   java -jar ${PILON} --genome ${seq}_pilon.fasta --frags ${seq}.bam
   mv pilon.fasta ${seq}_final.fasta
fi 

exit 0
