vcf_loader
=========

Prototype for loading VCF Datasets into scidb. Currently built around the 1000 Genomes dataset.
Very very early, unstable.

Part of the original prototype was adapted from scidb-genotypes by Douglas Slotta (NCBI)
See: https://github.com/slottad/scidb-genotypes

## Pre-reqs
0. Assumes running SciDB, Python, CPP compiler. To load many files, turn up the thread settings, i.e.:
  1. execution-threads=68
  2. result-prefetch-queue-size=2
  3. result-prefetch-threads=64
  4. operator-threads=2
1. Also may want to set sshd MaxSessions and MaxStartups to 2048 on all nodes.

## Loading
1. Build vcfstreamer c++ executable (Makefile provided)
2. Edit loadcsv_express.py. Find the reference to /opt/scidb/14.8 and replace with your DB version if different
3. Edit load_multifiles.sh:
  1. Specify your scidb configuration name (used for restarts between large redims :( ) 
  2. Specify the FILEs to load (try 1 at first)
  3. All the FILEs will be parsed and loaded in parallel, then redimensioned into the target KG arrays sequentially
4. Run ./reset_db.sh once initially to create all the target arrays
5. Run ./load_multifiles.sh 
6. Hang onto something

The error-handling strategy just isn't there yet. Best way to recover from errors is restart scidb.
Working on it...
