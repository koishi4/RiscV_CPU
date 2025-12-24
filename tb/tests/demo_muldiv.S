# Demo2: latency hiding (hart0 mul/div, hart1 counter loop)
# Hart0 @ 0x0000_0000: x1=10, x2=3, mul/div/rem, then loop.
# Hart1 @ 0x0000_0100: x10 increments in a tight loop.

# hart0
addi x1, x0, 10
addi x0, x0, 0
addi x0, x0, 0
addi x2, x0, 3
addi x0, x0, 0
addi x0, x0, 0
mul  x3, x1, x2
div  x4, x1, x2
rem  x5, x1, x2
beq  x0, x0, 0

# hart1 (place at 0x0000_0100)
addi x10, x10, 1
addi x0, x0, 0
addi x0, x0, 0
beq  x0, x0, -12
