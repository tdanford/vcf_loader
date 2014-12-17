vcf_tools
=========

Prototype for loading VCF Datasets into SciDB, currently built around the 1000 Genomes dataset.
Very very early, unstable. Work in progress.

Part of the original prototype was adapted from scidb-genotypes by Douglas Slotta (NCBI)
See: https://github.com/slottad/scidb-genotypes

# kg_loader: Based on the 1000 Genomes Dataset
Built to load 1000 Genomes data or data with very similar organization

## Pre-reqs
0. Assumes running SciDB 14.8 or newer, Python, CPP compiler. The larger the cluster - the faster this will run.
1. Install load_tools from www.github.com/paradigm4/load_tools
2. Currently, all VCFs must contain the same number of samples in the same positions
3. Currently, no two VCFs may have the same variant 
4. But this can be - and probably soon will be - a lot more flexible. Needs a few more code paths in load_file.sh

## Loading
1. Run ./kg_loader/recreate_db.sh once initially to create all the target arrays; run it again to blow away all the data
2. Run ./kg_loader/load_file.sh <FILENAME>
3. Hang onto something

## R toolkit
After data is loaded, one can install shim and SciDBR and then run the examples and queries in vcf_toolkit.R. 
The schema is younger than the file, not all queries will work right away. Working on it.

## AMI
A slightly older version of this is packaged into the Bioinformatics AMI. Instructions for that are here: http://www.paradigm4.com/try_scidb/

# gvcf: Tools for loading and processing gvcf files
Work in progress
