##rm(list=setdiff(ls(),run.param))
library(knitr)
library(limma)
library(edgeR)
library(RColorBrewer)
library(gplots)
library(matrixTests)
library(kableExtra)
library(knitr)

RDIR = "../R"
FILES = "../lib"
source("../R/pgx-include.R")

##source("options.R")
MAX.GENES = 8000
MAX.GENESETS = 8000
BATCH.CORRECT=TRUE
SUBSAMPLE=TRUE

## run all available methods 
GENETEST.METHODS=c("ttest.welch","trend.limma","edger.qlf","deseq2.wald")
##USER.GENETEST.METHODS=c("ttest","ttest.welch","ttest.rank","trend.limma")
GENESETTEST.METHODS = c("fisher","gsva","camera","fgsea")

rda.file="../data/GSE10846-dlbcl2.pgx"
rda.file

##load(file=rda.file, verbose=1)
ngs <- list()  ## empty object
ngs$name = gsub("^.*/|[.]pgx$","",rda.file)
ngs$datatype = "mRNA (microarray)"
ngs$description = "GSE10846 data set (Lenz et al, 2008). The retrospective study included 181 clinical samples from CHOP-treated patients and 233 clinical samples from Rituximab-CHOP-treated patients. DLBCL has ABC and GCB subtypes."

## READ/PARSE DATA
if(PROCESS.DATA) {

    ## ##############################################################
    ##   Differential expression analysis with limma
    if(0) {
        BiocManager::install("hgu133plus2.db")
        BiocManager::install("GEOquery")
    }
    library(Biobase)
    library(GEOquery)
    library(limma)
    library(hgu133plus2.db)
    
    ## load series and platform data from GEO
    gset <- getGEO("GSE10846", GSEMatrix =TRUE, AnnotGPL=TRUE)
    length(gset)
    attr(gset, "names")

    pdata = pData(gset[[1]])
    head(pdata)
    clinvar <- pdata[,grep(":ch1$",colnames(pdata))]
    head(clinvar)

    sampleTable <- data.frame(pdata[,0])
    sampleTable$dlbcl.type = gsub(".*:","",pdata[,"characteristics_ch1.6"])
    sampleTable$dlbcl.type <- sub("NA","not.specified",sampleTable$dlbcl.type)
    sampleTable$dlbcl.type <- sub(".DLBCL$","",sampleTable$dlbcl.type)
    sampleTable$gender = gsub(".*:","",pdata[,"Gender:ch1"])
    sampleTable$age = gsub(".*:","",pdata[,"Age:ch1"])
    sampleTable$LDH.ratio = gsub(".*:","",pdata[,"characteristics_ch1.12"])
    sampleTable$Chemotherapy = gsub(".*:","",pdata[,"characteristics_ch1.9"])
    sampleTable$OS.status = gsub(".*:","",pdata[,"characteristics_ch1.7"])
    sampleTable$OS.years  = gsub(".*:","",pdata[,"characteristics_ch1.8"])
    sampleTable <- apply(sampleTable,2,function(s) gsub("^ ","",s))
    sampleTable <- apply(sampleTable,2,function(s) gsub("[ ]",".",s))
    sampleTable <- data.frame(sampleTable)
    ##sampleTable$treatment <- as.character(sampleTable$Chemotherapy)
    ##sampleTable$group <- sampleTable$dlbcl.type
    table(sampleTable$Chemotherapy)
    ##table(sampleTable$treatment)

    sampleTable$Chemotherapy = gsub("-Like.Regimen","",sampleTable$Chemotherapy)
    sampleTable$Chemotherapy <- sub("NA",NA,as.character(sampleTable$Chemotherapy))
    head(sampleTable)
    
    ## merge data sets
    X = exprs(gset[[1]])
    max(X)  ## check max for checking logarithm
    X = X[order(-apply(X,1,sd)),]
    dim(X)

    ## convert affymetrix ID to GENE symbol
    affx  = sapply(as.list(hgu133plus2SYMBOL),"[[",1)
    symbol = affx[rownames(X)]
    hugo = alias2hugo(symbol)
    rownames(X) = symbol
    X = X[which(!duplicated(symbol) & !is.na(symbol) & symbol!=""),]
    dim(X)
    X = X[which(rowMeans(is.na(X))==0), ]  ## no missing values
    sum(is.na(X))
    dim(X)

    ## conform tables
    table(rownames(sampleTable) == colnames(X))
    ##-------------------------------------------------------------------
    ## sample QC filtering
    ##-------------------------------------------------------------------
    kk <- which( !is.na(sampleTable$Chemotherapy) &
                sampleTable$dlbcl.type %in% c("ABC","GCB") )
    length(kk)
    sampleTable <- sampleTable[kk,]
    sampleTable$dlbcl.type <- as.character(sampleTable$dlbcl.type)
    X  <- X[,kk]
    dim(X)

    ##-------------------------------------------------------------------
    ## subsample???
    ##-------------------------------------------------------------------
    if(SUBSAMPLE) {
        ##kk <- c( sample(which(sampleTable$dlbcl.type=="ABC"),80),
        ##        sample(which(sampleTable$dlbcl.type=="GCB"),80) )
        kk <- c( head(which(sampleTable$dlbcl.type=="ABC"),80),
                head(which(sampleTable$dlbcl.type=="GCB"),80) )
        length(kk)
        X  <- X[,kk]
        sampleTable <- sampleTable[colnames(X),]
        dim(X)
    }

    ##-------------------------------------------------------------------
    ## gene annotation
    ##-------------------------------------------------------------------
    require(org.Hs.eg.db)
    GENE.TITLE = unlist(as.list(org.Hs.egGENENAME))
    gene.symbol = unlist(as.list(org.Hs.egSYMBOL))
    names(GENE.TITLE) = gene.symbol
    head(GENE.TITLE)
    gene_title <- GENE.TITLE[rownames(X)]

    ## get chromosome locations
    chrloc = as.list(org.Hs.egCHRLOC)
    names(chrloc) = gene.symbol
    chrloc <- chrloc[rownames(X)]
    loc <- abs(sapply(chrloc, "[", 1))
    chrom <- sapply(chrloc, function(s) names(s)[1])
    chrom[sapply(chrom,is.null)] <- NA
    chrom <- as.vector(unlist(chrom))

    genes = data.frame( gene_name=rownames(X),
                       gene_title=gene_title,
                       chr=chrom, pos=loc)
    ##genes = apply(genes,2,as.character)
    head(genes)
    rownames(genes) = rownames(X)

    ##--------------------------------------------------------------------
    ## check if batch correction is needed
    ##--------------------------------------------------------------------
    BATCH.CORRECT
    if(BATCH.CORRECT) {
        require(sva)
        batch <- sampleTable$Chemotherapy
        design = model.matrix( ~ as.character(sampleTable$dlbcl.type))
        ##bX = ComBat(X, batch=as.character(batch), mod=design)
        bX = removeBatchEffect(X, batch=as.character(batch),
                               ##batch2=as.character(sampleTable$gender),
                               design=design)
        X = normalizeQuantiles(bX)
    }
    
    ##-------------------------------------------------------------------
    ## Now create an DGEList object  (see tximport Vignette)
    ##-------------------------------------------------------------------
    ngs$counts <- as.matrix(2**X)  ## treat as counts
    ngs$samples <- sampleTable
    ngs$genes = genes
    ##lib.size <- colSums(data$counts / 1e6)  ## get original summed intensity as lib.size
    ##ngs$samples$batch <- NULL  ##???
    ##ngs$samples$batch <- as.integer(lib.size2)

    ## tagged rownames
    ##row.id = paste0("tag",1:nrow(ngs$genes),":",ngs$genes[,"gene_name"])  
    row.id = ngs$genes[,"gene_name"]
    rownames(ngs$genes) = rownames(ngs$counts) = row.id
    names(ngs)

    ##-------------------------------------------------------------------
    ## collapse multiple row for genes by summing up counts
    ##-------------------------------------------------------------------
    sum(duplicated(ngs$genes$gene_name))

    ## x1 = apply(ngs$counts, 2, function(x) tapply(x, ngs$genes$gene_name, sum))
    ## ngs$genes = ngs$genes[match(rownames(x1),ngs$genes$gene_name),]
    ## ngs$counts = x1
    ## dim(x1)
    ## rownames(ngs$genes) = rownames(ngs$counts) = rownames(x1)
    ## remove(x1)
    ngs <- ngs.collapseByGene(ngs)
    dim(ngs$counts)
        
    ##-------------------------------------------------------------------
    ## Pre-calculate t-SNE for and get clusters early so we can use it
    ## for doing differential analysis.
    ##-------------------------------------------------------------------
    ngs <- pgx.clusterSamples( ngs, skipifexists=FALSE, prefix="C",
                              clust.detect="hclust", kclust=3)
    table(ngs$samples$cluster)    

}


