if(0) {

    sigdb = "../data/datasets-allFC.csv"
    h5.file = "../data/sigdb-gse25k.h5"
    FILES="../lib"
    RDIR="../R"
    source("../R/pgx-include.R")
    source("../R/pgx-files.R")

    gmt.files = dir("~/Projects/Data/Creeds","gmt$",full.names=TRUE)
    gmt.files = dir("../../Data/Creeds","gmt$",full.names=TRUE)
    h5.file = "../lib/sigdb-creeds.h5.test"
    h5.file = "../lib/sigdb-creeds.h5"

    fc <- ngs$gx.meta$meta[[1]]$meta.fx
    names(fc) <- rownames(ngs$gx.meta$meta[[1]])

}

pgx.computeConnectivityScores <- function(ngs, sigdb, ntop=1000, contrasts=NULL)
{
    require(rhdf5)
    meta = pgx.getMetaFoldChangeMatrix(ngs, what="meta")
    colnames(meta$fc)
    
    is.h5ref <- grepl("h5$",sigdb)       
    ##cat("[calcConnectivityScores] sigdb =",sigdb,"\n")
    ##cat("[calcConnectivityScores] ntop =",ntop,"\n")
    h5.file <- NULL
    refmat <- NULL
    if(grepl("csv$",sigdb)) {
        refmat <- read.csv(sigdb,row.names=1,check.names=FALSE)
        dim(refmat)
    }
    if(grepl("h5$",sigdb)) {
        if(file.exists(sigdb)) h5.file <- sigdb
    }
    
    if(is.null(contrasts)) {
        contrasts <- colnames(meta$fc)
    }
    contrasts <- intersect(contrasts, colnames(meta$fc))

    scores <- list()
    ct <- contrasts[1]
    for(ct in contrasts) {
        
        fc <- meta$fc[,ct]
        names(fc) <- rownames(meta$fc)
        names(fc) <- toupper(names(fc)) ## for mouse
        
        h5.file
        if(!is.null(h5.file))  {
            res <- pgx.correlateSignatureH5(
                fc, h5.file = h5.file,
                nsig=100, ntop=ntop, nperm=9999)            

        } else if(!is.null(refmat)) {                
            res <- pgx.correlateSignature(
                fc, refmat = refmat,
                nsig=100, ntop=ntop, nperm=9999)
            
        } else {
            stop("FATAL:: could not determine reference type")
        }
        dim(res)
        scores[[ct]] <- res
    }

    names(scores)
    return(scores)
}


