#!/bin/bash -l

#PBS -j oe
#PBS -l walltime=100:00:00
#PBS -l nodes=1:ppn=8
#PBS -l mem=8gb
##PBS -q highmem

cd $PBS_O_WORKDIR

export cores="$PBS_NP"
module load R/4.1.2 
module load hmmer/3.3
make -e working/summarystats.txt
