#!/bin/bash

MYDIR=`dirname $0`
pushd $MYDIR
MYDIR=`pwd`

if [ $# -ne 2 ]; then
    echo "Please provide the input file name and prefix! KTHXBYE"
    exit 1
fi

INFILE=$1

if [ ! -f $INFILE ] ; then
    echo "Cannot find input file $INFILE! KTHXBYE"
    exit 1
fi

PREFIX=$2

if [ ${#PREFIX} -eq 0 ] ; then
	 echo "Please provide prefix! KTHXBYE"
	 exit 1
fi

SAMPLE_BUF_ATTRIBUTES=" <nsid:   int64       ,
                         sample_name: string >"
VAR_BUF_ATTRIBUTES="    <nvid:   int64       ,
                         chrom:  string      ,
                         pos:    int64       ,
                         id:     string  null,
                         ref:    string      ,
                         alt:    string      ,
                         qual:   double  null,
                         filter: string  null,
                         ns:     int64   null,
                         an:     int64   null,
                         misc:   string  null>"
GT_BUF_ATTRIBUTES="     <nvid:   int64       , 
                         nsid:   int64       , 
                         gt:     string      >"
MV_BUF_ATTRIBUTES="     <nvid:   int64       ,
                         order_nbr:   int64  ,
                         ac:     int64   null,
                         af:     double  null>"

iquery -anq "remove(${PREFIX}_KG_SAMPLE_BUF)"       > /dev/null 2>&1 
iquery -anq "remove(${PREFIX}_KG_VAR_BUF)"          > /dev/null 2>&1
iquery -anq "remove(${PREFIX}_KG_GT_BUF)"           > /dev/null 2>&1
iquery -anq "remove(${PREFIX}_KG_MV_BUF)"           > /dev/null 2>&1

set -e 

iquery -aq "create array ${PREFIX}_KG_SAMPLE_BUF $SAMPLE_BUF_ATTRIBUTES [ n             = 0:*,1000000,0]" > /dev/null
iquery -aq "create array ${PREFIX}_KG_VAR_BUF    $VAR_BUF_ATTRIBUTES    [ n             = 0:*,1000000,0]" > /dev/null
iquery -aq "create array ${PREFIX}_KG_GT_BUF     $GT_BUF_ATTRIBUTES     [ n             = 0:*,1000000,0]" > /dev/null
iquery -aq "create array ${PREFIX}_KG_MV_BUF     $MV_BUF_ATTRIBUTES     [ n             = 0:*,1000000,0]" > /dev/null

rm -rf ${PREFIX}_sample_buf_file ${PREFIX}_vcf_buf_fifo ${PREFIX}_gt_buf_fifo ${PREFIX}_mv_buf_fifo 
rm -rf ${PREFIX}_vcf_load.log ${PREFIX}_gt_load.log ${PREFIX}_mv_load.log ${PREFIX}_samples_load.log

echo "Launching streamer"

mkfifo ${PREFIX}_vcf_buf_fifo
mkfifo ${PREFIX}_gt_buf_fifo
mkfifo ${PREFIX}_mv_buf_fifo

zcat $INFILE | ./vcfstreamer/vcfstreamer ${PREFIX}_sample_buf_file ${PREFIX}_vcf_buf_fifo ${PREFIX}_gt_buf_fifo ${PREFIX}_mv_buf_fifo &

loadcsv.py           -v -i ${PREFIX}_vcf_buf_fifo   -a ${PREFIX}_KG_VAR_BUF     -D '\t' > ${PREFIX}_vcf_load.log 2>&1 &
./loadcsv_express.py -v -i ${PREFIX}_gt_buf_fifo    -a ${PREFIX}_KG_GT_BUF      -D '\t' > ${PREFIX}_gt_load.log  2>&1 &
loadcsv.py           -v -i ${PREFIX}_mv_buf_fifo    -a ${PREFIX}_KG_MV_BUF      -D '\t' > ${PREFIX}_mv_load.log  2>&1 &

FAILURES=0
for job in `jobs -p`
do
    wait $job || let "FAILURES+=1"
done

if [ "$FAILURES" == "0" ];
then
echo "Streamer load completed"
else
echo "Streamer load failed"
exit 1
fi

loadcsv.py -i ${PREFIX}_sample_buf_file -a ${PREFIX}_KG_SAMPLE_BUF -D '\t' > ${PREFIX}_samples_load.log 2>&1

#So if we made it this far, chances are life is good
rm -rf ${PREFIX}_sample_buf_file ${PREFIX}_vcf_buf_fifo ${PREFIX}_gt_buf_fifo ${PREFIX}_mv_buf_fifo
rm ${PREFIX}_*.log
