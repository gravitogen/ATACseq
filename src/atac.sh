#!/bin/bash

if [ $# -ne 4 ]
then
    echo "Usage: $0 <read1.fq.gz> <read2.fq.gz> <genome.fa> <outprefix>"
    exit -1
fi

SCRIPT=$(readlink -f "$0")
BASEDIR=$(dirname "$SCRIPT")

THREADS=4

FQ1=${1}
FQ2=${2}
HG=${3}
OUTP=${4}

# Programs
PICARD=${BASEDIR}/picard/build/libs/picard.jar
SAM=${BASEDIR}/samtools/samtools
BCF=${BASEDIR}/bcftools/bcftools
FASTQC=${BASEDIR}/FastQC/fastqc
BOWTIE=${BASEDIR}/bowtie/bowtie2
SKEWER=${BASEDIR}/skewer/skewer

# Tmp directory
DSTR=$(date +'%a_%y%m%d_%H%M')
export TMP=/tmp/tmp_atac_${DSTR}
mkdir -p ${TMP}
JAVAOPT="-Xms4g -Xmx32g -XX:ParallelGCThreads=${THREADS} -Djava.io.tmpdir=${TMP}"
PICARDOPT="MAX_RECORDS_IN_RAM=5000000 TMP_DIR=${TMP} VALIDATION_STRINGENCY=SILENT"

# Generate IDs
FQ1ID=`echo ${OUTP} | sed 's/$/.fq1/'`
FQ2ID=`echo ${OUTP} | sed 's/$/.fq2/'`
BAMID=`echo ${OUTP} | sed 's/$/.align/'`

# Fastqc
mkdir -p ${OUTP}/prefastqc/ && ${FASTQC} -o ${OUTP}/prefastqc/ ${FQ1} && ${FASTQC} -o ${OUTP}/prefastqc/ ${FQ2}

# Adapter trimming
${SKEWER} -z -o ${OUTP}/${OUTP} -x CTGTCTCTTATACACATCTCCGAGCCCACGAGACNNNNNNNNATCTCGTATGCCGTCTTCTGCTTG -y CTGTCTCTTATACACATCTGACGCTGCCGACGANNNNNNNNGTGTAGATCTCGGTGGTCGCCGTATCATT -m pe ${FQ1} ${FQ1}

# Fastqc
mkdir -p ${OUTP}/postfastqc/ && ${FASTQC} -o ${OUTP}/postfastqc/ ${OUTP}/${OUTP}-trimmed-pair1.fastq.gz && ${FASTQC} -o ${OUTP}/postfastqc/ ${OUTP}/${OUTP}-trimmed-pair2.fastq.gz

# Bowtie
${BOWTIE} --threads ${THREADS} --very-sensitive --maxins 2000  --no-discordant --no-mixed -x ${HG} -1 ${OUTP}/${OUTP}-trimmed-pair1.fastq.gz -2 ${OUTP}/${OUTP}-trimmed-pair2.fastq.gz | samtools view -bT ${HG} - > ${OUTP}/${BAMID}.bam

# Removed trimmed fastq
rm ${OUTP}/${OUTP}-trimmed-pair1.fastq.gz ${OUTP}/${OUTP}-trimmed-pair2.fastq.gz

# Sort & Index
${SAM} sort -o ${OUTP}/${BAMID}.srt.bam ${OUTP}/${BAMID}.bam && rm ${OUTP}/${BAMID}.bam && ${SAM} index ${OUTP}/${BAMID}.srt.bam

# Clean .bam file
java ${JAVAOPT} -jar ${PICARD} CleanSam I=${OUTP}/${BAMID}.srt.bam O=${OUTP}/${BAMID}.srt.clean.bam ${PICARDOPT} && rm ${OUTP}/${BAMID}.srt.bam*

# Mark duplicates
java ${JAVAOPT} -jar ${PICARD} MarkDuplicates I=${OUTP}/${BAMID}.srt.clean.bam O=${OUTP}/${BAMID}.srt.clean.rmdup.bam M=${OUTP}/${OUTP}.markdups.log PG=null MAX_FILE_HANDLES_FOR_READ_ENDS_MAP=1000 ${PICARDOPT} && rm ${OUTP}/${BAMID}.srt.clean.bam* && ${SAM} index ${OUTP}/${BAMID}.srt.clean.rmdup.bam