if(DIFF.EXPRESSION) {

    ##load(file=rda.file, verbose=1)
    
    head(ngs$samples)
    ngs$samples$group <- as.character(ngs$samples$dlbcl.type)
    levels = unique(ngs$samples$group)
    levels

    contr.matrix <- makeContrasts(
        ABC_vs_GCB = ABC - GCB,
        GCB_vs_ABC = GCB - ABC,
        levels = c("ABC","GCB"))
    
    res <- makeDirectContrasts2(
        Y = ngs$samples[,c("dlbcl.type","gender","cluster")],
        ref = c("GCB","male",NA))
    contr.matrix <- res$contr.matrix
    ngs$samples$group <- res$group
    table(res$group)

    dim(contr.matrix)
    head(contr.matrix)
    colnames(contr.matrix) <- sub(".*:","",colnames(contr.matrix))  ## strip prefix 
    head(contr.matrix)
        
    ## new callling methods
    ngs <- compute.testGenes(
        ngs, contr.matrix,
        max.features = MAX.GENES,
        test.methods = GENETEST.METHODS)
    head(ngs$gx.meta$meta[[1]])        
    
    ngs <- compute.testGenesets(
        ngs, max.features = MAX.GENESETS,
        test.methods = GENESETTEST.METHODS,
        lib.dir = FILES)
    head(ngs$gset.meta$meta[[1]])

    extra <- c("wordcloud")
    extra <- c("meta.go","deconv","infer","drugs","wordcloud")
    ngs <- compute.extra(ngs, extra, lib.dir=FILES) 

}

## save
rda.file
ngs.save(ngs, file=rda.file)









