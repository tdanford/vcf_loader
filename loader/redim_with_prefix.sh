#!/bin/bash

MYDIR=`dirname $0`
pushd $MYDIR
MYDIR=`pwd`

if [ $# -ne 1 ]; then
    echo "Please provide the Prefix! KTHXBYE"
    exit 1
fi

PREFIX=$1

iquery -anq "remove(KG_VAR_GUIDE_BUF)"    > /dev/null 2>&1
iquery -anq "remove(KG_SAMPLE_GUIDE_BUF)" > /dev/null 2>&1
iquery -anq "remove(KG_SIG_BUF)"          > /dev/null 2>&1

set -e 
set -x

NUM_SAMPLES=`iquery -ocsv -aq "op_count(${PREFIX}_KG_SAMPLE_BUF)" | tail -n 1`
echo File has $NUM_SAMPLES samples
NUM_VARIANTS=`iquery -ocsv -aq "op_count(${PREFIX}_KG_VAR_BUF)" | tail -n 1`
echo File has $NUM_VARIANTS variants
NUM_GT=`iquery -ocsv -aq "op_count(${PREFIX}_KG_GT_BUF)" | tail -n 1`

if [ "$((NUM_SAMPLES * NUM_VARIANTS))" != "$NUM_GT" ];
then 
  echo "Num gt: $NUM_GT does not match; exiting"
  exit 1
fi

NUM_EXISTING_SAMPLES=`iquery -ocsv -aq "op_count(KG_SAMPLE)" | tail -n 1`
time iquery -naq "
insert(
 redimension(
  apply(
   uniq(
    sort(
     project(
      filter(
       index_lookup(${PREFIX}_KG_SAMPLE_BUF, KG_SAMPLE, ${PREFIX}_KG_SAMPLE_BUF.sample_name, sample_id), 
       sample_id is null
      ), 
      sample_name
     )
    )
   ), 
   sample_id, i+$NUM_EXISTING_SAMPLES
  ),
  KG_SAMPLE
 ),
 KG_SAMPLE
)"

NUM_EXISTING_CHROMOSOMES=`iquery -ocsv -aq "op_count(KG_CHROMOSOME)" | tail -n 1`
time iquery -naq "
insert(
 redimension(
  apply(
   uniq(
    sort(
     project(
      filter(
       index_lookup(${PREFIX}_KG_VAR_BUF, KG_CHROMOSOME, ${PREFIX}_KG_VAR_BUF.chrom, existing_chrom_id),
       existing_chrom_id is null
      ),
      chrom
     )
    )
   ),
   chrom_id, i + $NUM_EXISTING_CHROMOSOMES
  ),
  KG_CHROMOSOME
 ),
 KG_CHROMOSOME
)"

iquery -anq "create temp array KG_SIG_BUF <signature: string> [variant_id =0:*,1000000,0]"
iquery -anq "insert(redimension(KG_VARIANT, KG_SIG_BUF), KG_SIG_BUF)"
NUM_EXISTING_SIGNATURES=`iquery -ocsv -aq "op_count(KG_SIG_BUF)" | tail -n 1`
time iquery -naq "
insert(
 redimension(
  apply(
   uniq(
    sort(
     project(
      filter(
       index_lookup(
        apply(
         ${PREFIX}_KG_VAR_BUF, 
         signature,
         chrom + ':' + string(pos) + ' ' + ref + '>' + alt
        ) as X,
        KG_SIG_BUF, X.signature, existing_signature_id),
       existing_signature_id is null
      ),
      signature
     )
    )
   ),
   variant_id, i + $NUM_EXISTING_SIGNATURES
  ),
  KG_SIG_BUF
 ),
 KG_SIG_BUF
)"

iquery -anq "create temp array KG_VAR_GUIDE_BUF <nvid:int64> [variant_id=0:*,1000000,0]"
time iquery -anq "
insert(
 redimension(
  index_lookup(
   apply(
     ${PREFIX}_KG_VAR_BUF, 
     signature,
     chrom + ':' + string(pos) + ' ' + ref + '>' + alt
   ) as X,
   KG_SIG_BUF,
   X.signature,
   variant_id
  ),
  KG_VAR_GUIDE_BUF
 ),
 KG_VAR_GUIDE_BUF
)"

time iquery -anq "
insert(
 redimension(
  index_lookup(
   index_lookup(
    apply(
      ${PREFIX}_KG_VAR_BUF, 
      signature,
      chrom + ':' + string(pos) + ' ' + ref + '>' + alt
    ) as X,
    KG_VAR_GUIDE_BUF,
    X.nvid,
    variant_id
   ),
   KG_CHROMOSOME,
   X.chrom,
   chrom_id
  ),
  KG_VARIANT
 ),
 KG_VARIANT
)"

iquery -anq "create temp array KG_SAMPLE_GUIDE_BUF <nsid:int64> [sample_id=0:*,10000000,0]"
time iquery -anq "
insert(
 redimension(
  index_lookup(
   ${PREFIX}_KG_SAMPLE_BUF as X,
   KG_SAMPLE,
   X.sample_name,
   sample_id
  ),
  KG_SAMPLE_GUIDE_BUF
 ),
 KG_SAMPLE_GUIDE_BUF
)"

time iquery -anq "
insert(
 redimension(
  index_lookup(
   index_lookup(
    ${PREFIX}_KG_GT_BUF,
    KG_SAMPLE_GUIDE_BUF,
    ${PREFIX}_KG_GT_BUF.nsid,
    sample_id
   ),
   KG_VAR_GUIDE_BUF,
   ${PREFIX}_KG_GT_BUF.nvid,
   variant_id
  ),
  KG_GENOTYPE
 ),
 KG_GENOTYPE
)"

time iquery -anq "
insert(
 redimension(
  index_lookup(
   index_lookup(
    apply(
     ${PREFIX}_KG_VAR_BUF,
     mask,
     bool(true)
    ),
    KG_VAR_GUIDE_BUF, 
    ${PREFIX}_KG_VAR_BUF.nvid,
    variant_id
   ),
   KG_CHROMOSOME,
   ${PREFIX}_KG_VAR_BUF.chrom,
   chrom_id
  ),
  KG_VARIANT_POSITION_MASK
 ),
 KG_VARIANT_POSITION_MASK
)"

delete_old_versions()
{
  ARRAY_NAME=$1
  MAX_VERSION=`iquery -ocsv -aq "aggregate(versions($ARRAY_NAME), max(version_id) as max_version)" | tail -n 1`
  iquery -anq "remove_versions($ARRAY_NAME, $MAX_VERSION)"
}

delete_old_versions "KG_CHROMOSOME" 
delete_old_versions "KG_GENOTYPE"
delete_old_versions "KG_SAMPLE"
delete_old_versions "KG_VARIANT"
delete_old_versions "KG_VARIANT_POSITION_MASK"

iquery -aq "op_count(KG_CHROMOSOME)"
iquery -aq "op_count(KG_GENOTYPE)"
iquery -aq "op_count(KG_SAMPLE)"
iquery -aq "op_count(KG_VARIANT)"
iquery -aq "op_count(KG_VARIANT_POSITION_MASK)"


