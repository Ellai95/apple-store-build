#!/usr/bin/env python3
"""Local fixture only. No credentials or production downloads."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from io import BytesIO
import sys, time, zipfile
buf=BytesIO()
with zipfile.ZipFile(buf,'w') as archive:
    archive.writestr('Payload/Fixture.app/Info.plist', b'fixture' * 160000)
data=buf.getvalue()
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            if self.path == '/stall':
                time.sleep(6); return
            if self.path == '/redirect':
                self.send_response(302);self.send_header('Location','/ipa');self.end_headers();return
            body = b'Forbidden' if self.path == '/denied' else b'<html>Not an IPA</html>' if self.path == '/html' else data
            self.send_response(403 if self.path == '/denied' else 200)
            if self.path != '/unknown-length': self.send_header('Content-Length',str(len(body)))
            self.end_headers()
            for offset in range(0,len(body),32768):
                self.wfile.write(body[offset:offset+32768]); self.wfile.flush(); time.sleep(.015)
        except (BrokenPipeError,ConnectionResetError): pass
    def log_message(self,*args): pass
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
Path(sys.argv[1]).write_text(str(server.server_address[1]))
server.serve_forever()
