#!/usr/bin/env nextflow
/*
vim: syntax=groovy
-*- mode: groovy;-*-
/*
 * SET UP CONFIGURATION VARIABLES
 */


// Pipeline version
version = 0.9

// Configurable variables
params.genome = 'ggal'
params.fasta = params.genome ? params.genomes[params.genome].fasta ?: false : false
params.gtf  = params.genome ? params.genomes[params.genome].gtf ?: false : false
params.reads = params.genomes[params.genome].reads
params.reads_file = params.genomes[params.genome].sample_reads_file
params.paired = params.genomes[params.genome].paired
params.outdir = params.genomes[params.genome].outdir
params.starindex= params.genome ? params.genomes[params.genome].star ?: false : false
params.bowtieindex= params.genome ? params.genomes[params.genome].bowtie ?: false : false
params.project = params.genome ? params.genomes[params.genome].project ?: false : false
params.aligner = params.genome ? params.genomes[params.genome].aligner ?: false : false
params.transcriptome = params.genome ? params.genomes[params.genome].transcriptome ?: false : false
params.kallistoindex = params.genome ? params.genomes[params.genome].kallistoindex ?: false : false
params.email = params.genome ? params.genomes[params.genome].email ?: false : false
params.refgenome = params.genome ? params.genomes[params.genome].refgenome ?: false : false
params.bed = params.genome ? params.genomes[ params.genome ].bed ?: false : false
params.saveReference = true

// Read and Map reads with samples using csv file

if (params.paired) {
    Channel
        .fromPath(params.reads_file)
        .splitCsv(header: true)
        .map {row -> [row.Sample_Name, [row.Read1, row.Read2]]}
        .ifEmpty { error "File ${params.reads_file} not parsed properly" }
        .into {read_files_fastqc; read_files_trimming}
} else {
    Channel
        .fromPath(params.reads_file)
        .splitCsv(header: true)
        .map {row -> [row.Sample_Name, [row.Read]]}
        .ifEmpty { error "File ${params.reads_file} not parsed properly" }
        .into {read_files_fastqc; read_files_trimming}
}



// Aligner options

if (params.aligner != 'star' && params.aligner != 'bowtie' && params.aligner != 'kallisto'){
    exit 1, "Invalid aligner option: ${params.aligner}. Valid options: 'star','bowtie','kallisto'"
}


// Validate inputs

if (params.starindex && params.aligner == 'star'){
    starindex = Channel
        .fromPath(params.starindex)
        .ifEmpty { exit 1, "STAR index not found: ${params.starindex}" }
        .toList()
}

else if (params.bowtieindex && params.aligner == 'bowtie' ){
    bowtieindex = Channel
        .fromPath(params.bowtieindex)
        .ifEmpty { exit 1, "Bowtie index not found: ${params.bowtieindex}" }
        .toList()
}

else if(params.kallistoindex && params.aligner == 'kallisto'){

   kallistoindex = Channel
        .fromPath(params.kallistoindex)
        .ifEmpty { exit 1, "Kallisto index not found: ${params.kallistoindex}" }
        .toList()
}


else if ( params.fasta ){
    fasta = file(params.fasta)
        if( !fasta.exists() ) exit 1, "Fasta file not found: ${params.fasta}"
}

else if ( ( params.aligner == 'bowtie' && !params.bowtieindex ) && !params.fasta ){
        exit 1, "No reference genome specified!"
}

if (params.transcriptome) {

        Channel
        .fromPath(params.transcriptome)
        .ifEmpty { exit 1, "Transcriptome file not found: ${params.transcriptome}" }
        .toList()
        .into { make_kallistoindex; transcriptome_kallisto  }
}


if (params.gtf){
    Channel
        .fromPath(params.gtf)
        .ifEmpty { exit 1, "GTF annotation file not found: ${params.gtf}" }
        .toList()
        .into { gtf_makeSTARindex; gtf_bowtieindex;gtf_star;gtf_bowtie;gtf_stringtieFPKM;  }
}

if( params.bed ){
    bed = Channel
        .fromPath(params.bed)
        .ifEmpty { exit 1, "BED annotation file not found: ${params.bed}" }
        .toList()

}
fasta = file(params.fasta)
gtf   = file(params.gtf)
transcriptome_file = file(params.transcriptome)
bed = file(params.bed)



