#'@include help.R
NULL

consensusRegion <- function(g){
  ## Defined the consensus start as the minimum basepair that is
  ## spanned by at least half of all identified CNVs
  ##cat(".")
  grl <- split(g, g$id)
  if(length(grl)/length(g) < 0.9){
    ## more than 10% of individuals have more than one cnv in the region
    ##
    ## assume that these individuals should have one cnv
    grl1 <- grl[elementNROWS(grl)==1]
    g1 <- unlist(grl1)
    #if(class(g1)=="list") browser()
    g1 <- GRanges(as.character(seqnames(g1)), IRanges(start(g1), end(g1)))
    grl2ormore <- grl[elementNROWS(grl) >= 2]
    grl3 <- unname(lapply(grl2ormore, reduce, min.gapwidth=1e6))
    g2ormore <- unlist(GRangesList(grl3))
    g <- c(g1, g2ormore)
  }
  threshold <- floor(length(g)/2)
  dj <- disjoin(g)
  cnt <- countOverlaps(disjoin(g), g)
  while(all(cnt <= threshold)){
    threshold <- floor(threshold/2)
  }
  ## the disjoint intervals are sorted, so we only need to take the
  ## first interval that passes this threshold
  index.start <- tryCatch(min(which(cnt > threshold)), error=function(e) NULL)
  index.end <- max(which(cnt > threshold))
  startg <- dj[index.start]
  endg <- dj[index.end]
  if(startg != endg){
    region <- GRanges(as.character(seqnames(startg)), IRanges(start(startg), end(endg)))
  } else region <- startg
  region
}

defineCnpRegions <- function(grl, thr=0.02){
  message("unlist GRangesList...")
  g <- unlist(grl)
  names(g) <- NULL
  dj <- disjoin(g)
  prop.cnv <- countOverlaps(dj, g)/length(grl)
  is_cnp <- prop.cnv > thr

  ## throw-out large CNVs and CNVs that do not overlap any of the CNPs
  ## gsmall <- g[width(g) < 200e3]
  gsmall <- subsetByOverlaps(g, dj[is_cnp])
  regions <- reduce(gsmall) ## 267 regions

  ## Split the cnvs by region
  hits <- findOverlaps(regions, g)
  hitlist <- split(subjectHits(hits), queryHits(hits))
  regionlist <- vector("list", length(hitlist))
  message("find consensus regions...")
  for(j in seq_along(hitlist)){
    message(".", appendLF=FALSE)
    i <- hitlist[[j]]
    regionlist[[j]] <- consensusRegion(g[i])
  }
  message("")
  ##regionlist <- GRangesList(foreach(i=hitlist) %do% consensusRegion(g[i]))
  regions <- GRangesList(regionlist)
  unlist(regions)
}