## ntop=1000;nsig=100;nperm=10000
pgx.correlateSignature <- function(fc, refmat, nsig=100, ntop=1000, nperm=10000)
{
    ##
    ##
    ##
    ##
    
    if(is.null(names(fc))) stop("fc must have names")

    ## mouse... mouse...
    names(fc) <- toupper(names(fc))
    
    ## or instead compute correlation on top100 fc genes (read from file)
    ##refmat = PROFILES$FC
    rn <- rownames(refmat)
    cn <- colnames(refmat)
    
    ## ---------------------------------------------------------------
    ## Compute simple correlation between query profile and signatures
    ## ---------------------------------------------------------------
    gg <- intersect(rn, names(fc))
    fc1 <- sort(fc[gg])
    gg <- unique(names(c(head(fc1,nsig), tail(fc1,nsig))))
    ##gg <- intersect(names(fc),rn)
    ##gg <- intersect(gg,rn)
    G  <- refmat[gg,,drop=FALSE]
    dim(G)

    ## rank correlation??
    rG  <- apply( G[gg,], 2, rank, na.last="keep" )
    rfc <- rank( fc[gg], na.last="keep" )
    ##rho <- cor(rG, rfc, use="pairwise")[,1]

    rG[is.na(rG)] <- 0  ## NEED RETHINK: are missing values to be treated as zero???
    rfc[is.na(rfc)] <- 0
    rho <- cor(rG, rfc, use="pairwise")[,1]
    
    remove(G,rG,rfc)
        
    ## --------------------------------------------------
    ## test all signature on query profile using fGSEA
    ## --------------------------------------------------
    
    require(fgsea)
    sel <- head(names(sort(-abs(rho))),ntop)
    
    notx <- setdiff(sel,colnames(refmat))
    if(length(notx)>0) {
        ## should not happen...   
        cat("[pgx.correlateSignature] length(sel)=",length(sel),"\n")
        cat("[pgx.correlateSignature] head(sel)=",head(sel),"\n")
        cat("[pgx.correlateSignature] head.notx=",head(notx),"\n")
    }

    sel <- intersect(sel, colnames(refmat))  
    X <- refmat[,sel,drop=FALSE]
    dim(X)
    X[is.na(X)] <- 0
    orderx <- apply(X,2,function(x) {
        idx=order(x);
        list(DN=head(idx,100),UP=rev(tail(idx,100)))
    })    
    sig100.dn <- sapply(orderx,"[[","DN")
    sig100.dn <- apply(sig100.dn, 2, function(i) rn[i])
    sig100.up <- sapply(orderx,"[[","UP")
    sig100.up <- apply(sig100.up, 2, function(i) rn[i])
    dim(sig100.dn)

    ## ---------------------------------------------------------------    
    ## combine up/down into one (unsigned GSEA test)
    ## ---------------------------------------------------------------
    gmt <- rbind(sig100.up, sig100.dn)
    gmt <- unlist(apply(gmt, 2, list),recursive=FALSE)
    names(gmt) <- colnames(X)
    length(gmt)
    
    ##system.time( res <- fgsea(gmt, fc, nperm=10000))
    suppressMessages( suppressWarnings(
        res <- fgsea(gmt, abs(fc), nperm=nperm)
    ))
    dim(res)
            
    ## ---------------------------------------------------------------
    ## Combine correlation+GSEA by combined score (NES*rho)
    ## ---------------------------------------------------------------
    jj <- match(res$pathway, names(rho))
    res$rho <- rho[jj]
    res$R2 <- rho[jj]**2
    res$score <- res$R2*res$NES
    res <- res[order(res$score, decreasing=TRUE),]

    if(0) {
        res$rho.p <- cor.pvalue(res$rho, n=length(gg))
        res$meta.p  <- apply( res[,c("pval","rho.p")], 1, function(p) sumz(p)$p)    
        res <- res[order(res$meta.p),]
    }
    
    head(res)
    return(res)
}

##ntop=1000;nsig=100;nperm=10000
pgx.correlateSignatureH5 <- function(fc, h5.file, nsig=100, ntop=1000, nperm=10000)
{
    ##
    ##
    ##
    ##
    require(rhdf5)
    
    if(is.null(names(fc))) stop("fc must have names")    
    ## mouse... mouse...
    names(fc) <- toupper(names(fc))

    ## or instead compute correlation on top100 fc genes (read from file)
    rn <- h5read(h5.file,"data/rownames")
    cn <- h5read(h5.file,"data/colnames")

    ## ---------------------------------------------------------------
    ## Compute simple correlation between query profile and signatures
    ## ---------------------------------------------------------------
    gg <- intersect(names(fc),rn)
    fc1 <- sort(fc[gg])
    gg <- unique(names(c(head(fc1,nsig), tail(fc1,nsig))))
    ## gg <- intersect(gg,rn)
    row.idx <- match(gg,rn)
    G <- h5read(h5.file, "data/matrix", index=list(row.idx,1:length(cn)))
    dim(G)
    ##head(G[,1])
    G[which(G < -999999)] <- NA
    ##G[is.na(G)] <- 0  ## NEED RETHINK: are missing values to be treated as zero???
    dim(G)    
    dimnames(G) <- list(rn[row.idx],cn)

    ## rank correlation??
    rG  <- apply( G[gg,], 2, rank, na.last="keep" )
    rfc <- rank( fc[gg], na.last="keep" )
    ##rho <- cor(rG, rfc, use="pairwise")[,1]
    rG[is.na(rG)] <- 0  ## NEED RETHINK: are missing values to be treated as zero???
    rfc[is.na(rfc)] <- 0
    rho <- cor(rG, rfc, use="pairwise")[,1]
    
    remove(G,rG,rfc)
    
    ## --------------------------------------------------
    ## test tops signatures using fGSEA
    ## --------------------------------------------------
    
    require(fgsea)
    sel <- head(names(sort(-abs(rho))), ntop)
    sel.idx <- match(sel, cn)
    sig100.up <- h5read(h5.file, "signature/sig100.up",
                        index = list(1:100, sel.idx) )
    sig100.dn <- h5read(h5.file, "signature/sig100.dn",
                        index = list(1:100, sel.idx) )                        
    ##head(sig100.up,2)    

    ## combine up/down into one (unsigned GSEA test)
    gmt <- rbind(sig100.up, sig100.dn)
    gmt <- unlist(apply(gmt, 2, list),recursive=FALSE)
    names(gmt) <- cn[sel.idx]
    length(gmt)
    
    ##system.time( res <- fgsea(gmt, fc, nperm=10000))
    system.time( res <- fgsea(gmt, abs(fc), nperm=nperm))  ## really unsigned???
    dim(res)
            
    ## ---------------------------------------------------------------
    ## Combine correlation+GSEA by combined score (NES*rho)
    ## ---------------------------------------------------------------
    jj <- match( res$pathway, names(rho))
    res$rho  <- rho[jj]
    res$R2 <- rho[jj]**2
    res$score <- res$R2*res$NES
    res <- res[order(res$score, decreasing=TRUE),]

    if(0) {
        res$rho.p <- cor.pvalue(res$rho, n=length(gg))
        res$meta.p  <- apply( res[,c("pval","rho.p")], 1, function(p) sumz(p)$p)    
        res <- res[order(res$meta.p),]
    }
    
    head(res)
    return(res)
}


