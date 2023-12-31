.empty_batch_model <- function(hp, mp){
  K <- k(hp)
  B <- 0L
  S <- iter(mp)
  ch <- initialize_mcmc(K, S, B)
  obj <- new("MultiBatchModel",
             k=as.integer(K),
             hyperparams=hp,
             theta=matrix(NA, 0, K),
             sigma2=matrix(NA, 0, K),
             mu=numeric(K),
             tau2=numeric(K),
             nu.0=numeric(1),
             sigma2.0=numeric(1),
             pi=numeric(K),
             predictive=numeric(K*B),
             zstar=integer(K*B),
             data=numeric(0),
             data.mean=matrix(NA, B, K),
             data.prec=matrix(NA, B, K),
             z=integer(0),
             zfreq=integer(K),
             probz=matrix(0, S, K),
             logprior=numeric(1),
             loglik=numeric(1),
             mcmc.chains=ch,
             mcmc.params=mp,
             batch=integer(0),
             batchElements=integer(0),
             label_switch=FALSE,
             marginal_lik=as.numeric(NA),
             .internal.constraint=5e-4,
             .internal.counter=0L)
  chains(obj) <- McmcChains(obj)
  obj
}

.ordered_thetas_multibatch <- function(model){
  thetas <- theta(model)
  checkOrder <- function(theta) identical(order(theta), seq_along(theta))
  is_ordered <- apply(thetas, 1, checkOrder)
  all(is_ordered)
}

reorderMultiBatch <- function(model){
  is_ordered <- .ordered_thetas_multibatch(model)
  if(is_ordered) return(model)
  ## thetas are not all ordered
  thetas <- theta(model)
  s2s <- sigma2(model)
  K <- k(model)
  ix <- order(thetas[1, ])
  B <- nBatch(model)
  . <- NULL
  tab <- tibble(z_orig=z(model),
                z=z(model),
                batch=batch(model)) %>%
    mutate(index=seq_len(nrow(.)))
  z_relabel <- NULL
  for(i in seq_len(B)){
    ix.next <- order(thetas[i, ])
    thetas[i, ] <- thetas[i, ix.next]
    s2s[i, ] <- s2s[i, ix]
    index <- which(tab$batch == i)
    tab2 <- tab[index, ] %>%
      mutate(z_relabel=factor(z, levels=ix.next)) %>%
      mutate(z_relabel=as.integer(z_relabel))
    tab$z[index] <- tab2$z_relabel
  }
  ps <- p(model)[ix]
  mu(model) <- mu(model)[ix]
  tau2(model) <- tau2(model)[ix]
  sigma2(model) <- s2s
  theta(model) <- thetas
  p(model) <- ps
  z(model) <- tab$z
  log_lik(model) <- computeLoglik(model)
  model
}

setMethod("sortComponentLabels", "MultiBatchModel", function(model){
  reorderMultiBatch(model)
})