log.info " PIPELINER RNAseq Pipeline v${version}"
log.info "===================================="
log.info "Project       : ${params.project}"
log.info "Reads         : ${params.reads}"
log.info "Genome        : ${params.genome}"
log.info "FASTA         : ${params.fasta}"
log.info "Transcriptome : ${params.transcriptome}"
log.info "Annotation    : ${params.gtf}"
log.info "Output dir    : ${params.outdir}"

        if(params.aligner == 'star')
        {
        log.info "Aligner        : STAR"
                if (params.starindex)
                        log.info "STAR Index: ${params.starindex}"

        }
        else if (params.aligner == 'bowtie')
        {
        log.info "Aligner        : Bowtie"
                if (params.bowtieindex)
                        log.info "Bowtie Index   : ${params.bowtieindex}"

        }

        else if (params.aligner == 'kallisto')
        {
        log.info "Pseudo Aligner        : Kallisto"
                if (params.kallistoindex)
                        log.info "Kallisto Index   : ${params.kallistoindex}"

        }

log.info "Current home  : $HOME"
log.info "Current user  : $USER"
log.info "Current path  : $PWD"
log.info "===================================="




/* PREPROCESSING - Build STAR index */

if(params.aligner == 'star' && !params.starindex &&fasta)

{ 
process makeSTARindex {

		publishDir path: "${params.outdir}/reference_genome", saveAs: { params.saveReference ? it : null }, mode: 'copy'


		tag fasta
		cache 'deep'
                
		input:
                file fasta from fasta
                file gtf from gtf_makeSTARindex
		
                output:
                file "star" into starindex

                script:
		
                """
		module load star/2.4.2a
		mkdir star
                STAR \\
                --runMode genomeGenerate \\
                --runThreadN ${task.cpus} \\
                --sjdbGTFfile $gtf \\
                --sjdbOverhang 149 \\
                --genomeDir star/ \\
                --genomeFastaFiles $fasta

                """
                }

}

else if(params.aligner == 'bowtie' && !params.bowtieindex)

{       println("index does not exits")

                process buildIndex{
		cache  'deep'
                tag fasta
		publishDir path: "${params.outdir}/reference_genome", saveAs: { params.saveReference ? it : null }, mode: 'copy'
                
		input:
                file fasta from fasta

                output:
                file "genome.*" into bowtieindex



                """
                module load bowtie2/2.2.9
                mkdir bowtie
                bowtie2-build -c fasta genome


                """
                }

}



logParams(params, "nextflow_paramters.txt")

def logParams(p, n) {
  File file = new File(n)
  file.write "Parameter:\tValue\n"

  for(s in p) {
     file << "${s.key}:\t${s.value}\n"
  }
}



/*
 * STEP 1 - FastQC 
 */

process fastqc {
     		tag "$sampleid"
		cache 'deep'
	    	publishDir "${params.outdir}/$sampleid/fastqc", mode: 'copy'
		  executor = 'sge'
  		clusterOptions = "-P ${params.project} -l h_rt=96:00:00 -l mem_total=5G -pe omp 12"
	

   		input:
    		set sampleid, reads from read_files_fastqc

    		output:
    		set sampleid, '*_fastqc.{zip,html}' into fastqc_results

    		script:
    		if (params.paired) 
		{
        
			"""
        		/restricted/projectnb/pulmseq/kkarri_netflow_test/FastQC/fastqc -o . -q ${reads[0]} ${reads[1]}

        		"""
    		}
    	
		else 
		{
        
			"""
        		/restricted/projectnb/pulmseq/kkarri_netflow_test/FastQC/fastqc -o . -q ${reads[0]}
        		"""
    		}
	}


/*
 * STEP 2 - Trim Galore!
 */

process trim_galore {
 	tag "$sampleid"
	cache 'deep'
	  executor = 'sge'
  	clusterOptions = "-P ${params.project} -l h_rt=96:00:00 -l mem_total=5G -pe omp 12"

	
	publishDir "${params.outdir}/$sampleid/trim_galore", mode: 'copy'

    	input:
    	set sampleid, reads from read_files_trimming

    	output:
    	set sampleid, '*fq.gz' into trimmed_reads
    	set sampleid, '*trimming_report.txt' into trimgalore_results

    	script:
    	if(params.paired) 
		{
        
			println("pairedend")
        	
			"""
        		module load python2.7/Python-2.7.3_gnu446
        		module load cutadapt/1.7.1_Python-2.7.3
        		/restricted/projectnb/pulmseq/kkarri_netflow_test/trim_galore --paired --gzip ${reads[0]} ${reads[1]}
        		"""
    		} 
	else 
		{
        		println("singleend")
        		"""
        		/* module load python2.7/Python-2.7.3_gnu446*/
        		/* module load cutadapt/1.7.1_Python-2.7.3*/
        		/restricted/projectnb/pulmseq/kkarri_netflow_test/trim_galore --gzip ${reads[0]}
        		"""
    		}
	}