#' Identify consensus start and stop coordinates of a copy number
#' polymorphism
#'
#' The collection of copy number variants (CNVs) identified in a study
#' can be encapulated in a GRangesList, where each element is a
#' GRanges of the CNVs identified for an individual.  (For a study
#' with 1000 subjects, the GRangesList object would have length 1000
#' if each individual had 1 or more CNVs.)  For regions in which CNVs
#' occur in more than 2 percent of study participants, the start and
#' end boundaries of the CNVs may differ because of biological
#' differences in the CNV size as well as due to technical noise of
#' the assay and the uncertainty of the breakpoints identified by a
#' segmentation of the genomic data.  Among subjects with a CNV called
#' at a given locus, the \code{consensusCNP} function identifies the
#' largest region that is copy number variant in half of these
#' subjects.
#'
#' @examples
#' library(GenomicRanges)
#' ##
#' ## Simulate 2 loci at which CNVs are common
#' ##
#' set.seed(100)
#' starts <- rpois(1000, 100) + 10e6L
#' ends <- rpois(1000, 100) + 10.1e6L
#' cnv1 <- GRanges("chr1", IRanges(starts, ends))
#' cnv1$id <- paste0("sample", seq_along(cnv1))
#'
#' starts <- rpois(500, 1000) + 101e6L
#' ends <- rpois(500, 1000) + 101.4e6L
#' cnv2 <- GRanges("chr5", IRanges(starts, ends))
#' cnv2$id <- paste0("sample", seq_along(cnv2))
#'
#' ##
#' ## Simulate a few other CNVs that are less common because they are
#' ## very large, or because they occur in regions that in which copy
#' ## number alerations are not common
#' ##
#' cnv3 <- GRanges("chr1", IRanges(9e6L, 15e6L), id="sample1400")
#' starts <- seq(5e6L, 200e6L, 10e6L)
#' ends <- starts + rpois(length(starts), 25e3L)
#' cnv4 <- GRanges("chr1", IRanges(starts, ends),
#'                 id=paste0("sample", sample(1000:1500, length(starts))))
#'
#' all_cnvs <- suppressWarnings(c(cnv1, cnv2, cnv3, cnv4))
#' grl <- split(all_cnvs, all_cnvs$id)
#' \dontrun{
#'   cnps <- consensusCNP(grl)
#'   ##
#'   ## 2nd CNP is filtered because of its size
#'   ##
#'   truth <- GRanges("chr1", IRanges(10000100L, 10100100L))
#'   seqinfo(truth) <- seqinfo(grl)
#'   identical(cnps, truth)
#' }
#'
#'
#' ##
#' ## Both CNVs identified
#' ##
#' \dontrun{
#'   cnps <- consensusCNP(grl, max.width=500e3)
#' }
#' truth <- GRanges(c("chr1", "chr5"),
#'                  IRanges(c(10000100L, 101000999L),
#'                          c(10100100L, 101400999L)))
#' seqlevels(truth, pruning.mode="coarse") <- seqlevels(grl)
#' seqinfo(truth) <- seqinfo(grl)
#' \dontrun{
#'   identical(cnps, truth)
#' }
#'
#' @param grl  A \code{GRangesList} of all CNVs in a study -- each
#' element is the collection of CNVs for one individual.
#' @param transcripts a \code{GRanges} object containing annotation of
#' genes or transcripts (optional)
#' @param min.width length-one integer vector specifying the minimum width of CNVs
#' @param max.width length-one integer vector specifying the maximum
#' width of CNVs
#' @param min.prevalance a length-one numeric vector specifying the
#' minimum prevalance of a copy number polymorphism.  Must be in the
#' interval [0,1].  If less that 0, this function will return all CNV
#' loci regardless of prevalance.  If greater than 1, this function
#' will return a length-zero GRanges object
#' @return a \code{GRanges} object providing the intervals of all
#' identified CNPs above a user-specified prevalance cutoff.
#' @export
consensusCNP <- function(grl, transcripts, min.width=2e3,
                         max.width=200e3, min.prevalance=0.02){
  g <- as(unlist(grl), "GRanges")
  si <- seqinfo(g)
  names(g) <- NULL
  grl <- split(g, g$id)
  ##grl <- grl[colnames(views)]
  regions <- defineCnpRegions(grl, thr=min.prevalance)
  filters <- width(regions) > min.width  & width(regions) <= max.width
  if(any(filters)){
    message("Dropping CNV regions failing min.width and max.width criteria. See ?consensusCNP to relax these settings.")
    regions <- regions[ filters ]
  }
  regions <- reduce(regions)
  if(!missing(transcripts)){
    regions <- annotateRegions(regions, transcripts)
  }
  seqlevels(regions, pruning.mode="coarse") <- seqlevels(si)
  seqinfo(regions) <- si
  regions
}

