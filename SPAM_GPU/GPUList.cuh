#include "cuda.h"
#include "cuda_runtime.h"
#include "cuda_runtime_api.h"
#include <iostream>
#include <time.h>

using namespace std;
__global__ void CudaSupportCount(int** src1, int** src2, int** dst, int * result, int listLen, int len, int bitmapType, bool type, int oldBlock);
__global__ void MemCheck(int ** src1);
__host__ __device__ int SupportCount(int n, int bitmapType);

#ifndef GPU_LIST
#define GPU_LIST

class GPUList{
public:
	int ** src1;
	int ** gsrc1;
	int ** src2;
	int ** gsrc2;
	int ** dst;
	int ** gdst;
	int * result;
	int * gresult;
	int length;
	bool hasGPUMem;
	static clock_t kernelTime;
	static clock_t copyTime;
	static clock_t H2DTime;
	static clock_t D2HTime;

	GPUList(int size){
		length = 0;

		cudaHostAlloc(&src1, sizeof(int*)* size, cudaHostAllocDefault);
		cudaHostAlloc(&src2, sizeof(int*)* size, cudaHostAllocDefault);
		cudaHostAlloc(&dst, sizeof(int*)* size, cudaHostAllocDefault);

		//src1 = new int*[size];
		//src2 = new int*[size];
		//dst = new int*[size];
		//hasGPUMem = false;
		if (cudaMalloc(&gsrc1, sizeof(int*)* size) != cudaSuccess){
			cout << "cudaMalloc error in gsrc1" << endl;
			system("pause");
			exit(-1);
		}
		if (cudaMalloc(&gsrc2, sizeof(int*)*size) != cudaSuccess){
			cout << "cudaMalloc error in gsrc2" << endl;
			system("pause");
			exit(-1);
		}
		if (cudaMalloc(&gdst, sizeof(int*)*size) != cudaSuccess){
			cout << "cudaMalloc error gdist" << endl;
			system("pause");
			exit(-1);
		}

	}
	
	void AddToTail(int *s1, int *s2, int *d, bool debug = false){
		src1[length] = s1;
		src2[length] = s2;
		dst[length] = d;
		if (debug && length == 112){
			cout << "here length 112 is " << src1[length] << endl;
		}
		length++;
		return;
	}

	void clear(){
		length = 0;
	}

	void CudaMemcpy(bool kind, cudaStream_t cudaStream){
		if (!kind){
			clock_t t1 = clock();
			if (cudaMemcpyAsync(gsrc1, src1, sizeof(int*)*length, cudaMemcpyHostToDevice, cudaStream) != cudaSuccess){
				cout << "cudaMemcpy error in gsrc1" << endl;
				system("pause");
				exit(-1);
			}
			if (cudaMemcpyAsync(gsrc2, src2, sizeof(int*)*length, cudaMemcpyHostToDevice, cudaStream) != cudaSuccess){
				cout << "cudaMemcpy error in gsrc2" << endl;
				system("pause");
				exit(-1);
			}
			if (cudaMemcpyAsync(gdst, dst, sizeof(int*)*length, cudaMemcpyHostToDevice, cudaStream) != cudaSuccess){
				cout << "cudaMemcpy error in gdist" << endl;
				system("pause");
				exit(-1);
			}
			H2DTime += (clock() - t1);
		}
		else{
			clock_t t1 = clock();
			cudaError_t error;
			error = cudaMemcpyAsync(result, gresult, sizeof(int)* length, cudaMemcpyDeviceToHost, cudaStream);
			if (error != cudaSuccess){
				cout << error << endl;
				cout << "cudaMemcpy error in gresult" << endl;
				system("pause");
				exit(-1);
			}
			D2HTime += (clock() - t1);
		}
		//instructionTime += (clock() - t1);
		//t1 = clock();
		//cudaStreamSynchronize(cudaStream);
		//waitingTime += clock() - t1;
	}

