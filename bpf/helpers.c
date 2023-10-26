// Copyright (c) Microsoft Corporation
// SPDX-License-Identifier: MIT

#include "bpf.h"

// Test to measure the overhead of bpf_get_prandom_u32
SEC("xdp/test_bpf_get_prandom_u32") int test_bpf_get_prandom_u32(void* ctx)
{
    int i = bpf_get_prandom_u32();
    return 0;
}

SEC("xdp/test_bpf_ktime_get_boot_ns") int test_bpf_ktime_get_boot_ns(void* ctx)
{
    uint64_t i = bpf_ktime_get_boot_ns();
    return 0;
}

SEC("xdp/test_bpf_ktime_get_ns") int test_bpf_ktime_get_ns(void* ctx)
{
    uint64_t i = bpf_ktime_get_ns();
    return 0;
}

SEC("xdp/test_bpf_get_smp_processor_id") int test_bpf_get_smp_processor_id(void* ctx)
{
    uint64_t i = bpf_get_smp_processor_id();
    return 0;
}