.testcnp <- function(){
    set.seed(100)
    starts <- rpois(1000, 100) + 10000000L
    ends <- rpois(1000, 100) + 10100000L
    cnv1 <- GRanges("chr1", IRanges(starts, ends))
    cnv1$id <- paste0("sample", seq_along(cnv1))
    starts <- rpois(500, 1000) + 101000000L
    ends <- rpois(500, 1000) + 101400000L
    cnv2 <- GRanges("chr5", IRanges(starts, ends))
    cnv2$id <- paste0("sample", seq_along(cnv2))
    cnv3 <- GRanges("chr1", IRanges(9000000L, 15000000L), id = "sample1400")
    starts <- seq(5000000L, 200000000L, 10000000L)
    ends <- starts + rpois(length(starts), 25000L)
    cnv4 <- GRanges("chr1", IRanges(starts, ends), id = paste0("sample",
        sample(1000:1500, length(starts))))
    all_cnvs <- suppressWarnings(c(cnv1, cnv2, cnv3, cnv4))
    grl <- split(all_cnvs, all_cnvs$id)
    cnps <- consensusCNP(grl)
    truth <- GRanges("chr1", IRanges(10000100L, 10100100L))
    seqinfo(truth) <- seqinfo(grl)
    ##expect_identical(truth, cnps)
    cnps <- consensusCNP(grl, max.width = 5e+05)
    truth <- GRanges(c("chr1", "chr5"), IRanges(c(10000100L,
        101000999L), c(10100100L, 101400999L)))
    seqlevels(truth, pruning.mode = "coarse") <- seqlevels(grl)
    seqinfo(truth) <- seqinfo(grl)
    ##expect_identical(truth, cnps)
}

annotateRegions <- function(regions, transcripts){
  hits <- findOverlaps(regions, transcripts)
  indices <- split(subjectHits(hits), queryHits(hits))
  hgnc.ids <- sapply(indices, function(i, tx){
    paste(unique(tx$hgnc[i]), collapse=",")
  }, tx=transcripts)
  drivers <- sapply(indices, function(i, tx){
    hgnc <- tx$hgnc[i]
    is.cancer.connection <- tx$cancer_connection[i]
    paste(unique(hgnc[is.cancer.connection]), collapse=",")
  }, tx=transcripts)
  regions$driver <- regions$hgnc <- ""
  i <- as.integer(names(indices))
  regions$driver[i] <- drivers
  regions$hgnc[i] <- hgnc.ids
  regions
}



permnK <- function(k, maxperm){
  if(k < 2) return(matrix(1,1,1))
  kperm <- permn(seq_len(k))
  kperm <- do.call("rbind", kperm)
  kperm.identity <- kperm[1, , drop=FALSE]
  kperm <- kperm[-1, , drop=FALSE]
  neq <- apply(kperm, 1, function(x, y) sum(x != y), y=kperm.identity)
  kperm <- kperm[order(neq, decreasing=TRUE), , drop=FALSE]
  N <- min(maxperm-1, nrow(kperm))
  kperm <- rbind(kperm.identity, kperm[seq_len(N), ])
  kperm
}

#' @param tiles a tibble as constructed by \code{tileMedians}
#' @rdname tile-functions
#' @export
tileSummaries <- function(tiles){
  batch <- tile <- logratio <- NULL
  tile.summaries <- tiles %>% group_by(tile) %>%
    summarize(avgLRR=mean(logratio),
              batch=unique(batch))
  tile.summaries
}


# This function is copied from dplyr! Just copied the code over since this
# is the only function used in dplyr.
ntile <- function(x, n) {
    floor((n * (rank(x, ties.method="first", na.last="keep") - 1)
           / length(x)) + 1)
}

#' Calculate posterior proportion of cases by component
#'
#' @examples
#' \dontrun{
#'      # generate random case control status
#'      case_control <- rbinom(length(y(SingleBatchModelExample)), 1, 0.5)
#'      case_control_posterior <- posterior_cases(SingleBatchModelExample,
#'                                                case_control)
#' }
#' @param model An instance of a \code{MixtureModel}-derived class.
#' @param case_control A vector of 1's and 0's where a 1 indicates a case and a 0 a control
#' @param alpha prior alpha for the beta
#' @param beta prior beta for the beta
#' @return A matrix of dimension S (MCMC iterations) by K (number of components) where each element i,j indicates the posterior proportion of cases at an iteration and component
#' @export
posterior_cases <- function(model, case_control, alpha=1, beta=1) {
    # model and MCMC params
    z.mat <- z(chains(model))
    S <- nrow(z.mat)

    # empty posterior matrix
    posterior <- matrix(0, nrow=S, ncol=k(model))

    # run model of probabilities
    for (i in seq_len(S)) {
        z <- z.mat[i, ]
        cont.tbl <- table(z, case_control)
        cases <- cont.tbl[, 2]
        controls <- cont.tbl[, 1]

        for (j in seq_len(length(cases))) {
            cases.row <- cases[j]
            controls.row <- controls[j]
            posterior[i, j] <- rbeta(1, cases.row + 1, controls.row + 1)
        }
    }

    return(posterior)
}

