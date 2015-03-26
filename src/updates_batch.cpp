#include "update.h" // getK
#include "miscfunctions.h" // for rdirichlet
#include <Rmath.h>
#include <Rcpp.h>

using namespace Rcpp ;

IntegerVector rev(IntegerVector ub){
  int B = ub.size() ;
  IntegerVector unique_batch(B);
  // for some reason unique is 
  for(int b = 0; b < B; ++b) unique_batch[b] = ub[ B-b-1 ] ;
  return unique_batch ;
}

// [[Rcpp::export]]
RcppExport SEXP tableBatchZ(SEXP xmod){
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  int K = getK(model.slot("hyperparams")) ;
  // int N = x.size() ;
  IntegerVector batch = model.slot("batch") ;
  IntegerVector ub = unique(batch) ;
  ub = rev(ub) ;
  int B = ub.size() ;
  IntegerVector z = model.slot("z") ;
  NumericMatrix nn(B, K) ;
  for(int j = 0; j < B; ++j){
    for(int k = 0; k < K; k++){
      nn(j, k) = sum(z == (k+1) & batch == ub[j] ) ;
      if(nn(j, k) < 1) {
        nn(j, k) = 1 ;
      }
    }
  }  
  return nn ;  
}

// [[Rcpp::export]]
RcppExport SEXP compute_loglik_batch(SEXP xmod){
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  int K = getK(model.slot("hyperparams")) ;
  NumericVector x = model.slot("data") ;
  int N = x.size() ;  
  NumericVector p = model.slot("pi") ;
  IntegerVector batch = model.slot("batch") ;
  IntegerVector ub = unique(batch);
  NumericMatrix theta = model.slot("theta") ;
  NumericMatrix sigma2 = model.slot("sigma2") ;
  IntegerVector batch_freq = model.slot("batchElements") ;
  NumericVector loglik_(1) ;
  NumericMatrix tabz = tableBatchZ(xmod) ;
  int B = ub.size() ;
  NumericMatrix P(B, K) ;
  NumericMatrix sigma(B, K) ;
  ub = rev(ub) ;
  // component probabilities for each batch
  for(int b = 0; b < B; ++b){
    int rowsum = 0 ;
    for(int k = 0; k < K; ++k){
      rowsum += tabz(b, k) ;
      sigma(b, k) = sqrt(sigma2(b, k)) ;
    }
    for(int k = 0; k < K; ++k){
      P(b, k) = tabz(b, k)/rowsum ;
    }
  }
  NumericMatrix lik(N, K) ;
  // double y ;
  NumericVector tmp(1) ;
  NumericVector this_batch(N) ;
  for(int k = 0; k < K; ++k){
    NumericVector dens(N) ;
    for(int b = 0; b < B; ++b){
      this_batch = batch == ub[b] ;
      tmp = P(b, k) * dnorm(x, theta(b, k), sigma(b, k)) * this_batch ;
      dens = dens + tmp ;
    }
    lik(_, k) = dens ;
  }
  NumericVector marginal_prob(N) ;
  for(int i = 0; i < N; ++i){
    for(int k = 0; k < K; ++k) {
      marginal_prob[i] += lik(i, k) ;
    }
    loglik_[0] += log(marginal_prob[i]) ;
  }
  return loglik_ ;
}

