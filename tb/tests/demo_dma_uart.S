# Demo: DMA + LED heartbeat + UART dump
# hart0: configure DMA, blink LED1 while polling DONE (LED0 set on done).
# hart1: wait for DONE, then stream DMA dst bytes over UART.

# Entry (both harts @ 0x0000_0000)
csrrs x5, mhartid, x0
bne   x5, x0, hart1_start

# hart0: DMA setup
lui  x9, 0x40001      # IO base 0x4000_1000
lui  x10, 0x40000     # DMA base 0x4000_0000
addi x11, x0, 0x200   # src
addi x12, x0, 0x300   # dst
addi x13, x0, 0x100   # len (256 bytes)
sw   x11, 0(x10)      # DMA_SRC
sw   x12, 4(x10)      # DMA_DST
sw   x13, 8(x10)      # DMA_LEN
addi x14, x0, 1       # START
sw   x14, 12(x10)     # DMA_CTRL
addi x20, x0, 0       # LED state

heart_loop:
    lui  x8, 0x400        # delay count (~0x400000)
delay_loop:
    addi x8, x8, -1
    bne  x8, x0, delay_loop

    xori x20, x20, 0x2    # toggle LED1
    lw   x6, 16(x10)      # DMA_STAT
    andi x7, x6, 0x2      # DONE?
    beq  x7, x0, no_done
    ori  x20, x20, 0x1    # set LED0
no_done:
    sw   x20, 0(x9)       # IO_LED
    beq  x0, x0, heart_loop

# hart1: wait for DMA done, then dump dst buffer
hart1_start:
    lui  x9, 0x40001      # IO base
    lui  x10, 0x40000     # DMA base
    addi x13, x0, 0x300   # dst
    addi x14, x0, 0x40    # words (256/4)

wait_done:
    lw   x5, 16(x10)
    andi x5, x5, 0x2
    beq  x5, x0, wait_done

send_loop:
    lw   x6, 0(x13)
tx0_wait:
    lw   x7, 8(x9)        # IO_UART_STAT
    andi x7, x7, 1
    bne  x7, x0, tx0_wait
    sw   x6, 4(x9)        # IO_UART_TX (byte0)

    srli x6, x6, 8
tx1_wait:
    lw   x7, 8(x9)
    andi x7, x7, 1
    bne  x7, x0, tx1_wait
    sw   x6, 4(x9)        # byte1

    srli x6, x6, 8
tx2_wait:
    lw   x7, 8(x9)
    andi x7, x7, 1
    bne  x7, x0, tx2_wait
    sw   x6, 4(x9)        # byte2

    srli x6, x6, 8
tx3_wait:
    lw   x7, 8(x9)
    andi x7, x7, 1
    bne  x7, x0, tx3_wait
    sw   x6, 4(x9)        # byte3

    addi x13, x13, 4
    addi x14, x14, -1
    bne  x14, x0, send_loop

done_loop:
    beq  x0, x0, done_loop