chunk=100
pgx.createCreedsSigDB <- function(gmt.files, h5.file, update.only=FALSE)
{
    require(rhdf5)
    h5exists <- function(h5.file, obj) {
        xobjs <- apply(h5ls(h5.file)[,1:2],1,paste,collapse="/")
        obj %in% gsub("^/|^//","",xobjs)
    }

    if(update.only && h5exists(h5.file, "data/matrix")) {
        X  <- h5read(h5.file, "data/matrix")
        rn <- h5read(h5.file,"data/rownames")
        cn <- h5read(h5.file,"data/colnames")
        rownames(X) <- rn
        colnames(X) <- cn
    } else {
        ##--------------------------------------------------
        ## make big FC signature matrix
        ##--------------------------------------------------
        F <- list()
        sig100.dn <- list()
        sig100.up <- list()
        cat("reading gene lists from",length(gmt.files),"gmt files ")
        i=1
        for(i in 1:length(gmt.files)) {
            if(!file.exists(gmt.files[i])) next()
            cat(".")
            try.error <- try( gmt <- read.gmt(gmt.files[i], add.source=TRUE) )
            if(class(try.error)=="try-error") next()
            ##gmt <- head(gmt,30)  ## ONLY FOR TESTING
            
            j1 <- grep("-up ", names(gmt))
            j2 <- grep("-dn ", names(gmt))
            f1 <- lapply( gmt[j1], function(gg) {x=length(gg):1;names(x)=gg;x})
            f2 <- lapply( gmt[j2], function(gg) {x=-length(gg):-1;names(x)=gg;x})

            s1 <- gmt[j1]
            s2 <- gmt[j2]

            ff <- lapply(1:length(f1),function(i) c(f1[[i]],f2[[i]]))
            sig.names <- sub("-up","",names(f1))
            prefix <- gsub(".*/|single_|_perturbations|.gmt|_signatures","",gmt.files[i])
            sig.names <- paste0("[CREEDS:",prefix,"] ",sig.names)
            
            names(s1) <- names(s2) <- names(ff) <- sig.names
            sig100.up <- c(sig100.up, s1)
            sig100.dn <- c(sig100.dn, s2)
            F <- c(F, ff)
        }
        cat("\n")

        genes <- as.vector(unlist(sapply(F[],names)))
        genes <- sort(unique(toupper(genes)))
        length(genes)    

        ## Filter out genes (not on known chromosomes...)
        gannot <- ngs.getGeneAnnotation(genes)
        table(!is.na(gannot$chr))
        sel <- which(!is.na(gannot$chr))
        genes <- sort(genes[sel])

        X <- lapply(F, function(x) x[match(genes,names(x))])
        X <- do.call(cbind, X)
        dim(X)
        rownames(X) <- genes    
        remove(F)
        
        h5.file
        pgx.saveMatrixH5(X, h5.file, chunk=c(nrow(X),1))
        
        na100 <- rep(NA,100)
        msig100.up <- sapply(sig100.up, function(g) head(c(intersect(g,genes),na100),100))
        msig100.dn <- sapply(sig100.dn, function(g) head(c(intersect(g,genes),na100),100))

        if(!h5exists(h5.file, "signature")) h5createGroup(h5.file,"signature")    
        h5write( msig100.up, h5.file, "signature/sig100.up")  ## can write list??
        h5write( msig100.dn, h5.file, "signature/sig100.dn")  ## can write list???    
        remove(sig100.up,sig100.dn,msig100.up,msig100.dn)

        ## check NA!!! sometimes it is set to large negative
        if(1) {

            h5ls(h5.file)
            X  <- h5read(h5.file, "data/matrix")
            head(X[,1])
            X[which(X < -999999)] <- NA
            head(X[,1])
            dim(X)
            h5write( X, h5.file, "data/matrix")  ## can write list??
            h5closeAll()
        }        

    }
    dim(X)
    
    
    ##--------------------------------------------------
    ## Precalculate t-SNE/UMAP
    ##--------------------------------------------------

    if(!update.only || !h5exists(h5.file, "clustering")) {

        X[is.na(X)] <- 0
        pos <- pgx.clusterBigMatrix(
            abs(X),  ## on absolute foldchange!!
            methods=c("pca","tsne","umap"),
            dims=c(2,3),
            reduce.sd = 2000,
            reduce.pca = 200 )
        names(pos)
        
        if(!h5exists(h5.file, "clustering")) h5createGroup(h5.file,"clustering")    
        h5ls(h5.file)
        h5write( pos[["pca2d"]], h5.file, "clustering/pca2d")  
        h5write( pos[["pca3d"]], h5.file, "clustering/pca3d")  
        h5write( pos[["tsne2d"]], h5.file, "clustering/tsne2d") 
        h5write( pos[["tsne3d"]], h5.file, "clustering/tsne3d") 
        h5write( pos[["umap2d"]], h5.file, "clustering/umap2d") 
        h5write( pos[["umap3d"]], h5.file, "clustering/umap3d") 
        
    }

    h5closeAll()
    ## return(X)

    ## check NA!!! sometimes it is set to large negative
    if(0) {
        h5ls(h5.file)
        X  <- h5read(h5.file, "data/matrix")
        head(X[,1])
        ##X[which(X < -999999)] <- NA
        ##head(X[,1])
        ##h5write( X, h5.file, "data/matrix")  ## can write list??
        ##h5closeAll()
    }        

}

