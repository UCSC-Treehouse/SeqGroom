#!/bin/bash

# Read in sequence data file names
input=$file1
input2=$file2

# Get sequence data ID
baseFileIDName=${input/[_,.][R,r][1,2][_,.]f*q*}
log=${baseFileIDName}.SeqGroom.log

# Make temporary output directory
mkdir $input'_'output

set -eu -o pipefail

# If input is in bam or cram file, convert to fastq
if  (! `echo $input | grep -q "fastq\|fq"`); then
  echo `date` "Samtools fastq conversion of $input" >> $log
  samtools fastq -1 ./$input'_'output/${input}.R1.fq -2 ./$input'_'output/${input}.R2.fq $input
# If inputs are fastq files
else
  for i in $input $input2; do
    # If fastq file is zipped
    if $(echo $i | grep -q "q.gz"); then
      echo `date` "Unzipping fastq file: $i" >> $log
      gzip -d --stdout $i > ./$input'_'output/${i/[_,.]f*q*}.fq
    # If fastq file is not zipped
    else
      cp $i ./$input'_'output/${i/[_,.]f*q*}.fq
    fi;
  done;
fi

# If paired-end reads, reorder fastq files by read name
a=./$input'_'output/${baseFileIDName}[_,.][R,r]1.fq
b=./$input'_'output/${baseFileIDName}[_,.][R,r]2.fq
# Get separator in read id
separator=$(head -n1 $a | python -c "import sys; import re; print(re.match('\S+(\s*)', sys.stdin.read().rstrip()).groups()[0])")
if [ -z "$separator" ]; then separator="None"; fi
size=$(wc -c < $b)
# If paired-end reads
if [ $size -ge 10 ]; then
  echo `date` "Reordering paired-end reads in $a and $b" >> $log
  python /root/scripts/fastqCombinePairedEnd_v2.py $a $b $separator
# If single-end reads
else
  echo `date` "${baseFileIDName} is single-end reads" >> $log
  mv ./$input'_'output/${baseFileIDName}[_,.][R,r]1.fq ./$input'_'output/${baseFileIDName}[_,.][R,r]1.fq_pairs_R1.fastq
fi

# Remove duplicate read ids
dedup=()
echo `date` "Removing duplicate read ids in ${baseFileIDName}" >> $log
for j in {1..2}; do
  cat ./$input'_'output/${baseFileIDName}[_,.][R,r]${j}.fq_pairs_R${j}.fastq | \
  perl /root/scripts/mergelines.pl | \
  sort -V -k1,1 -t " "  --stable --parallel=10 -T ./ -S 10G | uniq | \
  perl /root/scripts/splitlines.pl > \
  $(echo ./$input'_'output/${baseFileIDName}[_,.][R,r]${j}.fq_pairs_R${j}.fastq | sed s'/.fq_pairs_R'$j'//')
  dedup+=$(echo ./$input'_'output/${baseFileIDName}[_,.][R,r]${j}.fq_pairs_R${j}.fastq | sed s'/.fq_pairs_R'$j'//')
  dedup+=" ";
done

# Compress groomed fastq files
for uncompressedFq in ${dedup[*]}; do
  echo `date` "Compressing file $uncompressedFq" >> $log;
  pigz $uncompressedFq;
done

# Rename groomed fastq files
for compressedFq in ./$input'_'output/*fastq.gz;do
  mv $compressedFq $(echo ${compressedFq} |sed -r 's/([R,r][1-2].fastq.gz)$/SeqGroomed\.\1/'| sed 's/\.[bcrs]*am\././')
done

echo `date` "${baseFileIDName} - conversion & grooming done using jackieroger/seqgroom" >> $log;

# Move groomed fastq files to work directory
array=()
for gz in ./$input'_'output/*.gz; do
  array+=$(echo $gz | sed s'/'${input}_output'/data/' | sed s'/.//')
  array+=" "
  mv $gz ./;
done
array+="/data/$log"

# Revove temporary output directory
rm -r $input'_'output

# Fix ownership of output files
finish() {
    uid=$(stat -c '%u:%g' /data)
    chown $uid $(printf '%s\n' "${array[@]}")
}
trap finish EXIT