// [[Rcpp::export]]
RcppExport SEXP update_mu_batch(SEXP xmod){
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  int K = getK(hypp) ;
  double tau2_0 = hypp.slot("tau2.0") ;
  double tau2_0_tilde = 1/tau2_0 ;
  double mu_0 = hypp.slot("mu.0") ;
  
  NumericVector tau2 = model.slot("tau2") ;
  NumericVector tau2_tilde = 1/tau2 ;
  IntegerVector z = model.slot("z") ;
  NumericMatrix theta = model.slot("theta") ;
  IntegerVector nn = model.slot("zfreq") ;

  IntegerVector batch = model.slot("batch") ;
  IntegerVector ub = unique(batch) ;
  ub = rev(ub) ;  
  int B = ub.size() ;
  
  NumericVector tau2_B_tilde(K) ;;
  for(int k = 0; k < K; ++k) tau2_B_tilde[k] = tau2_0_tilde + B*tau2_tilde[k] ;
  
  NumericVector w1(K) ;
  NumericVector w2(K) ;
  for(int k = 0; k < K; ++k){
    w1[k] = tau2_0_tilde/(tau2_0_tilde + B*tau2_tilde[k]) ;
    w2[k] = B*tau2_tilde[k]/(tau2_0_tilde + B*tau2_tilde[k]) ;
  }
  NumericMatrix n_b = tableBatchZ(xmod) ;
  NumericVector theta_bar(K) ;
  NumericVector th(K) ;
  //
  // sort the rows of theta
  //
//  NumericMatrix thetas = clone(theta) ;
//  for(int b=0; b < B; ++b){
//    th = theta(b, _) ;
//    //NumericVector ts = clone(th) ;
//    //std::sort(ts.begin(), ts.end()) ;
//    theta(b, _) = ts ;
//  }
  
  for(int k = 0; k < K; ++k){
    double n_k = 0.0 ; // number of observations for component k
    double colsumtheta = 0.0;
    for(int i = 0; i < B; ++i){
      colsumtheta += n_b(i, k)*theta(i, k) ;
      n_k += n_b(i, k) ;
    }
    theta_bar[k] = colsumtheta/n_k ;
  }
  NumericVector mu_n(K) ;
  NumericVector mu_new(K) ;
  double post_prec ;
  for(int k=0; k<K; ++k){
    post_prec = sqrt(1.0/tau2_B_tilde[k]) ;
    mu_n[k] = w1[k]*mu_0 + w2[k]*theta_bar[k] ;
    mu_new[k] = as<double>(rnorm(1, mu_n[k], post_prec)) ;
  }
  //return mu_n ;
  return mu_new ;
}

// [[Rcpp::export]]
RcppExport SEXP update_tau2_batch(SEXP xmod){
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  double m2_0 = hypp.slot("m2.0") ;
  int K = getK(hypp) ;
  double eta_0 = hypp.slot("eta.0") ;

  NumericVector mu = model.slot("mu") ;
  NumericMatrix theta = model.slot("theta") ;
  
  IntegerVector batch = model.slot("batch") ;
  IntegerVector ub = unique(batch) ;
  // ub = rev(ub) ;  
  int B = ub.size() ;
  double eta_B = eta_0 + B ;
  
  NumericVector s2_k(B) ;
  for(int k = 0; k < K; ++k){
    for(int i = 0; i < B; ++i){
      s2_k[k] += pow(theta(i, k) - mu[k], 2) ;
    }
  }
  double m2_k ;
  NumericVector tau2(K) ;
  for(int k = 0; k < K; ++k) {
    m2_k = 1.0/eta_B*(eta_0*m2_0 + s2_k[k]) ;
    tau2[k] = 1.0/as<double>(rgamma(1, 0.5*eta_B, 2.0/(eta_B*m2_k))) ;
  }
  return tau2 ;
}

// [[Rcpp::export]]
RcppExport SEXP update_sigma20_batch(SEXP xmod){
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  int K = getK(hypp) ;
  IntegerVector batch = model.slot("batch") ;
  IntegerVector ub = unique(batch) ;
  // ub = rev(ub) ;  
  int B = ub.size() ;
  double a = hypp.slot("a") ;
  double b = hypp.slot("b") ;
  double nu_0 = model.slot("nu.0") ;  

  NumericMatrix sigma2 = model.slot("sigma2") ;
  double prec ;
  for(int i = 0; i < B; ++i){
    for(int k = 0; k < K; ++k){
      prec += 1.0/sigma2(i, k) ;
    }
  }
  double a_k = a + 0.5*(K * B)*nu_0 ;
  double b_k = b + 0.5*prec ;
  NumericVector sigma2_0(1) ;
  sigma2_0[0] = as<double>(rgamma(1, a_k, 1.0/b_k)) ;
  return sigma2_0 ;
}

