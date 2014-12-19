#!/bin/bash

#Organize a [START, END] array of genomic ranges for fast range lookups
iquery -aq "remove(KG_VARIANT_RANGE_MASK)" > /dev/null 2>&1
iquery -anq "
store(
 redimension(
  apply(
   KG_VARIANT,
   endpos,
   iif(substr(alt,0,1)<>'<', int64(maxlen_csv(alt)) - 1 + pos , 
    iif( keyed_value(info,  'END',    string(null)) is not null,
     int64(keyed_value(info, 'END',    string(null))),             --not 100% on some of the intricacies here; needs verification
     pos + int64(keyed_value(info, 'SVLEN',  string(null))) )),
   mask, 
   bool(true)
  ),
  <mask:bool>[chrom_id=0:*,1,0, variant_id=0:*,10000,0,pos=0:*,10000000,0, endpos=0:*,10000000,0]
 ),
 KG_VARIANT_RANGE_MASK
)"

#Example: find all variants in a particular range
#EGFR
CHROMOSOME=7
REGION_START=55086678
REGION_END=55279262

time iquery -aq "
cross_join(
 KG_VARIANT,
 cross_join(
  between(KG_VARIANT_RANGE_MASK, null, null, null, $REGION_START,  null, null, $REGION_END, null) as A,
  filter(KG_CHROMOSOME, chrom= '$CHROMOSOME') as B,
  A.chrom_id,
  B.chrom_id
 ),
 KG_VARIANT.variant_id,
 A.variant_id
)"