.MB <- function(dat=numeric(),
                hp=HyperparametersMultiBatch(),
                mp=McmcParams(iter=1000, thin=10,
                              burnin=1000, nStarts=4),
                batches=integer()){
  ## If the data is not ordered by batch,
  ## its a little harder to sort component labels
  ##dat2 <- tibble(y=dat, batch=batches)
  ub <- unique(batches)
  nbatch <- setNames(as.integer(table(batches)), ub)
  B <- length(ub)
  N <- length(dat)
  ## move to setValidity
  if(length(dat) != length(batches)) {
    stop("batch vector must be the same length as data")
  }
  K <- k(hp)
  ## mu_k is the average across batches of the thetas for component k
  ## tau_k is the sd of the batch means for component k
  mu <- sort(rnorm(k(hp), mu.0(hp), sqrt(tau2.0(hp))))
  tau2 <- 1/rgamma(k(hp), 1/2*eta.0(hp), 1/2*eta.0(hp) * m2.0(hp))
  p <- rdirichlet(1, alpha(hp))[1, ]
  sim_theta <- function(mu, tau, B) sort(rnorm(B, mu, tau))
  . <- NULL
  thetas <- map2(mu, sqrt(tau2), sim_theta, B) %>%
    do.call(cbind, .) %>%
    apply(., 1, sort) %>%
    t
  if(K == 1) thetas <- t(thetas)
  nu.0 <- 3.5
  sigma2.0 <- 0.25
  sigma2s <- 1/rgamma(k(hp) * B, 0.5 * nu.0, 0.5 * nu.0 * sigma2.0) %>%
    matrix(B, k(hp))
  u <- rchisq(length(dat), hp@dfr)
  S <- iter(mp)
  ch <- initialize_mcmc(K, S, B)
  obj <- new("MultiBatchModel",
             k=as.integer(K),
             hyperparams=hp,
             theta=thetas,
             sigma2=sigma2s,
             mu=mu,
             tau2=tau2,
             nu.0=nu.0,
             sigma2.0=sigma2.0,
             pi=p,
             predictive=numeric(K*B),
             zstar=integer(K*B),
             data=dat,
             u=u,
             data.mean=matrix(NA, B, K),
             data.prec=matrix(NA, B, K),
             z=sample(seq_len(K), N, replace=TRUE),
             zfreq=integer(K),
             probz=matrix(0, N, K),
             logprior=numeric(1),
             loglik=numeric(1),
             mcmc.chains=ch,
             mcmc.params=mp,
             batch=batches,
             batchElements=nbatch,
             label_switch=FALSE,
             marginal_lik=as.numeric(NA),
             .internal.constraint=5e-4,
             .internal.counter=0L)
  obj
}

#' Constructor for MultiBatchModel
#'
#' Initializes a MultiBatchModel, a container for storing data, parameters, and MCMC output for mixture models with batch- and component-specific means and variances.
#'
#' @param dat the data for the simulation.
#' @param batches an integer-vector of the different batches
#' @param hp An object of class `Hyperparameters` used to specify the hyperparameters of the model.
#' @param mp An object of class 'McmcParams'
#' @return An object of class `MultiBatchModel`
#' @examples
#'   model <- MultiBatchModel2(rnorm(10), batch=rep(1:2, each=5))
#'   set.seed(100)
#'   nbatch <- 3
#'   k <- 3
#'   means <- matrix(c(-2.1, -2, -1.95, -0.41, -0.4, -0.395, -0.1,
#'       0, 0.05), nbatch, k, byrow = FALSE)
#'   sds <- matrix(0.15, nbatch, k)
#'   sds[, 1] <- 0.3
#'   N <- 1000
#'   truth <- simulateBatchData(N = N, batch = rep(letters[1:3],
#'                                                 length.out = N),
#'                              p = c(1/10, 1/5, 1 - 0.1 - 0.2),
#'                              theta = means,
#'                              sds = sds)
#'
#'     truth <- simulateBatchData(N = 2500,
#'                                batch = rep(letters[1:3], length.out = 2500),
#'                                theta = means, sds = sds,
#'                                p = c(1/5, 1/3, 1 - 1/3 - 1/5))
#'     MultiBatchModel2(dat=y(truth), batches=batch(truth),
#'                      hp=hpList(k=3)[["MB"]])
#' @rdname MultiBatchModel
#' @export
MultiBatchModel2 <- function(dat=numeric(),
                             hp=HyperparametersMultiBatch(),
                             mp=McmcParams(iter=1000, thin=10,
                                           burnin=1000, nStarts=4),
                             batches=integer()){
  if(length(dat) == 0){
    return(.empty_batch_model(hp, mp))
  }
  iter <- 0
  validZ <- FALSE
  mp.tmp <- McmcParams(iter=0, burnin=burnin(mp), thin=1, nStarts=1)
  while(!validZ){
    ##
    ## Burnin with MB model
    ##
    mb <- .MB(dat, hp, mp.tmp, batches)
    mb <- runBurnin(mb)
    tabz1 <- table(batch(mb), z(mb))
    tabz2 <- table(z(mb))
    validZ <- length(tabz2) == k(hp) && all(tabz1 > 1)
    iter <- iter + 1
    if(iter == 100) {
      message("Trouble initializing a valid model. The number of components is likely too large")
      return(NULL)
    }
  }
  mb2 <- sortComponentLabels(mb)
  mcmcParams(mb2) <- mp
  chains(mb2) <- McmcChains(mb2)
  probz(mb2)[,] <- 0
  mb2
}

