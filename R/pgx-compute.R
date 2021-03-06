if(0) {

    ##source("../scripts/options.R")
    ## MAX.GENES
    DIR = "../data/exampledata/"
    DIR = "~/bigomics/projects/vogel2019-tcell/data"
    counts  = as.matrix(read.csv(file.path(DIR,"counts.csv"), row.names=1))
    samples = read.csv(file.path(DIR,"samples.csv"), row.names=1, stringsAsFactors=FALSE)
    ##genes   = read.csv(file.path(DIR,"genes.csv"), row.names=1, stringsAsFactors=FALSE)
    contrasts = as.matrix(read.csv(file.path(DIR,"contrasts.csv"), row.names=1))
    progress = NULL

    counts = aa$counts
    samples = aa$samples
    contrasts = aa$contrasts

}

if(0) {
    max.genes=max.genesets=25000;lib.dir=FILES;progress=NULL;only.hugo=1;extra.methods=c("meta.go","deconv","infer","drugs","wordcloud")
    gx.methods=c("ttest.welch","trend.limma");gset.methods=c("fisher","gsva");
}

pgx.computeObjectPGX <- function(counts, samples, contrasts, ## genes, 
                                 ##gx.methods = c("trend.limma","edger.qlf","deseq2.wald"),
                                 max.genes = 9999, max.genesets = 9999, only.hugo=TRUE,
                                 gx.methods = c("ttest.welch","trend.limma","edger.qlf"),
                                 gset.methods = c("fisher","gsva","fgsea"),
                                 extra.methods = c("meta.go","deconv","infer","drugs","wordcloud"),
                                 lib.dir = "../lib", do.cluster=TRUE,
                                 progress=NULL)
{

    library(org.Hs.eg.db)

    if(!is.null(progress)) progress$inc(0.01, detail = "creating object")
    
    ##-------------------------------------------------------------------
    ## create ngs object
    ##-------------------------------------------------------------------
    ##load(file=rda.file, verbose=1)
    ngs <- list()  ## empty object
    ngs$name = "data set"
    ngs$date = date()
    ngs$datatype = "unknown"
    ngs$description = "data set"

    ngs$samples = samples
    ngs$counts  = counts
    ##ngs$genes   = data.frame(genes)
    ngs$contrasts = contrasts
    
    ##-------------------------------------------------------------------
    ## check counts
    ##-------------------------------------------------------------------
    is.log <- (min(ngs$counts,na.rm=TRUE) < 0 || max(ngs$counts,na.rm=TRUE) < 100)
    is.log
    if(is.log) {
        ngs$counts <- 2**ngs$counts  ## undo logarithm
        cat("[pgx-upload.R] undo logarithm\n")
    }

    mean.counts <- mean(colSums(ngs$counts,na.rm=TRUE))
    is.toobig <- log10(mean.counts) > 10
    is.toobig
    ngs$counts_multiplier = 1
    if(is.toobig) {
        ## scale to about 10 million reads
        ##progress$inc(0.01, detail = "scaling down counts")
        unit <- 10**(round(log10(mean.counts)) - 7)  
        ngs$counts <- ngs$counts / unit
        ngs$counts_multiplier = unit
    }
    ngs$counts_multiplier
    cat("[pgx-upload.R] count_multiplier= ",ngs$counts_multiplier,"\n")
    
    ##-------------------------------------------------------------------
    ## create gene annotation if not given
    ##-------------------------------------------------------------------
    is.mouse <- (mean(grepl("[a-z]",rownames(counts))) > 0.9)
    org = ifelse(is.mouse, "mouse", "human")
    org
    gene.symbol <- NULL
    if(org == "human") {
        require(org.Hs.eg.db)
        GENE.TITLE = unlist(as.list(org.Hs.egGENENAME))
        gene.symbol = unlist(as.list(org.Hs.egSYMBOL))
        gene.map <- sapply(as.list(org.Hs.egMAP),"[",1)
        names(GENE.TITLE) = gene.symbol
        names(gene.map) = gene.symbol
    }
    if(org == "mouse") {
        require(org.Mm.eg.db)
        GENE.TITLE = unlist(as.list(org.Mm.egGENENAME))
        gene.symbol = unlist(as.list(org.Mm.egSYMBOL))
        gene.map <- sapply(as.list(org.Mm.egMAP),"[",1)
        names(GENE.TITLE) = gene.symbol
        names(gene.map) = gene.symbol
    }
    if(!is.null(progress)) {
        aa <- paste("detected organism: ",org)
        progress$inc(0.01, detail = aa)
    }
    cat("[pgx-upload.R] detected organism: ",org,"\n")
    
    gene <- rownames(ngs$counts)
    gene1 <- sapply(gene, function(s) strsplit(s,split="[;,]")[[1]][1])
    gene1 <- alias2hugo(gene1)  ## convert to HUGO
    ngs$genes = data.frame( gene_name = gene1,
                           gene_alias = gene,
                           chr_loc = gene.map[gene1],
                           gene_title = GENE.TITLE[gene1] )
    ##rownames(ngs$genes) <- gene1
    
    ##-------------------------------------------------------------------
    ## collapse multiple row for genes by summing up counts
    ##-------------------------------------------------------------------
    ndup <- sum(duplicated(ngs$genes$gene_name))
    ndup
    if(ndup>0) {
        gg = as.character(ngs$genes$gene_name)
        x1 = apply( ngs$counts, 2, function(x) tapply(x, gg, sum))
        ngs$genes = ngs$genes[match(rownames(x1), ngs$genes$gene_name),]
        ngs$counts = x1
        rownames(ngs$genes) = rownames(ngs$counts) = rownames(x1)
        remove(x1)
    }

    ##-------------------------------------------------------------------
    ## Filter genes?
    ##-------------------------------------------------------------------
    if(org == "mouse") {
        has.name <- !is.na(ngs$genes$gene_name)
        is.official = TRUE
        if(only.hugo) is.official <- (ngs$genes$gene_name %in% gene.symbol)
        rik.genes <- grepl("Rik",ngs$genes$gene_name)
        ##imm.gene <- grepl("^TR_|^IG_",ngs$genes$gene_biotype)
        has.chrloc <- !is.na(ngs$genes$chr_loc)
        
        keep <- (has.name & !rik.genes & is.official & has.chrloc)
        ngs$counts <- ngs$counts[keep,]
        ngs$genes  <- ngs$genes[keep,]        
    }
    if(org == "human") {
        has.name <- !is.na(ngs$genes$gene_name)
        is.official = TRUE
        if(only.hugo) is.official <- (ngs$genes$gene_name %in% gene.symbol)
        ##orf.genes <- grepl("ORF",ngs$genes$gene_name)
        ##imm.gene <- grepl("^TR_|^IG_",ngs$genes$gene_biotype)
        has.chrloc <- !is.na(ngs$genes$chr_loc)

        keep <- (has.name & is.official & has.chrloc)
        ngs$counts <- ngs$counts[keep,]
        ngs$genes  <- ngs$genes[keep,]        
    }
    
    cat("DBG [pgx-upload] 1: dim(ngs$counts)=",dim(ngs$counts),"\n")
    cat("DBG [pgx-upload] 1: sum.is.na(ngs$counts)=",sum(is.na(ngs$counts)),"\n")
    cat("DBG [pgx-upload] 1: dim(ngs$samples)=",dim(ngs$samples),"\n")
    cat("DBG [pgx-upload] 1: dim(ngs$genes)=",dim(ngs$genes),"\n")

    ##-------------------------------------------------------------------
    ## Pre-calculate t-SNE for and get clusters early so we can use it
    ## for doing differential analysis.
    ##-------------------------------------------------------------------
    if(do.cluster) {
        if(!is.null(progress)) progress$inc(0.01, detail = "clustering")
        perplexity <- max(2,min(30,round(ncol(ngs$counts)/4)))
        perplexity
        ngs <- pgx.clusterSamples(ngs, skipifexists=FALSE, perplexity=perplexity)
        head(ngs$samples)
        table(ngs$samples$cluster)
    }
    
    ##======================================================================
    ##======================================================================
    ##======================================================================

    ## contrast matrix
    contr.matrix <- ngs$contrasts

    ## create groups if not exists
    if(!"group" %in% colnames(ngs$samples)) {
        ct = apply(ngs$samples,2,function(px) mean(px %in% rownames(ngs$contrasts),na.rm=TRUE))
        group.col = which(ct > 0.95)
        if(length(group.col)>0) {
            grp.var = colnames(ngs$samples)[group.col[1]]
            cat(paste0("INFO [pgx-upload] assigning '",grp.var,"' variable as 'group' column\n"))
            ## colnames(ngs$samples)[group.col[1]] <- "group"
            ngs$samples$group <- ngs$samples[,group.col[1]] 
        } else {
            stop("sample annotation file must have 'group' column\n")
        }
    }
    
    ##======================================================================
    ##======================================================================
    ##======================================================================

    ngs$timings <- c()
    
    GENETEST.METHODS = c("ttest","ttest.welch","ttest.rank",
                         "voom.limma","trend.limma","notrend.limma",
                         "edger.qlf","edger.lrt","deseq2.wald","deseq2.lrt")
    GENESETTEST.METHODS = c("fisher","gsva","ssgsea","spearman",
                            "camera", "fry","fgsea") ## no GSEA, too slow...
    
    ## ------------------ gene level tests ---------------------
    if(!is.null(progress)) progress$inc(0.1, detail = "testing genes")
    
    ngs <- compute.testGenes(
        ngs, contr.matrix,
        max.features = max.genes,
        test.methods = gx.methods)
    head(ngs$gx.meta$meta[[1]])        
    
    ## ------------------ gene set tests -----------------------
    if(!is.null(progress)) progress$inc(0.2, detail = "testing gene sets")

    max.features=max.genes;test.methods=gset.methods
    system.time(
        ngs <- compute.testGenesets(
            ngs, max.features = max.genesets,
            test.methods = gset.methods,
            lib.dir = lib.dir )
    )
    head(ngs$gset.meta$meta[[1]])
    
    ## ------------------ extra analyses ---------------------
    if(!is.null(progress)) progress$inc(0.3, detail = "extra modules")
    ##extra <- c("meta.go","deconv","infer","drugs")
    ##extra <- c("meta.go","infer","drugs")
    ngs <- compute.extra(ngs, extra=extra.methods, lib.dir=lib.dir)
    
    ngs$timings
    return(ngs)
}