gelmanDiag <- function(model){
  theta.ch <- thetac(model)
  cut1 <- floor(iter(model)/2)
  chain1 <- theta.ch[1:cut1, ]
  chain2 <- theta.ch[(cut1+1):nrow(theta.ch), ]
  theta.mc <- mcmc.list(mcmc(chain1),
                        mcmc(chain2))
  result <- gelman.diag(theta.mc)
  result$mpsrf
}

##
## This is a tough example. Best approach is unclear.
##
smallPlates <- function(x){
  tab <- table(x)
  names(tab)[tab < 20]
}

.read_hapmap <- function(){
  ddir <- "~/Dropbox/labs/cnpbayes"
  lrr <- readRDS(file.path(ddir, "data/EA_198_lrr.rds"))
}

readLocalHapmap <- function(){
  lrr <- .read_hapmap()
  lrr1 <- lapply(lrr, function(x) x/1000)
  batch.id <- c(rep(0,8), rep(1, 8))
  ##avg.lrr <- unlist(lapply(lrr1, colMeans, na.rm=TRUE))
  avg.lrr <- unlist(lapply(lrr1, colMedians, na.rm=TRUE))
  plate <- substr(names(avg.lrr), 1, 5)
  avg.lrr <- avg.lrr[!plate %in% smallPlates(plate)]
  plate <- plate[!plate %in% smallPlates(plate)]
  names(avg.lrr) <- plate
  avg.lrr
}

mclustMeans <- function(y, batch){
  ylist <- split(y, batch)
  .mclust <- function(y){
    Mclust(y)$parameters$mean
  }
  mns <- lapply(ylist, .mclust)
  L <- sapply(mns, length)
  collections <- split(names(L), L)
}

#' Simulate data from the posterior predictive distribution
#'
#' Simulating from the posterior predictive distribution can be helpful for assessing the adequacy of the mixture model.
#'
#' @examples
#'
#' \dontrun{
#'    model <- SingleBatchModelExample
#'    mp <- McmcParams(iter=200, burnin=50)
#'    mcmcParams(model) <- mp
#'    model <- posteriorSimulation(model)
#'    pd <- posteriorPredictive(model)
#'    if(FALSE) qqplot(pd, y(model))
#'
#'    bmodel <- MultiBatchModelExample
#'    mp <- McmcParams(iter=500, burnin=150, nStarts=20)
#'    mcmcParams(bmodel) <- mp
#'    bmodel <- posteriorSimulation(bmodel)
#'    batchy <- posteriorPredictive(bmodel)
#' }
#'
#' @param model a SingleBatchModel or MultiBatchModel
#' @export
posteriorPredictive <- function(model){
  if(class(model)=="SingleBatchModel"){
    tab <- .posterior_predictive_sb(model)
  }
  if(class(model)=="MultiBatchModel"){
    tab <- .posterior_predictive_mb(model)
  }
  if(class(model)=="MultiBatchCopyNumber"){
    tab <- .posterior_predictive_mb(model)
  }
  if(class(model) == "SingleBatchPooled"){
    tab <- .posterior_predictive_sbp(model)
  }
  if(class(model) == "MultiBatchPooled"){
    tab <- .posterior_predictive_mbp(model)
  }
  if(class(model) == "MultiBatchCopyNumberPooled"){
    tab <- .posterior_predictive_mbp(model)
  }
  if(class(model) == "TrioBatchModel"){
    tab <- .posterior_predictive_trio(model)
  }
  tab <- tab[, c("y", "component", "batch")]
  tab$model <- modelName(model)
  return(tab)
}