// [[Rcpp::export]]
RcppExport SEXP update_nu0_batch(SEXP xmod){
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  int K = getK(hypp) ;
  NumericMatrix sigma2 = model.slot("sigma2") ;
  int B = sigma2.nrow() ;  
  double sigma2_0 = model.slot("sigma2.0") ;  
  double prec = 0.0;
  double lprec = 0.0 ;
  double betas = hypp.slot("beta") ;
  for(int i = 0; i < B; ++i){
    for(int k = 0; k < K; ++k){
      prec += 1.0/sigma2(i, k) ;
      lprec += log(1.0/sigma2(i, k)) ;
    }
  }
  NumericVector x(100) ;  
  for(int i = 0; i < 100; i++)  x[i] = i+1 ;
  NumericVector lpnu0(100);
  NumericVector y1(100) ;
  NumericVector y2(100) ;
  NumericVector y3(100) ;
  NumericVector prob(100) ;
  y1 = K*(0.5*x*log(sigma2_0*0.5*x) - lgamma(x*0.5)) ;
  y2 = (0.5*x - 1.0) * lprec ;
  y3 = x*(betas + 0.5*sigma2_0*prec) ;
  lpnu0 =  y1 + y2 - y3 ;
  prob = exp(lpnu0) ; // - maxprob) ;
  prob = prob/sum(prob) ;
  NumericVector nu0(1) ;
  //int u ;
  NumericVector u(1) ;
  double cumprob ;
  // sample x with probability prob
  for(int i = 0; i < 100; i++){
    cumprob += prob[i] ;
    u = runif(1) ;
    if (u[0] < cumprob){
      nu0[0] = x[i] ;
      break ;
    }
  }
  return nu0 ;  
}

// [[Rcpp::export]]
RcppExport SEXP update_multinomialPr_batch(SEXP xmod) {
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  int K = getK(hypp) ;
  IntegerVector batch = model.slot("batch") ;
  IntegerVector ub = unique(batch) ;
  ub = rev(ub) ;
  NumericVector p = model.slot("pi") ;
  NumericMatrix sigma2 = model.slot("sigma2") ;
  NumericMatrix theta = model.slot("theta") ;
  // ub = rev(ub) ;  
  int B = sigma2.nrow() ;
  NumericVector x = model.slot("data") ;
  IntegerVector nb = model.slot("batchElements") ;
  int N = x.size() ;
  NumericMatrix lik(N, K) ;
  NumericVector this_batch(N) ;
  NumericVector tmp(N) ;
  for(int k = 0; k < K; ++k){
    NumericVector dens(N) ;
    for(int b = 0; b < B; ++b){
      this_batch = batch == ub[b] ;
      tmp = p[k] * dnorm(x, theta(b, k), sqrt(sigma2(b, k))) * this_batch ;
      dens = dens + tmp ;
    }
    lik(_, k) = dens ;
  }
  NumericMatrix P(N, K) ;
  for(int i = 0; i < N; ++i){
    double rowsum = 0.0 ;
    for(int k = 0; k < K; ++k) {
      rowsum += lik(i, k) ;
    }
    P(i, _) = lik(i, _)/rowsum ;
  }
  return P ;
  // return this_batch ;
  //return lik ;
}

//
// Note, this is currently the same as the marginal model
//
// [[Rcpp::export]]
RcppExport SEXP update_p_batch(SEXP xmod) {
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;  
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  int K = getK(hypp) ;
  IntegerVector z = model.slot("z") ;  
  IntegerVector nn = model.slot("zfreq");
  IntegerVector alpha = hypp.slot("alpha") ;
  NumericVector alpha_n(K) ;  // really an integer vector, but rdirichlet expects numeric
  for(int k=0; k < K; k++) alpha_n[k] = alpha[k] + nn[k] ;
  NumericVector p(K) ;
  // pass by reference
  rdirichlet(alpha_n, p) ;
  return p ;
  //  return alpha_n ;
}

// [[Rcpp::export]]
RcppExport SEXP update_z_batch(SEXP xmod) {
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;  
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  int K = getK(hypp) ;
  NumericVector x = model.slot("data") ;
  int n = x.size() ;
  NumericMatrix p(n, K);
  p = update_multinomialPr_batch(xmod) ;
  NumericMatrix cumP(n, K);
  for(int i=0; i < n; i++){
    for(int k = 0; k < K; k++){
      if(k > 0){
        cumP(i, k) = cumP(i, k-1) + p(i, k) ;
      } else {
        cumP(i, k) = p(i, k) ;
      }
    }
  }
  NumericVector u = runif(n) ;
  IntegerVector zz(n) ;
  for(int i = 0; i < n; i++){
    int k = 0 ;
    while(k <= K) {
      if( u[i] < cumP(i, k) ){
        zz[i] = k + 1 ;
        break ;
      }
      k++ ;
    }
  }
  return zz ;
}

