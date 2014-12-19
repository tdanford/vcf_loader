#!/bin/bash

file=$1
SAMPLE=`basename $file | sed -e "s;\..*$;;g"`

echo "loading $file with sample $SAMPLE"

echo "drop array gvcf_tmp;" | iquery

echo "loading data..."

MAX_CHROM=`iquery -ocsv -aq "aggregate(gvcf_chrom, count(*));" | grep -v count`
MAX_SAMPLE=`iquery -ocsv -aq "aggregate(gvcf_sample, count(*));" | grep -v count`

echo "MAX_CHROM: $MAX_CHROM"
echo "MAX_SAMPLE: $MAX_SAMPLE" 

iquery -n -aq "store(parse(split('$file'), 'num_attributes=10'), gvcf_tmp)"

sed -e "s;%SAMPLE%;$SAMPLE;g" convert.iquery | iquery -n -a 
sed -e "s;%MAX_CHROM%;$MAX_CHROM;g" update_chroms.iquery | iquery -n -a 
sed -e "s;%MAX_SAMPLE%;$MAX_SAMPLE;g" update_samples.iquery | iquery -n -a 

iquery -n -a < update_sample_chrom_attributes.iquery
