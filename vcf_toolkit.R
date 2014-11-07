# BEGIN_COPYRIGHT
# 
# Copyright © 2014 Paradigm4, Inc.
# This script is used in conjunction with the Community Edition of SciDB.
# SciDB is free software: you can redistribute it and/or modify it under the terms of the Affero General Public License, version 3, as published by the Free Software Foundation.
#
# END_COPYRIGHT

require("scidb")
scidbconnect()

covariance_demo = function()
{
  #Run these interactively for an example VCF workload.
  
  #First - generate an adjacency matrix [sample, variant]. ETA 4 minutes
  generate_covar_matrix()
  matrix = scidb("COVAR_MATRIX")
  
  #R image function overloaded for SciDB objects: generate a smaller image in SciDB first, then download and plot
  image(matrix)
  
  #Center
  matrix_centered = scidbtemp(sweep(matrix, 2, apply(matrix,2,mean)), keep_bounds=TRUE)
  
  #Compute covariance matrix: multiply by the transpose. ETA another several minutes
  #Note: tcga_toolkit has a more involved example of covariance followed by correlation
  scidbremove("COVAR_RESULT", force=TRUE, error=invisible, warn=FALSE)
  CV = scidbeval(crossprod(matrix_centered)/(nrow(matrix_centered)-1), name = "COVAR_RESULT", gc=FALSE)
  #CV is now a sample x sample distance metric
  CV
  
  #Looks interesting. We think the different bands in the image may correspond to particular ethnic groups
  image(CV)
}

VARIANT          = scidb("KG_VARIANT")
GENOTYPE         = scidb("KG_GENOTYPE")
VGENE            = scidb("GENE_36")
VARIANT_POS_MASK = scidb("KG_VARIANT_POSITION_MASK")
VCHROMOSOME      = scidb("KG_CHROMOSOME")
VARIANT_MULT_VAL = scidb("KG_VARIANT_MULT_VAL")
VSAMPLE          = scidb("KG_SAMPLE")

######
# Sample queries
######

# Select all the instances of a given variant
# foo = all_instances_of_variant()
# iqdf(foo)
all_instances_of_variant = function( variant_signature = "21:10435894 C>T")
{
  selected_variants = subset(VARIANT, sprintf("signature = '%s'", variant_signature))
  #It is also possible to filter by separate components, i.e. subset(VARIANT, "pos=10009196")...
  #Let's take all the genotypes that have a variation in at least one chromosome:
  result = merge(subset(GENOTYPE, "gt<>'0|0'"), selected_variants)
  result = merge(VSAMPLE, result)
  #You can now do count(result), result@schema, project(result, "zygocity"),...
  #Or head(unpack(result))
  #What output attributes do you want?
  result = project(result, c("signature", "sample_name", "gt"))
  return (result)
}

# Select all variants observed in a given gene list
# In order for this to work, align_variants_to_genes() found below was first run to create the mapping
all_variants_in_genes = function ( gene_symbols = c('MRAP', 'SOD1'))
{
  VARIANT_GENE= scidb("VARIANT_GENE_36") #created by a utility function below
  selected_genes = subset(VGENE, paste("gene_symbol = '", gene_symbols, "'", sep="", collapse=" or "))
  selected_genes = project(selected_genes, c("gene_symbol", "genomic_start", "genomic_end"))
  result = merge(VARIANT_GENE, selected_genes)
  result = merge(VARIANT, result)
  result = project(result, c("gene_symbol", 
                             "signature"))
  #You can also do merge(subset(GENOTYPE...), result) just like in the above function to get the individual variations
  result
}