#' Constructor for MultiBatchModel
#'
#' Initializes a MultiBatchModel, a container for storing data, parameters, and MCMC output for mixture models with batch- and component-specific means and variances.
#'
#' @param dat the data for the simulation.
#' @param batches an integer-vector of the different batches
#' @param hp An object of class `Hyperparameters` used to specify the hyperparameters of the model.
#' @param mp An object of class 'McmcParams'
#' @return An object of class `MultiBatchModel`
#' @examples
#'   model <- MultiBatchModel2(rnorm(10), batch=rep(1:2, each=5))
#'   set.seed(100)
#'   nbatch <- 3
#'   k <- 3
#'   means <- matrix(c(-2.1, -2, -1.95, -0.41, -0.4, -0.395, -0.1,
#'       0, 0.05), nbatch, k, byrow = FALSE)
#'   sds <- matrix(0.15, nbatch, k)
#'   sds[, 1] <- 0.3
#'   N <- 1000
#'   truth <- simulateBatchData(N = N, batch = rep(letters[1:3],
#'                                                 length.out = N),
#'                              p = c(1/10, 1/5, 1 - 0.1 - 0.2),
#'                              theta = means,
#'                              sds = sds)
#'     MB(dat=y(truth), batches=batch(truth),
#'        hp=hpList(k=3)[["MB"]])
#' @export
#' @rdname MultiBatchModel
MB <- MultiBatchModel2

ensureAllComponentsObserved <- function(obj){
  zz <- table(batch(obj), z(obj))
  K <- seq_len(k(obj))
  if(any(zz<=1)){
    index <- which(rowSums(zz<=1) > 0)
    for(i in seq_along(index)){
      j <- index[i]
      zup <- z(obj)[batch(obj) == j]
      zfact <- factor(zup, levels=K)
      minz <- as.integer(names(table(zfact))[table(zfact) <= 1])
      ##missingk <- K[!K %in% unique(zup)]
      maxk <- names(table(zfact))[which.max(table(zfact))]
      nreplace <- length(minz)*2
      zup[sample(which(zup == maxk), nreplace)] <- as.integer(minz)
      obj@z[batch(obj) == j] <- as.integer(zup)
    }
  }
  obj
}

##
## Multiple batches, but only 1 component
##
UnivariateBatchModel <- function(data, k=1, batch, hypp, mcmc.params){
  mcmc.chains <- McmcChains()
  zz <- integer(length(data))
  zfreq <- as.integer(table(zz))
  bf <- factor(batch)
  batch <- as.integer(bf)
  ix <- order(bf)
  ##B <- length(levels(batch))
  nbatch <- elementNROWS(split(batch, batch))
  B <- length(nbatch)
  if(missing(hypp)) hypp <- HyperparametersMultiBatch(k=1)
  obj <- new("UnivariateBatchModel",
             k=as.integer(k),
             hyperparams=hypp,
             theta=matrix(NA, B, 1),
             sigma2=matrix(NA, B, 1),
             mu=numeric(k),
             tau2=numeric(k),
             nu.0=numeric(1),
             sigma2.0=numeric(1),
             pi=numeric(k),
             ##pi=matrix(NA, B, 1),
             data=data[ix],
             data.mean=matrix(NA, B, 1),
             data.prec=matrix(NA, B, 1),
             z=integer(length(data)),
             zfreq=zfreq,
             probz=matrix(0, length(data), 1),
             logprior=numeric(1),
             loglik=numeric(1),
             mcmc.chains=mcmc.chains,
             mcmc.params=mcmc.params,
             batch=batch[ix],
             batchElements=nbatch,
             label_switch=FALSE,
             .internal.constraint=5e-4)
  obj <- startingValues(obj)
  if(!is.null(obj)){
    obj@probz[, 1] <- 1
  }
  obj
}

