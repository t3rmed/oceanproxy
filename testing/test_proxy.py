import requests
import time
import json

def test_proxy_with_timing(proxy_url, test_url="http://ipinfo.io/json"):
    """Test a proxy and measure response time"""
    print(f"Testing proxy: {proxy_url}")
    
    start_time = time.time()
    
    try:
        # Make request through proxy
        resp = requests.get(
            test_url, 
            proxies={"http": proxy_url, "https": proxy_url},
            timeout=30  # 30 second timeout
        )
        
        end_time = time.time()
        response_time = end_time - start_time
        
        # Log successful response
        print(f"✅ SUCCESS - Response time: {response_time:.3f} seconds")
        print(f"Status code: {resp.status_code}")
        
        # Try to parse and display IP info with country
        try:
            ip_data = resp.json()
            ip_address = ip_data.get('ip', 'N/A')
            country = ip_data.get('country', 'N/A')
            city = ip_data.get('city', 'N/A')
            region = ip_data.get('region', 'N/A')
            org = ip_data.get('org', 'N/A')
            
            print(f"Response IP: {ip_address}")
            print(f"Country: {country}")
            print(f"City: {city}, {region}")
            print(f"Organization: {org}")
        except Exception as parse_error:
            print(f"Failed to parse JSON response: {parse_error}")
            print(f"Response text: {resp.text[:200]}...")
        
        return {
            "success": True,
            "response_time": response_time,
            "status_code": resp.status_code,
            "proxy": proxy_url,
            "ip_data": ip_data if 'ip_data' in locals() else None
        }
        
    except requests.exceptions.Timeout:
        end_time = time.time()
        response_time = end_time - start_time
        print(f"❌ TIMEOUT - Time elapsed: {response_time:.3f} seconds")
        return {
            "success": False,
            "response_time": response_time,
            "error": "Timeout",
            "proxy": proxy_url
        }
        
    except requests.exceptions.ProxyError as e:
        end_time = time.time()
        response_time = end_time - start_time
        print(f"❌ PROXY ERROR - Time elapsed: {response_time:.3f} seconds")
        print(f"Error: {str(e)}")
        return {
            "success": False,
            "response_time": response_time,
            "error": f"Proxy Error: {str(e)}",
            "proxy": proxy_url
        }
        
    except Exception as e:
        end_time = time.time()
        response_time = end_time - start_time
        print(f"❌ ERROR - Time elapsed: {response_time:.3f} seconds")
        print(f"Error: {str(e)}")
        return {
            "success": False,
            "response_time": response_time,
            "error": str(e),
            "proxy": proxy_url
        }

# Test the proxy
proxy = "http://testuser_1753852444-country-us:testpass@alpha.oceanproxy.io:9876"
result = test_proxy_with_timing(proxy)

print("\n" + "="*50)
print("SUMMARY:")
print(f"Proxy: {result['proxy']}")
print(f"Success: {result['success']}")
print(f"Response Time: {result['response_time']:.3f} seconds")
if result['success'] and result.get('ip_data'):
    ip_data = result['ip_data']
    print(f"IP Address: {ip_data.get('ip', 'N/A')}")
    print(f"Country: {ip_data.get('country', 'N/A')}")
    print(f"City: {ip_data.get('city', 'N/A')}, {ip_data.get('region', 'N/A')}")
if not result['success']:
    print(f"Error: {result.get('error', 'Unknown error')}")
print("="*50)