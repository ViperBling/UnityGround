#define PREFIX_SUM_ARRAY_NAME PrefixArray

// Original array needs to be calculated.
// Make its length round to THREADS.
RWStructuredBuffer<uint> PREFIX_SUM_ARRAY_NAME;

// Temp array with the length of ceil(length(arr) / THREADS).
RWStructuredBuffer<uint> GroupArray;

// Make it power of two.
#define THREADS 1024

// Double buffered
groupshared uint Temp[THREADS * 2];

[numthreads(THREADS, 1, 1)]
void PrefixSum1(uint3 id : SV_DispatchThreadID)
{
    
}

[numthreads(THREADS, 1, 1)]
void PrefixSum2(uint3 id : SV_DispatchThreadID)
{
    
}

[numthreads(THREADS, 1, 1)]
void PrefixSum3(uint3 id : SV_DispatchThreadID)
{
    
}