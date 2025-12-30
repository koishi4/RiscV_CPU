import time
import serial
from PIL import Image  # 新增: 用于图像处理和显示

port = "COM4"
baud = 115200

# 模式: "raw" 只接收固定字节并打印; "img" 接收图像并显示
MODE = "raw"
w, h = 16, 16
EXPECTED_LEN = 16  # raw 模式下的期望字节数; img 模式会被 w*h 覆盖

# 建议: uart_seq_imm_h0.mem 用 00 11 22 33 作为帧头同步
HEADER = b"\x00\x11\x22\x33"
USE_HEADER = True
HEADER_TIMEOUT_S = 10
FALLBACK_ON_NO_HEADER = True
HEADER_FALLBACK_CAPTURE_S = 2.0

# 串口行为
DISABLE_DTR_RTS = True
RESET_INPUT = True
START_TIMEOUT_S = None  # 等待首字节; None 表示一直等
INTERBYTE_TIMEOUT_S = 1.0  # 首字节后，超过此间隔则停止接收
CAPTURE_UNTIL_IDLE = True  # 等到串口空闲再停止，便于抓到完整帧

PRINT_HEX = True
HEX_DUMP_BYTES = 32
SAVE_BIN = True
SAVE_FRAME_BIN = True


def read_exact(ser, nbytes, start_timeout_s=None, interbyte_timeout_s=None):
    buf = bytearray()
    start = time.time()
    first_rx = None
    last_rx = None
    while len(buf) < nbytes:
        if start_timeout_s is not None and len(buf) == 0:
            if (time.time() - start) > start_timeout_s:
                break
        chunk = ser.read(nbytes - len(buf))
        if chunk:
            buf.extend(chunk)
            now = time.time()
            if first_rx is None:
                first_rx = now
            last_rx = now
        else:
            if len(buf) == 0:
                continue
            if interbyte_timeout_s is not None and last_rx is not None:
                if (time.time() - last_rx) > interbyte_timeout_s:
                    break
    return buf, first_rx, last_rx


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


def read_frame(ser, header, total_len, start_timeout_s=None, interbyte_timeout_s=None):
    if header:
        ok = wait_for_header(ser, header, timeout_s=HEADER_TIMEOUT_S)
        if not ok:
            return bytearray(), None, None
        buf = bytearray(header)
        remain = max(0, total_len - len(header))
        if remain:
            data, first_rx, last_rx = read_exact(
                ser, remain, start_timeout_s=None, interbyte_timeout_s=interbyte_timeout_s
            )
            buf.extend(data)
            return buf, first_rx, last_rx
        now = time.time()
        return buf, now, now
    return read_exact(
        ser, total_len, start_timeout_s=start_timeout_s, interbyte_timeout_s=interbyte_timeout_s
    )


def read_until_idle(ser, start_timeout_s=None, interbyte_timeout_s=None):
    buf = bytearray()
    start = time.time()
    first_rx = None
    last_rx = None
    while True:
        if start_timeout_s is not None and len(buf) == 0:
            if (time.time() - start) > start_timeout_s:
                break
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            buf.extend(chunk)
            now = time.time()
            if first_rx is None:
                first_rx = now
            last_rx = now
        else:
            if len(buf) == 0:
                continue
            if interbyte_timeout_s is not None and last_rx is not None:
                if (time.time() - last_rx) > interbyte_timeout_s:
                    break
    return buf, first_rx, last_rx


def read_for_duration(ser, seconds):
    buf = bytearray()
    start = time.time()
    while (time.time() - start) < seconds:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            buf.extend(chunk)
    return buf


def extract_frames(buf, header, frame_len):
    frames = []
    if frame_len <= 0:
        return frames
    if header:
        start = 0
        while True:
            idx = buf.find(header, start)
            if idx < 0:
                break
            end = idx + frame_len
            if end <= len(buf):
                frames.append(buf[idx:end])
            start = idx + 1
    else:
        if len(buf) >= frame_len:
            frames.append(buf[:frame_len])
    return frames


