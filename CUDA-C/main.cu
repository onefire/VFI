//////////////////////////////////////////////////////////////////////////////
///
/// @file main.cu
///
/// @brief File containing main function for the VFI problem.
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
#include "auxFuncs.h"
#include "cublas_v2.h"
#include <iostream>
#include <ctime>
#include <typeinfo>
#include <fstream>

using namespace std;

#include "vfStep.cu"

//////////////////////////////////////////////////////////////////////////////
///
/// @fn main()
///
/// @brief Main function for the VFI problem.
///
/// @details This function solves a standard neoclassical growth model with
/// value function iteration on a GPU.
///
/// @details See Aldrich, Eric M., Jesus Fernandez-Villaverde,
/// A. Ronald Gallant and Juan F. Rubio-Ramirez (2011), "Tapping the
/// supercomputer under your desk: Solving dynamic equilibrium models with
/// graphics processors", Journal of Economic Dynamics & Control, 35, 386-393.
///
/// @returns 0 upon successful completion, 1 otherwise.
///
//////////////////////////////////////////////////////////////////////////////
int main()
{ 

  // admin
  int imax;
  REAL diff = 1.0;
  cublasHandle_t handle;
  cublasCreate(&handle);
  REAL negOne = -1.0;
  double tic = curr_second(); // Start time

  // Load parameters
  parameters params;
  params.load("../parameters.txt");
  int nk = params.nk;
  int nz = params.nz;

  // pointers to variables in device memory
  REAL *K, *Z, *P, *V0, *V, *G, *Vtemp;

  // allocate variables in device memory
  size_t sizeK = nk*sizeof(REAL);
  size_t sizeZ = nz*sizeof(REAL);
  size_t sizeP = nz*nz*sizeof(REAL);
  size_t sizeV = nk*nz*sizeof(REAL);
  size_t sizeG = nk*nz*sizeof(REAL);
  cudaMalloc((void**)&K, sizeK);
  cudaMalloc((void**)&Z, sizeZ);
  cudaMalloc((void**)&P, sizeP);
  cudaMalloc((void**)&V0, sizeV);
  cudaMalloc((void**)&Vtemp, sizeV);
  cudaMalloc((void**)&V, sizeV);
  cudaMalloc((void**)&G, sizeG);

  // blocking
  const int block_size = 4; ///< Block size for CUDA kernel.
  dim3 dimBlockV(block_size, nz);
  dim3 dimGridV(nk/block_size,1);
 
  // compute TFP grid, capital grid and initial VF
  REAL hK[nk], hZ[nz], hP[nz*nz], hV0[nk*nz];
  ar1(params, hZ, hP);
  kGrid(params, hZ, hK);
  vfInit(params, hZ, hV0);

  // copy capital grid, TFP grid and transition matrix to GPU memory
  cudaMemcpy(K, hK, sizeK, cudaMemcpyHostToDevice);
  cudaMemcpy(Z, hZ, sizeZ, cudaMemcpyHostToDevice);
  cudaMemcpy(P, hP, sizeP, cudaMemcpyHostToDevice);
  cudaMemcpy(V0, hV0, sizeV, cudaMemcpyHostToDevice);

  // iterate on the value function
  int count = 0;
  bool how = false;
  while(fabs(diff) > params.tol){
    if(count < 3 | count % params.howard == 0) how = false; else how = true;
    vfStep<<<dimGridV,dimBlockV>>>(params,how,K,Z,P,V0,V,G);
    if(typeid(realtype) == typeid(singletype)){
      cublasSaxpy(handle, nk*nz, (float*)&negOne, (float*)V, 1, (float*)V0, 1);
      cublasIsamax(handle, nk*nz, (float*)V0, 1, &imax);
    } else if(typeid(realtype) == typeid(doubletype)){
      cublasDaxpy(handle, nk*nz, (double*)&negOne, (double*)V, 1, (double*)V0, 1);
      cublasIdamax(handle, nk*nz, (double*)V0, 1, &imax);
    }
    cudaMemcpy(&diff, V0+imax, sizeof(REAL), cudaMemcpyDeviceToHost);
    Vtemp = V0;
    V0 = V;
    V = Vtemp;
    ++count;
  }
  V = V0;
  
  // Compute solution time
  REAL toc = curr_second();
  REAL solTime  = toc - tic;

  // copy value and policy functions to host memory
  REAL* hV = new REAL[nk*nz];
  REAL* hG = new REAL[nk*nz];
  cudaMemcpy(hV, V, sizeV, cudaMemcpyDeviceToHost);
  cudaMemcpy(hG, G, sizeG, cudaMemcpyDeviceToHost);

  // free variables in device memory
  cudaFree(K);
  cudaFree(Z);
  cudaFree(P);
  cudaFree(V0);
  cudaFree(V);
  cudaFree(Vtemp);
  cudaFree(G);
  cublasDestroy(handle);

  // write to file (row major)
  ofstream fileSolTime, fileValue, filePolicy;
  fileSolTime.open("solutionTime.dat");
  fileValue.open("valueFunc.dat");
  filePolicy.open("policyFunc.dat");
  fileSolTime << solTime << endl;
  fileValue << nk << endl;
  fileValue << nz << endl;
  filePolicy << nk << endl;
  filePolicy << nz << endl;
  for(int jx = 0 ; jx < nz ; ++jx){
    for(int ix = 0 ; ix < nk ; ++ix){
      fileValue << hV[ix*nz+jx] << endl;
      filePolicy << hG[ix*nz+jx] << endl;
    }
  }  
  fileSolTime.close();
  fileValue.close();
  filePolicy.close();

  return 0;

}