if(params.aligner == 'star')
{
        process star {
                  executor = 'sge'
                clusterOptions = "-P ${params.project} -l h_rt=96:00:00 -l mem_total=5G -pe omp 12"


                tag "$sampleid"
                cache 'deep'
                publishDir "${params.outdir}/$sampleid/STAR", mode: 'copy'

                input:
                file index from starindex.first()
                file gtf from gtf_star.first()
                set sampleid, file (reads:'*') from trimmed_reads

                output:
                 set sampleid,file("${sampleid}*.bam") into  bam_files
		 set sampleid,file("${sampleid}*.bam") into  bam_count
                 set sampleid,file("${sampleid}*.bam") into bam_rseqc_junc_annot
		 set sampleid,file("${sampleid}*.bam")  into bam_stringtieFPKM
	 	 set sampleid,file("${sampleid}*.bam") into bam_rseqc_genecoverage
		 set sampleid,file("${sampleid}*.bam")  into bam_rseqc_bamstats

                set sampleid, '*.out' into alignment_logs
                set sampleid, '*SJ.out.tab' into alignment_tab

                script:
                """
                module load star/2.4.2a
               f='$reads';f=(\$f);f=\${f[0]};f=\${f%.gz};f=\${f%.fastq};f=\${f%.fq};f=\${f%_val_1};f=\${f%_trimmed};f=\${f%_1};f=\${f%_R1};f=\${f%_R1_001}
                prefix=\$f
 
		STAR --genomeDir $index \\
                --sjdbGTFfile $gtf \\
                --readFilesIn $reads  \\
                --runThreadN ${task.cpus} \\
                --twopassMode Basic \\
                --outWigType bedGraph \\
                --outSAMtype BAM SortedByCoordinate \\
                --readFilesCommand zcat \\
                --outFileNamePrefix \$prefix
		
		"""
                }




}



if(params.aligner == 'bowtie')

{

        process mapping {
                tag "$sampleid"
                publishDir "${params.outdir}/$sampleid/tophat", mode: 'copy'
		echo true
		cache 'deep'
                executor = 'sge'
                clusterOptions = "-P ${params.project} -l h_rt=96:00:00 -l mem_total=5G -pe omp 12"


                input:
                file fasta from fasta
                file genome from bowtieindex.first()
                set sampleid, file (reads:'*') from trimmed_reads
		file gtf from gtf_bowtie

                output:
		set sampleid,file ("tophat_out/*acceptedhits.bam") into bam_stringtieFPKM1
		set sampleid,file ("tophat_out/*acceptedhits.bam") into bam_stringtieFPKM2
		set sampleid,file ("tophat_out/*acceptedhits.bam") into bam_files
                set sampleid,file ("tophat_out/*acceptedhits.bam") into bam_rseqc
//		set sampleid,file ("tophat_out/*acceptedhits.bam") into bam_rseqc
//		set sampleid,file ("tophat_out/*acceptedhits.bam") into bam_rseqc

                file ("tophat_out/logs") into alignment_logs

		script:

                """
                module load python/2.7.11
              	module load boost/1.58.0
               	module load bowtie2/2.2.9
               	module load tophat/2.1.1

                tophat2 -G  $gtf genome ${reads}
		
	        cp tophat_out/accepted_hits.bam tophat_out/${sampleid}.acceptedhits.bam
                """
        }

}




// BamStats for the bam file


process rseqc{
    tag "$sampleid"
    publishDir "${params.outdir}/$sampleid/rseqc", mode: 'copy'

    input:
    set sampleid,file(bamfiles)from bam_rseqc
    file bed from bed

    output:
	 file ("*.{txt,pdf,r,xls}") into rseqc_results

   file('*.bam_stats') into bam_stats_results
   file ('*geneBodyCoverage.*') into gene_coverage_results
    stdout into gene_coverage_log
    file ('*junction.*') into junction_annotation_results
 //   file('junc_annot.junction.xls') into junction
//   file('gene_coverage.geneBodyCoverage.txt') into coverage
    script:
    """
    samtools index $bamfiles
    bam_stat.py -i $bamfiles > ${sampleid}.bam_stats
    geneBody_coverage.py -r $bed -i $bamfiles -o ${sampleid}
    junction_annotation.py -i $bamfiles -o ${sampleid} -r $bed
    """
}


