#!/bin/bash

bname=`echo $1 | sed s/.vcf.gz//`

#DP for sample is alt depth 
#-GF AD is useless- not set

gatk -R ~/work/tools/bcbio/genomes/Hsapiens/GRCh37/seq/GRCh37.fa -T VariantsToTable -V $1 \
     -F CHROM -F POS -F REF -F ALT  -F DP -GF DP -o $bname.table --allowMissingData 