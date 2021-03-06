## Workflow for differential expression analysis (at gene level)
##
## Input:  contr.matrix to be defined using group as levels
##
##
##
##
##

SAVE.PARAMS <- ls()

compute.testGenes <- function(ngs, contr.matrix,
                              gene.testmethods=c("trend.limma","deseq2.wald","edger.qlf"),
                              geneset.testmethods=c("gsva","camera","fgsea"),
                              prior.cpm=1, cpm.scaling=1e6)
{
    ## fill me...
    return(ngs)
}


##-----------------------------------------------------------------------------
## Check parameters, decide group level
##-----------------------------------------------------------------------------

if(!("counts" %in% names(ngs))) {
    stop("cannot find counts in ngs object")
}

group = NULL
if( all(rownames(contr.matrix) %in% ngs$samples$group)) {
    cat("testing on groups...\n")
    group = as.character(ngs$samples$group)
}
if( all(rownames(contr.matrix) %in% ngs$samples$cluster)) {
    cat("testing on clusters...\n")
    group = as.character(ngs$samples$cluster)
}
if( all(rownames(contr.matrix) %in% rownames(ngs$samples))) {
    cat("testing on samples...\n")
    group = rownames(ngs$samples)
}

if(is.null(group)) {
    stop("invalid contrast matrix. could not assign groups")
}

table(group)
##dim(contr.matrix)

##-----------------------------------------------------------------------------
## normalize contrast matrix to zero mean and signed sums to one
##-----------------------------------------------------------------------------
contr.matrix[is.na(contr.matrix)] <- 0
contr.matrix0 <- contr.matrix  ## SAVE

## take out any empty comparisons
contr.matrix <- contr.matrix0[,which( colSums(contr.matrix0!=0)>0),drop=FALSE]
for(i in 1:ncol(contr.matrix)) {
    m <- contr.matrix[,i]
    m[is.na(m)] <- 0
    contr.matrix[,i] <- 1*(m>0)/sum(m>0) - 1*(m<0)/sum(m<0)
}
dim(contr.matrix)

##-----------------------------------------------------------------------------
## create design matrix from defined contrasts (group or clusters)
##-----------------------------------------------------------------------------

no.design <- all(group %in% rownames(ngs$samples))  ## sample-wise design
no.design
design=NULL

if(no.design) {
    ## SAMPLE-WISE DESIGN
    design=NULL
    exp.matrix <- contr.matrix
} else {
    ## GROUP DESIGN
    ##group[is.na(group)] <- "_"
    group[which(!group %in% rownames(contr.matrix))] <- "_"
    design <- model.matrix(~ 0 + group )  ## clean design no batch effects...
    colnames(design) <- gsub("group", "", colnames(design))
    rownames(design) <- colnames(ngs$counts)
    design

    ## check contrasts for sample sizes (at least 2 in each group) and
    ## remove otherwise
    design <- design[,match(rownames(contr.matrix),colnames(design))]
    colnames(design)
    design = design[,rownames(contr.matrix)]
    exp.matrix = (design %*% contr.matrix)
    keep <- rep(TRUE,ncol(contr.matrix))
    keep = (colSums(exp.matrix > 0) >= 1 & colSums(exp.matrix < 0) >= 1)
    ##keep = ( colSums(exp.matrix > 0) >= 2 & colSums(exp.matrix < 0) >= 2 )
    table(keep)
    contr.matrix = contr.matrix[,keep,drop=FALSE]
    exp.matrix = (design %*% contr.matrix)
}

##xfit = cpm$counts  ## gets used later!!!
##xfit = normalizeQuantiles(xfit)
##vfit <- lmFit( log2(1 + ngs$counts), design)
##efit <- eBayes(contrasts.fit(vfit, contrasts=contr.matrix), trend=TRUE)
model.parameters <- list(design=design, contr.matrix=contr.matrix, ## efit=efit,
                         exp.matrix=exp.matrix)

##-----------------------------------------------------------------------------
## Filter genes
##-----------------------------------------------------------------------------

## get *RAW* counts but use filtered probes from cooked
counts = ngs$counts  ##??
genes  = ngs$genes
samples = ngs$samples

## prefiltering for low-expressed genes (recommended for edgeR and
## DEseq2). Require at least in 2 or 1% of total
if(0) {
    x <- edgeR::cpm(counts[counts>0])
    hist(log2(1e-8+x), breaks=100)
    q0 <- quantile(x, probs=c(0.01,0.10))
    q0
    abline(v=log2(q0),col="red",lty=2)
    hist(log2(x/q0[1]+1), breaks=100)
}


