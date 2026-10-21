// A hello world web application.
const http = require("http");

const port = Number(process.env.PORT || 8080);

http.createServer((req, res) => {
  if (req.url === "/healthz") { res.writeHead(200); return res.end("ok"); }
  res.writeHead(200, { "content-type": "application/json" });
  res.end(JSON.stringify({
    message: process.env.MESSAGE || "hello world",
    environment: process.env.ENVIRONMENT || "unknown",
    version: process.env.VERSION || "unknown",
    // The secret's last 4 characters only, to show which one arrived.
    apiKey: process.env.API_KEY ? "…" + process.env.API_KEY.slice(-4) : "missing",
  }) + "\n");
}).listen(port, () => console.log(`web listening on ${port}`));
