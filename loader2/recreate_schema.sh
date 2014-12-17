#!/bin/bash

#Blow the world away and create a clean slate
iquery --ignore-errors -aq "
remove(KG_SAMPLE);
remove(KG_VARIANT);
remove(KG_GENOTYPE);
remove(KG_VARIANT_POSITION_MASK);
remove(KG_CHROMOSOME);

create array KG_SAMPLE
<   sample_name :string  >
[   sample_id =0:*,100,0 ];

create array KG_VARIANT
<
    signature :string,
    pos       :int64,
    ref       :string,
    alt       :string,
    id        :string null,
    qual      :double null,
    filter    :string null,
    info      :string null
>
[
    chrom_id     =0:*,1,0,
    variant_id   =0:*,10000,0
];

create array KG_GENOTYPE
<
    gt :string null 
>
[
    variant_id =0:*,10000,0,
    sample_id  =0:*,100,0
];

create array KG_VARIANT_POSITION_MASK
<
    mask :bool 
>
[
    variant_id =0:*,10000,0,
    pos        =0:*,10000000,0,
    chrom_id   =0:*,1,0 
];

create array KG_CHROMOSOME
<
    chrom: string
>
[
    chrom_id   = 0:*,1,0
];
"
