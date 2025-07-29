from config import config

def generate_payment_url(telegram_id, amount):
    # Replace with real Heleket API or redirect format
    return f"https://heleket.com/pay?merchant_id={config.HELEKET_MERCHANT_ID}&amount={amount}&user_id={telegram_id}&callback_url={config.HELEKET_CALLBACK_URL}"