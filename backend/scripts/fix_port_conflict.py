#!/usr/bin/env python3
import json

# Read the proxy log
with open('/var/log/oceanproxy/proxies.json', 'r') as f:
    data = json.load(f)

# Fix port conflict - assign unique ports
port_assignments = {
    "usa": 10000,
    "eu": 20000, 
    "datacenter": 40000,
    "alpha": 30000,
    "beta": 40000,
    "mobile": 50000,
    "unlim": 60000
}

port_counter = {}

for entry in data:
    subdomain = entry['subdomain']
    base_port = port_assignments.get(subdomain, 10000)
    
    if subdomain not in port_counter:
        port_counter[subdomain] = 0
    
    # Assign unique port for this subdomain
    entry['local_port'] = base_port + port_counter[subdomain]
    port_counter[subdomain] += 1
    
    print(f"✅ {entry['plan_id'][:8]}... ({entry['username']}) {subdomain} → port {entry['local_port']}")

# Save updated data
with open('/var/log/oceanproxy/proxies.json', 'w') as f:
    json.dump(data, f, indent=2)

print(f"\n🎉 Fixed port conflicts! Updated {len(data)} entries.")