// [[Rcpp::export]]
RcppExport SEXP compute_means_batch(SEXP xmod) {
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  NumericVector x = model.slot("data") ;
  int n = x.size() ;
  IntegerVector z = model.slot("z") ;
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  int K = getK(hypp) ;  
  IntegerVector nn = model.slot("zfreq") ;
  IntegerVector batch = model.slot("batch") ;
  IntegerVector ub = unique(batch) ;
  ub = rev(ub) ;
  int B = ub.size() ;
  NumericMatrix means(B, K) ;
  NumericMatrix tabz = tableBatchZ(xmod) ;
  NumericVector is_z(n) ;
  NumericVector this_batch(n) ;  
  for(int b = 0; b < B; ++b){
    this_batch = batch == ub[b] ;
    for(int k = 0; k < K; ++k){
      is_z = z == (k + 1) ;
      means(b, k) = sum(x * this_batch * is_z) / tabz(b, k) ;
    }
  }
  return means ;
}

// [[Rcpp::export]]
RcppExport SEXP compute_prec_batch(SEXP xmod){
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  NumericVector x = model.slot("data") ;
  int n = x.size() ;
  IntegerVector z = model.slot("z") ;
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  int K = getK(hypp) ;  
  IntegerVector nn = model.slot("zfreq") ;
  IntegerVector batch = model.slot("batch") ;
  IntegerVector ub = unique(batch) ;
  ub = rev(ub) ;
  int B = ub.size() ;
  NumericMatrix vars(B, K) ;
  NumericMatrix prec(B, K) ;
  NumericMatrix tabz = tableBatchZ(xmod) ;
  NumericMatrix mn = model.slot("data.mean") ;
  for(int i = 0; i < n; ++i){
    for(int b = 0; b < B; ++b){
      if(batch[i] != ub[b]) continue ;
      for(int k = 0; k < K; ++k){
        if(z[i] == k+1){
          vars(b, k) += pow(x[i] - mn(b, k), 2.0)/(tabz(b, k)-1) ;
        }
        prec(b, k) = 1.0/vars(b, k) ;
      }
    }
  }
  return prec ;
}


// [[Rcpp::export]]
RcppExport SEXP compute_vars_batch(SEXP xmod) {
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  NumericVector x = model.slot("data") ;
  int n = x.size() ;
  IntegerVector z = model.slot("z") ;
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  int K = getK(hypp) ;  
  IntegerVector nn = model.slot("zfreq") ;
  IntegerVector batch = model.slot("batch") ;
  IntegerVector ub = unique(batch) ;
  ub = rev(ub) ;
  int B = ub.size() ;
  NumericMatrix prec(B, K) ;
  NumericMatrix vars(B, K) ;
  NumericMatrix tabz = tableBatchZ(xmod) ;
  NumericMatrix mn = model.slot("data.mean") ;
  for(int i = 0; i < n; ++i){
    for(int b = 0; b < B; ++b){
      if(batch[i] != ub[b]) continue ;
      for(int k = 0; k < K; ++k){
        if(z[i] == k+1){
          vars(b, k) += (pow(x[i] - mn(b, k), 2.0)/(tabz(b, k)-1)) ;
        }
      }
    }
  }
//   for(int b = 0; b < B; ++b){
//     for(int k = 0; k < K; ++k){
//       prec(b, k) = 1.0/vars(b, k) ;
//     }
//   }
//   model.slot("data.prec") = prec ;
//  prec = compute_prec_batch(vars) ;
  //return vars ;
  //  return prec ;
  return vars ;
}

