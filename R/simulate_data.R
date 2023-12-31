#' Create simulated batch data for testing.
#'
#' @param N number of observations
#' @param p a vector indicating probability of membership to each component
#' @param theta a matrix of means.  Columns are components and rows are batches.
#' @param sds a matrix of standard deviations.  Columns are components and rows are batches.
#' @param batch a vector of labels indication from which batch each simulation should come from
#' @param zz a vector indicating latent variable membership. Can be omitted.
#' @param df length-1 numeric vector for the t-distribution degrees of freedom
#' @return An object of class 'MultiBatchModel'
#' @examples
#' k <- 3
#' nbatch <- 3
#' means <- matrix(c(-1.2, -1.0, -0.8,
#'                   -0.2, 0, 0.2,
#'                   0.8, 1, 1.2), nbatch, k, byrow=FALSE)
#' sds <- matrix(0.1, nbatch, k)
#' N <- 1500
#' truth <- simulateBatchData(N=N,
#'                            batch=rep(letters[1:3], length.out=N),
#'                            theta=means,
#'                            sds=sds,
#'                            p=c(1/5, 1/3, 1-1/3-1/5))
#' @export
simulateBatchData <- function(N=2500, p, theta, sds, batch, zz, df=10){
  ## order ys by batch
  if(length(p) != ncol(theta)) stop("length of p must be same as ncol(theta)")
  if(sum(p)!=1) stop("elements of p must sum to 1")
  if(missing(batch)) {
    batch <- rep(1L, N)
  } else {
    batch <- as.integer(factor(batch))
  }
  batch <- sort(batch)
  if(missing(zz)) {
    zz <- simulateZ(N, p)
  }
  yy <- rep(NA, N)
  ub <- unique(batch)
  rownames(theta) <- rownames(sds) <- ub
  for(b in ub){
    index <- which(batch==b)
    nn <- length(index)
    cn <- zz[index]
    mu <- theta[b, ]
    s <- sds[b, ]
    yy[index] <- rnorm(nn, mu[cn], s[cn])/sqrt(rchisq(nn, df)/df)
  }
  ##ix <- order(batch)
  ##object <- MultiBatchModel(yy, batch=batch, k=ncol(theta))
  object <- MultiBatchModel2(dat=yy, batches=batch,
                             hpList(k=ncol(theta))[["MB"]])
  z(object) <- as.integer(factor(zz))
  ##
  ## Must initialize the slots independently (must point to different
  ## locations in memory)
  ##
  theta(object) <- computeMeans(object)
  dataMean(object) <- computeMeans(object)
  mu(object) <- colMeans(dataMean(object))
  sigma2(object) <- computeVars(object)
  dataPrec(object) <- 1/computeVars(object)
  p(object) <- as.numeric(table(z(object))/N)
  log_lik(object) <- computeLoglik(object)
  object
}

#' Create simulated data for testing.
#'
#' @param N number of observations
#' @param p a vector indicating probability of membership to each component
#' @param theta a vector of means, one per component
#' @param sds a vector of standard deviations, one per component
#' @param df length-1 numeric vector for the t-distribution degrees of freedom
#' @return An object of class 'SingleBatchModel'
#' @examples
#' truth <- simulateData(N=2500, p=rep(1/3, 3),
#'                       theta=c(-1, 0, 1),
#'                       sds=rep(0.1, 3))
#' @export
simulateData <- function(N, p, theta, sds, df=10){
  theta <- matrix(theta, nrow=1)
  sds <- matrix(sds, nrow=1)
  object <- simulateBatchData(N=N,
                              p=p,
                              theta=theta,
                              sds=sds,
                              df=df,
                              batch=rep(1L, N))
  return(object)
##  zz <- simulateZ(N, p)
##  y <- rnorm(N, theta[zz], sds[zz]/sqrt(rchisq(N, df)/df))
##  ## y <- rnorm(N, theta[zz], sds[zz])
##  ##object <- SingleBatchModel(data=y, k=length(theta))
##  object <- SingleBatchModel2(dat=y, hp=hpList(k=length(theta))[["SB"]])
##  z(object) <- as.integer(factor(zz, levels=unique(sort(zz))))
##  p(object) <- p
##  theta(object) <- matrix(as.numeric(sapply(split(y(object), z(object)), mean)),
##                          nrow=1)
##  sigma2(object) <- matrix(as.numeric(sapply(split(y(object), z(object)), var)),
##                           nrow=1)
##  p(object) <- as.numeric(sapply(split(y(object),
##                                       z(object)),
##                                 length)/length(z(object)))
##  mu(object) <- mean(theta(object))
##  tau2(object) <- var(theta(object))
##  log_lik(object) <- computeLoglik(object)
##  logPrior(object) <- computePrior(object)
##  object
}

