% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/methods-MixtureModel.R
\name{muc}
\alias{muc}
\title{Retrieve overall mean at each iteration of the MCMC.}
\usage{
muc(object)
}
\arguments{
\item{object}{an object of class MarginalModel or BatchModel}
}
\value{
A vector of length N or matrix of size N x B, where N is the 
number of observations and B is the number of unique batches.
}
\description{
Retrieve overall mean at each iteration of the MCMC.
}
\examples{
     head(muc(SingleBatchModelExample))
}
