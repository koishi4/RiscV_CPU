# Trap smoke test (CSR + mret)
# hart0 @ 0x0000_0000
addi x1, x0, 0x100
addi x0, x0, 0
csrrw x0, mtvec, x1
addi x2, x0, 8
addi x0, x0, 0
csrrs x0, mstatus, x2
addi x2, x0, 0x800
addi x0, x0, 0
csrrs x0, mie, x2
csrrw x6, mhartid, x0
addi x0, x0, 0
addi x3, x3, 1
beq  x0, x0, -4

# ISR @ 0x0000_0100
addi x5, x0, 1
mret
beq  x0, x0, 0

# hart1 @ 0x0000_0200
beq  x0, x0, 0
