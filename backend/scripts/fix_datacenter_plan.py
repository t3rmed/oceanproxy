#!/usr/bin/env python3
import json

# Read the proxy log
with open('/var/log/oceanproxy/proxies.json', 'r') as f:
    data = json.load(f)

# Fix the yourfmbhpv plan to be datacenter
for entry in data:
    if entry['plan_id'] == '8cef29b7-b7b0-53f1-2364-52f1d45df58a':
        # Update to datacenter settings
        entry['auth_host'] = 'dcp.proxies.fo'
        entry['auth_port'] = 10808
        entry['subdomain'] = 'datacenter'
        entry['local_host'] = 'datacenter.oceanproxy.io'
        entry['local_port'] = 40001  # Use next available datacenter port
        entry['public_port'] = 1339
        
        print(f"✅ Fixed plan {entry['plan_id'][:8]}... to datacenter:")
        print(f"   - auth_host: {entry['auth_host']}")
        print(f"   - auth_port: {entry['auth_port']}")
        print(f"   - subdomain: {entry['subdomain']}")
        print(f"   - local_port: {entry['local_port']}")

# Save updated data
with open('/var/log/oceanproxy/proxies.json', 'w') as f:
    json.dump(data, f, indent=2)

print("🎉 Fixed plan to be datacenter with correct settings")