// [[Rcpp::export]]
RcppExport SEXP compute_logprior_batch(SEXP xmod){
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  int K = getK(hypp) ;
  IntegerVector batch = model.slot("batch") ;
  IntegerVector ub = unique(batch) ;
  NumericVector tau2 = model.slot("tau2") ;
  NumericVector mu = model.slot("mu") ;
  double mu_0 = hypp.slot("mu.0") ;
  double tau2_0 = hypp.slot("tau2.0") ;
  NumericVector sigma2_0 = model.slot("sigma2.0") ;
  double a = hypp.slot("a") ;
  double b = hypp.slot("b") ;
  double beta = hypp.slot("beta") ;
  IntegerVector nu0 = model.slot("nu.0") ;
  NumericVector p_mu(K) ;
  NumericVector p_sigma2_0(K) ;
  NumericVector p_nu0(K) ;
  p_mu = dnorm(mu, mu_0, sqrt(tau2_0)) ;
  p_sigma2_0 = dgamma(sigma2_0, a, 1.0/b) ;
  p_nu0 = dgeom(nu0, beta) ;
  NumericVector logprior(1) ;
  logprior = sum(log(p_mu)) + log(p_sigma2_0) + log(p_nu0) ;
  return logprior ;
}

// [[Rcpp::export]]
RcppExport SEXP update_theta_batch(SEXP xmod){
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  int K = getK(hypp) ;
  NumericVector x = model.slot("data") ;
  NumericMatrix theta = model.slot("theta") ;
  NumericVector tau2 = model.slot("tau2") ;
  NumericMatrix sigma2 = model.slot("sigma2") ;
  NumericMatrix n_hb = tableBatchZ(xmod) ;
  NumericVector mu = model.slot("mu") ;
  int B = n_hb.nrow() ;
  NumericMatrix ybar = model.slot("data.mean") ;
  NumericMatrix theta_new(B, K) ;
  double w1 = 0.0 ;
  double w2 = 0.0 ;
  double mu_n = 0.0 ;
  double tau_n = 0.0 ;
  double post_prec = 0.0 ;
  for(int b = 0; b < B; ++b){
    for(int k = 0; k < K; ++k){
      post_prec = 1.0/tau2[k] + n_hb(b, k)*1.0/sigma2(b, k) ;
      tau_n = sqrt(1.0/post_prec) ;
      w1 = (1.0/tau2[k])/post_prec ;
      w2 = (n_hb(b, k) * 1.0/sigma2(b, k))/post_prec ;
      mu_n = w1*mu[k] + w2*ybar(b, k) ;
      theta_new(b, k) = as<double>(rnorm(1, mu_n, tau_n)) ;
    }
  }
  return theta_new ;
}

// [[Rcpp::export]]
RcppExport SEXP update_sigma2_batch(SEXP xmod){
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  int K = getK(hypp) ;
  NumericVector x = model.slot("data") ;
  NumericMatrix theta = model.slot("theta") ;
  double nu_0 = model.slot("nu.0") ;
  double sigma2_0 = model.slot("sigma2.0") ;
  int n = x.size() ;
  IntegerVector z = model.slot("z") ;
  int B = theta.nrow() ;
  //IntegerVector nn = model.slot("zfreq") ;
  NumericMatrix tabz = tableBatchZ(xmod) ;
  IntegerVector batch = model.slot("batch") ;
  IntegerVector ub(K) ;
  ub = rev(unique(batch)) ;
  NumericMatrix ss(B, K) ;
  for(int i = 0; i < n; ++i){
    for(int b = 0; b < B; ++b){
      if(batch[i] != ub[b]) continue ;
      for(int k = 0; k < K; ++k){
        if(z[i] == k+1){
          ss(b, k) += pow(x[i] - theta(b, k), 2) ;
        }
      }
    }
  }
  //NumericMatrix sigma2_nh(B, K) ;
  double shape ;
  double rate ;
  double sigma2_nh ;
  double nu_n ;
  NumericMatrix sigma2_tilde(B, K) ;
  NumericMatrix sigma2_(B, K) ;
  for(int b = 0; b < B; ++b){
    for(int k = 0; k < K; ++k){
      nu_n = nu_0 + tabz(b, k) ;
      sigma2_nh = 1.0/nu_n*(nu_0*sigma2_0 + ss(b, k)) ;
      shape = 0.5 * nu_n ;
      rate = shape * sigma2_nh ;
      sigma2_tilde(b, k) = as<double>(rgamma(1, shape, 1.0/rate)) ;
      sigma2_(b, k) = 1.0/sigma2_tilde(b, k) ;
    }
  }
  return sigma2_ ;
}


