import requests

API_KEY = "883a66ee-5a59-660b-9daf-1577e6b447ba"
BASE_URL = "https://app.proxies.fo/api"

def create_plan():
    url = f"{BASE_URL}/plans/new"
    headers = {
        "X-Api-Auth": f"{API_KEY}",
        "Content-Type": "application/x-www-form-urlencoded"
    }
    payload = "reseller=b3fd0f3c-693d-4ec5-b49f-c77feaab0b72&duration=1&threads=500"
    response = requests.post(url, headers=headers, data=payload)
    print(url)
    print(headers)
    print(payload)
    print(response.status_code)
    print(response.text)

create_plan()