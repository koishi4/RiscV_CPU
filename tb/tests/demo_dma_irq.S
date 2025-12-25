# Demo3: DMA + interrupt
# Hart0 @ 0x0000_0000 sets up DMA and waits on flag.
# ISR @ 0x0000_0100 clears DMA done, sets flag, and writes LED.
# Hart1 @ 0x0000_0180 loops.

# hart0
addi x1, x0, 0x100     # mtvec = 0x100
addi x0, x0, 0
addi x0, x0, 0
csrrw x0, mtvec, x1

addi x2, x0, 0x800     # MEIE
addi x0, x0, 0
addi x0, x0, 0
csrrs x0, mie, x2

addi x3, x0, 8         # MSTATUS.MIE
addi x0, x0, 0
addi x0, x0, 0
csrrs x0, mstatus, x3

lui  x10, 0x40000      # DMA base 0x4000_0000
addi x15, x0, 0x400    # flag addr
addi x0, x0, 0
addi x0, x0, 0

addi x11, x0, 0x200    # src
addi x0, x0, 0
addi x0, x0, 0
sw   x11, 0(x10)

addi x12, x0, 0x300    # dst
addi x0, x0, 0
addi x0, x0, 0
sw   x12, 4(x10)

addi x13, x0, 0x10     # len
addi x0, x0, 0
addi x0, x0, 0
sw   x13, 8(x10)

addi x14, x0, 3        # START | IRQ_EN
addi x0, x0, 0
addi x0, x0, 0
sw   x14, 12(x10)

lw   x5, 0(x15)        # wait flag
addi x0, x0, 0
addi x0, x0, 0
bne  x5, x0, 8
beq  x0, x0, -16
beq  x0, x0, 0

# ISR @ 0x0000_0100
addi x2, x0, 1
lui  x9, 0x40001       # IO base 0x4000_1000
addi x0, x0, 0
sw   x2, 0(x15)        # flag = 1
sw   x2, 0(x9)         # LED0 = 1
addi x0, x0, 0
sw   x2, 20(x10)       # DMA_CLR
mret

# hart1 @ 0x0000_0180
beq  x0, x0, 0
