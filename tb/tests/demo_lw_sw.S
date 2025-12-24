# Demo: LW/SW directed test (no forwarding, insert NOPs)
# hart0 @ 0x0000_0000
addi x1, x0, 0x200
addi x0, x0, 0
addi x0, x0, 0
addi x2, x0, 7
addi x0, x0, 0
addi x0, x0, 0
sw   x2, 0(x1)
addi x0, x0, 0
addi x0, x0, 0
lw   x3, 0(x1)
addi x0, x0, 0
addi x0, x0, 0
beq  x0, x0, 0

# hart1 @ 0x0000_0100
addi x0, x0, 0
beq  x0, x0, 0