.posterior_predictive_sb <- function(model){
  ch <- chains(model)
  alpha <- p(ch)
  thetas <- theta(ch)
  sigmas <- sigma(ch)
  mcmc.iter <- iter(model)
  Y <- matrix(NA, mcmc.iter, ncol(alpha))
  K <- seq_len(k(model))
  N <- length(K)
  tab.list <- vector("list", mcmc.iter)
  df <- dfr(hyperParams(model))
  for(i in 1:nrow(alpha)){
    zz <- sample(K, N, prob=alpha[i, ], replace=TRUE)
    ##y <- rnorm(ncol(thetas), (thetas[i, ])[zz], (sigmas[i, ])[zz])
    y <- rst(ncol(thetas), df=df, mean=(thetas[i, ])[zz], sigma=(sigmas[i, ])[zz])
    tab.list[[i]] <- tibble(y=y, component=zz)
    ##Y[i, ] <- y
  }
  tab <- do.call(bind_rows, tab.list)
  tab$batch <- "1"
  tab
}

.posterior_predictive_sbp <- function(model){
  ch <- chains(model)
  alpha <- p(ch)
  thetas <- theta(ch)
  sigmas <- sigma(ch)
  mcmc.iter <- iter(model)
  Y <- matrix(NA, mcmc.iter, ncol(alpha))
  K <- seq_len(k(model))
  N <- length(K)
  df <- dfr(hyperParams(model))
  tab.list <- vector("list", mcmc.iter)
  for(i in 1:nrow(alpha)){
    zz <- sample(K, N, prob=alpha[i, ], replace=TRUE)
    ##y <- rnorm(ncol(thetas), (thetas[i, ])[zz], (sigmas[i, ]))
    y <- rst(ncol(thetas), df=df, mean=(thetas[i, ])[zz], sigma=(sigmas[i, ]))
    tab.list[[i]] <- tibble(y=y, component=zz)
    ##Y[i, ] <- y
  }
  tab <- do.call(bind_rows, tab.list)
  tab$batch <- "1"
  tab
}

.posterior_predictive_trio <- function(model){
  ch <- chains(model)
  alpha <- p(ch)
  thetas <- theta(ch)
  sigmas <- sigma(ch)
  tab <- table(batch(model))
  nb <- nrow(theta(model))
  K <- k(model)
  nn <- K * nb
  Y <- matrix(NA, nrow(alpha), nn)
  ylist <- list()
  components <- seq_len(K)
  mcmc.iter <- iter(model)
  tab.list <- vector("list", mcmc.iter)
  df <- dfr(hyperParams(model))
  batches <- sort(rep(unique(batch(model)), each=K))
  for(i in seq_len(mcmc.iter)){
    ## same p assumed for each batch
    a <- alpha[i, ]
    mu <- matrix(thetas[i, ], nb, K)
    s <- matrix(sigmas[i, ], nb, K)
    ## for each batch, sample K observations with
    ## mixture probabilities alpha
    ## MC: should sample zz for offspring from mendelian probabilities
    zz <- sample(components, K, prob=a, replace=TRUE)
    for(b in seq_len(nb)){
      ylist[[b]] <- rst(K, df=df, mean=(mu[b, ])[zz], sigma=(s[b, ])[zz])
    }
    y <- unlist(ylist)
    tab.list[[i]] <- tibble(y=y, batch=batches, component=rep(zz, nb))
  }
  tab <- do.call(bind_rows, tab.list)
  tab$batch <- as.character(tab$batch)
  tab
}

