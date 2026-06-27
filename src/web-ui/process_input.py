import sys
import time
import subprocess

def process_input(user_text):
    print(f"Parsing code... ", flush=True)
    with open("code.txt", "w") as code_file:
        code_file.write(user_text)
    process = subprocess.Popen(
            "../build/renderer code.txt",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            shell=True,
            bufsize=1,
        )
    print(process.stdout, flush=True)
    print("Generating image", flush=True)
    time.sleep(2)
    print("Done!", flush=True)

if __name__ == "__main__":
    user_text = sys.argv[1] if len(sys.argv) > 1 else ""
    process_input(user_text)