pgx.createSignatureDatabaseH5 <- function(pgx.files, h5.file, update.only=FALSE)
{
    require(rhdf5)

    h5exists <- function(h5.file, obj) {
        xobjs <- apply(h5ls(h5.file)[,1:2],1,paste,collapse="/")
        obj %in% gsub("^/|^//","",xobjs)
    }

    if(update.only && h5exists(h5.file, "data/matrix")) {
        X  <- h5read(h5.file, "data/matrix")
        rn <- h5read(h5.file,"data/rownames")
        cn <- h5read(h5.file,"data/colnames")
        rownames(X) <- rn
        colnames(X) <- cn
    } else {
        ##--------------------------------------------------
        ## make big FC signature matrix
        ##--------------------------------------------------
        F <- list()
        cat("reading FC from",length(pgx.files),"pgx files ")
        i=1
        for(i in 1:length(pgx.files)) {
            if(!file.exists(pgx.files[i])) next()
            cat(".")
            try.error <- try( load(pgx.files[i], verbose=0) )
            if(class(try.error)=="try-error") next()
            meta <- pgx.getMetaFoldChangeMatrix(ngs, what="meta")
            rownames(meta$fc) <- toupper(rownames(meta$fc))  ## mouse-friendly
            pgx <- gsub(".*[/]|[.]pgx$","",pgx.files[i])
            colnames(meta$fc) <- paste0("[",pgx,"] ",colnames(meta$fc))
            F[[ pgx ]] <- meta$fc    
        }
        cat("\n")
        
        genes <- as.vector(unlist(sapply(F,rownames)))
        genes <- sort(unique(toupper(genes)))
        length(genes)    
        F <- lapply(F, function(x) x[match(genes,rownames(x)),,drop=FALSE])
        X <- do.call(cbind, F)
        rownames(X) <- genes    

        ## Filter out genes (not on known chromosomes...)
        genes <- rownames(X)
        gannot <- ngs.getGeneAnnotation(genes)
        table(is.na(gannot$chr))
        sel <- which(!is.na(gannot$chr))
        X <- X[sel,,drop=FALSE]
        dim(X)

        pgx.saveMatrixH5(X, h5.file, chunk=c(nrow(X),1))

        if(0) {
            h5ls(h5.file)
            h5write( X, h5.file, "data/matrix")  ## can write list??
            h5write( colnames(X), h5.file,"data/colnames")
            h5write( rownames(X), h5.file,"data/rownames")
        }        
        remove(F)
    }
    dim(X)
    
    ##--------------------------------------------------
    ## Calculate top100 gene signatures
    ##--------------------------------------------------
    cat("Creating top-100 signatures...\n")
    
    if(!update.only || !h5exists(h5.file, "signature")) {
        ## X  <- h5read(h5.file, "data/matrix")
        rn <- h5read(h5.file,"data/rownames")
        cn <- h5read(h5.file,"data/colnames")
        h5ls(h5.file)
        
        dim(X)
        ##X <- X[,1:100]
        X[is.na(X)] <- 0
        orderx <- apply(X,2,function(x) {
            idx=order(x);
            list(DN=head(idx,100),UP=rev(tail(idx,100)))
        })    
        sig100.dn <- sapply(orderx,"[[","DN")
        sig100.dn <- apply(sig100.dn, 2, function(i) rn[i])
        sig100.up <- sapply(orderx,"[[","UP")
        sig100.up <- apply(sig100.up, 2, function(i) rn[i])
        
        if(!h5exists(h5.file, "signature")) h5createGroup(h5.file,"signature")    
        h5write( sig100.dn, h5.file, "signature/sig100.dn")  ## can write list???    
        h5write( sig100.up, h5.file, "signature/sig100.up")  ## can write list??
        
        remove(orderx)
        remove(sig100.dn)
        remove(sig100.up)
    }
    
    ##--------------------------------------------------
    ## Precalculate t-SNE/UMAP
    ##--------------------------------------------------
    dim(X)

    if(!update.only || !h5exists(h5.file, "clustering")) {
        
        if(!h5exists(h5.file, "clustering")) h5createGroup(h5.file,"clustering")    
        h5ls(h5.file)
        
        pos <- pgx.clusterBigMatrix(
            abs(X),  ## on absolute foldchange!!
            methods=c("pca","tsne","umap"),
            dims=c(2,3),
            reduce.sd = 2000,
            reduce.pca = 200 )
        names(pos)
        
        h5write( pos[["pca2d"]], h5.file, "clustering/pca2d")  ## can write list??    
        h5write( pos[["pca3d"]], h5.file, "clustering/pca3d")  ## can write list??    
        h5write( pos[["tsne2d"]], h5.file, "clustering/tsne2d")  ## can write list??    
        h5write( pos[["tsne3d"]], h5.file, "clustering/tsne3d")  ## can write list??    
        h5write( pos[["umap2d"]], h5.file, "clustering/umap2d")  ## can write list??    
        h5write( pos[["umap3d"]], h5.file, "clustering/umap3d")  ## can write list??            

    }

    h5closeAll()
    ## return(X)
}