// [[Rcpp::export]]
RcppExport SEXP mcmc_batch_burnin(SEXP xmod, SEXP mcmcp) {
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  int K = getK(hypp) ;  
  Rcpp::S4 params(mcmcp) ;
  IntegerVector up = params.slot("param_updates") ;
  int S = params.slot("burnin") ;
  if( S == 0 ){
    return xmod ;
  }
  for(int s = 0; s < S; ++s){
    if(up[0] > 0)
      model.slot("theta") = update_theta_batch(xmod) ;
    if(up[1] > 0)
      model.slot("sigma2") = update_sigma2_batch(xmod) ;
    if(up[3] > 0)
      model.slot("mu") = update_mu_batch(xmod) ;    
    if(up[4] > 0)    
      model.slot("tau2") = update_tau2_batch(xmod) ;
    if(up[6] > 0)        
      model.slot("sigma2.0") = update_sigma20_batch(xmod) ;    
    if(up[5] > 0)    
      model.slot("nu.0") = update_nu0_batch(xmod) ;
    if(up[2] > 0)
      model.slot("pi") = update_p_batch(xmod) ;
    if(up[7] > 0){        
      model.slot("z") = update_z_batch(xmod) ;
      model.slot("zfreq") = tableZ(K, model.slot("z")) ;
    }
    model.slot("data.mean") = compute_means_batch(xmod) ;
    model.slot("data.prec") = compute_prec_batch(xmod) ;
  }
  // compute log prior probability from last iteration of burnin
  // compute log likelihood from last iteration of burnin
  model.slot("loglik") = compute_loglik_batch(xmod) ;
  model.slot("logprior") = compute_logprior_batch(xmod) ;    
  return xmod ;
  // return vars ;
}

