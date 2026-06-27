from flask import Flask, Response, render_template, request
import subprocess
import os
import shutil

app = Flask(__name__)

@app.route('/')
def hello_world():
    return render_template('index.html')

@app.route('/stream')
def stream():
    user_text = request.args.get('input', '')
    use_opengl = request.args.get('usegl', 'false').lower() == 'true'

    def generator():
        with open("code.txt", 'w') as f:
            f.write(user_text)
        env = os.environ.copy()
        env["DISPLAY"] = ":0"
        env["XAUTHORITY"] = "/homes/ssg25/.Xauthority"
        if use_opengl:
            process = subprocess.Popen(
                "cd .. ; build/renderer web-ui/code.txt",
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1, env=env, shell=True
            )
        else:
            process = subprocess.Popen(
                "cd .. ; build/renderer web-ui/code.txt web-ui/static/output.jpg",
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1, env=env, shell=True
            )
        for line in process.stdout:
            line = line.rstrip()
            if line:
                yield f"data: {line}\n\n"
        process.wait()

        if not use_opengl and process.returncode == 0:
            # adjust source path to wherever the renderer writes its output
            yield "data: __DONE__\n\n"
            src = os.path.join("..", "output.jpg")
            if os.path.exists(src):
                shutil.copy(src, os.path.join("static", "output.jpg"))



    return Response(generator(), mimetype='text/event-stream')

if __name__ == '__main__':
    app.run(debug=True)