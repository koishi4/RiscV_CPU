import time
import serial

port = "COM4"
baud = 115200
# 每次尝试读取的块大小，32字节一行比较方便看
block_size = 32 

print(f"--- 串口数据监听器 ---")
print(f"端口: {port}, 波特率: {baud}")
print(f"正在监听... (按 Ctrl+C 停止)")

try:
    with serial.Serial(port, baud, timeout=0.1) as ser:
        # 清空残留数据
        ser.reset_input_buffer()
        
        while True:
            # 方法：读取缓冲区中所有可用数据，或者至少读 block_size 这么多
            # 这里我们使用 read() 配合 timeout=0.1，实现持续流式读取
            
            # 如果你希望每行严格对齐 32 字节，可以用 ser.read(32)
            # 如果你希望有一点数据就马上打出来，用 ser.read(ser.in_waiting or 1)
            
            # 这里采用“读取缓冲区所有数据”的方式，反应最快
            if ser.in_waiting > 0:
                raw_data = ser.read(ser.in_waiting)
                
                # 为了防止一次读太多刷屏看不清，我们把大数据块切片打印
                # 类似 Hex Editor 的视图
                hex_str = raw_data.hex()
                
                # 简单的处理：每 64 个字符（32字节）加一个换行，方便你看
                for i in range(0, len(hex_str), 64):
                    chunk = hex_str[i:i+64]
                    # 打印格式： [当前时间] 数据
                    timestamp = time.strftime("%H:%M:%S", time.localtime())
                    print(f"[{timestamp}] {chunk}")
            
            #稍微休眠一下避免 CPU 占用过高（可根据数据发送频率调整，甚至去掉）
            time.sleep(0.01) 

except serial.SerialException as e:
    print(f"\n串口错误: {e}")
except KeyboardInterrupt:
    print("\n用户手动停止 (Ctrl+C)")
except Exception as e:
    print(f"\n发生错误: {e}")