.posterior_predictive_mb <- function(model){
  ch <- chains(model)
  alpha <- p(ch)
  thetas <- theta(ch)
  sigmas <- sigma(ch)
  nb <- nrow(theta(model))
  K <- k(model)
  nn <- K * nb
  Y <- matrix(NA, nrow(alpha), nn)
  ylist <- list()
  components <- seq_len(K)
  mcmc.iter <- iter(model)
  tab.list <- vector("list", mcmc.iter)
  df <- dfr(hyperParams(model))
  batches <- sort(rep(unique(batch(model)), each=K))
  ##
  ## we could just sample B observations from each MCMC
  ##
  for(i in seq_len(mcmc.iter)){
    ## same p assumed for each batch
    a <- alpha[i, ]
    mu <- matrix(thetas[i, ], nb, K)
    s <- matrix(sigmas[i, ], nb, K)
    ## for each batch, sample K observations with
    ## mixture probabilities alpha
    zz <- sample(components, K, prob=a, replace=TRUE)
    for(b in seq_len(nb)){
      ylist[[b]] <- rst(K, df=df, mean=(mu[b, ])[zz], sigma=(s[b, ])[zz])
    }
    y <- unlist(ylist)
    tab.list[[i]] <- tibble(y=y, batch=batches, component=rep(zz, nb))
  }
  tab <- do.call(bind_rows, tab.list)
  tab$batch <- as.character(tab$batch)
  tab
}


.posterior_predictive_mbp <- function(model){
  ch <- chains(model)
  alpha <- p(ch)
  thetas <- theta(ch)
  sigmas <- sigma(ch)
  tab <- table(batch(model))
  nb <- nrow(theta(model))
  K <- k(model)
  nn <- K * nb
  Y <- matrix(NA, nrow(alpha), nn)
  ylist <- list()
  components <- seq_len(K)
  mcmc.iter <- iter(model)
  tab.list <- vector("list", mcmc.iter)
  ##batches <- rep(unique(batch(model)), each=K)
  batches <- sort(rep(unique(batch(model)), each=K))
  df <- dfr(hyperParams(model))
  ##  bb <- rownames(theta(model))
  ##  ix <- match(as.character(seq_along(bb)), bb)
  ##browser()
  for(i in seq_len(mcmc.iter)){
    ## same p assumed for each batch
    a <- alpha[i, ]
    mu <- matrix(thetas[i, ], nb, K)
    s <- sigmas[i, ]
    ## for each batch, sample K observations with mixture probabilities alpha
    zz <- sample(components, K, prob=a, replace=TRUE)
    for(b in seq_len(nb)){
      ## sigma is batch-specific but indpendent of z
      ylist[[b]] <- rst(K, df=df, mean=(mu[b, ])[zz], sigma=s[b])
    }
    y <- unlist(ylist)
    tab.list[[i]] <- tibble(y=y, batch=batches, component=rep(zz, nb))
  }
  tab <- do.call(bind_rows, tab.list)
  tab$batch <- as.character(tab$batch)
  tab
}



missingBatch <- function(dat, ix){
  batches <- dat$provisional_batch
  batches.sub <- batches[ix]
  u.batch <- unique(batches)
  u.batch.sub <- unique(batches.sub)
  missing.batch <- u.batch[ !u.batch %in% u.batch.sub ]
  missing.batch
}

