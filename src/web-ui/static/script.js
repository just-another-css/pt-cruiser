const output = document.getElementById("output");
const input = document.getElementById("code-input");
const use_gl = document.getElementById("usegl");
const button = document.getElementById("generate");
const form = document.querySelector("form");
let source = null;

form.addEventListener("submit", function (e) {
    e.preventDefault();

    output.textContent = "";
    if (source) source.close();

    const text = input.value;
    const glOn = use_gl.checked;
    source = new EventSource("/stream?input=" + encodeURIComponent(text) + "&usegl=" + encodeURIComponent(glOn));

    source.onmessage = function (event) {
        if (event.data === "__DONE__") {
            source.close();
            if (!glOn) {
                output.innerHTML = "";
                const img = document.createElement("img");
                img.src = "/static/output.jpg?t=" + Date.now();
                img.style.maxWidth = "100%";
                output.appendChild(img);
            }
            return;
        }
        output.textContent += event.data + "\n";
    };

    source.onerror = function () {
        source.close();
    };
});