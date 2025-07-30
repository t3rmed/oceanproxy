import requests

BEARER_TOKEN = "Bearer Dr1N47VFDszVsDd7DDKQgTZZfIJ-gN3k9O6yymH1TuM"
BASE_URL = "https://api.nettify.xyz/"

# balance request
def balance():
    url = f"{BASE_URL}/balance"
    headers = {
        "Authorization": BEARER_TOKEN
    }
    response = requests.get(url, headers=headers)
    json_response = response.json()
    balance = json_response.get("balance", 0)
    print(f"Balance: ${balance}")
    return json_response

def countries():
    url = f"{BASE_URL}/countries"
    headers = {
        "Authorization": BEARER_TOKEN
    }
    response = requests.get(url, headers=headers)
    json_response = response.json()
    countries = json_response.get("countries", [])
    print(f"Countries: {', '.join(countries)}")
    return json_response

def my_plans():
    url = f"{BASE_URL}/plans"
    headers = {
        "Authorization": BEARER_TOKEN
    }
    response = requests.get(url, headers=headers)
    json_response = response.json()
    return json_response

def create_plan(username, password, plan_type, bandwidth, hours=None):
    bandwidth_mb = bandwidth * 1024  # Convert GB to MB
    url = f"{BASE_URL}/plans/create"
    headers = {
        "Authorization": BEARER_TOKEN,
        "Content-Type": "application/json"
    }
    
    if plan_type == 'unlimited':
        data = {
            "username": username,
            "password": password,
            "plan_type": plan_type,  # unlimited
            "duration_hours": hours
        }
    data = {
        "username": username,
        "password": password,
        "plan_type": plan_type, # residential, datacenter, mobile, etc.
        "bandwidth_mb": bandwidth_mb
    }
    response = requests.post(url, headers=headers, json=data)
    plan_id = response.json().get("plan_id")
    print(response.json())
    return plan_id

def get_plan_details(plan_id):
    url = f"{BASE_URL}/plans/{plan_id}"
    headers = {
        "Authorization": BEARER_TOKEN
    }
    response = requests.get(url, headers=headers)
    return response.json()

def update_plan(plan_id, password):
    url = f"{BASE_URL}/plans/{plan_id}"
    headers = {
        "Authorization": BEARER_TOKEN,
        "Content-Type": "application/json"
    }
    data = {
        "password": password
    }
    response = requests.put(url, headers=headers, json=data)
    return response.json()

def delete_plan(plan_id):
    url = f"{BASE_URL}/plans/{plan_id}"
    headers = {
        "Authorization": BEARER_TOKEN
    }
    response = requests.delete(url, headers=headers)
    return response.json()

print("balance:", balance())
print("countries:", countries())
plan_id = create_plan("test_user", "password", "residential", 1)
print("my plans:", my_plans())
print("get_plan_details:", get_plan_details(plan_id))