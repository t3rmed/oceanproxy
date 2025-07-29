import requests

BEARER_TOKEN = "Bearer UVvSib3fZ5cJvpSG5zSsTOZXqaqJ6mTcH6wiZQ3GgP9XL4M0xk8e6MZVldHVwuH0"
BASE_URL = "https://api.oceanproxy.io"

def create_residential_plan():
    url = f"{BASE_URL}/plan"
    headers = {
        "Authorization": BEARER_TOKEN,
        "Content-Type": "application/x-www-form-urlencoded"
    }
    payload = "reseller=residential&bandwidth=1"
    response = requests.post(url, headers=headers, data=payload)
    return response.text

def get_proxies():
    url = f"{BASE_URL}/proxies"
    headers = {
        "Authorization": BEARER_TOKEN,
    }
    response = requests.get(url, headers=headers)
    print(f"Status Code: {response.status_code}")
    print(f"Headers: {dict(response.headers)}")
    return response.text

def restore_proxies():
    url = f"{BASE_URL}/restore"
    headers = {
        "Authorization": BEARER_TOKEN,
    }
    response = requests.post(url, headers=headers)
    return response.text

# print(create_residential_plan())
print(restore_proxies())
print(get_proxies())