#' Down sample the observations in a mixture
#'
#' For large datasets (several thousand subjects), the computational burden for fitting Bayesian mixture models can be high.  Downsampling can reduce the computational burden with little effect on inference.  This function draws a random sample with replacement.  Batches with few observations are combined with larger batches that have a similar median log R ratio.
#'
#' @param dat data.frame with required columns medians, batches, and plate
#' @param size the number of observations to sample with replacement
#' @param min.batchsize the smallest number of observations allowed in a batch.  Batches smaller than this size will be combined with other batches
#' @return A tibble of the downsampled data (medians), the original batches, and the updated batches after downsampling 
#' @export
#' @examples
#' ## TODO: this is more complicated than it needs to be
#' library(dplyr)
#' mb <- MultiBatchModelExample
#' mapping <- tibble(plate=letters[1:10],
#'                   batch_orig=sample(c("1", "2", "3"), 10, replace=TRUE))
#' full.data <- tibble(medians=y(mb),
#'                     batch_orig=as.character(batch(mb))) %>%
#'   left_join(mapping, by="batch_orig")
#' partial.data <- downSample(full.data, 200)
#' ## map the original batches to the batches after down-sampling
#' mapping <- partial.data %>%
#'   select(c(plate, batch_index)) %>%
#'   group_by(plate) %>%
#'   summarize(batch_index=unique(batch_index))
#' mp <- McmcParams(iter=50, burnin=100)
#' \dontrun{
#'     mb2 <- MultiBatchModel2(dat=ds$medians,
#'                             batches=ds$batch_index, mp=mp)
#'     mb2 <- posteriorSimulation(mb2)
#'     if(FALSE) ggMixture(mb2)
#'     full.dat2 <- full.data %>%
#'       left_join(mapping, by="plate")
#'     ## compute probabilities for the full dataset
#'     mb.up <- upSample2(full.dat2, mb2)
#'     if(FALSE) ggMixture(mb2)
#' }
#' @rdname downSample
downSample <- function(dat,
                       size=1000,
                       min.batchsize=75){
  N <- nrow(dat)
  size <- min(size, N)
  ##dat <- tiles$logratio
  ix <- sample(seq_len(N), size, replace=TRUE)
  missing.batch <- missingBatch(dat, ix)
  if(length(missing.batch) > 0){
    ix2 <- which(dat$provisional_batch %in% missing.batch)
    ix <- c(ix, ix2)
  }
  dat.sub <- dat[ix, ]
  ## tricky part:
  ##
  ## - if we down sample, there may not be enough observations to estimate the mixture densities for batches with few samples
  ##
  ##tab <- tibble(medians=dat.sub,
  ##              batch.var=batches[ix]) %>%
  ##  mutate(batch.var=as.character(batch.var))
  ##
  ## combine batches with too few observations based on the location (not scale)
  ##
  batch_orig <- NULL
  medians <- NULL
  largebatch <- NULL
  other <- NULL
  . <- NULL
  batch_New <- NULL
  select <- dplyr::select
  . <- medians <- largebatch <- other <- batch_orig <- NULL
  batch_new <- NULL
  b
  batch.sum <- dat.sub %>%
    group_by(batch_orig) %>%
    summarize(mean=mean(medians),
              n=n())

  small.batch <- batch.sum %>%
    filter(n < min.batchsize) %>%
    mutate(largebatch="")
  large.batch <- batch.sum %>%
    filter(n >= min.batchsize) %>%
    mutate(smallbatch="")
  if(nrow(large.batch) == 0){
    batch.sum3 <- small.batch %>%
      select(-largebatch) %>%
      mutate(batch_new=1L)
  } else {
    for(i in seq_len(nrow(small.batch))){
      j <- order(abs(small.batch$mean[i] - large.batch$mean))[1]
      small.batch$largebatch[i] <- large.batch$batch_orig[j]
      if(nchar(large.batch$smallbatch[j]) > 0){
        large.batch$smallbatch[j] <- paste0(large.batch$smallbatch[j], ",",
                                            small.batch$batch_orig[i])
      } else{
        large.batch$smallbatch[j] <- small.batch$batch_orig[i]
      }
    }
    colnames(large.batch)[4] <- colnames(small.batch)[4] <- "other"
    batch.sum2 <- bind_rows(large.batch,
                            small.batch) %>%
      mutate(batch_new=paste0(batch_orig, ",", other)) %>%
      select(-other)
    if(is.character(batch.sum2$batch_new)){
      batch.sum2$batch_new <- batch.sum2$batch_new %>%
        strsplit(., ",") %>%
        map(as.numeric) %>%
        map(unique) %>%
        map(sort) %>%
        map_chr(paste, collapse=",")
    }
    ## need to do it once more
    small.batch <- filter(batch.sum2, n < min.batchsize)
    large.batch <- filter(batch.sum2, n >= min.batchsize)
    for(i in seq_len(nrow(small.batch))){
      j <- order(abs(small.batch$mean[i] - large.batch$mean))[1]
      small.batch$batch_new[i] <- large.batch$batch_new[j]
    }
    batch.sum3 <- bind_rows(large.batch, small.batch)
  }
  tab2 <- left_join(dat.sub, batch.sum3, by="batch_orig") %>%
    select(-c(mean, n)) %>%
    mutate(batch_index=as.integer(factor(batch_new,
                                         levels=unique(batch_new))))
  tab2
}