##mc.cores=24;lib.dir=FILES
pgx.addEnrichmentSignaturesH5 <- function(h5.file, X=NULL, mc.cores=4, lib.dir,
                                          methods = c("gsea","gsva") ) 
{
    require(rhdf5)
    
    h5exists <- function(h5.file, obj) {
        xobjs <- apply(h5ls(h5.file)[,1:2],1,paste,collapse="/")
        obj %in% gsub("^/|^//","",xobjs)
    }

    if(is.null(X)) {
        X  <- h5read(h5.file, "data/matrix")
        rn <- h5read(h5.file,"data/rownames")
        cn <- h5read(h5.file,"data/colnames")
        rownames(X) <- rn
        colnames(X) <- cn
        X[which(X < -999999)] <- NA
    }

    ##sig100.dn <- h5read(h5.file, "signature/sig100.dn")  
    ##sig100.up <- h5read(h5.file, "signature/sig100.up")  
    
    G <- readRDS(file.path(lib.dir,"gset-sparseG-XL.rds"))
    dim(G)    
    sel <- grep("HALLMARK|C[1-9]|^GO", rownames(G))
    sel <- grep("HALLMARK", rownames(G))
    sel <- grep("HALLMARK|KEGG", rownames(G))
    length(sel)

    G <- G[sel,,drop=FALSE]
    gmt <- apply( G, 1, function(x) colnames(G)[which(x!=0)])
    ##X <- X[,1:20]
    ##X[is.na(X)] <- 0

    if(!h5exists(h5.file, "enrichment")) {
        h5createGroup(h5.file,"enrichment")
    }
    if(h5exists(h5.file, "enrichment/genesets")) {
        h5delete(h5.file, "enrichment/genesets")
    }
    h5write(names(gmt), h5.file, "enrichment/genesets")

    if("gsea" %in% methods) {
        cat("[pgx.addEnrichmentSignaturesH5] starting fGSEA for",length(gmt),"gene sets...\n")    
        require(fgsea)
        F1 <- mclapply(1:ncol(X), function(i) {
            xi <- X[,i]
            xi[is.na(xi)] <- 0
            xi <- xi + 1e-3*rnorm(length(xi))
            fgsea( gmt, xi, nperm=10000 )$NES
        })  
        F1 <- do.call(cbind, F1)
        cat("[pgx.addEnrichmentSignaturesH5] dim(F1)=",dim(F1),"\n")
        rownames(F1) <- names(gmt)
        colnames(F1) <- colnames(X)
        dim(F1)
        rownames(F1) <- names(gmt)
        if(h5exists(h5.file, "enrichment/GSEA")) h5delete(h5.file, "enrichment/GSEA")
        h5write(F1, h5.file, "enrichment/GSEA")
        h5write(rownames(F1), h5.file, "enrichment/genesets")
    }
    
    if("gsva" %in% methods) {
        cat("[pgx.addEnrichmentSignaturesH5] starting GSVA for",length(gmt),"gene sets...\n")            
        require(GSVA)
        ## mc.cores = 4
        F2 <- gsva(X, gmt, method="gsva", parallel.sz=mc.cores)
        cat("[pgx.addEnrichmentSignaturesH5] dim(F2)=",dim(F2),"\n")
        rownames(F2) <- names(gmt)
        dim(F2)
        if(h5exists(h5.file, "enrichment/GSVA")) h5delete(h5.file, "enrichment/GSVA")
        h5write(F2, h5.file, "enrichment/GSVA")
        h5write(rownames(F2), h5.file, "enrichment/genesets")
    }
    
    h5ls(h5.file)
    h5closeAll()

    cat("[pgx.addEnrichmentSignaturesH5] done!\n")
    
}

