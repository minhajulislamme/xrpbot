import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# API configuration
API_KEY = os.getenv('BINANCE_API_KEY', '')
API_SECRET = os.getenv('BINANCE_API_SECRET', '')

# Testnet configuration
API_TESTNET = os.getenv('BINANCE_API_TESTNET', 'False').lower() == 'true'

# API URLs - Automatically determined based on testnet setting
if API_TESTNET:
    # Testnet URLs
    API_URL = 'https://testnet.binancefuture.com'
    WS_BASE_URL = 'wss://stream.binancefuture.com'
else:
    # Production URLs
    API_URL = os.getenv('BINANCE_API_URL', 'https://fapi.binance.com')
    WS_BASE_URL = 'wss://fstream.binance.com'

# API request settings
RECV_WINDOW = int(os.getenv('BINANCE_RECV_WINDOW', '10000'))

# Trading parameters
TRADING_SYMBOL = os.getenv('TRADING_SYMBOL', 'XRPUSDT')  # Changed to XRP as default
TRADING_TYPE = 'FUTURES'  # Use futures trading
LEVERAGE = int(os.getenv('LEVERAGE', '20'))  # Increased to 20x leverage for futures trading
MARGIN_TYPE = os.getenv('MARGIN_TYPE', 'ISOLATED')  # ISOLATED or CROSSED

# Position sizing
INITIAL_BALANCE = float(os.getenv('INITIAL_BALANCE', '50.0'))  # Starting with $50
RISK_PER_TRADE = float(os.getenv('RISK_PER_TRADE', '0.03'))  # 3% risk per trade
MAX_OPEN_POSITIONS = int(os.getenv('MAX_OPEN_POSITIONS', '6'))

# Auto-compounding settings
AUTO_COMPOUND = os.getenv('AUTO_COMPOUND', 'True').lower() == 'true'
COMPOUND_REINVEST_PERCENT = float(os.getenv('COMPOUND_REINVEST_PERCENT', '0.75'))  # Reinvest 75% of profits
COMPOUND_INTERVAL = os.getenv('COMPOUND_INTERVAL', 'DAILY')  # Can be TRADE, DAILY, WEEKLY

# Strategy parameters
STRATEGY = os.getenv('STRATEGY', 'XRP_FuturesGrid')  # Changed to our new XRP_FuturesGrid strategy
RSI_PERIOD = int(os.getenv('RSI_PERIOD', '14'))
RSI_OVERBOUGHT = int(os.getenv('RSI_OVERBOUGHT', '70'))
RSI_OVERSOLD = int(os.getenv('RSI_OVERSOLD', '30'))
FAST_EMA = int(os.getenv('FAST_EMA', '8'))
SLOW_EMA = int(os.getenv('SLOW_EMA', '21'))
TIMEFRAME = os.getenv('TIMEFRAME', '15m')  # Default timeframe

# Grid strategy parameters
GRID_LEVELS = int(os.getenv('GRID_LEVELS', '20'))
GRID_STEP_PERCENT = float(os.getenv('GRID_STEP_PERCENT', '0.5'))

# Advanced TA-Lib indicator parameters
BB_PERIOD = int(os.getenv('BB_PERIOD', '20'))
BB_STD = float(os.getenv('BB_STD', '2.0'))
ICHIMOKU_FAST = int(os.getenv('ICHIMOKU_FAST', '9'))
ICHIMOKU_MEDIUM = int(os.getenv('ICHIMOKU_MEDIUM', '26'))
ICHIMOKU_SLOW = int(os.getenv('ICHIMOKU_SLOW', '52'))
MACD_FAST = int(os.getenv('MACD_FAST', '12'))
MACD_SLOW = int(os.getenv('MACD_SLOW', '26'))
MACD_SIGNAL = int(os.getenv('MACD_SIGNAL', '9'))
STOCH_K = int(os.getenv('STOCH_K', '14'))
STOCH_D = int(os.getenv('STOCH_D', '3'))
STOCH_SMOOTH = int(os.getenv('STOCH_SMOOTH', '3'))
EMA_SHORT = int(os.getenv('EMA_SHORT', '5'))
EMA_MEDIUM = int(os.getenv('EMA_MEDIUM', '21'))
EMA_LONG = int(os.getenv('EMA_LONG', '55'))
ATR_PERIOD = int(os.getenv('ATR_PERIOD', '14'))
VWAP_WINDOW = int(os.getenv('VWAP_WINDOW', '14'))

# Risk management
USE_STOP_LOSS = os.getenv('USE_STOP_LOSS', 'True').lower() == 'true'
STOP_LOSS_PCT = float(os.getenv('STOP_LOSS_PCT', '0.025'))  # 2.5% stop loss
USE_TAKE_PROFIT = os.getenv('USE_TAKE_PROFIT', 'True').lower() == 'true'
TAKE_PROFIT_PCT = float(os.getenv('TAKE_PROFIT_PCT', '0.08'))  # 8% take profit
TRAILING_STOP = os.getenv('TRAILING_STOP', 'True').lower() == 'true'  # Enabled trailing stop
TRAILING_STOP_PCT = float(os.getenv('TRAILING_STOP_PCT', '0.025'))  # 2.5% trailing stop
TRAILING_TAKE_PROFIT = os.getenv('TRAILING_TAKE_PROFIT', 'True').lower() == 'true'
TRAILING_TAKE_PROFIT_PCT = float(os.getenv('TRAILING_TAKE_PROFIT_PCT', '0.08'))

# Backtesting parameters
BACKTEST_START_DATE = os.getenv('BACKTEST_START_DATE', '2023-01-01')
BACKTEST_END_DATE = os.getenv('BACKTEST_END_DATE', '')  # Empty means use current date
BACKTEST_INITIAL_BALANCE = float(os.getenv('BACKTEST_INITIAL_BALANCE', '50.0'))
BACKTEST_COMMISSION = float(os.getenv('BACKTEST_COMMISSION', '0.0004'))  # 0.04% taker fee
BACKTEST_USE_AUTO_COMPOUND = os.getenv('BACKTEST_USE_AUTO_COMPOUND', 'True').lower() == 'true'

# Pre-live backtest validation
BACKTEST_BEFORE_LIVE = os.getenv('BACKTEST_BEFORE_LIVE', 'True').lower() == 'true'
BACKTEST_MIN_PROFIT_PCT = float(os.getenv('BACKTEST_MIN_PROFIT_PCT', '3.0'))
BACKTEST_MIN_WIN_RATE = float(os.getenv('BACKTEST_MIN_WIN_RATE', '40.0'))
BACKTEST_PERIOD = os.getenv('BACKTEST_PERIOD', '30 days')

# Logging and notifications
LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
USE_TELEGRAM = os.getenv('USE_TELEGRAM', 'True').lower() == 'true'
TELEGRAM_BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN', '')
TELEGRAM_CHAT_ID = os.getenv('TELEGRAM_CHAT_ID', '')
SEND_DAILY_REPORT = os.getenv('SEND_DAILY_REPORT', 'True').lower() == 'true'
DAILY_REPORT_TIME = os.getenv('DAILY_REPORT_TIME', '00:00')  # 24-hour format

# Other settings
RETRY_COUNT = int(os.getenv('RETRY_COUNT', '3'))
RETRY_DELAY = int(os.getenv('RETRY_DELAY', '5'))  # seconds