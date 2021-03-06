#' Bayesian estimation in mixed nonlinear regression models
#'
#' @description Bayesian estimation of the random effects \eqn{\phi_j} in the mixed nonlinear regression model
#'  \eqn{y_{ij}= f(\phi_j, t_{ij}) + \epsilon_{ij}, \epsilon_{ij}~N(0,\gamma^2*s^2(t_{ij}), \phi_j~N(\mu, \Omega)} and the parameters
#'  \eqn{\mu, \Omega, \gamma^2}.
#' @param t vector of observation times
#' @param y matrix of the M trajectories
#' @param prior list of prior parameters - list(m, v, priorOmega, alpha, beta)
#' @param start list of starting values
#' @param fODE regression function
#' @param sVar variance function
#' @param ipred which of the M trajectories is the one to be predicted
#' @param cut the index how many of the ipred-th series are used for estimation
#' @param len number of iterations of the MCMC algorithm
#' @param Omega structure of the variance matrix Omega of the random effects, diagonal matrix, otherwise inverse wishart distributed
#' @param mod model out of {Gompertz, Richards, logistic, Weibull}, only used instead of fODE
#' @param propPar proposal standard deviation of phi is |start$mu|*propPar
#'
#' @return
#' \item{phi}{samples from posterior of \eqn{\phi}}
#' \item{mu}{samples from posterior of \eqn{\mu}}
#' \item{Omega}{samples from posterior of \eqn{\Omega}}
#' \item{gamma2}{samples from posterior of \eqn{\gamma^2}}
#'
#' @examples
#' mod <- "Gompertz"
#' fODE <- getFun("ODE", mod)
#' mu <- getPar("ODE", mod, "truePar")
#' n <- 5
#' parameters <- defaultPar(mu, n)
#' y <- drawData("ODE", fODE, parameters)
#' t <- parameters$t
#' prior <- getPrior(mu, parameters$gamma2)
#' start <- getStart(mu, n)
#' chains <- estReg(t, y, prior=prior, start=start, fODE=fODE)
#' plot(phi_ij(chains$phi, 1, 1), type="l")
#' plot(chains$gamma, type="l"); abline(h=parameters$gamma2, col=2)
#'
#' @export
estReg <- function(t, y, prior, start, fODE, sVar, ipred=1, cut, len=1000, Omega="diag", mod=c("Gompertz","logistic","Weibull","Richards","Paris","Paris2"), propPar=0.02){
  mod <- match.arg(mod)
  if(is.matrix(y)){
    if(nrow(y)==length(t)){
      y <- t(y)
    }else{
      if(ncol(y)!=length(t)){
        print("length of t has to be equal to the columns of y")
        break
      }
    }
    if(missing(cut)) cut <- length(t)
    t1 <- t
    y1 <- y
    t <- list()
    y <- list()
    for(i in (1:nrow(y1))[-ipred]){
      t[[i]] <- t1
      y[[i]] <- y1[i,]
    }
    t[[ipred]] <- t1[1:cut]
    y[[ipred]] <- y1[ipred,1:cut]
  }

  if(missing(fODE)) fODE <- getFun("ODE", mod)
  if(missing(sVar)) sVar <- getFunVar()

  if(Omega=="diag"){
    postOm <- function(phi,mu){
      postOmegaDiag(prior$priorOmega$alpha,prior$priorOmega$beta,phi,mu)
    }
    if(!is.list(prior$priorOmega)){print("prior parameter for Omega has to be list of alpha and beta")}
  }else{
    postOm <- function(phi,mu){
      postOmega(prior$priorOmega,phi,mu)
    }
    if(!is.matrix(prior$priorOmega)){print("prior parameter for Omega has to be matrix R")}
  }
  propSd <- abs(start$mu)*propPar
  postPhii <- function(lastPhi, mu, Omega, gamma2, y, t){
    lt <- length(t)
    phi_old <- lastPhi

    phi_drawn <- rnorm(length(mu),phi_old,propSd)
    ratio <- dmvnorm(phi_drawn,mu,Omega)/dmvnorm(phi_old,mu,Omega)
    ratio <- ratio* prod(dnorm(y, fODE(phi_drawn,t), sqrt(gamma2*sVar(t)))/dnorm(y, fODE(phi_old,t), sqrt(gamma2*sVar(t))))
    if(is.na(ratio)){ratio <- 0}
    if(runif(1)<ratio){
      phi_old <- phi_drawn
    }
    phi_old
  }
  N_all <- sum(sapply(y,length))
  n <- length(y)
  postGamma2 <- function(phi){
    alphaPost <- prior$alpha + N_all/2
    help <- numeric(n)
    for(i in 1:n){
      help[i] <- sum((y[[i]]-fODE(phi[i,], t[[i]]))^2/sVar(t[[i]]))
    }
    betaPost <-  prior$beta + sum(help)/2
    1/rgamma(1, alphaPost, betaPost)
  }

  phi_out <- list()
  mu_out <- matrix(0,len,length(start$mu))
  Omega_out <- list()
  gamma2_out <- numeric(len)

  phi <- start$phi
  gamma2 <- start$gamma2
  mu <- start$mu
  Omega <- postOm(phi, mu)

  for(count in 1:len){

    for(i in 1:n){
      phi[i,] <- postPhii(phi[i,], mu, Omega, gamma2, y[[i]], t[[i]])
    }
    mu <- postmu(phi, prior$m, prior$v, Omega)
    Omega <- postOm(phi, mu)
    gamma2 <- postGamma2(phi)

    phi_out[[count]] <- phi
    mu_out[count,] <- mu
    Omega_out[[count]] <- Omega
    gamma2_out[count] <- gamma2
  }
  list(phi=phi_out, mu=mu_out, Omega=Omega_out, gamma2=gamma2_out)
}
