integerMatrix <- function(x, scale=100) {
        if(!is(x, "matrix")) stop("argument x must be a matrix")
        dms <- dimnames(x)
        if(scale != 1){
                xx <- as.integer(x*scale)
        } else xx <- as.integer(x)
        x <- matrix(xx, nrow(x), ncol(x))
        dimnames(x) <- dms
        return(x)
}

#' @export
setAs("MixtureModel", "SummarizedExperiment", function(from, to){
  cnmat <- matrix(y(from), 1, length(y(from)))
  cnmat <- integerMatrix(cnmat, 1000)
  message("making something up for rowRanges...")
  rr <- GRanges(Rle("chr1", nrow(cnmat)),
                IRanges(seq_len(nrow(cnmat)), width=1L))
  rr <- GRanges(rep("chr1", nrow(cnmat)),
                IRanges(seq_len(nrow(cnmat)), width=1L))
  names(rr) <- paste0("CNP", seq_len(nrow(cnmat)))
  se <- SummarizedExperiment(assays=SimpleList(medr=cnmat),
                             rowRanges=rr,
                             colData=DataFrame(plate=batch(from)))
  se
})

#' @rdname collapseBatch-method
#' @aliases collapseBatch,SummarizedExperiment-method
setMethod("collapseBatch", "SummarizedExperiment", function(object, provisional_batch, THR=0.1){
  batch <- as.character(object$provisional_batch)
  collapseBatch(assays(object)[["medr"]][1, ]/1000)
})

#' @rdname collapseBatch-method
#' @aliases collapseBatch,numeric-method
setMethod("collapseBatch", "numeric", function(object, provisional_batch, THR=0.1, nchar=8){
  N <- choose(length(unique(provisional_batch)), 2)
  if(N == 1){
    B <- provisional_batch
    provisional_batch <- .combineBatches(object, provisional_batch, THR=THR)
  }
  cond2 <- TRUE
  while(N > 1 && cond2){
    B <- provisional_batch
    provisional_batch <- .combineBatches(object, provisional_batch, THR=THR)
    cond2 <- !identical(B, provisional_batch)
    N <- choose(length(unique(provisional_batch)), 2)
  }
  makeUnique(provisional_batch, nchar)
})




## #' @rdname combinePlates-method
## #' @aliases combinePlates,numeric-method
## setMethod("combinePlates", "numeric", function(object, plate, THR=0.1){
##   N <- choose(length(unique(plate)), 2)
##   cond2 <- TRUE
##   while(N > 1 && cond2){
##     B <- plate
##     plate <- .combinePlates(object, plate, THR=THR)
##     cond2 <- !identical(B, plate)
##     N <- choose(length(unique(plate)), 2)
##   }
##   makeUnique(plate)
## })

##
## Combine the most similar batches first.
##
.combineBatches <- function(yy, B, THR=0.1){
  uB <- unique(B)
  ## One plate can pair with many other plates.
  for(j in seq_along(uB)){
    for(k in seq_along(uB)){
      if(k <= j) next() ## next k
      b1 <- uB[j]
      b2 <- uB[k]
      stat <- suppressWarnings(ks.test(yy[B==b1], yy[B==b2]))
      if(stat$p.value < THR) next()
      b <- paste(b1, b2, sep=",")
      B[B %in% b1 | B %in% b2] <- b
      ## once we've defined a new batch, return the new batch to the
      ## calling function
      return(B)
    }
  }
  B
}