##

#' extract data, latent variable, and batch for given observation
#' @name extract
#' @param x An object of class MultiBatchModel, McmcChains, or McmcParams
#' @param i An element of the instance to be extracted.
#' @param j Not used.
#' @param ... Not used.
#' @param drop Not used.
#' @return An object of class 'MultiBatchModel'
#' @aliases [,MultiBatchModel-method [,MultiBatchModel,ANY-method [,MultiBatchModel,ANY,ANY-method [,MultiBatchModel,ANY,ANY,ANY-method
#' @docType methods
#' @rdname extract-methods
setMethod("[", "MultiBatchModel", function(x, i, j, ..., drop=FALSE){
  if(!missing(i)){
    y(x) <- y(x)[i]
    z(x) <- z(x)[i]
    batch(x) <- batch(x)[i]
  }
  x
})

#' @rdname bic-method
#' @aliases bic,MultiBatchModel-method
setMethod("bic", "MultiBatchModel", function(object){
  object <- useModes(object)
  ## K: number of free parameters to be estimated
  ##   - component and batch-specific parameters:  theta, sigma2  ( k(model) * nBatch(model))
  ##   - mixing probabilities: (k-1)*nBatch
  ##   - component-specific parameters: mu, tau2                 2 x k(model)
  ##   - length-one parameters: sigma2.0, nu.0                   +2
  K <- 2*k(object)*nBatch(object) + (k(object)-1) + 2*k(object) + 2
  n <- length(y(object))
  bicstat <- -2*(log_lik(object) + logPrior(object)) + K*(log(n) - log(2*pi))
  bicstat
})


#' @rdname collapseBatch-method
#' @aliases collapseBatch,MultiBatchModel-method
setMethod("collapseBatch", "MultiBatchModel", function(object){
  collapseBatch(y(object), as.character(batch(object)))
})


batchLik <- function(x, p, mean, sd)  p*dnorm(x, mean, sd)


setMethod("computeMeans", "MultiBatchModel", function(object){
  compute_means(object)
})


setMethod("computePrec", "MultiBatchModel", function(object){
  compute_prec(object)
})


setMethod("computePrior", "MultiBatchModel", function(object){
  compute_logprior(object)
})

.computeModesBatch <- function(object){
  i <- argMax(object)
  mc <- chains(object)
  B <- nBatch(object)
  K <- k(object)
  thetamax <- matrix(theta(mc)[i, ], B, K)
  sigma2max <- matrix(sigma2(mc)[i, ], B, K)
  pmax <- p(mc)[i, ]
  mumax <- mu(mc)[i, ]
  tau2max <- tau2(mc)[i,]
  modes <- list(theta=thetamax,
                sigma2=sigma2max,
                mixprob=pmax,
                mu=mumax,
                tau2=tau2max,
                nu0=nu.0(mc)[i],
                sigma2.0=sigma2.0(mc)[i],
                zfreq=zFreq(mc)[i, ],
                loglik=log_lik(mc)[i],
                logprior=logPrior(mc)[i])
  modes
}

setMethod("computeModes", "MultiBatchModel", function(object){
  .computeModesBatch(object)
})

componentVariances <- function(y, z)  v <- sapply(split(y, z), var)


setMethod("computeVars", "MultiBatchModel", function(object){
  compute_vars(object)
})


#' @rdname mu-method
#' @aliases mu,MultiBatchModel-method
setMethod("mu", "MixtureModel", function(object) object@mu)


setReplaceMethod("mu", "MultiBatchModel", function(object, value){
  object@mu <- value
  object
})

nBatch <- function(object) length(uniqueBatch(object))

batchElements <- function(object) object@batchElements

setReplaceMethod("p", "MixtureModel", function(object, value){
  object@pi <- value
  object
})

setMethod("pMean", "MultiBatchModel", function(object) {
  mns <- colMeans(pic(object))
  mns
})

setMethod("showMeans", "MixtureModel", function(object){
  thetas <- round(theta(object), 2)
  mns <- c("\n", paste0(t(cbind(thetas, "\n")), collapse="\t"))
  mns <- paste0("\t", mns[2])
  mns <- paste0("\n", mns[1])
  mns
})

