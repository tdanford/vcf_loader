#!/bin/bash

iquery -ocsv -aq " project( apply( cross_join( project( apply( filter( cross_join(gvcf, gvcf_chrom, gvcf.chrom_id, gvcf_chrom.chrom_id), (name='$1') and (end > $2) and (start <= $3)), chrom_name, name, start, start, end, end), ref, alts, chrom_name, gt, pl, start, end) as A, gvcf_sample, A.sample_id, gvcf_sample.sample_id), sample_name, name), chrom_name, start, end, sample_name, ref, alts, gt, pl );" 
