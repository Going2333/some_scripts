import subprocess
import os

# --- 配置区域 ---
EXE_PATH = "main.exe"
INPUT_FILE = "1.txt"
# ----------------

def run():
    # 1. 读取 UTF-8 的参数文件
    # 确保你的 1.txt 是 UTF-8 编码
    try:
        with open(INPUT_FILE, 'r', encoding='utf-8') as f:
            input_text = f.read()
            
        # 细节修正：Windows控制台程序通常需要 \r\n 作为回车
        # 如果文件里只有 \n，可能会导致输入卡住或不被确认
        if '\r\n' not in input_text:
            input_text = input_text.replace('\n', '\r\n')
            
    except Exception as e:
        print(f"读取文件失败: {e}")
        return

    print("正在启动程序并强制注入 UTF-8 环境...")

    # 2. 关键步骤：设置环境变量
    # 复制当前系统的环境变量，并添加 Python 专用的编码设置
    my_env = os.environ.copy()
    my_env["PYTHONIOENCODING"] = "utf-8"

    try:
        # 3. 启动进程
        # 注意：这里传入了 env=my_env
        process = subprocess.Popen(
            EXE_PATH,
            stdin=subprocess.PIPE,
            stdout=None, 
            stderr=None,
            shell=False,
            env=my_env  # <--- 核心改动：告诉 exe 里的 Python "请只讲 UTF-8"
        )

        # 4. 发送 UTF-8 字节流
        input_bytes = input_text.encode('utf-8')
        process.communicate(input=input_bytes)

    except FileNotFoundError:
        print(f"错误：找不到 {EXE_PATH}")
    except Exception as e:
        print(f"发生异常：{e}")

if __name__ == "__main__":
    run()
