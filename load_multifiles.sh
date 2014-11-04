#!/bin/bash

MYDIR=`dirname $0`
pushd $MYDIR
MYDIR=`pwd`

DBNAME=bio64

FILES="example20k.vcf.gz \
	   example20k.vcf.gz \
	   example20k.vcf.gz \
	   example20k.vcf.gz \
	   example20k.vcf.gz \
	   example20k.vcf.gz"

echo "Launching the lost children..."
N=1
for FILE in $FILES; do
    PREFIX="FILE_${N}"	
	N=$((N+1))
    time ./stream_vcf_1d.sh $FILE $PREFIX > ${PREFIX}_child_stream.log 2>&1 &
done

echo "Waiting..."
FAILURES=0
for job in `jobs -p`
do
	wait $job || let "FAILURES+=1"
done

if [ "$FAILURES" == "0" ];
    then
		echo "Loads succeeded"
	else
		echo "Some of the children failed"
		exit 1
fi

rm -rf redim.log
N=1
for FILE in $FILES; do
	PREFIX="FILE_${N}"
    N=$((N+1))
	echo "Redimming $PREFIX"
    time ./redim_with_prefix.sh $PREFIX >> redim.log 2>&1
	scidb.py stopall $DBNAME > /dev/null
	scidb.py startall $DBNAME > /dev/null
done