#Lookup variants based on allele frequency and genomic coordinates
lookup_by_freq_pos = function( chrom='21', pos_start = 11000000, pos_end = 12000000, min_freq = 0.9)
{
  #showing some syntactic possibilities: construct AFL
  result = scidb(sprintf("between(%s, null, %i, null, null, %i, null)", VARIANT_POS_MASK@name, pos_start, pos_end))
  
  #R-like syntax for simpler filters:
  result = merge(result, VCHROMOSOME %==% '21')$mask
  result = merge(VARIANT_MULT_VAL, result)
  result = subset(result, sprintf("af>%f", min_freq))
  
  result = redimension(result, "<af:double null> [variant_id=0:*,10000,0,order_nbr=0:*,5,0]")
  
  #A more thorough lookup: the variant may have many alternates, the allele frequency is different for each alternate.
  #Make sure we match the right genotype.
  #Alternatively, we could split the variants into unique alternates at load time - also a very reasonable approach.
  result = bind(result, "alternate_no", "string(order_nbr+1)")
  result = merge(VARIANT, result)
  result = project(result, c("signature", "alternate_no"))
  result = scidbtemp(subset(merge(GENOTYPE, result), "substr(gt, 2,1) = alternate_no or substr(gt, 0,1) = alternate_no"))
  result = merge(VSAMPLE, result)
  result
}

#Generate seed data for covariance matrices of variants
generate_covar_matrix = function(min_frequency = 0.5)
{
  scidbremove("COVAR_MATRIX", force=TRUE, error=invisible, warn=FALSE)
  scidbremove("COVAR_SELECTED_VARIANTS", force=TRUE, error=invisible, warn=FALSE)
  
  #Here we are somewhat sloppy about variants with multiple alternates
  #they make up a small fraction of the total set of variants, so they don't have a large effect on pairwise distances
  #a more precise workflow is possible
  selected_variants = subset(VARIANT_MULT_VAL, sprintf("af>= %f", min_frequency))
  selected_variants = merge(VARIANT[,0], selected_variants)
  selected_variants = redimension(selected_variants, "<signature:string> [variant_id=0:*,10000,0]")
  sparse_selected_variants = scidbtemp(selected_variants)
  
  num_variants = count(selected_variants)
  num_samples  = count(VSAMPLE)
  
  print(sprintf("Generating matrix using %i variants by %i samples", num_variants, num_samples))
  
  dense_selected_variants = unique(sparse_selected_variants)
  dense_selected_variants = scidbeval(repart(dense_selected_variants, chunk=10000), name = "COVAR_SELECTED_VARIANTS")
  
  matrix = bind(GENOTYPE, "variant_present", "double(iif(gt='0|0', 0.0, 1.0))")
  matrix = merge(matrix, sparse_selected_variants)
  matrix = index_lookup(matrix, dense_selected_variants, "signature", "dense_variant_id")
  matrix = redimension(matrix, sprintf("<variant_present:double NULL> [dense_variant_id=0:%i,10000,0, sample_id=0:%i,313,0]", num_variants-1,  num_samples-1))
  matrix = scidbeval(replaceNA(matrix), name = "COVAR_MATRIX")
  return(matrix)
}

######
# Maintenance Routines
######

#Maintenance routine: align variants to genes and create the VARIANT_GENE array
#This function isn't designed to return an object, but stores a new array in the database.
#The new array shall have the given name, and relate variants to a particular genomic assembly. 
#The target array is removed in case it already exists.
#This is technically a part of the load step, however it can be used interactively,
#should you add another genomic assembly for example. 
#This is a good example of how to write your own array objects into the database.
#This is also a decent algorithm for the "inexact spatial join" - partition data into buckets and then evaluate 
#only pairs that fit into a particular bucket in parallel
align_variants_to_genes = function(target_array_name = "VARIANT_GENE_36")
{
  scidbremove(target_array_name, error=invisible, warn=FALSE, force=TRUE)
  
  var_redim = bind(VARIANT, "pos_bucket", "int64(pos/1000000)")
  var_redim = redimension(var_redim, "<pos:int64> [chrom_id=0:*,1,0, pos_bucket=0:*,1,0, variant_id=0:*,10000,0]")
  var_redim = scidbtemp(var_redim)

  gene_redim = bind(VGENE, "chrom", "string(chromosome_nbr)")
  gene_redim = index_lookup(gene_redim,  VCHROMOSOME, "chrom", "chrom_id")
  gene_redim_1 = bind(gene_redim, "pos_bucket", "int64(genomic_start) / 1000000")
  gene_redim_1 = redimension(gene_redim_1, "<genomic_start:uint64, genomic_end:uint64> [chrom_id=0:*,1,0, pos_bucket=0:*,1,0, gene_id_36=0:*,40000,0]")
  gene_redim_1 = scidbtemp(gene_redim_1)
  
  gene_redim_2 = bind(gene_redim, "pos_bucket", "int64(genomic_end) / 1000000")
  gene_redim_2 = redimension(gene_redim_2, "<genomic_start:uint64, genomic_end:uint64> [chrom_id=0:*,1,0, pos_bucket=0:*,1,0, gene_id_36=0:*,40000,0]")
  gene_redim_2 = scidbtemp(gene_redim_2)
  
  mask1 = subset(merge(var_redim, gene_redim_1), "pos>=genomic_start and pos<=genomic_end")
  mask1 = bind(mask1, "mask", "bool(true)")
  mask1 = redimension(mask1, "<mask:bool>[variant_id =0:*,10000,0, gene_id_36=0:*,40000,0]")
  mask1 = scidbtemp(mask1)
  
  mask2 = subset(merge(var_redim, gene_redim_2), "pos>=genomic_start and pos<=genomic_end")
  mask2 = bind(mask2, "mask", "bool(true)")
  mask2 = redimension(mask2, "<mask:bool>[variant_id =0:*,10000,0, gene_id_36=0:*,40000,0]")
  mask2 = scidbtemp(mask2)
  
  result = merge(mask1, mask2, merge=TRUE)
  result = scidbeval(result, name=target_array_name, gc=0)
}