#' Estimate batch from any sample-level surrogate variables that capture aspects of sample processing, such as the PCR experiment (e.g., the 96 well chemistry plate), laboratory, DNA source, or DNA extraction method.
#'
#' In high-throughput assays, low-level summaries of copy number at
#' copy number polymorphic loci (e.g., the mean log R ratio for each
#' sample, or a principal-component derived summary) often differ
#' between groups of samples due to technical sources of variation
#' such as reagents, technician, or laboratory.  Technical (as opposed
#' to biological) differences between groups of samples are referred
#' to as batch effects.  A useful surrogate for batch is the chemistry
#' plate on which the samples were hybridized. In large studies, a
#' Bayesian hierarchical mixture model with plate-specific means and
#' variances is computationally prohibitive.  However, chemistry
#' plates processed at similar times may be qualitatively similar in
#' terms of the distribution of the copy number summary statistic.
#' Further, we have observed that some copy number polymorphic loci
#' exhibit very little evidence of a batch effect, while other loci
#' are more prone to technical variation.  We suggest combining plates
#' that are qualitatively similar in terms of the Kolmogorov-Smirnov
#' two-sample test of the distribution and to implement this test
#' independently for each candidate copy number polymophism identified
#' in a study.  The \code{collapseBatch} function is a wrapper to the
#' \code{ks.test} implemented in the \code{stats} package that
#' compares all pairwise combinations of plates.  The \code{ks.test}
#' is performed recursively on the batch variables defined for a given
#' CNP until no batches can be combined. For smaller values of THR, plates are more likely to be judged as similar and combined.
#' @export
#' @param object a MultiBatch instance
#' @param THR scalar for the p-value cutoff from the K-S test.  Two batches with p-value > THR will be combined to define a single new batch
#'
#' @details All pairwise comparisons of batches are performed.  The two most similar batches are combined if the p-value exceeds THR.  The process is repeated recursively until no two batches can be combined.
#' @return MultiBatch object
setMethod("findSurrogates", "MultiBatch", function(object, THR=0.1){
  dat <- downSampledData(object) %>%
    select(c(id, provisional_batch, oned))
  dat2 <- find_surrogates(dat, THR) %>%
    mutate(batch=factor(batch, levels=unique(batch)),
           batch_labels=as.character(batch),
           batch=as.integer(batch)) %>%
    filter(!duplicated(id)) %>%
    arrange(batch) %>%
    select(c(provisional_batch, batch, batch_labels))
  ##
  ## There is a many to one mapping from provisional_batch to batch
  ## Since each sample belongs to a single plate, samples in the downsampled data will only belong to a single batch
  full.data <- assays(object)
  full.data2 <- full.data %>%
    select(-batch) %>%
    left_join(dat2, by="provisional_batch") %>%
    filter(!duplicated(id)) %>%
    arrange(batch)
  assays(object) <- full.data2
  L <- length(unique(full.data2$batch))
  if( L != specs(object)$number_batches ){
    spec <- specs(object)
    spec$number_batches <- L
    specs(object) <- spec
  }
  object
})

find_surrogates <- function(dat, THR=0.1, min_oned=-1){
  ## do not define batches based on homozygous deletion
  dat2 <- filter(dat, oned > min_oned)
  current <- dat2$provisional_batch
  oned <- dat2$oned
  latest <- NULL
  while(!identical(current, latest)){
    if(is.null(latest)) latest <- current
    current <- latest
    latest <- .find_surrogates(oned, current, THR)$batches
  }
  result <- tibble(provisional_batch=dat2$provisional_batch,
                   batch=latest) %>%
    group_by(provisional_batch) %>%
    summarize(batch=unique(batch))
  if("batch" %in% colnames(dat)){
    dat <- select(dat, -batch)
  }
  dat3 <- dat %>%
    left_join(result, by="provisional_batch")
  dat3
}

.find_surrogates <- function(x, B, THR=0.1){
  if(length(unique(B))==1) return(B)
  B2 <- B
  dat <- tibble(x=x, batch=B) %>%
    group_by(batch) %>%
    summarize(n=n()) %>%
    arrange(-n)
  uB <- unique(dat$batch)
  ##uB <- unique(B)
  ## One plate can pair with many other plates.
  stat <- matrix(NA, length(uB), length(uB))
  comparison <- stat
  pval <- stat
  for(j in seq_along(uB)){
    for(k in seq_along(uB)){
      if(k <= j) next() ## next k
      ## get rid of duplicate values
      x <- x + runif(length(x), -1e-10, 1e-10)
      b1 <- uB[j]
      b2 <- uB[k]
      ## edits
      tmp <- ks.test(x[B==b1], x[B==b2])
      stat[j, k] <- tmp$statistic
      bb <- c(b1, b2) %>%
        sort %>%
        paste(collapse="::")
      comparison[j, k] <- bb
      pval[j, k] <- tmp$p.value
    }
  }
  ## Combine the most similar plates according to the KS test statistic (smallest test statistic)
  stat2 <- as.numeric(stat)
  comp2 <- as.character(comparison)
  pval2 <- as.numeric(pval)
  ##min.index <- which.min(stat2)
  max.index <- which.max(pval2)
  sim.batches <- strsplit(comp2[max.index], "::")[[1]]
  max.pval <- pval2[max.index]
  if(max.pval < THR) return(list(pval=max.pval, batches=B))
  comp3 <- gsub("::", ",", comp2[max.index])
  B2[ B %in% sim.batches ] <- comp3
  result <- list(pval=max.pval, batches=B2)
  result
}

#' Save se data
#'
#' Batches drawn from the same distribution as identified by Kolmogorov-Smirnov test are combined.
#' @param se a SummarizedExperiment object
#' @param batch.file the file name to which to save the data
#' @param THR threshold below which the null hypothesis should be rejected and batches are collapsed.
#' @return A vector of collapsed batch labels
#' @export
saveBatch <- function(se, batch.file, THR=0.1){
  if(file.exists(batch.file)){
    bt <- readRDS(batch.file)
    return(bt)
  }
  bt <- collapseBatch(se, THR=THR)
  saveRDS(bt, file=batch.file)
  bt
}