try:
    expected = w * h if MODE == "img" else EXPECTED_LEN
    with serial.Serial(port, baud, timeout=1, rtscts=False, dsrdtr=False) as ser:
        if DISABLE_DTR_RTS:
            ser.dtr = False
            ser.rts = False

        if RESET_INPUT:
            ser.reset_input_buffer()

        if USE_HEADER:
            print(f"正在监听 {port}... 等待帧头 {HEADER.hex()}")
        else:
            print(f"正在监听 {port}... 请按下 FPGA 的复位/发送键")

        if CAPTURE_UNTIL_IDLE:
            if USE_HEADER:
                ok = wait_for_header(ser, HEADER, timeout_s=HEADER_TIMEOUT_S)
                if not ok:
                    if FALLBACK_ON_NO_HEADER:
                        print("未找到帧头，进入兜底抓取模式...")
                        buf = read_for_duration(ser, HEADER_FALLBACK_CAPTURE_S)
                        first_rx = None
                        last_rx = None
                    else:
                        buf = bytearray()
                        first_rx = None
                        last_rx = None
                else:
                    buf = bytearray(HEADER)
                    first_rx = time.time()
                    data, data_first, data_last = read_until_idle(
                        ser, start_timeout_s=None, interbyte_timeout_s=INTERBYTE_TIMEOUT_S
                    )
                    buf.extend(data)
                    if data_first is None:
                        last_rx = first_rx
                    else:
                        last_rx = data_last
            else:
                buf, first_rx, last_rx = read_until_idle(
                    ser, start_timeout_s=START_TIMEOUT_S, interbyte_timeout_s=INTERBYTE_TIMEOUT_S
                )
        else:
            buf, first_rx, last_rx = read_frame(
                ser,
                header=HEADER if USE_HEADER else None,
                total_len=expected,
                start_timeout_s=START_TIMEOUT_S,
                interbyte_timeout_s=INTERBYTE_TIMEOUT_S,
            )

    frames = extract_frames(buf, HEADER if USE_HEADER else None, expected)
    selected = frames[-1] if frames else buf

    if len(selected) < expected:
        print(f"警告: 接收不足 {len(selected)} / {expected} bytes")
    else:
        print("\n接收完成！")
    if CAPTURE_UNTIL_IDLE:
        print(f"总流长度: {len(buf)} bytes")
        if frames:
            print(f"检测到 {len(frames)} 帧，使用最后一帧")

    if PRINT_HEX:
        print(f"前{HEX_DUMP_BYTES}字节:", selected[:HEX_DUMP_BYTES].hex())
    if first_rx is not None and last_rx is not None and last_rx > first_rx and len(selected) > 1:
        dur = last_rx - first_rx
        baud_est = (len(selected) * 10.0) / dur
        print(f"估算波特率: {baud_est:.1f} bps (采样时长 {dur*1000:.1f} ms)")

    if SAVE_BIN and buf:
        with open("uart_dump.bin", "wb") as f:
            f.write(buf)
        print("已保存 uart_dump.bin")
    if SAVE_FRAME_BIN and selected:
        with open("uart_frame.bin", "wb") as f:
            f.write(selected)
        print("已保存 uart_frame.bin")

    if MODE != "img":
        raise SystemExit(0)

    # --- 图像处理 ---
    if len(selected) >= w * h:
        img = Image.frombytes('L', (w, h), bytes(selected[: w * h]))
        img_large = img.resize((w * 20, h * 20), resample=Image.NEAREST)
        print("正在弹窗显示图片...")
        img_large.show()
        img_large.save("dma_result.png")
        print("已保存 dma_result.png")
        with open("img.pgm", "wb") as f:
            f.write(f"P5\n{w} {h}\n255\n".encode())
            f.write(selected[: w * h])
        print("已备份 img.pgm")
    else:
        print("数据不足以生成图像。")

except serial.SerialException as e:
    print(f"串口错误: {e}")
except SystemExit:
    pass
except Exception as e:
    print(f"发生错误: {e}")
