#define PREFIX_SUM_ARRAY_NAME GlobalHashCounter

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
    uint length, stride;
    PREFIX_SUM_ARRAY_NAME.GetDimensions(length, stride);

    // id.x从0-1024*1024，和1023按位与后，会得到0-1023的值，也就是所有大于1023的值都会被忽略
    uint localIndex = id.x & (THREADS - 1);
    if (id.x < length)
    {
        // 从粒子的hash表中取出每个Hash对应的粒子数量
        Temp[localIndex] = PREFIX_SUM_ARRAY_NAME[id.x];
    }
    // 同步点，确保之前的Temp写入完成
    GroupMemoryBarrierWithGroupSync();

    uint bufferIndex = 0;
    for (uint i = 1; i < THREADS; i <<= 1)
    {
        if (id.x < length)
        {
            if (localIndex >= i)
            {
                Temp[localIndex + (bufferIndex ^ 1) * THREADS] = Temp[(localIndex - i) + bufferIndex * THREADS] + Temp[localIndex + bufferIndex * THREADS];
            }
            else
            {
                Temp[localIndex + (bufferIndex ^ 1) * THREADS] = Temp[localIndex + bufferIndex * THREADS];
            }
        }
        bufferIndex ^= 1;
        GroupMemoryBarrierWithGroupSync();
    }
    // Write results.
    if (id.x < length)
    {
        PREFIX_SUM_ARRAY_NAME[id.x] = Temp[localIndex + bufferIndex * THREADS];
    }
}

[numthreads(THREADS, 1, 1)]
void PrefixSum2(uint3 id : SV_DispatchThreadID)
{
    uint length, stride;
    GroupArray.GetDimensions(length, stride);

    uint localIndex = id.x & (THREADS - 1);
    if (id.x < length)
    {
        Temp[localIndex] = PREFIX_SUM_ARRAY_NAME[id.x * THREADS + (THREADS - 1)];
    }
    // 同步点，确保之前的Temp写入完成
    GroupMemoryBarrierWithGroupSync();

    uint bufferIndex = 0;
    for (uint i = 1; i < THREADS; i <<= 1)
    {
        if (id.x < length)
        {
            if (localIndex >= i)
            {
                Temp[localIndex + (bufferIndex ^ 1) * THREADS] = Temp[(localIndex - i) + bufferIndex * THREADS] + Temp[localIndex + bufferIndex * THREADS];
            }
            else
            {
                Temp[localIndex + (bufferIndex ^ 1) * THREADS] = Temp[localIndex + bufferIndex * THREADS];
            }
        }
        bufferIndex ^= 1;
        GroupMemoryBarrierWithGroupSync();
    }
    // Write results.
    if (id.x < length)
    {
        GroupArray[id.x] = Temp[localIndex + bufferIndex * THREADS];
    }
}

[numthreads(THREADS, 1, 1)]
void PrefixSum3(uint3 id : SV_DispatchThreadID)
{
    uint length, stride;
    PREFIX_SUM_ARRAY_NAME.GetDimensions(length, stride);

    if (id.x < length)
    {
        if (id.x >= THREADS)
        {
            PREFIX_SUM_ARRAY_NAME[id.x] += GroupArray[id.x / THREADS - 1];
        }
    }
}