pgx.ReclusterSignatureDatabase <- function(h5.file, reduce.sd=1000, reduce.pca=100)
{
    require(rhdf5)

    h5exists <- function(h5.file, obj) {
        xobjs <- apply(h5ls(h5.file)[,1:2],1,paste,collapse="/")
        obj %in% gsub("^/|^//","",xobjs)
    }
    
    X  <- h5read(h5.file, "data/matrix")
    rn <- h5read(h5.file,"data/rownames")
    cn <- h5read(h5.file,"data/colnames")
    rownames(X) <- rn
    colnames(X) <- cn
    X[which(X < -999999)] <- NA
    
    ##--------------------------------------------------
    ## Precalculate t-SNE/UMAP
    ##--------------------------------------------------
    dim(X)
    
    if(!h5exists(h5.file, "clustering")) h5createGroup(h5.file,"clustering")    
    
    pos <- pgx.clusterBigMatrix(
        abs(X),  ## on absolute foldchange!!
        methods = c("pca","tsne","umap"),
        dims = c(2,3),
        reduce.sd = reduce.sd,
        reduce.pca = reduce.pca )
    names(pos)
    
    h5write( pos[["pca2d"]], h5.file, "clustering/pca2d")  ## can write list??    
    h5write( pos[["pca3d"]], h5.file, "clustering/pca3d")  ## can write list??    
    h5write( pos[["tsne2d"]], h5.file, "clustering/tsne2d")  ## can write list??    
    h5write( pos[["tsne3d"]], h5.file, "clustering/tsne3d")  ## can write list??    
    h5write( pos[["umap2d"]], h5.file, "clustering/umap2d")  ## can write list??    
    h5write( pos[["umap3d"]], h5.file, "clustering/umap3d")  ## can write list??            
    h5closeAll()    
}