## Specify the PRIOR CPM amount to regularize the counts and filter genes
PRIOR.CPM = 0.25
PRIOR.CPM = 1
AT.LEAST = ceiling(pmax(2,0.01*ncol(counts)))

cat("filtering for low-expressed genes: >",PRIOR.CPM,"CPM in >=",AT.LEAST,"samples\n")
keep <- (rowSums( edgeR::cpm(counts) > PRIOR.CPM) >= AT.LEAST)
##keep <- edgeR::filterByExpr(counts)  ## default edgeR filter
ngs$filtered <- NULL
ngs$filtered[["low.expressed"]] <- paste(rownames(counts)[which(!keep)],collapse=";")
table(keep)
counts <- counts[which(keep),,drop=FALSE]
genes <- genes[which(keep),,drop=FALSE]
cat("filtering out",sum(!keep),"low-expressed genes\n")
cat("keeping",sum(keep),"expressed genes\n")

##-----------------------------------------------------------------------------
## Shrink number of genes before testing
##-----------------------------------------------------------------------------
if(!exists("MAX.GENES")) MAX.GENES <- -1
if(MAX.GENES > 0 && nrow(counts) > MAX.GENES) {
    cat("shrinking data matrices: n=",MAX.GENES,"\n")
    ##avg.prior.count <- mean(PRIOR.CPM * Matrix::colSums(counts) / 1e6)  ##
    ##logcpm = edgeR::cpm(counts, log=TRUE, prior.count=avg.prior.count)
    logcpm <- log2( PRIOR.CPM + edgeR::cpm(counts, log=FALSE))
    sdx <- apply(logcpm,1,sd)
    jj <- head( order(-sdx), MAX.GENES )  ## how many genes?
    ## always add immune genes??
    if("gene_biotype" %in% colnames(genes)) {
        imm.gene <- grep("^TR_|^IG_",genes$gene_biotype)
        imm.gene <- imm.gene[which(sdx[imm.gene] > 0.001)]
        jj <- unique(c(jj,imm.gene))
    }
    jj0 <- setdiff(1:nrow(counts),jj)
    ##ngs$filtered[["low.variance"]] <- NULL
    ngs$filtered[["low.variance"]] <- paste(rownames(counts)[jj0],collapse=";")
    counts <- counts[jj,]
    genes <- genes[jj,]
}
head(genes)
genes  = genes[,c("gene_name","gene_title")]
dim(counts)

##-----------------------------------------------------------------------------
## Do the fitting
##-----------------------------------------------------------------------------
## Select test methods
##
all.methods=c("ttest","ttest.welch","voom.limma","trend.limma","notrend.limma",
              "edger.qlf","edger.lrt","deseq2.wald","deseq2.lrt")
methods=c("trend.limma","edger.qlf","deseq2.wald")
if(ncol(counts)>500) methods=c("trend.limma","edger.qlf","edger.lrt")
methods
if(!is.null(USER.GENETEST.METHODS)) methods = USER.GENETEST.METHODS
if(methods[1]=="*") methods = all.methods

cat(">>> Testing differential expressed genes (DEG) with methods:",methods,"\n")

## Run all test methods
##
gx.meta <- ngs.fitContrastsWithAllMethods(
    X=counts, samples=samples, genes=NULL, ##genes=genes,
    methods=methods, design=design,
    contr.matrix=contr.matrix,
    prior.cpm=PRIOR.CPM,  ## prior count regularization
    ##cpm.scale=1e7,  ## total count scaling for logCPM only
    ##quantile.normalize=FALSE,  ## really? please compare
    quantile.normalize=TRUE,  ## only for logCPM
    remove.batch=FALSE,  ## we do explicit batch correction instead
    conform.output=TRUE, do.filter=FALSE,
    custom=NULL, custom.name=NULL )

names(gx.meta)
names(gx.meta$outputs)
names(gx.meta$outputs[[1]])
names(gx.meta$outputs[[1]][[1]])

print(gx.meta$timings)

##--------------------------------------------------------------------------------
## set default matrices
##--------------------------------------------------------------------------------

rownames(gx.meta$timings) <- paste0("[testgenes]",rownames(gx.meta$timings))
ngs$timings <- rbind(ngs$timings, gx.meta$timings)
ngs$X = gx.meta$X
##ngs$genes = ngs$genes[rownames(ngs$X),]
##ngs$Y = ngs$samples[colnames(ngs$X),]
ngs$model.parameters <- model.parameters
ngs$gx.meta <- gx.meta

## remove large outputs... (uncomment if needed!!!)
ngs$gx.meta$outputs <- NULL

## ---------- clean up ----------------
contr.matrix <- contr.matrix0  ## RESTORE
rm(list=setdiff(ls(),SAVE.PARAMS))
