#!/bin/bash

#RIND is an extra string tacked on to the end of object and file names to avoid collisions
#Useful when running several loads in parallel
#RIND=$$ #PID is a good option
RIND="1"
LINES_PER_CHUNK=500
NUM_PRESAMPLE_ATTRIBUTES=9 #CHROM, POS, ID, REF, ALT, QUAL, FILTER, INFO, FORMAT
NUM_SAMPLES=2504
NUM_ATTRIBUTES=$((NUM_PRESAMPLE_ATTRIBUTES + NUM_SAMPLES))
CHUNK_SIZE_SAMPLE=100
#For Debug output
DATESTRING="+%Y_%m_%d_%H_%M_%S_%N"

function log()
{
  echo "`date $DATESTRING` > $1"
}

function error()
{
  echo "`date $DATESTRING` !!! ERROR !!! $1" >&2
  echo "KTHXBYE"
  exit 1
}

function delete_old_versions()
{
  ARRAY_NAME=$1
  MAX_VERSION=`iquery -ocsv -aq "aggregate(versions($ARRAY_NAME), max(version_id) as max_version)" | tail -n 1`
  iquery -anq "remove_versions($ARRAY_NAME, $MAX_VERSION)" > /dev/null
}

#set -x
if [ $# -ne 1 ]; then
    error "Please provide the input file!"
fi
FILE=$1
filedir=`dirname $FILE`
pushd $filedir >> /dev/null
FILE="`pwd`/`basename $FILE`"
if [ ! -f $FILE ] ; then
 error "Cannot find file $FILE!"
fi
log "Loading $FILE"
popd > /dev/null
mydir=`dirname $0`
pushd $mydir >> /dev/null
mydir=`pwd`
gzip_status_command='file '$FILE' | grep gzip | wc -l'
gzip_status=`eval $gzip_status_command`
if [ $? -ne 0 ] ; then
 error "Error code running '$gzip_status_command'"
fi
gzipped=0
if [ $gzip_status -eq 0 ]; then
 log "File does not appear to be gzipped, loading direct"
elif [ $gzip_status -eq 1 ]; then
 log "File appears to be gzipped, loading through zcat"
 gzipped=1
else
 error "Unexpected result running '$gzip_status_command'; expected 1 or 0"
fi
iquery -anq "remove(KG_LOAD_BUF_$RIND)" > /dev/null 2>&1
iquery -anq "remove(KG_LOAD_SAMPLE_LINE_LOCATION_$RIND)" > /dev/null 2>&1
iquery -anq "remove(KG_LOAD_SAMPLES_$RIND)" > /dev/null 2>&1
iquery -anq "remove(KG_LOAD_VARIANT_BUF_$RIND)" > /dev/null 2>&1
fifo_path=$mydir/load_$RIND.fifo
#Entering the clean zone:
set -e
rm -rf $fifo_path
mkfifo $fifo_path
if [ $gzipped -eq 1 ]; then
 zcat $FILE > $fifo_path &
else 
 cat  $FILE > $fifo_path &
fi
#Load the file
iquery -anq "create array KG_LOAD_BUF_$RIND <a:string null> [source_instance_id=0:*,1,0,chunk_no=0:*,1,0,line_no=0:*,$LINES_PER_CHUNK,0,attribute_no=0:$NUM_ATTRIBUTES,$((NUM_ATTRIBUTES+1)),0]" > /dev/null
iquery -anq "store(parse(split('$fifo_path', 'source_instance_id=0', 'lines_per_chunk=$LINES_PER_CHUNK'), 'num_attributes=$NUM_ATTRIBUTES', 'chunk_size=$LINES_PER_CHUNK', 'split_on_dimension=1'), KG_LOAD_BUF_$RIND)" > /dev/null
rm -rf $fifo_path
log "File ingested"
iquery -anq "create temp array KG_LOAD_SAMPLE_LINE_LOCATION_$RIND <source_instance_id:int64,chunk_no:int64,line_no:int64> [i=0:*,1,0]" > /dev/null
iquery -anq "
store(
 project(
  unpack(
   filter(
    slice(KG_LOAD_BUF_1, attribute_no, 0), 
    substr(a, 0, 1) = '#' and substr(a,1,1) <> '#'
   ), 
   i, 1
  ), 
  source_instance_id, chunk_no, line_no
 ),
 KG_LOAD_SAMPLE_LINE_LOCATION_$RIND
)" > /dev/null
#Store sample line chunk no and sample line no
SL_CN=`iquery -ocsv -aq "project(KG_LOAD_SAMPLE_LINE_LOCATION_$RIND, chunk_no)" | tail -n 1`
SL_LN=`iquery -ocsv -aq "project(KG_LOAD_SAMPLE_LINE_LOCATION_$RIND, line_no)"  | tail -n 1`
log "Found the sample line at chunk $SL_CN, line number $SL_LN"
#Ich wants no errors past the sample line!
NUM_ERRORS=`iquery -ocsv -aq "
op_count(
 filter(
  slice(KG_LOAD_BUF_$RIND, attribute_no, $NUM_ATTRIBUTES),
  (chunk_no > $SL_CN or line_no > $SL_LN) and a is not null
 )
)" | tail -n 1`
if [ $NUM_ERRORS -ne 0 ] ; then
 error "Found unexpected attribute errors in the data load. Examine KG_LOAD_BUF_$RIND."
else
 log "Found no errors past the sample line"
fi
iquery -anq "create temp array KG_LOAD_SAMPLES_$RIND <sample_name:string> [sample_id =0:*,$CHUNK_SIZE_SAMPLE, 0]" > /dev/null
iquery -anq "
store(
 redimension(
  substitute(
   apply(
    between(
     cross_join(
      KG_LOAD_BUF_$RIND as A,
      redimension(KG_LOAD_SAMPLE_LINE_LOCATION_$RIND, <i:int64> [chunk_no=0:*,1,0, line_no=0:*,$LINES_PER_CHUNK, 0]) as B,
      A.chunk_no, B.chunk_no,
      A.line_no, B.line_no
     ),
     null, null, null, $((NUM_PRESAMPLE_ATTRIBUTES)),
     null, null, null, $((NUM_ATTRIBUTES-1))
    ),
    sample_name, a,
    sample_id, attribute_no - $((NUM_PRESAMPLE_ATTRIBUTES))
   ),
   build(<val:string> [x=0:0,1,0], ''),
   sample_name
  ),
  KG_LOAD_SAMPLES_$RIND
 ),
 KG_LOAD_SAMPLES_$RIND
)" > /dev/null
NUM_SAMPLES_IN_FILE=`iquery -ocsv -aq "op_count(KG_LOAD_SAMPLES_$RIND)" | tail -n 1`
if [ -z $NUM_SAMPLES_IN_FILE -o  $NUM_SAMPLES_IN_FILE -ne $NUM_SAMPLES ]; then
 error "Number of samples in the file does not match expected. Examine KG_LOAD_BUF_$RIND."
else
 log "Confirmed $NUM_SAMPLES_IN_FILE samples in file"
fi
#Load SAMPLE
NUM_SAMPLES_IN_DB=`iquery -ocsv -aq "op_count(KG_SAMPLE)" | tail -n 1`
SAMPLES_ALIGNED=0
if [ $NUM_SAMPLES_IN_DB -eq 0 ]; then
 log "No samples are in DB; populating with samples from file."
 iquery -anq "store(KG_LOAD_SAMPLES_$RIND, KG_SAMPLE)" > /dev/null
 SAMPLES_ALIGNED=1
elif [ $NUM_SAMPLES_IN_DB -ne $NUM_SAMPLES_IN_FILE ]; then
 SAMPLES_ALIGNED=0
else 
 JOINED_SAMPLES=`iquery -ocsv -aq "aggregate(apply(join(KG_LOAD_SAMPLES_$RIND as A, KG_SAMPLE as B), t, iif(A.sample_id = B.sample_id, 1, 0)), sum(t))" | tail -n 1`
 if [ $JOINED_SAMPLES -ne $NUM_SAMPLES_IN_FILE ] ; then 
  SAMPLES_ALIGNED=0
 else
  SAMPLES_ALIGNED=1
 fi
fi
if [ $SAMPLES_ALIGNED -ne 1 ] ; then
 error "Samples in the file are not aligned with the samples in the DB. Sorry! This code path is not implemented yet."
fi
log "Separating variant data into a temporary KG_LOAD_VARIANT_BUF_$RIND"
iquery -anq "
create temp array KG_LOAD_VARIANT_BUF_$RIND
<chrom:     string null,
 pos:       int64  null,
 id:        string null,
 ref:       string null,
 alt:       string null,
 qual:      double null,
 filter:    string null,
 info:      string null,
 format:    string null,
 signature: string null>
[ln=0:*,1000000,0]" > /dev/null
iquery -anq "
store(
 apply(
  redimension(
   apply(
    between(
     filter(
      KG_LOAD_BUF_$RIND,
      chunk_no > $SL_CN or line_no > $SL_LN
     ),
     null,null,null,0,
     null,null,null,$((NUM_PRESAMPLE_ATTRIBUTES-1))
    ),
    chrom,  iif(attribute_no =0, a, null),
    pos,    int64(iif(attribute_no =1, a, null)),
    id,     iif(attribute_no =2, a, null),
    ref,    iif(attribute_no =3, a, null),
    alt,    iif(attribute_no =4, a, null),
    qual,   double(iif(attribute_no =5, a, null)),
    filter, iif(attribute_no =6, a, null),
    info,   iif(attribute_no =7, a, null),
    format, iif(attribute_no =8, a, null),
    ln, line_no + chunk_no * $LINES_PER_CHUNK - $SL_CN * $LINES_PER_CHUNK - $SL_LN - 1
   ),
   <chrom:     string null,
    pos:       int64  null,
    id:        string null,
    ref:       string null,
    alt:       string null,
    qual:      double null,
    filter:    string null,
    info:      string null,
    format:    string null>
   [ln=0:*,1000000,0],
   max(chrom) as chrom, max(pos) as pos, max(id) as id, max(ref) as ref, max(alt) as alt, max(qual) as qual, 
   max(filter) as filter, max(info) as info, max(format) as format
  ),
  signature,
  chrom + ':' + string( pos ) + ' ' + ref + '>' + alt
 ),
 KG_LOAD_VARIANT_BUF_$RIND
)" > /dev/null
NUM_VARIANTS=`iquery -ocsv -aq "op_count(KG_LOAD_VARIANT_BUF_$RIND)" | tail -n 1`
if [ $NUM_VARIANTS -le 0 ] ; then
 error "Found no variants in the file?"
else
 log "Identified $NUM_VARIANTS variants in the file"
fi
NUM_NULL_SIGS=`iquery -ocsv -aq "op_count(filter(KG_LOAD_VARIANT_BUF_$RIND, signature is null))" | tail -n 1`
if [ $NUM_NULL_SIGS -ne 0 ] ; then
 error "Some of the variants have incomplete chrom,pos,ref,alt information. Examine KG_LOAD_VARIANT_BUF_$RIND"
fi
NUM_OVERLAPPING_VARIANTS=`iquery -ocsv -aq "
op_count(
 filter(
  index_lookup(
   KG_LOAD_VARIANT_BUF_$RIND,
   project(unpack(project(KG_VARIANT, signature), j), signature),
   KG_LOAD_VARIANT_BUF_$RIND.signature,
   idx
  ),
  idx is not null
 )
)" | tail -n 1`
if [ $NUM_OVERLAPPING_VARIANTS -ne 0 ]; then
 error "Some of the variants from the file are already in the DB. The append pathway is not implemented yet. Sorry!."
else
 log "Identified no overlapping variants"
fi
log "Loading into KG_CHROMOSOME"
iquery -anq "
insert(
 redimension(
  apply(
   cross_join(
    project(
     unpack(
      filter(
       index_lookup(
        uniq(
         sort(
          project(
           apply(
            slice(
             filter(
              KG_LOAD_BUF_$RIND,
              chunk_no > $SL_CN or line_no > $SL_LN
             ),
             attribute_no, 0
            ),
            chrom, a
           ),
           chrom
          )
         )
        ) as C,
        KG_CHROMOSOME as D,
        C.chrom,
        idx
       ),
       idx is null
      ),
      j
     ),
     chrom
    ) as NEW_CHROMOSOMES,
    op_count(KG_CHROMOSOME) as CN
   ),
   chrom_id, NEW_CHROMOSOMES.j+CN.count
  ),
  KG_CHROMOSOME
 ),
 KG_CHROMOSOME
)" > /dev/null
log "Loading into KG_VARIANT"
NEW_NUM_VARIANTS=`iquery -ocsv -aq "
op_count(
 insert(
  redimension(
   apply(
    index_lookup(
     cross_join(
      substitute(
       substitute(
        KG_LOAD_VARIANT_BUF_$RIND,
        build(<v1:string> [x1=0:0,1,0], 'INVALID'),
        signature, chrom, ref, alt
       ),
       build(<v2:int64> [x2=0:0,1,0], -1),
       pos
      ) as A,
      op_count(KG_VARIANT) as B
     ),
     KG_CHROMOSOME,
     A.chrom,
     chrom_id
    ),
    variant_id, ln + B.count
   ),
   KG_VARIANT
  ),
  KG_VARIANT  
 )
)" | tail -n 1`
if [ -z $NEW_NUM_VARIANTS -o $NEW_NUM_VARIANTS -le 0 ]; then
 error "Error on insertion"
fi
log "Loading into KG_GENOTYPE"
iquery -anq "
insert(
 redimension(
  apply(
   between(
    KG_LOAD_BUF_$RIND,
    null, null, null, $NUM_PRESAMPLE_ATTRIBUTES, 
    null, null, null, $NUM_ATTRIBUTES-1
   ),
   sample_id,  attribute_no - $NUM_PRESAMPLE_ATTRIBUTES,
   variant_id, iif(chunk_no > $SL_CN or line_no > $SL_LN, $NEW_NUM_VARIANTS - $NUM_VARIANTS + line_no + chunk_no * $LINES_PER_CHUNK - $SL_CN * $LINES_PER_CHUNK - $SL_LN - 1, int64(null)),
   gt, a
  ),
  KG_GENOTYPE
 ),
 KG_GENOTYPE
)" > /dev/null
log "Loading into KG_VARIANT_POSITION_MASK"
iquery -anq "
insert(
 redimension(
  apply(
   between(
    KG_VARIANT,
    null, $NEW_NUM_VARIANTS-$NUM_VARIANTS, 
    null, $NEW_NUM_VARIANTS-1
   ),
   mask, bool(true)
  ),
  KG_VARIANT_POSITION_MASK
 ),
 KG_VARIANT_POSITION_MASK
)" > /dev/null
log "Cleaning up"
delete_old_versions "KG_CHROMOSOME"
delete_old_versions "KG_GENOTYPE"
delete_old_versions "KG_SAMPLE"
delete_old_versions "KG_VARIANT"
delete_old_versions "KG_VARIANT_POSITION_MASK"
iquery -anq "remove(KG_LOAD_BUF_$RIND)" > /dev/null
iquery -anq "remove(KG_LOAD_SAMPLE_LINE_LOCATION_$RIND)" > /dev/null
iquery -anq "remove(KG_LOAD_SAMPLES_$RIND)" > /dev/null
iquery -anq "remove(KG_LOAD_VARIANT_BUF_$RIND)" > /dev/null
log "Loaded $NUM_VARIANTS variants; DB now contains $NEW_NUM_VARIANTS"


