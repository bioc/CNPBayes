% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/methods-Hyperparameters.R
\name{HyperparametersMultiBatch}
\alias{HyperparametersMultiBatch}
\title{Create an object of class 'HyperparametersMultiBatch' for the
batch mixture model}
\usage{
HyperparametersMultiBatch(k = 3L, mu.0 = 0, tau2.0 = 0.4,
  eta.0 = 32, m2.0 = 0.5, alpha, beta = 0.1, a = 1.8, b = 6,
  dfr = 100)
}
\arguments{
\item{k}{length-one integer vector specifying number of components
(typically 1 <= k <= 4)}

\item{mu.0}{length-one numeric vector of the of the normal prior
for the component means.}

\item{tau2.0}{length-one numeric vector of the variance for the normal
prior of the component means}

\item{eta.0}{length-one numeric vector of the shape parameter for
the Inverse Gamma prior of the component variances, tau2_h.  The
shape parameter is parameterized as 1/2 * eta.0.  In the batch
model, tau2_h describes the inter-batch heterogeneity of means for
component h.}

\item{m2.0}{length-one numeric vector of the rate parameter for the
Inverse Gamma prior of the component variances, tau2_h.  The rate
parameter is parameterized as 1/2 * eta.0 * m2.0.  In the batch
model, tau2_h describes the inter-batch heterogeneity of means for
component h.}

\item{alpha}{length-k numeric vector of the shape parameters for
the dirichlet prior on the mixture probabilities}

\item{beta}{length-one numeric vector for the parameter of the
geometric prior for nu.0 (nu.0 is the shape parameter of the
Inverse Gamma sampling distribution for the component-specific
variances. Together, nu.0 and sigma2.0 model inter-component
heterogeneity in variances.).  beta is a probability and must be
in the interval [0,1].}

\item{a}{length-one numeric vector of the shape parameter for the
Gamma prior used for sigma2.0 (sigma2.0 is the shape parameter of
the Inverse Gamma sampling distribution for the component-specific
variances).}

\item{b}{a length-one numeric vector of the rate parameter for the
Gamma prior used for sigma2.0 (sigma2.0 is the rate parameter of
the Inverse Gamma sampling distribution for the component-specific
variances)}

\item{dfr}{length-one numeric vector for t-distribution degrees of freedom}
}
\value{
An object of class HyperparametersBatch
}
\description{
Create an object of class 'HyperparametersMultiBatch' for the
batch mixture model
}
\examples{
HyperparametersMultiBatch(k=3)

}
\seealso{
\code{\link{hpList}}
}