simulateZ <- function(N, p){
  P <- rdirichlet(N, p)
  cumP <- t(apply(P, 1, cumsum))
  u <- runif(N)
  zz <- rep(NA, N)
  zz[u < cumP[, 1]] <- 1
  k <- 2
  while(k <= ncol(P)){
    zz[u < cumP[, k] & u >= cumP[, k-1]] <- k
    k <- k+1
  }
  zz
}

cumProbs <- function(p, k){
  pcum <- list()
  cols <- 2:(k-1)
  for(j in seq_along(cols)){
    g <- cols[j]
    pcum[[j]] <- rowSums(p[, 1:g, drop=FALSE])
  }
  pcum2 <- cbind(p[, 1], do.call(cbind, pcum), 1)
}

simulateProbeLevel <- function(samples=2000,
                               cnvs=200, K=4,
                               probes=10,
                               arguments, qual="easy") {
  l <- probes
  sl.good <- arguments$sl.good
  sl.bad <- arguments$sl.bad
  prbias <- arguments$prbias
  n <- arguments$n
  prvar <- arguments$prvar

  Z <- array(data=NA, dim=c(cnvs,samples,K))
  Z[,,1] <- 1L
  ## Simulate copy numbers from multinomial distribution according to HWE
  theta = 30
  alpha = rbeta(200, 13.3, 13.3)
  ## probability of starting with homozygous,hemizygous,diploid
  ##
  for(j in 2:K) {
    k = j
    i = 0:(k-1)
    lambda = matrix(NA, cnvs, k)
    for(s in 1:cnvs) {
      w = choose(k-1, i) * alpha[s]^i * (1 - alpha[s])^((k-1) - i)
      lambda[s,] <- rdirichlet(1, w * theta)
    }
    ##        w = choose(k-1, i) * alpha^i * (1 - alpha)^((k-1) - i)
    ##        lambda <- rdirichlet(cnvs, w * theta)
    Z[,,j] <- rMultinom(lambda, samples)
    ##randomly shift multinomial sample to begin with 0, 1, or 2 copy number.
    ##Z[,,j] + sample(c(-1,0,1), 1)
  }

  A <- array(data=NA, dim=c(samples, l, cnvs, K))
  Pb  <- matrix(NA, cnvs, l)
  Pv <- matrix(NA, cnvs, l)
  for(i in 1:nrow(Pb)) Pb[i,] <- rnorm(l, 0, prbias)
  for(i in 1:nrow(Pb)) Pv[i,]   <- rgamma(l, shape = prvar[1], scale = prvar[2])

  corrupted <- sample(samples, ceiling(0.004*samples))
  for(k in 1:K) {
    for(j in 1:cnvs) {
      for(i in 1:samples) {
        p.mean <- c(rep(sl.good,3),rep(sl.bad,7)) * Z[j,i,k] + Pb[j,]
        p.sd <- n + Pv[j,]

        A[i,,j,k] <- rnorm(l,  p.mean, p.sd)
      }
      ## null measurements for medium and bad quality
      if(qual == "medium" || qual == "hard") {
        v <- range(A[,,j,k])
        for(ind in corrupted) A[ind,,j,k] <- runif(l, v[1], v[2])
      }
    }
  }
  return(list("measurements"=A, "assignments"=Z))
}