/*
* stringtie FPKM
*/

if(params.aligner == "star" | params.aligner == "bowtie")

{
process stringtieFPKM1 {
    tag "$sampleid"
    // publishDir "${params.outdir}/${sampleid}/stringtieFPKM", mode: 'copy'

    input:
    set sampleid, file(bamfiles) from bam_stringtieFPKM1
    file gtf from gtf

    output:
    file '*_transcripts.gtf' into gtf_list

    script:
    """
    stringtie $bamfiles \\
        -o ${bamfiles}_transcripts.gtf \\
        -v \\
        -G $gtf \\
    """
}

process gtf_merge {
    publishDir "${params.outdir}/stringtiemerge", mode: 'copy'

    input:
    val gtfs from gtf_list.toList()
    file gtf from gtf

	output:
    file 'merged_gtf.gtf' into merged_gtf

	script:
    String gtf_string = gtfs .flatten() .join(' ')
	"""
	stringtie --merge $gtf_string -G $gtf -e -F -T -o merged_gtf.gtf
	"""
}

bam_stringtieFPKM2
    .combine(merged_gtf)
    .into {stringtie_input}

// Repeat STRINGTIE again here
process stringtieFPKM2 {
    tag "$sampleid"
    publishDir "${params.outdir}/${sampleid}/stringtieFPKM", mode: 'copy'
    echo true

    input:
    // set sampleid, file(bamfiles) from bam_stringtieFPKM2
    set sampleid, file(bamfiles), file(mergedgtf) from stringtie_input
    // file mergedgtf from merged_gtf

    output:
    file '*_transcripts.gtf' into final_gtf_list
    file '*.gene_abund.txt' into gene_abund
    file '*.cov_refs.gtf'
    stdout into stringtie_log

    script:
    """
    stringtie $bamfiles \\
        -o ${bamfiles}_transcripts.gtf \\
        -v \\
        -G $mergedgtf \\
        -A ${bamfiles}.gene_abund.txt \\
        -C ${bamfiles}.cov_refs.gtf \\
        -e \\
        -b ${bamfiles}_ballgown
	 echo "File name: $bamfiles Stringtie version "\$(stringtie --version)
    """
}

// Make gene count and transcript count matrix
process aggregate_counts {
   publishDir "${params.outdir}/counts", mode: "copy"

   input:
   val abund_file_list from gene_abund.toList()

   output:
   file "fpkm.csv" into fpkm_counts
   file "tpm.csv" into tpm_counts

   script:
   String file_list = abund_file_list .flatten() .join(' ')
   """
   aggregate_counts.py $file_list
   """
}
}

/*
 * STEP 11 MultiQC
 */

process multiqc {
    publishDir "${params.outdir}/MultiQC", mode: 'copy'

    input:
    file ('fastqc/*') from fastqc_results.flatten().toList()
    file ('trimgalore/*') from trimgalore_results.flatten().toList()
    file ('tophat/*') from alignment_logs.flatten().toList()
    file ('stringtie/*') from stringtie_log.flatten().toList()
    file('counts/*') from fpkm_counts.flatten().toList()
   file ('rseqc/*') from gene_coverage_results.flatten().toList()
   file ('rseqc/*') from junction_annotation_results.flatten().toList()

    output:
    file "*multiqc_report.html"
    file "*multiqc_data"

    script:
    """
    multiqc -f ${params.outdir}
    """
}







workflow.onComplete {
	println ( workflow.success ? "CONGRATULATIONS !!!!! Your pipeline executed successfully :) !!" : "Oops .. something went wrong" )
	def subject = 'My pipeline execution'
	def recipient = (params.email)

    ['mail', '-s', subject, recipient].execute() << """
    Pipeline execution summary
    ---------------------------
    Completed at: ${workflow.complete}
    Duration    : ${workflow.duration}
    Success     : ${workflow.success}
    workDir     : ${workflow.workDir}
    exit status : ${workflow.exitStatus}
    Error report: ${workflow.errorReport ?: '-'}
    """
}
