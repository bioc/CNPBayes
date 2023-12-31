% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/AllGenerics.R, R/methods-Hyperparameters.R,
%   R/methods-MixtureModel.R
\docType{methods}
\name{dfr}
\alias{dfr}
\alias{dfr<-}
\alias{dfr,Hyperparameters-method}
\alias{dfr<-,Hyperparameters,numeric-method}
\alias{dfr,MixtureModel-method}
\alias{dfr<-,MixtureModel,numeric-method}
\alias{dfr,MixtureModel,numeric-method}
\title{Accessor for degrees of freedom}
\usage{
dfr(object)

dfr(object) <- value

\S4method{dfr}{Hyperparameters}(object)

\S4method{dfr}{Hyperparameters,numeric}(object) <- value

\S4method{dfr}{MixtureModel}(object)

\S4method{dfr}{MixtureModel,numeric}(object) <- value
}
\arguments{
\item{object}{a Hyperparameters- or MixtureModel-derived class}

\item{value}{scalar providing degrees of freedom for t-distribution}
}
\description{
Accessor for degrees of freedom

Accessor for degrees of freedom
}
\examples{
  hp <- Hyperparameters()
  dfr(hp)
  dfr(hp) <- 10
  dfr(hp)
}
