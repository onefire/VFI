//////////////////////////////////////////////////////////////////////////////
///
/// @file vfStep.cpp
///
/// @brief File containing main iterative step of the VFI problem.
///
/// @author Eric M. Aldrich \n
///         ealdrich@ucsc.edu
///
/// @version 1.0
///
/// @date 23 Oct 2012
///
/// @copyright Copyright Eric M. Aldrich 2012 \n
///            Distributed under the Boost Software License, Version 1.0
///            (See accompanying file LICENSE_1_0.txt or copy at \n
///            http://www.boost.org/LICENSE_1_0.txt)
///
//////////////////////////////////////////////////////////////////////////////

#include "global.h"
#include <math.h>
#include <iostream>
#include <typeinfo>
#include <Eigen/Dense>
#include <stdlib.h>

using namespace std;
using namespace Eigen;

//////////////////////////////////////////////////////////////////////////////
///
/// @brief Function to update value function.
///
/// @details This function performs one iteration of the value function
/// iteration algorithm, using V0 as the current value function and either
/// maximizing the LHS of the Bellman if @link howard @endlink = false or
/// using the concurrent policy function as the argmax if
/// @link howard @endlink = true. Maximization is performed by either
/// @link gridMax @endlink or @link binaryMax @endlink.
///
/// @param [in] param Object of class parameters.
/// @param [in] howard Indicates if the current iteration of the value
/// function will perform a maximization (false) or if it will simply compute
/// the new value function using the concurrent policy function (true).
/// @param [in] K Grid of capital values.
/// @param [in] Z Grid of TFP values.
/// @param [in] P TFP transition matrix.
/// @param [in] V0 Matrix storing current value function.
/// @param [out] V Matrix storing updated value function.
/// @param [in,out] G Matrix storing policy function (updated if
/// howard = false).
///
/// @returns Void.
///
//////////////////////////////////////////////////////////////////////////////
void vfStep(const parameters& param, const bool& howard, const VectorXR& K,
	    const VectorXR& Z, const MatrixXR& P, const MatrixXR& V0,
	    MatrixXR& V, MatrixXi& G)
{

  // Basic parameters
  const int nk = param.nk;
  const int nz = param.nz;
  const REAL eta = param.eta;
  const REAL beta = param.beta;
  const REAL alpha = param.alpha;
  const REAL delta = param.delta;
  const char maxtype = param.maxtype;

  // output and depreciated capital
  MatrixXR ydepK = (K.array().pow(alpha)).matrix()*Z.transpose();
  ydepK.colwise() += (1-delta)*K;

  int klo, khi, nksub;
  VectorXR Exp, w;
  VectorXR::Index indMax;
  for(int i = 0 ; i < nk ; ++i){
    for(int j = 0 ; j < nz ; ++j){

      // maximize on non-howard steps
      if(howard == false){

	// impose constraints on grid for future capital
	klo = 0;
	khi = binaryVal(ydepK(i,j), K); // consumption nonnegativity
	if(K[khi] > ydepK(i,j)) khi -= 1;

	// further restrict capital grid via monotonicity (CPU only)
	if(i > 0){
	  if(G(i-1,j) > klo & G(i-1,j) < khi) klo = G(i-1,j);
	}
	nksub = khi-klo+1;

	// continuation value for subgrid
	// note that this computes more values than necessary for
	// the maximization methods, but the Eigen matrix multiply
	// is so efficient that it is faster to compute all possible
	// continuation values outside of the max routine rather than
	// only the necessary values inside the routine.
	Exp = V0.block(klo, 0, nksub, nz)*P.row(j).transpose();

	// maximization
	if(maxtype == 'g'){
	  gridMax(klo, nksub, ydepK(i,j), eta, beta, K, Exp, V(i,j), G(i,j));
	} else if (maxtype == 'b') {
	  binaryMax(klo, nksub, ydepK(i,j), eta, beta, K, Exp, V(i,j), G(i,j));
	}

      // iterate on the policy function on non-howard steps
      } else {
	Exp = V0.row(G(i,j))*P.row(j).transpose();
	V(i,j) = pow(ydepK(i,j)-K(G(i,j)),1-eta)/(1-eta) + beta*Exp(0);
      }
    }
  }
}
