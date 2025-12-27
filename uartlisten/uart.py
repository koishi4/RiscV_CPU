import time
import serial
from PIL import Image  # 新增: 用于图像处理和显示

port = "COM4"
baud = 115200
w, h = 16, 16
size = w * h

# 若使用 uart_ramp_repeat.mem，打开帧头同步；只发一次的数据则设为 None
HEADER = b"\xA5\x5A\xA5\x5A"
USE_HEADER = False
HEADER_TIMEOUT_S = 10
PRINT_HEX = True


def read_exact(ser, nbytes):
    buf = bytearray()
    while len(buf) < nbytes:
        chunk = ser.read(nbytes - len(buf))
        if chunk:
            buf.extend(chunk)
    return buf


def wait_for_header(ser, header, timeout_s=None):
    if not header:
        return True
    buf = bytearray()
    start = time.time()
    while True:
        b = ser.read(1)
        if b:
            buf += b
            if len(buf) > len(header):
                buf = buf[-len(header):]
            if buf == header:
                return True
        elif timeout_s is not None and (time.time() - start) > timeout_s:
            return False

try:
    with serial.Serial(port, baud, timeout=1) as ser:
        # 清空缓冲区，确保读到的是最新的数据
        ser.reset_input_buffer()
        if USE_HEADER:
            print(f"正在监听 {port}... 等待帧头 {HEADER.hex()}")
            if not wait_for_header(ser, HEADER, timeout_s=HEADER_TIMEOUT_S):
                print("等待帧头超时，改为直接接收（适用于一次性发送的镜像）。")
        else:
            print(f"正在监听 {port}... 请按下 FPGA 的复位/发送键")
        
        buf = read_exact(ser, size)

    print("\n接收完成！正在处理图像...")
    if PRINT_HEX:
        print("前32字节:", buf[:32].hex())

    # --- 新增部分：使用 PIL 处理图像 ---
    # 1. 从原始字节创建图片 (模式 'L' 代表 8位灰度)
    img = Image.frombytes('L', (w, h), bytes(buf))

    # 2. 放大图片 (放大 20 倍，否则 16像素在 4K 屏上像个坏点)
    # 使用 NEAREST (最近邻插值) 保持像素的锐利感，不模糊
    img_large = img.resize((w * 20, h * 20), resample=Image.NEAREST)

    # 3. 直接弹窗显示
    print("正在弹窗显示图片...")
    img_large.show()

    # 4. 保存为 PNG (通用格式，不需要特殊软件就能看)
    img_large.save("dma_result.png")
    print("已保存为 dma_result.png")
    
    # 同时也保留你原来的 PGM 备份
    with open("img.pgm", "wb") as f:
        f.write(f"P5\n{w} {h}\n255\n".encode())
        f.write(buf)
    print("已备份 img.pgm")

except serial.SerialException as e:
    print(f"串口错误: {e}")
except Exception as e:
    print(f"发生错误: {e}")
