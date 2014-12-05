#!/bin/bash

file=$1

echo "loading $file"

echo "drop array gvcf_tmp;" | iquery

echo "loading data..."
iquery -n -aq "store(parse(split('$file'), 'num_attributes=10'), gvcf_tmp)"

iquery -n -a < convert.iquery