################
# Helper functions.
##################
force_unpack = function( scidb_object )
{
  if(class(scidb_object)[1] == "scidb")
  {
    return(unpack(scidb_object))
  }
  else if (class(scidb_object)[1] == "scidbdf")
  {
    dimname = scidb:::make.unique_(c(dimensions(scidb_object), scidb_attributes(scidb_object)),"i")
    query = paste("unpack(", scidb_object@name, ", ", dimname, ")", sep ="")
    return(scidb(query))
  } 
}

#Run a query or download data into R
#Flattens the data into a dataframe form. Valid to use on any scidb object.
#For example: iqdf(project(subset(GENE, "gene_id<>0 and chromosome_id=0"), "gene_symbol"))
#n is the number of returned values to download
iqdf = function( scidb_object, n = 50, prob = 1)
{
  result = scidb_object;
  if ( class(result) == "character")
  {
    result = scidb(result)
  }
  if ( prob < 1 )
  {
    result = bernoulli(result, prob)
  }
  result = force_unpack(result)
  if ( n > 0 && is.finite(n))
  {
    return(result[0:n-1, ][])   
  }
  return(result[])
}

clear_temp_arrays = function()
{
  scidbremove(scidbls("R_array.*"), force=1)
}

#Helper: Create a TEMP array - stored in memory
#Note: still needs a "depends" flag, or does it?
scidbtemp = function(expr, name, gc = TRUE, keep_bounds = FALSE)
{
  if (missing(name))
  {
    newname = scidb:::tmpnam()
  }
  else
  {
    newname = name
  }
  if (!(class(expr) %in% c("scidb", "scidbdf")))
  {
    expr = scidb(expr)
  }
  #pass empty name because we want a nameless schema to pass to create_array
  if (keep_bounds)
  {
    newschema = expr@schema
  }
  else
  {
    newschema = make_unbounded_schema(expr, new_name="")  
  }
  return(tryCatch({
    query = sprintf("create_array(%s, %s, 'TEMP')", newname, newschema)
    iquery(query)
    query = sprintf("store(%s, %s)", expr@name, newname)
    iquery(query)
    result = scidb(newname, gc=gc)
  }, error = function(e) {
    scidbremove(newname, force=TRUE, warn=FALSE, error=invisible)
    stop(e)
  }))
}

#Helper: generate an unbounded schema for an array. Currently needed to work around a SciDB limitation
make_unbounded_schema = function( array, new_name = "temp_unbound_schema")
{
  new_lengths = rep("*",length(array@dimensions))
  new_dims = scidb:::build_dim_schema(array, newlen=new_lengths)
  new_attrs = scidb:::build_attr_schema(array)
  result = paste(new_name, new_attrs, new_dims, sep=" ")
  return(result)
}

