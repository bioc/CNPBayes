% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/AllGenerics.R, R/methods-McmcChains.R,
%   R/methods-MultiBatchModel.R
\docType{methods}
\name{mu}
\alias{mu}
\alias{mu,McmcChains-method}
\alias{mu,MixtureModel-method}
\alias{mu,MultiBatchModel-method}
\title{Retrieve overall mean}
\usage{
mu(object)

\S4method{mu}{McmcChains}(object)

\S4method{mu}{MixtureModel}(object)
}
\arguments{
\item{object}{see \code{showMethods(mu)}}
}
\value{
A vector containing 'mu'
}
\description{
Retrieve overall mean
}
\examples{
     mu(SingleBatchModelExample)
}