	void SupportCounting(int blockNum, int threadNum, int bitmapType, bool type, cudaStream_t kernelStream){
		CudaMemcpy(false, kernelStream);
		clock_t t1 = clock();
		for (int oldBlock = 0; oldBlock < length; oldBlock += blockNum){
			CudaSupportCount << < (length-oldBlock) < blockNum?(length-oldBlock) : blockNum, threadNum, sizeof(int)*threadNum, kernelStream >> >(gsrc1, gsrc2, gdst, gresult, length, SeqBitmap::size[bitmapType], bitmapType, type, oldBlock);
			cudaError_t err = cudaGetLastError();
			if (err != cudaSuccess) printf("Error: %s\n", cudaGetErrorString(err));
		}
		kernelTime += (clock() - t1);
	}
};

clock_t GPUList::kernelTime = 0;
clock_t GPUList::copyTime = 0;
clock_t GPUList::H2DTime = 0;
clock_t GPUList::D2HTime = 0;

#endif

__global__ void CudaSupportCount(int** src1, int** src2, int** dst, int * result, int listLen, int len, int bitmapType, bool type, int oldBlock){

	__shared__ extern int sup[];

	int tid = threadIdx.x;
	int bid = blockIdx.x;
	int blockSize = blockDim.x;
	unsigned int *gsrc1, *gsrc2, *gdst;

	int currentBlock = oldBlock + bid;
	if (currentBlock >= listLen) return;

	sup[tid] = 0;
	gsrc1 = (unsigned*) src1[currentBlock];
	gsrc2 = (unsigned*) src2[currentBlock];
	gdst =  (unsigned*) dst[currentBlock];
	int s1, s2, d;

	__syncthreads();
	int tmp;
	if (bitmapType == 4){
		tmp = len / 2 + blockSize;
	}
	else{
		tmp = len + blockSize;
	}

//	int lmax = 4190;
//	int lmin = 4182;
//	if (tid == 0 && bid == 0) printf("%d %d  ", lmax, lmin);
	for (int i = 0; i < tmp; i += blockSize){
		int threadPos = i + tid;
		if ((threadPos >= len&& bitmapType != 4) || (bitmapType ==4 && threadPos >= len/2)){
			break;
		}
		if (bitmapType == 4){
			unsigned int s11, s12, s21, s22, d1, d2;
			s11 = gsrc1[2 * threadPos];
			s12 = gsrc1[2 * threadPos + 1];
			s21 = gsrc2[2 * threadPos];
			s22 = gsrc2[2 * threadPos + 1];
			d1 = s11 & s21;
			d2 = s12 & s22;
			if (d1 || d2) sup[tid]++;
			gdst[2 * threadPos] = d1;
			gdst[2 * threadPos + 1] = d2;

		}
		else{
			s1 = gsrc1[threadPos];
			s2 = gsrc2[threadPos];
			d = s1 & s2;
			sup[tid] += SupportCount( d, bitmapType);
			gdst[threadPos] = d;
		}
	}
	__syncthreads();

	for (int s = blockSize / 2; s > 0; s >>= 1){
		if (tid < s){
			sup[tid] += sup[tid + s];
		}
		__syncthreads();
	}
	if (tid == 0){
			result[currentBlock] += sup[0];
	}
}

__global__ void MemCheck(int ** src1){
	for (int i = 105; i <= 115; i++){
		printf("%d %x ", i, src1[i]);
	}
	printf("\n");
}

__host__ __device__ int SupportCount(int n, int bitmapType){
	int r = 0;
	switch (bitmapType){
	case 0:
		if (n & 0xF0000000) r++;
		if (n & 0x0F000000) r++;
		if (n & 0x00F00000) r++;
		if (n & 0x000F0000) r++;
		if (n & 0x0000F000) r++;
		if (n & 0x00000F00) r++;
		if (n & 0x000000F0) r++;
		if (n & 0x0000000F) r++;
		break;
	case 1:
		if (n & 0xFF000000) r++;
		if (n & 0x00FF0000) r++;
		if (n & 0x0000FF00) r++;
		if (n & 0x000000FF) r++;
		break;
	case 2:
		if (n & 0xFFFF0000) r++;
		if (n & 0x0000FFFF) r++;
		break;
	case 3:
		if (n) r++;
		break;
	default:
		printf("this should not happen!\n");
		break;
	}
	return r;
}