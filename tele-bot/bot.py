from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, InputMediaPhoto
from telegram.ext import ApplicationBuilder, CommandHandler, CallbackQueryHandler, ContextTypes
from config import config
from db import init_db, add_user, log_payment
from heleket import generate_payment_url

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    add_user(user.id, user.username)
    
    welcome_text = (
        f"🦈 *Welcome*, {user.username}, to Ocean Proxy!\n"
        "❗️ By using our bot, you agree that you know what you are buying and agree to the [terms of use](https://example.com).\n\n"
        "🔄 Updates: @OceanProxyIO\n"
        "🐳 Support: @OceanProxySupport"
    )
    
    keyboard = [
        [InlineKeyboardButton("🌊 Buy a proxy", callback_data="buy_proxy")],
        [
            InlineKeyboardButton("👤 Profile", callback_data="profile"),
            InlineKeyboardButton("💎 Partnerships", callback_data="partners")
        ],
        [
            InlineKeyboardButton("🌐 Our website", url="https://oceanproxy.io"),
        ],
        [
            InlineKeyboardButton("❗️ Rules and FAQ", callback_data="rules"),
        ],
        [InlineKeyboardButton("🐳 Contact support", url="https://t.me/OceanProxySupport")]
    ]
    
    # Check if this is called from a callback query or direct message
    if update.callback_query:
        # Called from button press - edit existing message with oceanproxy.png
        try:
            with open("./oceanproxy.png", "rb") as photo_file:
                await update.callback_query.edit_message_media(
                    media=InputMediaPhoto(
                        media=photo_file,
                        caption=welcome_text,
                        parse_mode='Markdown'
                    ),
                    reply_markup=InlineKeyboardMarkup(keyboard)
                )
        except FileNotFoundError:
            # If oceanproxy.png doesn't exist, just edit the caption
            await update.callback_query.edit_message_caption(
                caption=welcome_text,
                parse_mode='Markdown',
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
    else:
        # Called from /start command - send new photo message
        await update.message.reply_photo(
            photo="./oceanproxy.png",
            caption=welcome_text,
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
    
async def buy_proxy(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    user = update.effective_user
    buy_text = (
        f"We have plenty to choose from\n"
        "Please join our news channel @OceanProxyIO\n"
        "By using our bot, you agree that you know what you are buying and agree to the [terms of use](https://example.com).\n"
        "and with the section Rules and FAQ\n"
    )
    
    keyboard = [
        [InlineKeyboardButton("🌊 Residential", callback_data="residential")],
        [
            InlineKeyboardButton("👤 Datacenter", callback_data="datacenter")
        ],
        [
            InlineKeyboardButton("💎 ISP", callback_data="isp")
        ],
        [
            InlineKeyboardButton("🔙 Back to main menu", callback_data="start"),
        ]
    ]
    
    # Edit both the image and caption
    try:
        with open("./proxies.png", "rb") as photo_file:
            await query.edit_message_media(
                media=InputMediaPhoto(
                    media=photo_file,
                    caption=buy_text,
                    parse_mode='Markdown'
                ),
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
    except FileNotFoundError:
        # If proxies.png doesn't exist, just edit the caption
        await query.edit_message_caption(
            caption=buy_text,
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
        
async def residential(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    user = update.effective_user
    buy_text = (
        f"Our residential pool(s) contain over 150 million IPs from all over the world.\n"
        "Please press the 'pricing' button to see our pricing.\n"
        "Please press the 'info' button to see more information about our residential proxies.\n"
    )
    
    keyboard = [
        [
            InlineKeyboardButton("➡ Buy Now", callback_data="select_resi_plan"),
        ],
        [
            InlineKeyboardButton("🌊 Pricing", url="https://oceanproxy.io/residential#pricing"),
            InlineKeyboardButton("👤 Info", url="https://oceanproxy.io/residential#info")
        ],
        [
            InlineKeyboardButton("🔙 Back to proxies menu", callback_data="buy_proxy"),
        ]
    ]
    
    # Edit both the image and caption
    try:
        with open("./resi.png", "rb") as photo_file:
            await query.edit_message_media(
                media=InputMediaPhoto(
                    media=photo_file,
                    caption=buy_text,
                    parse_mode='Markdown'
                ),
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
    except FileNotFoundError:
        # If resi.png doesn't exist, just edit the caption
        await query.edit_message_caption(
            caption=buy_text,
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
        
async def datacenter(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    user = update.effective_user
    buy_text = (
        f"Our datacenter proxies are fast and reliable, perfect for scraping and automation tasks.\n"
        "Please press the 'pricing' button to see our pricing.\n"
        "Please press the 'info' button to see more information about our datacenter proxies.\n"
    )
    
    keyboard = [
        [InlineKeyboardButton("🌊 Pricing", url="https://oceanproxy.io/datacenter#pricing"),
         InlineKeyboardButton("👤 Info", url="https://oceanproxy.io/datacenter#info")],
        [
            InlineKeyboardButton("🔙 Back to proxies menu", callback_data="buy_proxy"),
        ]
    ]
    
    # Edit both the image and caption
    try:
        with open("./datacenter.png", "rb") as photo_file:
            await query.edit_message_media(
                media=InputMediaPhoto(
                    media=photo_file,
                    caption=buy_text,
                    parse_mode='Markdown'
                ),
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
    except FileNotFoundError:
        # If datacenter.png doesn't exist, just edit the caption
        await query.edit_message_caption(
            caption=buy_text,
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup(keyboard)
        )

async def isp(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    user = update.effective_user
    buy_text = (
        f"Our ISP proxies are designed for high performance and reliability.\n"
        "Please press the 'pricing' button to see our pricing.\n"
        "Please press the 'info' button to see more information about our ISP proxies.\n"
    )
    
    keyboard = [
        [InlineKeyboardButton("🌊 Pricing", url="https://oceanproxy.io/isp#pricing"),
         InlineKeyboardButton("👤 Info", url="https://oceanproxy.io/isp#info")],
        [
            InlineKeyboardButton("🔙 Back to proxies menu", callback_data="buy_proxy"),
        ]
    ]
    
    # Edit both the image and caption
    try:
        with open("./isp.png", "rb") as photo_file:
            await query.edit_message_media(
                media=InputMediaPhoto(
                    media=photo_file,
                    caption=buy_text,
                    parse_mode='Markdown'
                ),
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
    except FileNotFoundError:
        # If isp.png doesn't exist, just edit the caption
        await query.edit_message_caption(
            caption=buy_text,
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup(keyboard)
        )

async def profile(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    user = update.effective_user
    user_balance = 0.0  # fetch from db
    user_orders = 0  # fetch from db
    profile_text = (
        "🦈 *Your Profile*\n\n"
        f"👤 *Username:* {user.username}\n"
        f"💰 *Balance:* ${user_balance:.2f}\n"
        f"📦 *Orders:* {user_orders}\n"
        f"🤝 *Referrals:* Coming soon!"
    )

    keyboard = [
        [InlineKeyboardButton("➕ Add Balance", callback_data="add_balance")],
        [
            InlineKeyboardButton("🔙 Back to main menu", callback_data="start"),
        ]
    ]
    
    # Edit both the image and caption
    try:
        with open("./user.png", "rb") as photo_file:
            await query.edit_message_media(
                media=InputMediaPhoto(
                    media=photo_file,
                    caption=profile_text,
                    parse_mode='Markdown'
                ),
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
    except FileNotFoundError:
        # If user.png doesn't exist, just edit the caption
        await query.edit_message_caption(
            caption=profile_text,
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
    
async def partnerships(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    partnerships_text = (
        "🤝 *Partnerships*\n\n"
        "🫂 Users:\n"
        "We offer a referral program where you can earn by inviting others to use our service. (Coming soon!)\n\n"
        "💼 Businesses:\n"
        "If you're a business and want to partner with us, please reach out to our support team."
    )

    keyboard = [
        [InlineKeyboardButton("➕ Add Balance", callback_data="add_balance")],
        [
            InlineKeyboardButton("🔙 Back to main menu", callback_data="start"),
        ]
    ]
    
    try:
        with open("./partners.png", "rb") as photo_file:
            await query.edit_message_media(
                media=InputMediaPhoto(
                    media=photo_file,
                    caption=partnerships_text,
                    parse_mode='Markdown'
                ),
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
    except FileNotFoundError:
        # If partners.png doesn't exist, just edit the caption
        await query.edit_message_caption(
            caption=partnerships_text,
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
    
async def rules(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    rules_text = (
        "📜 *Rules*\n\n"
        "1. Be respectful to others.\n"
        "2. No spamming or advertising.\n"
        "3. Use the appropriate channels for support."
    )

    keyboard = [
        [
            InlineKeyboardButton("🔙 Back to main menu", callback_data="start"),
        ]
    ]

    # Edit both the image and caption
    try:
        with open("./rules.png", "rb") as photo_file:
            await query.edit_message_media(
                media=InputMediaPhoto(
                    media=photo_file,
                    caption=rules_text,
                    parse_mode='Markdown'
                ),
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
    except FileNotFoundError:
        # If rules.png doesn't exist, just edit the caption
        await query.edit_message_caption(
            caption=rules_text,
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup(keyboard)
        )

async def website(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    website_text = (
        "🌐 *Our Website*\n\nClick the button below to visit our website:"
    )

    keyboard = [
        [InlineKeyboardButton("🌐 Visit oceanproxy.io", url="https://oceanproxy.io")],
        [InlineKeyboardButton("🔙 Back to main menu", callback_data="start")]
    ]
    
    # Edit both the image and caption
    try:
        with open("./web.png", "rb") as photo_file:
            await query.edit_message_media(
                media=InputMediaPhoto(
                    media=photo_file,
                    caption=website_text,
                    parse_mode='Markdown'
                ),
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
    except FileNotFoundError:
        # If web.png doesn't exist, just edit the caption
        await query.edit_message_caption(
            caption=website_text,
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup(keyboard)
        )

async def error(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    website_text = (
        "We ran into a little issue with your request :C\n"
    )

    keyboard = [
        [InlineKeyboardButton("🔙 Back to main menu", callback_data="start")]
    ]
    
    # Edit both the image and caption
    try:
        with open("./web.png", "rb") as photo_file:
            await query.edit_message_media(
                media=InputMediaPhoto(
                    media=photo_file,
                    caption=website_text,
                    parse_mode='Markdown'
                ),
                reply_markup=InlineKeyboardMarkup(keyboard)
            )
    except FileNotFoundError:
        # If web.png doesn't exist, just edit the caption
        await query.edit_message_caption(
            caption=website_text,
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup(keyboard)
        )

async def handle_button(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    user = update.effective_user
    await query.answer()

    if query.data == "buy_proxy":
        await buy_proxy(update, context)
    elif query.data == "start":
        await start(update, context)
    elif query.data == "profile":
        await profile(update, context)
    elif query.data == "partners":
        await partnerships(update, context)
    elif query.data == "rules":
        await rules(update, context)
    # individual proxy menus
    elif query.data == "residential":
        await residential(update, context)
    elif query.data == "datacenter":
        await datacenter(update, context)
    elif query.data == "isp":
        await isp(update, context)
    else:
        # Edit the existing message instead of sending a new one
        await error(update, context)

def main():
    init_db()
    app = ApplicationBuilder().token(config.BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(handle_button))
    app.run_polling()

if __name__ == "__main__":
    print("Starting Ocean Proxy Bot...")
    main()
