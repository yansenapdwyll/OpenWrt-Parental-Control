#!/usr/bin/ucode
'use strict';

import * as socket from 'socket';

let srv = socket.listen('0.0.0.0', 8088);
if (!srv) {
    exit(1);
}

let html_body = `<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Dostęp Wstrzymany - Kwarantanna</title>
    <style>
        body { font-family: system-ui, sans-serif; background: #0f172a; color: #f8fafc; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
        .card { background: #1e293b; padding: 2rem; border-radius: 12px; max-width: 400px; text-align: center; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }
        h1 { color: #f43f5e; font-size: 1.5rem; }
        p { color: #94a3b8; font-size: 0.95rem; line-height: 1.5; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Wykryto nowe urządzenie</h1>
        <p>Twoje urządzenie (lub funkcja <b>Prywatnego adresu MAC</b>) wymaga autoryzacji przez rodzica.</p>
        <p>Wyłącz opcję "Prywatny adres Wi-Fi" w ustawieniach sieci lub poproś rodzica o przypisanie urządzenia.</p>
    </div>
</body>
</html>`;

let response = "HTTP/1.1 200 OK\r\n" +
               "Content-Type: text/html; charset=UTF-8\r\n" +
               "Content-Length: " + length(html_body) + "\r\n" +
               "Connection: close\r\n\r\n" +
               html_body;

while (true) {
    let client = srv.accept();
    if (!client) continue;
    client.recv(1024);
    client.send(response);
    client.close();
}
