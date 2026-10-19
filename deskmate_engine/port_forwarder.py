"""
Utility port forwarder: forwards connections from port 2026 to port 8080
so Flutter instances bound to default port 2026 reach the active backend.
"""
import socket
import threading
import sys

def forward(src, dst):
    try:
        while True:
            data = src.recv(8192)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        try:
            src.close()
        except Exception:
            pass
        try:
            dst.close()
        except Exception:
            pass

def handle_client(client_sock):
    try:
        server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_sock.connect(('127.0.0.1', 8080))
        t1 = threading.Thread(target=forward, args=(client_sock, server_sock), daemon=True)
        t2 = threading.Thread(target=forward, args=(server_sock, client_sock), daemon=True)
        t1.start()
        t2.start()
    except Exception:
        client_sock.close()

def main():
    listen_port = 2026
    target_port = 8080
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind(('127.0.0.1', listen_port))
    except Exception as e:
        print(f"Cannot bind to port {listen_port}: {e}")
        sys.exit(1)

    server.listen(128)
    print(f"Forwarding localhost:{listen_port} -> localhost:{target_port}")
    while True:
        try:
            client_sock, _ = server.accept()
            threading.Thread(target=handle_client, args=(client_sock,), daemon=True).start()
        except KeyboardInterrupt:
            break
        except Exception:
            pass

if __name__ == '__main__':
    main()
