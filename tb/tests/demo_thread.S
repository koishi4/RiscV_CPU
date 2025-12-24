# Demo1: dual-hart ADDI demo (no forwarding, insert NOPs)
# Hart0 @ 0x0000_0000: x1=1, x2=3, x3=6 then loop
# Hart1 @ 0x0000_0100: x1=5, x2=11, x3=18 then loop

# hart0
addi x1, x0, 1
addi x0, x0, 0
addi x2, x1, 2
addi x0, x0, 0
addi x3, x2, 3
beq  x0, x0, 0

# hart1 (place at 0x0000_0100)
addi x1, x0, 5
addi x0, x0, 0
addi x2, x1, 6
addi x0, x0, 0
addi x3, x2, 7
beq  x0, x0, 0