rst <- function (n, u, df = 100, mean = 0, sigma = 1){
  if (any(sigma <= 0))
    stop("The sigma parameter must be positive.")
  if (any(df <= 0))
    stop("The df parameter must be positive.")
  n <- ceiling(n)
  y <- rnorm(n)
  if(missing(u)){
    u <- rchisq(n, df=df)
  }
  x <- mean + sigma * y * sqrt(df/u)
  return(x)
}

#' Abbreviated model name
#'
#' @param object a SingleBatchModel, MultiBatchModel, etc.
#' @examples
#' modelName(SingleBatchModelExample)
#' @export
setMethod("modelName", "MixtureModel", function(object){
  . <- NULL
  model.name <- class(object) %>%
    gsub("CopyNumber", "", .) %>%
    gsub("SingleBatchPooled", "SBP", .) %>%
    gsub("SingleBatchModel", "SB", .) %>%
    gsub("MultiBatchModel", "MB", .) %>%
    gsub("MultiBatchCopyNumber", "MB", .) %>%
    gsub("MultiBatchPooled", "MBP", .) %>%
    gsub("MultiBatch", "MB", .)
  L <- length(unique(batch(object)))
  if(L == 1){
    model.name <- gsub("MB", "SB", model.name)
  }
  model.name <- paste0(model.name, k(object))
  model.name
})

freeParams <- function(model){
  ## K: number of free parameters to be estimated
  ##   - component and batch-specific parameters:  theta, sigma2  ( k(model) * nBatch(model))
  ##   - mixing probabilities: (k-1)*nBatch
  ##   - component-specific parameters: mu, tau2                 2 x k(model)
  ##   - length-one parameters: sigma2.0, nu.0                   +2
  nBatch <- function(model) length(unique(batch(model)))
  nm <- substr(modelName(model), 1, 2)
  nsigma <- ncol(sigma(model))
  ntheta <- k(model)
  if(is.null(nsigma)) nsigma <- length(sigma(model))
  K <- (ntheta + nsigma)*nBatch(model) + (k(model)-1) + 2*k(model) + 2
  K
}

#' Compute the Bayes factor
#'
#' Calculated as log(ML1) - log(ML2) + log prior odds
#' where ML1 is the marginal likelihood of the model with the most free parameters
#'
#' @param model.list list of models from \code{gibbs}
#' @param prior.odds scalar
#' @export
bayesFactor <- function(model.list, prior.odds=1){
  ## set null model to be the model with the fewest free parameters
  free.params <- sapply(model.list, freeParams)
  ix <- order(free.params, decreasing=TRUE)
  model.list2 <- model.list[ix]
  model.names <- sapply(model.list2, modelName)
  nm <- paste(model.names, collapse="-")
  ##p2 <- p[ix]
  ## log marginal likelihood
  log.mlik <- sapply(model.list2, marginal_lik)
  bf <- log.mlik[1] - log.mlik[2] + log(prior.odds)
  names(bf) <- nm
  bf
}

#' Order models by Bayes factor
#'
#' @param models list of \code{MixtureModel}-derived objects
#' @param bf.thr scalar: minimal bayes factor for selecting a model with more parameters over a more parsimonious model
#'
#' @export
orderModels <- function(models, bf.thr=10){
  mliks <- sapply(models, marginal_lik)
  if(!any(is.na(mliks))){
    ml <- marginalLik(models)
    bf <- bayesFactor(models, prior.odds=1)
    model.order <- strsplit(names(bf), "-")[[1]]
    if(bf < bf.thr) model.order <- rev(model.order)
    models <- models[ model.order ]
  }
  models
}

#' Extract marginal likelihoods from a list of models
#'
#' @param models list of models
#' @export
marginalLik <- function(models){
  ml <- sapply(models, marginal_lik) %>%
  round(1)
  names(ml) <- sapply(models, modelName)
  ml2 <- paste0(names(ml), ": ", ml)
  names(ml2) <- names(ml)
  ml2
}