##-------------------------------------------------------------------
## Pre-calculate geneset expression with different methods
##-------------------------------------------------------------------

pgx.computeMultiOmicsGSE <- function(X, gmt, omx.type, 
                                     method=NULL, center=TRUE)
{
    if(0) {
        omx.type <- c("MRNA","MIR")[1+grepl("^MIR",rownames(X))]
        table(omx.type)
        omx.type <- sample(c("MRNA","CNV"),nrow(X),replace=TRUE)
    }
    if(is.null(omx.type))
        omx.type <- gsub("[:=].*","",rownames(X))
    omx.types <- setdiff(unique(omx.type),c("MIR",""))
    omx.types

    sx <- list()
    for(tp in omx.types) {
        x1 <- X[which(omx.type==tp),]
        rownames(x1) <- sub(":.*","",rownames(x1))
        sx[[tp]] <- pgx.computeGeneSetExpression(x1, gmt, method=method, center=center)
        sx[[tp]] <- lapply(sx[[tp]],function(x) {
            rownames(x)=paste0(tp,"=",rownames(x))
            x
        })
    }

    ## concatenate all omx-types
    cx <- sx[[1]]
    for(j in 1:length(sx[[1]])) {
        cx[[j]] <- do.call(rbind, lapply(sx,"[[",j))
    }
    
    return(cx)
}

pgx.computeGeneSetExpression <- function(X, gmt, method=NULL,
                                         min.size=10, center=TRUE)
{    
    library(GSVA)
    ALL.METHODS <- c("gsva","spearman","average")
    ALL.METHODS <- c("gsva","ssgsea","spearman","average")
    if(is.null(method))
        method <- ALL.METHODS
    if(0){
        X=ngs$X;gmt=GSETS[grep("HALLMARK",names(GSETS))]
    }
    ## this is important!!! centering on genes (GSVA does)
    if(center) {
        X <- X - rowMeans(X,na.rm=TRUE)
    }
    dim(X)
    
    gmt.size <- sapply(gmt, function(x) sum(x %in% rownames(X)))
    gmt <- gmt[ gmt.size >= min.size ]
    length(gmt)
    
    S <- list()
    if("gsva" %in% method) {
        S[["gsva"]] <- gsva(X, gmt, method="gsva")
    }
    if("ssgsea" %in% method) {
        S[["ssgsea"]] <- gsva(X, gmt, method="ssgsea", min.sz=1)
    }
    if(any(method %in% c("spearman","average"))) {
        gg <- rownames(X)
        G <- gmt2mat(gmt, bg=gg)
        if("spearman" %in% method) {
            ##rho <- cor(as.matrix(G[gg,]), apply(X[gg,],2,rank))
            rho <- t(G[gg,]) %*% scale(apply(X[gg,],2,rank)) / sqrt(nrow(X)-1)
            rho[is.na(rho)] <- 0
            S[["spearman"]] <- rho
        }
        if("average" %in% method) {
            ##rho <- cor(as.matrix(G[gg,]), apply(G[gg,],2,rank))
            avg.X <- t(G[gg,]) %*% X[gg,] / Matrix::colSums(G[gg,])
            avg.X[is.na(avg.X)] <- 0
            S[["average"]] <- avg.X
        }        
    }

    ## compute meta score
    S1 <- lapply(S,function(x) apply(x,2,rank)) ## rank by sample
    S[["meta"]] <- scale(Reduce('+',S1)/length(S1))   
    gs <- Reduce(intersect, lapply(S,rownames)) 
    S <- lapply(S, function(x) x[gs,])
    
    if(0) {
        ## show pairs
        names(S)
        dim(S[[1]])
        pairs(sapply(S,function(x) x[,1])) ## corr by genesets
        pairs(sapply(S,function(x) x[1,])) ## corr by sample       
    }
            
    return(S)
}


