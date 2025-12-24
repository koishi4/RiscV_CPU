# Latency Notes

This document summarizes module-level latency/throughput assumptions for demos.

## muldiv_unit
- MUL/MULH/MULHU/MULHSU: fixed 4-cycle latency
- DIV/DIVU/REM/REMU: fixed 32-cycle latency
- Single-issue: one operation in flight

## dma_engine
- Read then write per word; ideal throughput is one word every 2 cycles when mem_ready=1
- Additional stalls track mem_ready