// [[Rcpp::export]]
RcppExport SEXP mcmc_batch(SEXP xmod, SEXP mcmcp) {
  RNGScope scope ;
  Rcpp::S4 model(xmod) ;
  Rcpp::S4 chain(model.slot("mcmc.chains")) ;
  Rcpp::S4 hypp(model.slot("hyperparams")) ;
  Rcpp::S4 params(mcmcp) ;
  IntegerVector up = params.slot("param_updates") ;
  int K = getK(hypp) ;
  int T = params.slot("thin") ;
  int S = params.slot("iter") ;
  NumericVector x = model.slot("data") ;
  int N = x.size() ;
  NumericMatrix theta = chain.slot("theta") ;
  NumericMatrix sigma2 = chain.slot("sigma2") ;
  NumericMatrix pmix = chain.slot("pi") ;
  NumericMatrix zfreq = chain.slot("zfreq") ;
  NumericMatrix mu = chain.slot("mu") ;  
  NumericMatrix tau2 = chain.slot("tau2") ;
  NumericVector nu0 = chain.slot("nu.0") ;
  NumericVector sigma2_0 = chain.slot("sigma2.0") ;
  NumericVector loglik_ = chain.slot("loglik") ;
  NumericVector logprior_ = chain.slot("logprior") ;
  NumericVector th(K) ;
  NumericVector s2(K) ;
  NumericVector p(K) ;
  NumericVector m(K) ; //mu
  NumericVector t2(K) ;//tau2
  NumericVector n0(1) ;//nu0
  IntegerVector z(N) ;
  NumericVector s20(1) ; //sigma2_0
  //  NumericVector mns(1) ;   
  // NumericVector precs(1) ;
  NumericVector ll(1) ;
  NumericVector lp(1) ;
  IntegerVector tmp(K) ;
  IntegerVector zf(K) ;
  // Initial values
  th = model.slot("theta") ;
  s2 = model.slot("sigma2") ;
  p = model.slot("pi") ;
  m = model.slot("mu") ;
  t2 = model.slot("tau2") ;
  n0 = model.slot("nu.0") ;
  s20 = model.slot("sigma2.0") ;
  zf = model.slot("zfreq") ;
  ll = model.slot("loglik") ;
  lp = model.slot("logprior") ;
  // Record initial values in chains
  mu(0, _) = m ;
  nu0[0] = n0[0] ;
  sigma2_0[0] = s20[0] ;
  loglik_[0] = ll[0] ;
  logprior_[0] = lp[0] ;
  int i = 0 ;
  theta(0, _) = th ;
  tau2(0, _) = t2 ;
  sigma2(0, _) = s2 ;
  pmix(0, _) = p ;
  zfreq(0, _) = zf ;
  // start at 1 instead of zero. Initial values are as above
  for(int s = 1; s < S; ++s){
    if(up[0] > 0) {
      th = update_theta_batch(xmod) ;
      model.slot("theta") = th ;
    } else {
      th = model.slot("theta") ;
    }
    theta(s, _) = th ;
    if(up[1] > 0){
      s2 = update_sigma2_batch(xmod) ;
      model.slot("sigma2") = s2 ;
    } else {
      s2 = model.slot("sigma2") ;
    }
    sigma2(s, _) = s2 ;
    if(up[2] > 0){
      p = update_p_batch(xmod) ;
      model.slot("pi") = p ;      
    } else {
      p = model.slot("pi") ;
    }
    pmix(s, _) = p ;
    if(up[3] > 0){
      m = update_mu_batch(xmod) ;
      model.slot("mu") = m ;
    } else {
      m = model.slot("mu") ;
    }
    mu(s, _) = m ;
    if(up[4] > 0){    
      t2 = update_tau2_batch(xmod) ;
      model.slot("tau2") = t2 ;
    } else {
      t2 = model.slot("tau2") ;
    }
    tau2(s, _) = t2 ;
    if(up[5] > 0){        
      n0 = update_nu0_batch(xmod) ;
      model.slot("nu.0") = n0 ;
    } else {
      n0 = model.slot("nu.0") ;
    }
    nu0[s] = n0[0] ;
    if(up[6] > 0){        
      s20 = update_sigma20_batch(xmod) ;
      model.slot("sigma2.0") = s20 ;
    } else {
      s20 = model.slot("sigma2.0") ;
    }
    sigma2_0[s] = s20[0] ;
    if(up[7] > 0){
      z = update_z_batch(xmod) ;
      model.slot("z") = z ;
      tmp = tableZ(K, z) ;
      model.slot("zfreq") = tmp ;
    } else {
      tmp = model.slot("zfreq") ;
    }
    zfreq(s, _) = tmp ;    
    model.slot("data.mean") = compute_means_batch(xmod) ;
    model.slot("data.prec") = compute_prec_batch(xmod) ;
    ll = compute_loglik_batch(xmod) ;
    loglik_[s] = ll[0] ;
    model.slot("loglik") = ll ;
    lp = compute_logprior_batch(xmod) ;
    logprior_[s] = lp[0] ;
    model.slot("logprior") = lp ;
    // Thinning
    for(int t = 0; t < T; ++t){
      if(up[0] > 0)
        model.slot("theta") = update_theta_batch(xmod) ;
      if(up[1] > 0)      
        model.slot("sigma2") = update_sigma2_batch(xmod) ;
      if(up[2] > 0)
        model.slot("pi") = update_p_batch(xmod) ;
      if(up[3] > 0)      
        model.slot("mu") = update_mu_batch(xmod) ;
      if(up[4] > 0)      
        model.slot("tau2") = update_tau2_batch(xmod) ;
      if(up[5] > 0)
        model.slot("nu.0") = update_nu0_batch(xmod) ;
      if(up[6] > 0)
        model.slot("sigma2.0") = update_sigma20_batch(xmod) ;
      if(up[7] > 0){
        model.slot("z") = update_z_batch(xmod) ;
        model.slot("zfreq") = tableZ(K, model.slot("z")) ;
      }
      model.slot("data.mean") = compute_means_batch(xmod) ;
      model.slot("data.prec") = compute_prec_batch(xmod) ;
    }
  }
  //
  // assign chains back to object
  //
  chain.slot("theta") = theta ;
  chain.slot("sigma2") = sigma2 ;
  chain.slot("pi") = pmix ;
  chain.slot("mu") = mu ;
  chain.slot("tau2") = tau2 ;
  chain.slot("nu.0") = nu0 ;
  chain.slot("sigma2.0") = sigma2_0 ;
  chain.slot("zfreq") = zfreq ;
  chain.slot("loglik") = loglik_ ;
  chain.slot("logprior") = logprior_ ;
  model.slot("mcmc.chains") = chain ;
  return xmod ;
}
