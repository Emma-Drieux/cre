# cre
Excel variant report generator and scripts to process WES data (cram/bam/fastq -> variant calls -> annotated variant calls -> prioritized variants -> excel report). Uses results from [bcbio variant2](https://bcbio-nextgen.readthedocs.io/en/latest/contents/pipelines.html#germline-variant-calling) germline variant calling pipeline.

# 0. Installation

  1. Install **Bcbio**.

  Use HPC or server. Add bcbio to PATH. bcbio installs many other useful tools (including java and R) and datasets through bioconda and cloudbiolinux.
  
  2. Clone **cre** to ~/cre and add it to PATH.  
  3. (Optional) Install/update OMIM.

    By default CRE uses [cre/data/omim.txt](../master/data/omim.txt) and [cre/data/omim.inheritance.csv](../master/data/omim.inheritance.csv).

  * Goto https://omim.org/downloads/ and request the latest database.
  * In a couple of days you will receive: genemap2.txt, genemap.txt, mim2gene.txt, mimTitles.percent.txt, mimTitles.txt, morbidmap.txt. 
  * Preprocess OMIM with [cre.omim.sh](../master/cre.omim.sh). 
  
  ```
      cd OMIM_DIR
      ~/cre/cre.omim.sh
  ```
  
    Result - omim.txt with omim description of diseases related to ~ 4000 genes
    We use improved OMIM inheritance table from [https://www.cs.toronto.edu/~buske/cheo/](https://www.cs.toronto.edu/~buske/cheo/).Download the second file with inheritance mappings. It references genes by gene name (symbol) rather than by Ensembl_id which is a requirement for CRE. Most gene names (symbols) could be mapped automatically with Ensembl biomart [genes.R](https://github.com/naumenko-sa/bioscripts/blob/master/genes.R), but some genes (not many) might need manual curation to assign the correct ENSEMBL_ID.

  4. (Optional) Install/update Orphanet.
```
    cd ~/cre/data
    ~/cre/cre.orphanet.sh
```
  Orphanet provides descriptions for ~3600 genes:. By default CRE uses [orphanet.txt](../master/data/orphanet.txt)

  5. (Optional) Update Gnomad gene contraint scores.
```
    Rscript ~/cre/cre.gnomad_scores.R
```
  By default using [~/cre/data/gnomad_scores.csv](../master/data/gnomad_scores.csv)
  
  6. (Optional) Install impriting annotation.
  By default using [~/cre/data/imprinting.txt](../master/data/imprinting.txt).

  7. (Optional) Install HGMD pro database
  Install HGMD pro and dump information with [~/cre/cre.hgmd2csv.sql](../master/cre.hgmd2csv.sql).

# 1. Creating bcbio project - grch37

* Prepare input files: family_sample_1.fq.gz, family_sample_2.fq.gz, or family_sample.bam and place them into family/input folder.
* There might be many samples in a family(project).
* TEST: NIST Ashkenazim trio: ftp://ftp-trace.ncbi.nlm.nih.gov/giab/ftp/data/AshkenazimTrio (download OsloUniversityHospital exomes).
* run [cre.prepare_bcbio_run.sh](../master/cre.prepare_bcbio_run.sh) [family].

By default it uses [bcbio.templates.wes.yaml](../master/bcbio.templates.wes.yaml) config with following features:
  * 4 callers, the order is important, because variant metrics in ensemble calling (like AD) are picked up from the first caller in the list (gatk)
  * ensemble calling
  * realignment and recalibration. There is no much gain in precision/sensitivity with RR, but to make bam files consistent with other projects it is on here. Actually, realignment helps samtools to call indels better.
  * no bed file. Let callers call every variant which has coverage, we will filter poorly covered variants later. Modern exome capture kits are so perfect, that
we can discover a useful non-coding variant. No sense to filter them out during that stage.
  * effects: VEP. There is a holywar VEP/snpEff/Annovar. My choice is VEP. You will see later both Ensembl and Refseq in the report, so no reason for using Annovar.
  * effects_transcripts: all. We want all effects of a variant on all transcripts to be reported.
  * aligner: bwa. Even staring with bam files, bwa is used. Sometimes input bam files aligned against older reference, or different (chr) naming scheme. It is better to have a bam file consistent with calls made.
  * custom annotation [cre.vcfanno.conf](../master/cre.vcfanno.conf) using data sources installed in bcbio.
  * creates gemini database with vcf2db

## 1a. Input files are in Illumina basespace.
* use basespace-cli to dump bcl files to HPC, then do 1b.

## 1b. Input is Illumina run (bcl files).
* create a sample sheet and run [bcl2fq.sh](../master/bcl2fq.sh).

## 1c. Input is cram file.
* Run [cram2fq.sh](../master/cram2.fq). 
* I would suggest to avoid crams when possible. A damaged bam file could be recovered with [cre.bam_recovery.sh](../master/cre.bam_recovery.sh), but nothing could be done for cram.

# 2. Running bcbio for grch37 with decoys

By default, for grch37 bcbio does not support decoy sequences, they are supported in grch38. Two step approach could be applied to use decoys https://github.com/bcbio/bcbio-nextgen/issues/2489:
- install custom reference with decoys: [cre.bcbio.custom_genome.sh](../master/cre.bcbio.custom_genome.sh)
- run alignment step vs grch37d5 reference: cre.prepare_bcbio_run.sh <project> align_decoy
- run variant calling with noalt_calling and bam_clean: remove_extracontigs

# 2. Running bcbio

* Single project
```
qsub ~/cre/bcbio.pbs -v project=[project_name]
```
Project should have a folder project_name in the current directory.

* Multiple projects
```
qsub -t 1-N ~/cre/bcbio.array.pbs
```
Current directory should have a list of projects in projects.txt.

# 3. Cleaning project directory and creating project.csv report
```
qsub ~/cre/cre.sh -v family=[family],cleanup=1
```

  During the cleanup step:
  * moves project results and sample bam files to family dir
  * removes work and final dirs from bcbio project
  * removes gemini databases for individual callers (we need only ensemble gemini database)

  During the report generation step:
  * dumps variants from gemini database to tab text file
  * dumps variant impacts from gemini database to tab text file
  * annotates variants with refseq in addition to ensembl
  * gets coverage from GATK Haplotype calls, freebayes, and platypus
  * build excel report based on gemini variants table, variant impacts, coverage information and some other fields.

# 4. Step 3 in detail

## 4.0 [Report description](https://docs.google.com/document/d/1zL4QoINtkUd15a0AK4WzxXoTWp2MRcuQ9l_P9-xSlS4/edit?usp=sharing).
## 4.1 [Report example for Ashkenazim trio from NIST](https://drive.google.com/open?id=0B_bLL10GwDnsN29vY3RRdGlXMWM).
## 4.2 [gemini.gemini2txt.sh](../master/gemini.gemini2txt.sh) [project-ensembl.db] - dumps a gemini database into text file.
I prefer to do report generation in R, and first I tried to access gemini database from R using sqlite interface. It turned out impossible, because
of packaging of genotype BLOB fields. I ended up with gemini utility query to dump fields I need from variants database. Filters are described in the doc.
## 4.3 [gemini.variant_impacts.sh](../master/gemini.variant_impacts.sh) [project-ensembl.db] dumps variant impacts from gemini.
## 4.4 creates a vcf file with rare and potentially harmful variants, the same set of variants will be shown in the excel report 
```
cat ${family}-ensemble.db.txt | cut -f 23,24  | sed 1d | sed s/chr// > ${family}-ensemble.db.txt.positions
    bcftools view -R ${family}-ensemble.db.txt.positions -o ${family}.vcf.gz -O z ${family}-ensemble-annotated-decomposed.vcf.gz

```
## 4.5 gets coverage from VCFs produced by GATK, platypus, and freebayes - requires gatk wrapper from bcbio.
```
vcf.freebayes.getAO.sh ${family}-freebayes-annotated-decomposed.vcf.gz
vcf.gatk.get_depth.sh ${family}-gatk-haplotype-annotated-decomposed.vcf.gz
vcf.platypus.getNV.sh ${family}-platypus-annotated-decomposed.vcf.gz

```
## 4.6 Rscript ~/cre/[cre.R](../master/cre.R) [family] - creates report family.csv.

# 5. How to create a database of variants

- cre.database.sh [input_dir] [output_dir] - creates sample-wise and variant-wise reports, which are necessary for annotation with cre.R.
- cre.database.pull_gene.sh [database_prefix] [gene_name] - pull a gene report from the database.

# 6. Coverage plots

- ~/bioscripts/genes.R - pull a bed file from Ensembl
- ~/bioscripts/bam.coverage.bamstats05.sh - calculate coverage
- cheo.R - plot coverage pictures

# 7. List of all scripts

* bcbio.array.pbs
* bcbio.pbs
* bcbio.prepare_families.sh
* bcbio.rename_old_names.sh
* bcl2fastq.sh
* cheo.R - mostly Venn diagrams to compare pipeline validations + some coverage analysis
* cre.prepare_bcbio_run.sh
* cre.bam.validate.sh
* cre.bam.remove_decoy_reads.sh - removes decoy reads for grch37d5 with VariantBam and grep.
* cre.bcbio.upgrade.sh
* cre.coverage.bamstats05.sh - calculate coverage
* cre.fixit.sh - fixes sample names
* cre.gemini_load.sh loads vep-annotated vcf to gemini db.
* cre.gnomad_scores.R - download and parse gnomad scores.
* cre.immunopanels.R - annotates CRE report with 6 immunopanels.
* cre.kinship.R - to plot relatedness (kinship) diagram for a group of samples. Sometimes helps to detect and solve mislabelling.
* cre.package.sh
* cre.rtg.validate.sh - validates NA12878 calls vs genome in a bottle callset with RTG and a bed file
* cre.sh - master script to produce variant reports from bcbio output
* cre.topmed.R - pull variant frequency from TopMed having rs_id
* cre.vcf.has2dp.sh fixes input vcf file from HAS pipeline (Illumina, TCAG) filling DP field
* omim.sh
* orphanet.sh
* vcf.freebayes.getAO.sh
* vcf.gatk.get_depth.sh
* vcf.platypus.getNV.sh
* vcf.samtools.get_depth.sh
* vcf.split_multi.sh
* vep4seqr_hg38.sh
* vep4seqr.sh

# 8. Credits

This work was inspired by 
* [bcbio](https://github.com/chapmanb/bcbio-nextgen/) and [gemini](https://github.com/arq5x/gemini) teams. Thank you all!
* Kristin Kernohan from Children's Hospital of Eastern Ontario (CHEO), who generated most ideas about the report contents. Thank you, Kristin, for all of the discussions!

Thank you colleagues at [CCM](https://ccm.sickkids.ca/), for seminars and personal discussions.