setMethod("showSigmas", "MixtureModel", function(object){
  sigmas <- round(sqrt(sigma2(object)), 2)
  sigmas <- c("\n", paste0(t(cbind(sigmas, "\n")), collapse="\t"))
  sigmas <- paste0("\t", sigmas[2])
  sigmas <- paste0("\n", sigmas[1])
  sigmas
})


setReplaceMethod("sigma2", "MixtureModel", function(object, value){
  rownames(value) <- uniqueBatch(object)
  object@sigma2 <- value
  object
})

#' @aliases sigma<-,MixtureModel-method
setReplaceMethod("sigma", "MixtureModel", function(object, value){
  sigma2(object) <- value^2
  object
})

#' @rdname sigma2-method
#' @aliases sigma2,MixtureModel-method
setMethod("sigma2", "MixtureModel", function(object) {
  s2 <- object@sigma2
  ##s2 <- matrix(s2, nBatch(object), k(object))
  rownames(s2) <- uniqueBatch(object)
  s2
})

#' @rdname sigma2-method
#' @aliases sigma,MixtureModel-method
setMethod("sigma", "MixtureModel", function(object) {
  s2 <- sigma2(object)
  ##s2 <- matrix(s2, nBatch(object), k(object))
  sqrt(s2)
})

setMethod("tablez", "MultiBatchModel", function(object){
  tab <- table(batch(object), z(object))
  tab[uniqueBatch(object), , drop=FALSE]
})

setMethod("sigmaMean", "MultiBatchModel", function(object) {
  mns <- colMeans(sigmac(object))
  mns <- matrix(mns, nBatch(object), k(object))
  rownames(mns) <- uniqueBatch(object)
  mns
})


#' @rdname tau2-method
#' @aliases tau2,MixtureModel-method
setMethod("tau2", "MixtureModel", function(object) object@tau2)

setReplaceMethod("tau2", "MultiBatchModel", function(object, value){
  object@tau2 <- value
  object
})


#' @rdname theta-method
#' @aliases theta,MixtureModel-method
setMethod("theta", "MixtureModel", function(object) {
  b <- object@theta
  ##b <- matrix(b, nBatch(object), k(object))
  rownames(b) <- uniqueBatch(object)
  b
})


setReplaceMethod("theta", "MultiBatchModel", function(object, value){
  rownames(value) <- uniqueBatch(object)
  object@theta <- value
  object
})

setMethod("thetaMean", "MultiBatchModel", function(object) {
  mns <- colMeans(thetac(object))
  mns <- matrix(mns, nBatch(object), k(object))
  rownames(mns) <- uniqueBatch(object)
  mns
})

setMethod("show", "MultiBatchModel", function(object){
  ##callNextMethod()
  cls <- class(object)
  cat(paste0("An object of class ", cls), "\n")
  cat("     n. obs              :", length(y(object)), "\n")
  cat("     n. batches          :", nBatch(object), "\n")
  cat("     k                   :", k(object), "\n")
  cat("     nobs/batch          :", table(batch(object)), "\n")
  cat("     log lik (s)         :", round(log_lik(object), 1), "\n")
  cat("     log prior (s)       :", round(logPrior(object), 1), "\n")
  cat("     log marginal lik (s):", round(marginal_lik(object), 1), "\n")
})

setMethod("tablez", "MixtureModel", function(object){
  tab <- table(batch(object), z(object))
  tab <- tab[uniqueBatch(object), , drop=FALSE]
  tab
})

uniqueBatch <- function(object) unique(batch(object))

setMethod("updateMultinomialProb", "MultiBatchModel", function(object){
  update_multinomialPr(object)
})


setMethod("computeLoglik", "MultiBatchModel", function(object){
  compute_loglik(object)
})

setMethod("updateZ", "MultiBatchModel", function(object){
  update_z(object)
})

setMethod("updateObject", "MultiBatchModel", function(object){
  chains(object) <- updateObject(chains(object))
  object <- callNextMethod(object)
  object
})
