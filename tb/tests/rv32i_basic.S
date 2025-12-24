# RV32I basic directed test (no forwarding, insert NOPs)
# hart0 @ 0x0000_0000
lui  x1, 0x00012
auipc x2, 0x1
jal  x3, 8
addi x0, x0, 0
addi x4, x0, 9
addi x5, x0, 0x28
addi x0, x0, 0
addi x0, x0, 0
jalr x6, x5, 0
addi x0, x0, 0
addi x7, x0, 0x33
beq  x0, x0, 0

# hart1 @ 0x0000_0200
beq  x0, x0, 0
