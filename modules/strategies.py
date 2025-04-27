import logging
import numpy as np
import pandas as pd
import ta
import time

logger = logging.getLogger(__name__)

class TradingStrategy:
    """Base class for trading strategies"""
    def __init__(self, strategy_name):
        self.strategy_name = strategy_name
        
    def prepare_data(self, klines):
        """Convert raw klines to a DataFrame with OHLCV data"""
        df = pd.DataFrame(klines, columns=[
            'open_time', 'open', 'high', 'low', 'close', 'volume',
            'close_time', 'quote_asset_volume', 'number_of_trades',
            'taker_buy_base_asset_volume', 'taker_buy_quote_asset_volume', 'ignore'
        ])
        
        # Convert string values to numeric
        for col in ['open', 'high', 'low', 'close', 'volume']:
            df[col] = pd.to_numeric(df[col])
            
        # Convert timestamps to datetime
        df['open_time'] = pd.to_datetime(df['open_time'], unit='ms')
        df['close_time'] = pd.to_datetime(df['close_time'], unit='ms')
        
        return df
    
    def get_signal(self, klines):
        """
        Should be implemented by subclasses.
        Returns 'BUY', 'SELL', or None.
        """
        raise NotImplementedError("Each strategy must implement get_signal method")


class BTCScalpingStrategy(TradingStrategy):
    """EMA 9/21 + RSI Scalping strategy optimized for BTC"""
    def __init__(self):
        super().__init__('BTC_Scalping')
        self.fast_ema = 9
        self.slow_ema = 21
        self.rsi_period = 7  # Shorter period for scalping
        self.rsi_overbought = 70
        self.rsi_oversold = 30
        self.volume_window = 10
        
    def get_signal(self, klines):
        df = self.prepare_data(klines)
        
        # Calculate indicators
        df['rsi'] = ta.momentum.RSIIndicator(
            close=df['close'], 
            window=self.rsi_period
        ).rsi()
        
        df['fast_ema'] = ta.trend.EMAIndicator(
            close=df['close'], 
            window=self.fast_ema
        ).ema_indicator()
        
        df['slow_ema'] = ta.trend.EMAIndicator(
            close=df['close'], 
            window=self.slow_ema
        ).ema_indicator()

        # Volume trend
        df['volume_change'] = df['volume'].pct_change() * 100
        df['volume_ma'] = df['volume'].rolling(window=self.volume_window).mean()
        df['is_volume_spike'] = df['volume'] > (df['volume_ma'] * 1.2)
        
        # Current values
        current_price = df['close'].iloc[-1]
        current_rsi = df['rsi'].iloc[-1] 
        current_fast_ema = df['fast_ema'].iloc[-1]
        current_slow_ema = df['slow_ema'].iloc[-1]
        volume_spike = df['is_volume_spike'].iloc[-1]
        
        # Previous values
        prev_fast_ema = df['fast_ema'].iloc[-2] 
        prev_slow_ema = df['slow_ema'].iloc[-2]
        prev_rsi = df['rsi'].iloc[-2]
        
        # Signal logic for BTC scalping
        buy_signal = False
        sell_signal = False
        reason = ""
        
        # BUY conditions for BTC (optimized for 1m-5m timeframes)
        # Condition 1: EMA crossover with RSI confirming uptrend
        if (current_fast_ema > current_slow_ema and prev_fast_ema <= prev_slow_ema):
            if current_rsi > prev_rsi and current_rsi > 40:
                buy_signal = True
                reason = "EMA 9/21 bullish crossover with RSI momentum"
        
        # Condition 2: RSI oversold bounce
        elif (current_rsi > prev_rsi and prev_rsi < self.rsi_oversold and current_rsi < 45):
            buy_signal = True
            reason = "RSI oversold bounce"
        
        # SELL conditions for BTC
        # Condition 1: EMA bearish crossover
        if (current_fast_ema < current_slow_ema and prev_fast_ema >= prev_slow_ema):
            sell_signal = True
            reason = "EMA 9/21 bearish crossover"
        
        # Condition 2: RSI overbought exit
        elif (current_rsi < prev_rsi and current_rsi > self.rsi_overbought):
            sell_signal = True
            reason = "RSI overbought exit signal"
            
        # Generate signals
        if buy_signal and (volume_spike or len(df) > 100):
            logger.info(f"BTC Scalping: BUY signal - {reason}")
            return "BUY"
        elif sell_signal:
            logger.info(f"BTC Scalping: SELL signal - {reason}")
            return "SELL"
            
        return None


class ETHStochMACD(TradingStrategy):
    """MACD + Stochastic Reversal strategy optimized for ETH"""
    def __init__(self):
        super().__init__('ETH_StochMACD')
        self.macd_fast = 12
        self.macd_slow = 26
        self.macd_signal = 9
        self.stoch_k = 14
        self.stoch_d = 3
        self.stoch_smooth = 3
        self.stoch_overbought = 80
        self.stoch_oversold = 20
        
    def get_signal(self, klines):
        df = self.prepare_data(klines)
        
        # Calculate MACD for trend strength
        macd = ta.trend.MACD(
            close=df['close'],
            window_fast=self.macd_fast,
            window_slow=self.macd_slow,
            window_sign=self.macd_signal
        )
        df['macd'] = macd.macd()
        df['macd_signal'] = macd.macd_signal()
        df['macd_hist'] = macd.macd_diff()  # Histogram
        
        # Calculate Stochastic Oscillator
        stoch = ta.momentum.StochasticOscillator(
            high=df['high'],
            low=df['low'],
            close=df['close'],
            window=self.stoch_k,
            smooth_window=self.stoch_smooth
        )
        df['stoch_k'] = stoch.stoch()
        df['stoch_d'] = stoch.stoch_signal()
        
        # Current values
        current_price = df['close'].iloc[-1]
        current_macd = df['macd'].iloc[-1]
        current_macd_signal = df['macd_signal'].iloc[-1]
        current_macd_hist = df['macd_hist'].iloc[-1]
        current_stoch_k = df['stoch_k'].iloc[-1]
        current_stoch_d = df['stoch_d'].iloc[-1]
        
        # Previous values
        prev_macd = df['macd'].iloc[-2]
        prev_macd_signal = df['macd_signal'].iloc[-2]
        prev_macd_hist = df['macd_hist'].iloc[-2]
        prev_stoch_k = df['stoch_k'].iloc[-2]
        prev_stoch_d = df['stoch_d'].iloc[-2]
        
        # Signal logic for ETH reversal strategy
        buy_signal = False
        sell_signal = False
        reason = ""
        
        # BUY conditions for ETH
        # Condition 1: MACD bullish crossover with stochastic confirming
        if (current_macd > current_macd_signal and prev_macd <= prev_macd_signal):
            if current_stoch_k < self.stoch_oversold and current_stoch_k > current_stoch_d:
                buy_signal = True
                reason = "MACD bullish crossover with stochastic confirmation"
        
        # Condition 2: Stochastic oversold reversal with positive MACD histogram
        elif (prev_stoch_k < self.stoch_oversold and current_stoch_k > current_stoch_d and
              current_stoch_k > prev_stoch_k and current_macd_hist > 0):
            buy_signal = True
            reason = "Stochastic oversold reversal with positive MACD"
        
        # SELL conditions for ETH
        # Condition 1: MACD bearish crossover with stochastic confirming
        if (current_macd < current_macd_signal and prev_macd >= prev_macd_signal):
            if current_stoch_k > self.stoch_overbought and current_stoch_k < current_stoch_d:
                sell_signal = True
                reason = "MACD bearish crossover with stochastic confirmation"
        
        # Condition 2: Stochastic overbought reversal with negative MACD histogram
        elif (prev_stoch_k > self.stoch_overbought and current_stoch_k < current_stoch_d and
              current_stoch_k < prev_stoch_k and current_macd_hist < 0):
            sell_signal = True
            reason = "Stochastic overbought reversal with negative MACD"
            
        # Generate signals
        if buy_signal:
            logger.info(f"ETH StochMACD: BUY signal - {reason}")
            return "BUY"
        elif sell_signal:
            logger.info(f"ETH StochMACD: SELL signal - {reason}")
            return "SELL"
            
        return None


class BNBGridStrategy(TradingStrategy):
    """Grid Trading strategy optimized for BNB sideways markets"""
    def __init__(self):
        super().__init__('BNB_Grid')
        self.bb_window = 20
        self.bb_std = 2.0
        self.rsi_period = 14
        self.rsi_middle = 50
        self.grid_levels = 5  # Number of grid levels within BB range
        
    def get_signal(self, klines):
        df = self.prepare_data(klines)
        
        # Calculate Bollinger Bands for grid levels
        bb_indicator = ta.volatility.BollingerBands(
            close=df['close'],
            window=self.bb_window,
            window_dev=self.bb_std
        )
        df['bb_high'] = bb_indicator.bollinger_hband()
        df['bb_low'] = bb_indicator.bollinger_lband()
        df['bb_mid'] = bb_indicator.bollinger_mavg()
        
        # Calculate RSI to detect ranging market
        df['rsi'] = ta.momentum.RSIIndicator(
            close=df['close'], 
            window=self.rsi_period
        ).rsi()
        
        # Calculate volatility
        df['atr'] = ta.volatility.AverageTrueRange(
            high=df['high'],
            low=df['low'],
            close=df['close'],
            window=14
        ).average_true_range()
        
        df['volatility'] = (df['atr'] / df['close']) * 100
        
        # Current values
        current_price = df['close'].iloc[-1]
        current_rsi = df['rsi'].iloc[-1]
        current_bb_high = df['bb_high'].iloc[-1]
        current_bb_low = df['bb_low'].iloc[-1]
        current_bb_mid = df['bb_mid'].iloc[-1]
        current_volatility = df['volatility'].iloc[-1]
        
        # Previous values
        prev_price = df['close'].iloc[-2]
        prev_rsi = df['rsi'].iloc[-2]
        
        # Calculate grid levels
        grid_range = current_bb_high - current_bb_low
        grid_step = grid_range / self.grid_levels
        
        # Signal logic for BNB grid trading - optimized for sideways markets
        buy_signal = False
        sell_signal = False
        reason = ""
        
        # Check if we're in a sideways market (low volatility + RSI near middle)
        is_sideways = (abs(current_rsi - self.rsi_middle) < 15) and (current_volatility < 2.0)
        
        # BUY conditions for BNB
        # Condition 1: Price near lower grid level in sideways market
        if is_sideways and (current_price < (current_bb_low + grid_step)):
            buy_signal = True
            reason = "Grid buy signal at lower band"
        
        # Condition 2: Price drop with RSI indicating no strong downtrend
        elif (current_price < prev_price and 
              current_price < current_bb_mid and 
              current_rsi > 40 and 
              current_rsi > prev_rsi):
            buy_signal = True
            reason = "Support level buy in range-bound market"
        
        # SELL conditions for BNB
        # Condition 1: Price near upper grid level in sideways market
        if is_sideways and (current_price > (current_bb_high - grid_step)):
            sell_signal = True
            reason = "Grid sell signal at upper band"
        
        # Condition 2: Price rise with RSI indicating no strong uptrend
        elif (current_price > prev_price and 
              current_price > current_bb_mid and 
              current_rsi < 60 and 
              current_rsi < prev_rsi):
            sell_signal = True
            reason = "Resistance level sell in range-bound market"
            
        # Generate signals
        if buy_signal:
            logger.info(f"BNB Grid: BUY signal - {reason}")
            return "BUY"
        elif sell_signal:
            logger.info(f"BNB Grid: SELL signal - {reason}")
            return "SELL"
            
        return None


class SOLSqueezeStrategy(TradingStrategy):
    """Bollinger Squeeze strategy optimized for SOL's explosive breakouts"""
    def __init__(self):
        super().__init__('SOL_Squeeze')
        self.bb_window = 20
        self.bb_std = 2.0
        self.kc_window = 20
        self.kc_mult = 1.5
        self.atr_period = 14
        self.rsi_period = 14
        
    def get_signal(self, klines):
        df = self.prepare_data(klines)
        
        # Calculate Bollinger Bands
        bb_indicator = ta.volatility.BollingerBands(
            close=df['close'],
            window=self.bb_window,
            window_dev=self.bb_std
        )
        df['bb_high'] = bb_indicator.bollinger_hband()
        df['bb_low'] = bb_indicator.bollinger_lband()
        df['bb_mid'] = bb_indicator.bollinger_mavg()
        df['bb_width'] = (df['bb_high'] - df['bb_low']) / df['bb_mid']
        
        # Calculate ATR for Keltner Channels
        df['atr'] = ta.volatility.AverageTrueRange(
            high=df['high'],
            low=df['low'],
            close=df['close'],
            window=self.atr_period
        ).average_true_range()
        
        # Calculate Keltner Channels
        typical_price = (df['high'] + df['low'] + df['close']) / 3
        df['kc_mid'] = typical_price.rolling(window=self.kc_window).mean()
        df['kc_high'] = df['kc_mid'] + self.kc_mult * df['atr']
        df['kc_low'] = df['kc_mid'] - self.kc_mult * df['atr']
        
        # Calculate RSI for trend direction
        df['rsi'] = ta.momentum.RSIIndicator(
            close=df['close'], 
            window=self.rsi_period
        ).rsi()
        
        # Calculate volume indicators
        df['volume_ma'] = df['volume'].rolling(window=20).mean()
        df['is_volume_spike'] = df['volume'] > (df['volume_ma'] * 1.5)
        
        # Calculate momentum
        df['momentum'] = df['close'].pct_change(5) * 100
        
        # Bollinger Squeeze occurs when Bollinger Bands are inside Keltner Channels
        df['squeeze_on'] = (df['bb_high'] < df['kc_high']) & (df['bb_low'] > df['kc_low'])
        df['squeeze_off'] = ~df['squeeze_on']
        
        # Detect squeeze release
        df['squeeze_release'] = df['squeeze_off'] & df['squeeze_on'].shift(1)
        
        # Current values
        current_price = df['close'].iloc[-1]
        current_rsi = df['rsi'].iloc[-1]
        current_momentum = df['momentum'].iloc[-1]
        current_squeeze_on = df['squeeze_on'].iloc[-1]
        current_squeeze_release = df['squeeze_release'].iloc[-1]
        volume_spike = df['is_volume_spike'].iloc[-1]
        
        # Previous values
        prev_price = df['close'].iloc[-2]
        prev_rsi = df['rsi'].iloc[-2]
        prev_momentum = df['momentum'].iloc[-2] if len(df) > 2 else 0
        
        # Signal logic for SOL squeeze strategy
        buy_signal = False
        sell_signal = False
        reason = ""
        
        # BUY conditions for SOL
        # Condition 1: Squeeze release with bullish momentum
        if current_squeeze_release and current_price > prev_price and current_momentum > 0:
            buy_signal = True
            reason = "Bullish squeeze release"
        
        # Condition 2: Squeeze building with early momentum
        elif (current_squeeze_on and 
              current_momentum > prev_momentum and 
              current_rsi > prev_rsi and 
              current_rsi > 50):
            buy_signal = True
            reason = "Early squeeze momentum building"
        
        # SELL conditions for SOL
        # Condition 1: Squeeze release with bearish momentum
        if current_squeeze_release and current_price < prev_price and current_momentum < 0:
            sell_signal = True
            reason = "Bearish squeeze release"
        
        # Condition 2: RSI overbought after squeeze
        elif not current_squeeze_on and current_rsi > 70 and current_rsi < prev_rsi:
            sell_signal = True
            reason = "Overbought after squeeze release"
            
        # Generate signals
        if buy_signal and (volume_spike or len(df) > 100):
            logger.info(f"SOL Squeeze: BUY signal - {reason}")
            return "BUY"
        elif sell_signal:
            logger.info(f"SOL Squeeze: SELL signal - {reason}")
            return "SELL"
            
        return None


class ADAEMATrendStrategy(TradingStrategy):
    """RSI + EMA Trend Riding strategy optimized for ADA"""
    def __init__(self):
        super().__init__('ADA_EMATrend')
        self.fast_ema = 8
        self.medium_ema = 21
        self.slow_ema = 55
        self.rsi_period = 14
        self.rsi_overbought = 70
        self.rsi_oversold = 30
        
    def get_signal(self, klines):
        df = self.prepare_data(klines)
        
        # Calculate EMAs
        df['fast_ema'] = ta.trend.EMAIndicator(
            close=df['close'], 
            window=self.fast_ema
        ).ema_indicator()
        
        df['medium_ema'] = ta.trend.EMAIndicator(
            close=df['close'], 
            window=self.medium_ema
        ).ema_indicator()
        
        df['slow_ema'] = ta.trend.EMAIndicator(
            close=df['close'], 
            window=self.slow_ema
        ).ema_indicator()
        
        # Calculate RSI
        df['rsi'] = ta.momentum.RSIIndicator(
            close=df['close'], 
            window=self.rsi_period
        ).rsi()
        
        # Current values
        current_price = df['close'].iloc[-1]
        current_fast_ema = df['fast_ema'].iloc[-1]
        current_medium_ema = df['medium_ema'].iloc[-1]
        current_slow_ema = df['slow_ema'].iloc[-1]
        current_rsi = df['rsi'].iloc[-1]
        
        # Previous values
        prev_price = df['close'].iloc[-2]
        prev_fast_ema = df['fast_ema'].iloc[-2]
        prev_medium_ema = df['medium_ema'].iloc[-2]
        prev_rsi = df['rsi'].iloc[-2]
        
        # Signal logic for ADA trend riding
        buy_signal = False
        sell_signal = False
        reason = ""
        
        # Check for EMA alignment (trend strength)
        bullish_alignment = current_fast_ema > current_medium_ema > current_slow_ema
        bearish_alignment = current_fast_ema < current_medium_ema < current_slow_ema
        
        # BUY conditions for ADA
        # Condition 1: RSI crosses above 30 with bullish EMA alignment
        if current_rsi > 30 and prev_rsi <= 30 and bullish_alignment:
            buy_signal = True
            reason = "RSI bounce from oversold with bullish EMA alignment"
        
        # Condition 2: Fast EMA crosses above medium EMA with rising RSI
        elif (current_fast_ema > current_medium_ema and prev_fast_ema <= prev_medium_ema and
              current_rsi > prev_rsi and current_rsi > 40):
            buy_signal = True
            reason = "Fast EMA crosses above medium with rising RSI"
        
        # Condition 3: Price pullback to fast EMA in uptrend
        elif (bullish_alignment and
              abs(current_price - current_fast_ema) / current_price < 0.005 and  # Price near fast EMA
              current_price > prev_price and current_rsi > 45):
            buy_signal = True
            reason = "Price pullback to fast EMA in uptrend"
        
        # SELL conditions for ADA
        # Condition 1: RSI crosses below 70 after being overbought
        if current_rsi < 70 and prev_rsi >= 70:
            sell_signal = True
            reason = "RSI crosses down from overbought"
        
        # Condition 2: Fast EMA crosses below medium EMA with falling RSI
        elif (current_fast_ema < current_medium_ema and prev_fast_ema >= prev_medium_ema and
              current_rsi < prev_rsi and current_rsi < 60):
            sell_signal = True
            reason = "Fast EMA crosses below medium with falling RSI"
        
        # Condition 3: Price in bearish alignment with strong downward momentum
        elif bearish_alignment and current_rsi < 40 and current_rsi < prev_rsi:
            sell_signal = True
            reason = "Strong bearish alignment with momentum"
            
        # Generate signals
        if buy_signal:
            logger.info(f"ADA EMATrend: BUY signal - {reason}")
            return "BUY"
        elif sell_signal:
            logger.info(f"ADA EMATrend: SELL signal - {reason}")
            return "SELL"
            
        return None


class XRPScalpingStrategy(TradingStrategy):
    """Aggressive Scalping strategy optimized for XRP's fast movements"""
    def __init__(self):
        super().__init__('XRP_Scalping')
        self.fast_ema = 5
        self.medium_ema = 13
        self.slow_ema = 21
        self.rsi_period = 6  # Very short for fast response
        self.rsi_overbought = 75
        self.rsi_oversold = 25
        self.bb_window = 15
        self.bb_std = 2.5
        
    def get_signal(self, klines):
        df = self.prepare_data(klines)
        
        # Calculate EMAs for multiple confirmations
        df['fast_ema'] = ta.trend.EMAIndicator(
            close=df['close'], 
            window=self.fast_ema
        ).ema_indicator()
        
        df['medium_ema'] = ta.trend.EMAIndicator(
            close=df['close'], 
            window=self.medium_ema
        ).ema_indicator()
        
        df['slow_ema'] = ta.trend.EMAIndicator(
            close=df['close'], 
            window=self.slow_ema
        ).ema_indicator()
        
        # Calculate RSI with very short period
        df['rsi'] = ta.momentum.RSIIndicator(
            close=df['close'], 
            window=self.rsi_period
        ).rsi()
        
        # Calculate Bollinger Bands 
        bb_indicator = ta.volatility.BollingerBands(
            close=df['close'],
            window=self.bb_window,
            window_dev=self.bb_std
        )
        df['bb_high'] = bb_indicator.bollinger_hband()
        df['bb_low'] = bb_indicator.bollinger_lband()
        
        # Calculate momentum
        df['price_change'] = df['close'].pct_change(3) * 100
        df['volume_change'] = df['volume'].pct_change(3) * 100
        
        # Current values
        current_price = df['close'].iloc[-1]
        current_fast_ema = df['fast_ema'].iloc[-1]
        current_medium_ema = df['medium_ema'].iloc[-1]
        current_slow_ema = df['slow_ema'].iloc[-1]
        current_rsi = df['rsi'].iloc[-1]
        current_bb_high = df['bb_high'].iloc[-1]
        current_bb_low = df['bb_low'].iloc[-1]
        current_price_change = df['price_change'].iloc[-1]
        current_volume_change = df['volume_change'].iloc[-1]
        
        # Previous values
        prev_price = df['close'].iloc[-2]
        prev_fast_ema = df['fast_ema'].iloc[-2]
        prev_medium_ema = df['medium_ema'].iloc[-2]
        prev_rsi = df['rsi'].iloc[-2]
        
        # Signal logic for XRP aggressive scalping
        buy_signal = False
        sell_signal = False
        reason = ""
        
        # XRP often moves quickly, so we want to catch early moves
        
        # BUY conditions for XRP
        # Condition 1: Quick RSI reversal from oversold
        if current_rsi > prev_rsi + 5 and prev_rsi < self.rsi_oversold:
            buy_signal = True
            reason = "Quick RSI reversal from oversold"
        
        # Condition 2: Fast EMA crossing above medium with strong momentum
        elif (current_fast_ema > current_medium_ema and prev_fast_ema <= prev_medium_ema and
              current_price_change > 1.0 and current_volume_change > 15):
            buy_signal = True
            reason = "Fast EMA crosses with strong momentum"
        
        # Condition 3: Price near lower BB with positive momentum shift
        elif (current_price < current_bb_low * 1.02 and  # Price near or below lower BB
              current_price > prev_price and current_rsi > prev_rsi):
            buy_signal = True
            reason = "Price bounce from lower BB"
        
        # SELL conditions for XRP
        # Condition 1: Quick RSI reversal from overbought
        if current_rsi < prev_rsi - 5 and prev_rsi > self.rsi_overbought:
            sell_signal = True
            reason = "Quick RSI reversal from overbought"
        
        # Condition 2: Fast EMA crossing below medium with momentum
        elif (current_fast_ema < current_medium_ema and prev_fast_ema >= prev_medium_ema and
              current_price_change < -1.0):
            sell_signal = True
            reason = "Fast EMA crosses below medium with momentum"
        
        # Condition 3: Price near upper BB with momentum shift
        elif (current_price > current_bb_high * 0.98 and  # Price near or above upper BB
              current_price < prev_price and current_rsi < prev_rsi):
            sell_signal = True
            reason = "Price rejection from upper BB"
            
        # Generate signals - for XRP we want to be more aggressive with entries
        if buy_signal:
            logger.info(f"XRP Scalping: BUY signal - {reason}")
            return "BUY"
        elif sell_signal:
            logger.info(f"XRP Scalping: SELL signal - {reason}")
            return "SELL"
            
        return None


class DOGEScalpingStrategy(TradingStrategy):
    """VWAP + EMA 5 Scalping strategy optimized for DOGE's meme volatility"""
    def __init__(self):
        super().__init__('DOGE_Scalping')
        self.fast_ema = 5
        self.medium_ema = 10
        self.rsi_period = 8
        self.rsi_overbought = 70
        self.rsi_oversold = 30
        self.vwap_window = 14
        
    def get_signal(self, klines):
        df = self.prepare_data(klines)
        
        # Calculate EMAs
        df['fast_ema'] = ta.trend.EMAIndicator(
            close=df['close'], 
            window=self.fast_ema
        ).ema_indicator()
        
        df['medium_ema'] = ta.trend.EMAIndicator(
            close=df['close'], 
            window=self.medium_ema
        ).ema_indicator()
        
        # Calculate RSI
        df['rsi'] = ta.momentum.RSIIndicator(
            close=df['close'], 
            window=self.rsi_period
        ).rsi()
        
        # Calculate VWAP (approximation since we don't have intraday data)
        df['typical_price'] = (df['high'] + df['low'] + df['close']) / 3
        df['tp_volume'] = df['typical_price'] * df['volume']
        
        # Create cumulative sums for the specified window
        df['cum_tp_volume'] = df['tp_volume'].rolling(window=self.vwap_window).sum()
        df['cum_volume'] = df['volume'].rolling(window=self.vwap_window).sum()
        
        # Calculate VWAP
        df['vwap'] = df['cum_tp_volume'] / df['cum_volume']
        
        # Calculate volume and price change
        df['volume_change'] = df['volume'].pct_change(3) * 100
        df['price_change_1'] = df['close'].pct_change(1) * 100
        df['price_change_3'] = df['close'].pct_change(3) * 100
        
        # Current values
        current_price = df['close'].iloc[-1]
        current_fast_ema = df['fast_ema'].iloc[-1]
        current_medium_ema = df['medium_ema'].iloc[-1]
        current_rsi = df['rsi'].iloc[-1]
        current_vwap = df['vwap'].iloc[-1]
        current_volume_change = df['volume_change'].iloc[-1]
        current_price_change_1 = df['price_change_1'].iloc[-1]
        current_price_change_3 = df['price_change_3'].iloc[-1]
        
        # Previous values
        prev_price = df['close'].iloc[-2]
        prev_fast_ema = df['fast_ema'].iloc[-2]
        prev_medium_ema = df['medium_ema'].iloc[-2]
        prev_rsi = df['rsi'].iloc[-2]
        prev_vwap = df['vwap'].iloc[-2]
        
        # Signal logic for DOGE meme volatility scalping
        buy_signal = False
        sell_signal = False
        reason = ""
        
        # BUY conditions for DOGE
        # Condition 1: Price crosses above VWAP with volume spike
        if current_price > current_vwap and prev_price <= prev_vwap and current_volume_change > 20:
            buy_signal = True
            reason = "Price crossed above VWAP with volume spike"
        
        # Condition 2: Fast EMA crossing above medium with momentum
        elif (current_fast_ema > current_medium_ema and prev_fast_ema <= prev_medium_ema and
              current_price_change_1 > 1.0):
            buy_signal = True
            reason = "Fast EMA 5 cross with strong momentum"
        
        # Condition 3: Price bounces off EMA 5 in uptrend
        elif (current_price > current_fast_ema and
              abs(prev_price - prev_fast_ema)/prev_price < 0.005 and  # Previous bar touched EMA
              current_price > prev_price and current_rsi > 50):
            buy_signal = True
            reason = "Price bounce from EMA 5 support"
        
        # SELL conditions for DOGE
        # Condition 1: Price crosses below VWAP with momentum
        if current_price < current_vwap and prev_price >= prev_vwap and current_price_change_1 < -1.0:
            sell_signal = True
            reason = "Price crossed below VWAP with momentum"
        
        # Condition 2: Fast EMA crossing below medium
        elif (current_fast_ema < current_medium_ema and prev_fast_ema >= prev_medium_ema):
            sell_signal = True
            reason = "Fast EMA crossed below medium EMA"
        
        # Condition 3: RSI overbought with price rejection
        elif current_rsi > self.rsi_overbought and current_price < prev_price:
            sell_signal = True
            reason = "RSI overbought with price rejection"
            
        # Generate signals
        if buy_signal:
            logger.info(f"DOGE Scalping: BUY signal - {reason}")
            return "BUY"
        elif sell_signal:
            logger.info(f"DOGE Scalping: SELL signal - {reason}")
            return "SELL"
            
        return None


class SHIBBreakoutStrategy(TradingStrategy):
    """Breakout Trading strategy optimized for SHIB's extreme moves"""
    def __init__(self):
        super().__init__('SHIB_Breakout')
        self.atr_period = 14
        self.rsi_period = 14
        self.lookback_period = 10
        self.volume_multiplier = 2.0
        
    def get_signal(self, klines):
        df = self.prepare_data(klines)
        
        # Calculate ATR for volatility
        df['atr'] = ta.volatility.AverageTrueRange(
            high=df['high'],
            low=df['low'],
            close=df['close'],
            window=self.atr_period
        ).average_true_range()
        
        # Calculate RSI
        df['rsi'] = ta.momentum.RSIIndicator(
            close=df['close'], 
            window=self.rsi_period
        ).rsi()
        
        # Calculate volume indicators
        df['volume_ma'] = df['volume'].rolling(window=20).mean()
        df['volume_ratio'] = df['volume'] / df['volume_ma']
        
        # Calculate price ranges for breakout detection
        df['highest_high'] = df['high'].rolling(window=self.lookback_period).max()
        df['lowest_low'] = df['low'].rolling(window=self.lookback_period).min()
        
        # Calculate momentum and volatility features
        df['price_change'] = df['close'].pct_change() * 100
        df['volatility'] = (df['atr'] / df['close']) * 100
        
        # Current values
        current_price = df['close'].iloc[-1]
        current_high = df['high'].iloc[-1]
        current_low = df['low'].iloc[-1]
        current_rsi = df['rsi'].iloc[-1]
        current_highest_high = df['highest_high'].iloc[-1]
        current_lowest_low = df['lowest_low'].iloc[-1]
        current_volume_ratio = df['volume_ratio'].iloc[-1]
        current_volatility = df['volatility'].iloc[-1]
        
        # Previous values
        prev_price = df['close'].iloc[-2]
        prev_high = df['high'].iloc[-2]
        prev_highest_high = df['highest_high'].iloc[-2]
        prev_lowest_low = df['lowest_low'].iloc[-2]
        
        # Signal logic for SHIB breakout trading
        buy_signal = False
        sell_signal = False
        reason = ""
        
        # BUY conditions for SHIB
        # Condition 1: Price breaks above previous high with volume
        if (current_high > prev_highest_high and 
            current_price > prev_price and 
            current_volume_ratio > self.volume_multiplier):
            buy_signal = True
            reason = "Bullish breakout with high volume"
        
        # Condition 2: Strong upward momentum on high volume
        elif (current_price > prev_price * 1.03 and  # 3% price jump
              current_volume_ratio > self.volume_multiplier):
            buy_signal = True
            reason = "Strong momentum breakout"
        
        # SELL conditions for SHIB
        # Condition 1: Price breaks below previous low with volume
        if (current_low < prev_lowest_low and 
            current_price < prev_price and 
            current_volume_ratio > self.volume_multiplier):
            sell_signal = True
            reason = "Bearish breakdown with high volume"
        
        # Condition 2: Strong downward momentum on high volume
        elif (current_price < prev_price * 0.97 and  # 3% price drop
              current_volume_ratio > self.volume_multiplier):
            sell_signal = True
            reason = "Strong momentum breakdown"
            
        # Generate signals
        if buy_signal:
            logger.info(f"SHIB Breakout: BUY signal - {reason}")
            return "BUY"
        elif sell_signal:
            logger.info(f"SHIB Breakout: SELL signal - {reason}")
            return "SELL"
            
        return None


class XRPFuturesGridStrategy(TradingStrategy):
    """Advanced Futures Grid strategy optimized for XRP's volatility with dynamic parameter adjustment"""
    def __init__(self):
        super().__init__('XRP_FuturesGrid')
        # Default parameters - will be dynamically adjusted
        self.grid_levels = 20
        self.grid_step_percent = 0.5
        self.bb_period = 20
        self.bb_std = 2.0
        self.ichimoku_fast = 9
        self.ichimoku_medium = 26
        self.ichimoku_slow = 52
        self.rsi_period = 14
        self.rsi_overbought = 70
        self.rsi_oversold = 30
        self.macd_fast = 12
        self.macd_slow = 26
        self.macd_signal = 9
        
        # Parameters for dynamic adjustment
        self.volatility_lookback = 20
        self.regime_lookback = 50
        self.last_adjustment_time = 0
        self.adjustment_interval = 12  # Hours between parameter recalibrations
        self.min_grid_levels = 10
        self.max_grid_levels = 40
        self.min_grid_step = 0.25
        self.max_grid_step = 1.5
        
    def detect_market_regime(self, df):
        """Detect if the market is trending, ranging, or volatile"""
        # Ensure we have enough data to calculate indicators
        if len(df) < max(30, self.regime_lookback):
            # Default to ranging market if not enough data
            return {
                'volatile': False,
                'trending': False,
                'ranging': True,
                'volatility': 2.0,
                'trend_strength': 15,
                'trend_direction': 0,
                'price_trend': 0
            }
        
        # Calculate volatility metrics
        df['daily_range'] = (df['high'] - df['low']) / df['low'] * 100
        
        # Calculate directional movement
        df['close_change'] = df['close'].pct_change()
        df['direction'] = df['close_change'].apply(lambda x: 1 if x > 0 else -1 if x < 0 else 0)
        df['direction_change'] = df['direction'].diff().abs()
        
        # Get recent metrics - safely
        lookback = min(self.volatility_lookback, len(df)-1)
        regime_lookback = min(self.regime_lookback, len(df)-1)
        
        recent_volatility = df['daily_range'].tail(lookback).mean()
        recent_direction_changes = df['direction_change'].tail(regime_lookback).sum()
        
        # Safe calculation of price trend
        if regime_lookback > 0:
            price_trend = (df['close'].iloc[-1] - df['close'].iloc[-regime_lookback]) / df['close'].iloc[-regime_lookback] * 100
        else:
            price_trend = 0
        
        # Calculate trend strength using ADX safely
        try:
            adx_window = min(14, len(df)//2)
            if adx_window < 2:
                adx_window = 2
                
            adx_indicator = ta.trend.ADXIndicator(
                high=df['high'],
                low=df['low'],
                close=df['close'],
                window=adx_window
            )
            
            # Handle potential NaN or division by zero issues in ADX calculation
            adx_value = adx_indicator.adx()
            if adx_value.iloc[-1] != adx_value.iloc[-1]:  # Check for NaN (NaN != NaN)
                adx = 15  # Default value if NaN
            else:
                adx = adx_value.iloc[-1]
                
        except Exception as e:
            logger.warning(f"Error calculating ADX: {e}")
            adx = 15  # Default value if calculation fails
        
        # Determine market regime
        is_volatile = recent_volatility > 3.0  # 3% average daily range
        is_trending = abs(price_trend) > 10 and adx > 25  # 10% move and ADX > 25
        is_ranging = recent_direction_changes > (regime_lookback * 0.4) and not is_trending
        
        return {
            'volatile': is_volatile,
            'trending': is_trending,
            'ranging': is_ranging,
            'volatility': recent_volatility,
            'trend_strength': adx,
            'trend_direction': 1 if price_trend > 0 else -1 if price_trend < 0 else 0,
            'price_trend': price_trend
        }
    
    def adjust_parameters(self, df, regime):
        """Dynamically adjust strategy parameters based on market conditions"""
        current_time = time.time()
        # Only adjust every adjustment_interval hours to avoid constant changes
        if current_time - self.last_adjustment_time < self.adjustment_interval * 3600:
            return
            
        # Adjust grid parameters based on volatility
        if regime['volatile']:
            # More grid levels with wider spacing in volatile markets
            self.grid_levels = min(int(20 * (1 + regime['volatility'] / 10)), self.max_grid_levels)
            self.grid_step_percent = min(self.max_grid_step, 0.5 * (1 + regime['volatility'] / 5))
            
            # Adjust Bollinger Bands for volatile markets
            self.bb_std = 2.5
            self.bb_period = 15  # Faster response in volatile markets
            
            # Adjust Ichimoku for faster signals
            self.ichimoku_fast = 7
            self.ichimoku_medium = 22
            
            # Widen RSI thresholds in volatile markets
            self.rsi_overbought = 75
            self.rsi_oversold = 25
            
            logger.info(f"XRP Strategy: Adjusted for volatile market. Grid levels={self.grid_levels}, step={self.grid_step_percent:.2f}%")
            
        elif regime['trending']:
            # Fewer grid levels with narrower spacing in trending markets
            trend_direction = regime['trend_direction']
            
            # Adjust based on trend direction
            if trend_direction > 0:  # Uptrend
                # In uptrend, set more grid levels above current price
                self.grid_levels = int(15 * (1 + regime['trend_strength'] / 30))
                self.grid_step_percent = 0.4 * (1 + regime['trend_strength'] / 40)
                
                # Adjust RSI for uptrend (avoid selling too early)
                self.rsi_overbought = 80
                self.rsi_oversold = 40
                
            else:  # Downtrend
                # In downtrend, set more grid levels below current price
                self.grid_levels = int(15 * (1 + regime['trend_strength'] / 30))
                self.grid_step_percent = 0.4 * (1 + regime['trend_strength'] / 40)
                
                # Adjust RSI for downtrend (avoid buying too early)
                self.rsi_overbought = 60
                self.rsi_oversold = 20
            
            # Adjust MACD for trend following
            self.macd_fast = 8
            self.macd_slow = 21
            
            logger.info(f"XRP Strategy: Adjusted for trending market ({regime['trend_direction']}). Grid levels={self.grid_levels}, step={self.grid_step_percent:.2f}%")
            
        elif regime['ranging']:
            # More grid levels with narrower spacing in ranging markets
            self.grid_levels = 30  # Maximum grid density for ranging markets
            self.grid_step_percent = self.min_grid_step
            
            # Adjust Bollinger Bands for ranging markets
            self.bb_std = 1.8
            self.bb_period = 20
            
            # Standard RSI values work well in ranging markets
            self.rsi_overbought = 70
            self.rsi_oversold = 30
            
            logger.info(f"XRP Strategy: Adjusted for ranging market. Grid levels={self.grid_levels}, step={self.grid_step_percent:.2f}%")
            
        else:
            # Default settings for normal markets
            self.grid_levels = 20
            self.grid_step_percent = 0.5
            self.bb_std = 2.0
            self.bb_period = 20
            self.rsi_overbought = 70
            self.rsi_oversold = 30
            
            logger.info("XRP Strategy: Using default parameters for normal market conditions")
        
        # Ensure parameters are within bounds
        self.grid_levels = max(min(self.grid_levels, self.max_grid_levels), self.min_grid_levels)
        self.grid_step_percent = max(min(self.grid_step_percent, self.max_grid_step), self.min_grid_step)
        
        # Update last adjustment time
        self.last_adjustment_time = current_time
        
    def get_signal(self, klines):
        """Get trading signal based on current market conditions"""
        # Convert klines to dataframe
        df = self.prepare_data(klines)
        
        # Check if we have enough data for indicators
        if len(df) < 30:
            logger.warning(f"XRP FuturesGrid: Not enough data to generate signal ({len(df)} candles)")
            return None
            
        # Detect market regime
        regime = self.detect_market_regime(df)
        
        # Dynamically adjust parameters based on market conditions
        self.adjust_parameters(df, regime)
        
        # Calculate Bollinger Bands for dynamic grid range - safely
        bb_period = min(self.bb_period, len(df)-1)
        if bb_period < 2:
            bb_period = 2
            
        try:
            bb_indicator = ta.volatility.BollingerBands(
                close=df['close'],
                window=bb_period,
                window_dev=self.bb_std
            )
            df['bb_high'] = bb_indicator.bollinger_hband()
            df['bb_low'] = bb_indicator.bollinger_lband()
            df['bb_mid'] = bb_indicator.bollinger_mavg()
            df['bb_width'] = (df['bb_high'] - df['bb_low']) / df['bb_mid']
        except Exception as e:
            logger.warning(f"Error calculating Bollinger Bands: {e}")
            return None
        
        # Calculate Ichimoku Cloud components - safely
        try:
            ichimoku_fast = min(self.ichimoku_fast, len(df)//2)
            ichimoku_medium = min(self.ichimoku_medium, len(df)//2)
            ichimoku_slow = min(self.ichimoku_slow, len(df)//2)
            
            if ichimoku_fast < 2: ichimoku_fast = 2
            if ichimoku_medium < 3: ichimoku_medium = 3
            if ichimoku_slow < 5: ichimoku_slow = 5
            
            df['tenkan_sen'] = self._calculate_ichimoku_line(df, ichimoku_fast)
            df['kijun_sen'] = self._calculate_ichimoku_line(df, ichimoku_medium)
            df['senkou_span_a'] = (df['tenkan_sen'] + df['kijun_sen']) / 2
            df['senkou_span_b'] = self._calculate_ichimoku_line(df, ichimoku_slow)
        except Exception as e:
            logger.warning(f"Error calculating Ichimoku: {e}")
            return None
        
        # Calculate MACD - safely
        try:
            macd_fast = min(self.macd_fast, len(df)//2)
            macd_slow = min(self.macd_slow, len(df)//2)
            macd_signal = min(self.macd_signal, len(df)//2)
            
            if macd_fast < 2: macd_fast = 2
            if macd_slow < 3: macd_slow = 3
            if macd_signal < 2: macd_signal = 2
            
            # Ensure slow is greater than fast
            if macd_slow <= macd_fast:
                macd_slow = macd_fast + 1
                
            macd = ta.trend.MACD(
                close=df['close'],
                window_fast=macd_fast,
                window_slow=macd_slow,
                window_sign=macd_signal
            )
            df['macd'] = macd.macd()
            df['macd_signal'] = macd.macd_signal()
            df['macd_hist'] = macd.macd_diff()
        except Exception as e:
            logger.warning(f"Error calculating MACD: {e}")
            return None
        
        # Calculate RSI for trend direction - safely
        try:
            rsi_period = min(self.rsi_period, len(df)//2)
            if rsi_period < 2: rsi_period = 2
            
            df['rsi'] = ta.momentum.RSIIndicator(
                close=df['close'], 
                window=rsi_period
            ).rsi()
        except Exception as e:
            logger.warning(f"Error calculating RSI: {e}")
            return None
        
        # Calculate ADX for trend strength - safely
        try:
            adx_period = min(14, len(df)//2)
            if adx_period < 2: adx_period = 2
            
            # Wrap the ADX calculation in try-except to handle divide by zero warnings
            with np.errstate(divide='ignore', invalid='ignore'):
                adx = ta.trend.ADXIndicator(
                    high=df['high'],
                    low=df['low'],
                    close=df['close'],
                    window=adx_period
                )
                df['adx'] = adx.adx()
                df['adx_pos'] = adx.adx_pos()
                df['adx_neg'] = adx.adx_neg()
                
                # Replace any NaN or infinity values
                df['adx'] = df['adx'].replace([np.inf, -np.inf], np.nan).fillna(15)
                df['adx_pos'] = df['adx_pos'].replace([np.inf, -np.inf], np.nan).fillna(20)
                df['adx_neg'] = df['adx_neg'].replace([np.inf, -np.inf], np.nan).fillna(20)
        except Exception as e:
            logger.warning(f"Error calculating ADX: {e}")
            df['adx'] = 15  # Default value if calculation fails
            df['adx_pos'] = 20
            df['adx_neg'] = 20
        
        # Ensure we have at least 2 rows of valid data that aren't NaN
        if len(df) < 2 or df['bb_high'].iloc[-1] != df['bb_high'].iloc[-1] or df['macd'].iloc[-1] != df['macd'].iloc[-1] or df['rsi'].iloc[-1] != df['rsi'].iloc[-1]:
            logger.warning("XRP FuturesGrid: Some indicators returned NaN values, skipping signal generation")
            return None
            
        # Check for any remaining NaN in key indicators
        key_indicators = ['bb_high', 'bb_low', 'macd', 'macd_signal', 'rsi', 'tenkan_sen', 'kijun_sen']
        for indicator in key_indicators:
            if df[indicator].iloc[-1] != df[indicator].iloc[-1]:  # Check for NaN (NaN != NaN)
                logger.warning(f"XRP FuturesGrid: NaN value in {indicator}, skipping signal generation")
                return None
        
        # Current values
        try:
            current_price = df['close'].iloc[-1]
            current_bb_high = df['bb_high'].iloc[-1]
            current_bb_low = df['bb_low'].iloc[-1]
            current_bb_mid = df['bb_mid'].iloc[-1]
            current_tenkan = df['tenkan_sen'].iloc[-1]
            current_kijun = df['kijun_sen'].iloc[-1]
            current_senkou_a = df['senkou_span_a'].iloc[-1]
            current_senkou_b = df['senkou_span_b'].iloc[-1]
            current_rsi = df['rsi'].iloc[-1]
            current_macd = df['macd'].iloc[-1]
            current_macd_signal = df['macd_signal'].iloc[-1]
            current_macd_hist = df['macd_hist'].iloc[-1]
            current_adx = df['adx'].iloc[-1]
            
            # Previous values
            prev_price = df['close'].iloc[-2]
            prev_tenkan = df['tenkan_sen'].iloc[-2]
            prev_kijun = df['kijun_sen'].iloc[-2]
            prev_macd = df['macd'].iloc[-2]
            prev_macd_signal = df['macd_signal'].iloc[-2]
            prev_macd_hist = df['macd_hist'].iloc[-2]
            prev_rsi = df['rsi'].iloc[-2]
        except Exception as e:
            logger.warning(f"Error accessing indicator values: {e}")
            return None
        
        # Calculate dynamic grid based on volatility and market regime
        grid_range = current_bb_high - current_bb_low
        grid_step = grid_range / max(self.grid_levels, 1)  # Avoid division by zero
        
        # Market condition assessment
        cloud_bullish = current_senkou_a > current_senkou_b
        price_above_cloud = current_price > max(current_senkou_a, current_senkou_b)
        price_below_cloud = current_price < min(current_senkou_a, current_senkou_b)
        is_strong_trend = current_adx > 25
        
        # Signal logic for XRP futures grid - dynamically adjusted based on market regime
        buy_signal = False
        sell_signal = False
        reason = ""
        
        # Dynamically adjust entry/exit conditions based on market regime
        if regime['trending']:
            if regime['trend_direction'] > 0:  # Uptrend
                # BUY conditions for uptrend - focus on pullbacks
                if (current_price <= current_bb_mid and
                    current_rsi > prev_rsi and current_rsi < 60 and
                    current_price > current_tenkan and
                    cloud_bullish):
                    buy_signal = True
                    reason = "Bullish trend pullback to midband"
                
                # SELL conditions for uptrend - focus on overbought conditions
                if (current_price >= current_bb_high and
                    current_rsi > self.rsi_overbought and
                    current_rsi < prev_rsi and
                    current_macd < current_macd_signal):
                    sell_signal = True
                    reason = "Overbought reversal in uptrend"
                    
            else:  # Downtrend
                # BUY conditions for downtrend - only on strong reversal signals
                if (current_price < current_bb_low and
                    current_rsi < self.rsi_oversold and
                    current_rsi > prev_rsi and
                    current_macd > prev_macd and
                    current_macd > current_macd_signal):
                    buy_signal = True
                    reason = "Potential trend reversal from oversold"
                
                # SELL conditions for downtrend - sell rallies
                if (current_price > current_bb_mid and
                    current_price < prev_price and
                    current_macd < current_macd_signal):
                    sell_signal = True
                    reason = "Selling rally in downtrend"
        
        elif regime['ranging']:
            # BUY conditions for ranging market - focus on grid levels
            if (current_price <= current_bb_low * 1.01):  # Price near lower BB
                if (current_rsi < 40 and current_rsi > prev_rsi):
                    buy_signal = True
                    reason = "Range trading buy at support"
            
            # SELL conditions for ranging market
            if (current_price >= current_bb_high * 0.99):  # Price near upper BB
                if (current_rsi > 60 and current_rsi < prev_rsi):
                    sell_signal = True
                    reason = "Range trading sell at resistance"
        
        elif regime['volatile']:
            # BUY conditions for volatile market - more conservative
            if (current_tenkan > current_kijun and prev_tenkan <= prev_kijun):  # TK Cross
                if (current_macd > current_macd_signal and 
                    current_macd_hist > prev_macd_hist and
                    current_price > current_bb_mid):
                    buy_signal = True
                    reason = "Volatile market bullish TK cross with momentum"
            
            # SELL conditions for volatile market - capture quick profits
            if (current_tenkan < current_kijun and prev_tenkan >= prev_kijun):  # TK Cross
                if (current_macd < current_macd_signal and 
                    current_macd_hist < prev_macd_hist and
                    current_price < current_bb_mid):
                    sell_signal = True
                    reason = "Volatile market bearish TK cross with momentum"
        
        else:
            # Default BUY conditions for normal market
            # Condition 1: Price at lower grid with bullish indicators
            if (current_price <= (current_bb_low + grid_step)):
                if (current_rsi < self.rsi_oversold and current_rsi > prev_rsi):
                    if (cloud_bullish or current_macd > current_macd_signal):
                        buy_signal = True
                        reason = "Grid buy at support with bullish confirmation"
            
            # Condition 2: Ichimoku TK cross in bullish market
            elif (current_tenkan > current_kijun and prev_tenkan <= prev_kijun):
                if price_above_cloud or (cloud_bullish and current_price > current_bb_mid):
                    if current_macd_hist > 0 and current_macd_hist > prev_macd_hist:
                        buy_signal = True
                        reason = "Bullish TK cross with MACD confirmation"
            
            # Default SELL conditions for normal market
            # Condition 1: Price at upper grid with bearish indicators
            if (current_price >= (current_bb_high - grid_step)):
                if (current_rsi > self.rsi_overbought and current_rsi < prev_rsi):
                    if (not cloud_bullish or current_macd < current_macd_signal):
                        sell_signal = True
                        reason = "Grid sell at resistance with bearish confirmation"
            
            # Condition 2: Ichimoku TK cross in bearish market
            elif (current_tenkan < current_kijun and prev_tenkan >= prev_kijun):
                if price_below_cloud or (not cloud_bullish and current_price < current_bb_mid):
                    if current_macd_hist < 0 and current_macd_hist < prev_macd_hist:
                        sell_signal = True
                        reason = "Bearish TK cross with MACD confirmation"
        
        # Generate signals
        if buy_signal:
            logger.info(f"XRP FuturesGrid: BUY signal - {reason} [Regime: {'Trending' if regime['trending'] else 'Ranging' if regime['ranging'] else 'Volatile' if regime['volatile'] else 'Normal'}]")
            return "BUY"
        elif sell_signal:
            logger.info(f"XRP FuturesGrid: SELL signal - {reason} [Regime: {'Trending' if regime['trending'] else 'Ranging' if regime['ranging'] else 'Volatile' if regime['volatile'] else 'Normal'}]")
            return "SELL"
            
        return None
    
    def _calculate_ichimoku_line(self, df, period):
        """Helper method to calculate Ichimoku lines with safety checks"""
        if len(df) < period:
            # Return a series of the same length as df but filled with the middle of min/max price
            mid_price = (df['high'].mean() + df['low'].mean()) / 2
            return pd.Series([mid_price] * len(df), index=df.index)
            
        # Safe calculation with fallback
        try:
            high_period = df['high'].rolling(window=period).max()
            low_period = df['low'].rolling(window=period).min()
            result = (high_period + low_period) / 2
            
            # Fill NaN values with rolling average of price
            if result.isna().any():
                mid_price = (df['high'] + df['low']) / 2
                result = result.fillna(mid_price.rolling(window=max(2, period//2)).mean())
            
            return result
        except Exception as e:
            logger.warning(f"Error in _calculate_ichimoku_line: {e}")
            # Fallback to simple moving average
            return df['close'].rolling(window=max(2, period)).mean().fillna(df['close'])


class SOLFuturesGridStrategy(TradingStrategy):
    """Advanced Futures Grid strategy for SOL with volatility-adjusted levels and dynamic parameter optimization"""
    def __init__(self):
        super().__init__('SOL_FuturesGrid')
        # Default parameters - will be dynamically adjusted
        self.grid_levels = 15
        self.grid_step_percent = 0.65
        self.vwap_window = 14
        self.atr_period = 14
        self.bb_period = 20
        self.bb_std = 2.0
        self.rsi_period = 14
        self.rsi_overbought = 70
        self.rsi_oversold = 30
        self.stoch_k = 14
        self.stoch_d = 3
        self.ema_short = 5
        self.ema_medium = 21
        self.ema_long = 55
        
        # Parameters for dynamic adjustment
        self.volatility_lookback = 20
        self.regime_lookback = 50
        self.last_adjustment_time = 0
        self.adjustment_interval = 12  # Hours between parameter recalibrations
        self.min_grid_levels = 8
        self.max_grid_levels = 30
        self.min_grid_step = 0.3
        self.max_grid_step = 2.0
        
        # Parameters for auto-optimization
        self.optimization_counter = 0
        self.optimization_interval = 168  # Hours (1 week)
        self.trade_results = {
            'wins': 0,
            'losses': 0,
            'profit': 0,
            'drawdown': 0
        }
        
    def detect_market_condition(self, df):
        """Detect current market condition for SOL"""
        # Safety check to ensure we have enough data
        if len(df) < max(30, self.volatility_lookback):
            # Default market condition for insufficient data
            return {
                'volatile': False,
                'trending': False,
                'ranging': True,  # Default to ranging
                'trend_direction': 0,
                'supertrend_direction': 1,
                'volatility': 3.0,
                'adx': 15,
                'price_change': 0,
                'volume_change': 0
            }
        
        # Calculate volatility metrics safely
        try:
            atr_period = min(self.atr_period, len(df)//2)
            if atr_period < 2: atr_period = 2
            
            df['atr'] = ta.volatility.AverageTrueRange(
                high=df['high'],
                low=df['low'],
                close=df['close'],
                window=atr_period
            ).average_true_range()
            
            df['atr_pct'] = (df['atr'] / df['close']) * 100
        except Exception as e:
            logger.warning(f"Error calculating ATR: {e}")
            # Create default values
            df['atr'] = df['close'] * 0.01  # 1% of price as default
            df['atr_pct'] = 1.0  # Default 1% volatility
        
        # Calculate momentum metrics - safe periods
        try:
            lookback = min(5, len(df)-1)
            df['close_change'] = df['close'].pct_change(periods=lookback) * 100
            df['volume_change'] = df['volume'].pct_change(periods=lookback) * 100
        except Exception as e:
            logger.warning(f"Error calculating momentum metrics: {e}")
            df['close_change'] = 0
            df['volume_change'] = 0
        
        # Initialize direction array with defaults
        df['direction'] = 1
        
        # Calculate trend metrics with Supertrend - only if enough data
        if len(df) > self.atr_period * 2:
            try:
                atr_multiplier = 3.0
                df['basic_upperband'] = (df['high'] + df['low']) / 2 + atr_multiplier * df['atr']
                df['basic_lowerband'] = (df['high'] + df['low']) / 2 - atr_multiplier * df['atr']
                
                # Initialize Supertrend columns
                df['supertrend'] = 0
                df['direction'] = 1
                
                # Calculate Supertrend
                for i in range(1, len(df)):
                    if df['close'].iloc[i] > df['basic_upperband'].iloc[i-1]:
                        df.loc[df.index[i], 'direction'] = 1
                    elif df['close'].iloc[i] < df['basic_lowerband'].iloc[i-1]:
                        df.loc[df.index[i], 'direction'] = -1
                    else:
                        df.loc[df.index[i], 'direction'] = df['direction'].iloc[i-1]
                        
                        if (df['direction'].iloc[i] == 1 and 
                            df['basic_lowerband'].iloc[i] < df['basic_lowerband'].iloc[i-1]):
                            df.loc[df.index[i], 'basic_lowerband'] = df['basic_lowerband'].iloc[i-1]
                            
                        if (df['direction'].iloc[i] == -1 and 
                            df['basic_upperband'].iloc[i] > df['basic_upperband'].iloc[i-1]):
                            df.loc[df.index[i], 'basic_upperband'] = df['basic_upperband'].iloc[i-1]
                            
                    if df['direction'].iloc[i] == 1:
                        df.loc[df.index[i], 'supertrend'] = df['basic_lowerband'].iloc[i]
                    else:
                        df.loc[df.index[i], 'supertrend'] = df['basic_upperband'].iloc[i]
            except Exception as e:
                logger.warning(f"Error calculating Supertrend: {e}")
                # Keep the default direction array
                
        # Calculate safe lookback periods
        lookback = min(self.volatility_lookback, len(df)-1)
        regime_lookback = min(self.regime_lookback, len(df)-1)
        
        # Get recent metrics - safely
        try:
            recent_volatility = df['atr_pct'].tail(lookback).mean()
            recent_volume_change = df['volume_change'].tail(lookback).mean()
        except Exception as e:
            logger.warning(f"Error calculating recent metrics: {e}")
            recent_volatility = 3.0  # Default value
            recent_volume_change = 0
        
        # Safe calculation of price change
        try:
            if regime_lookback > 0 and len(df) > regime_lookback:
                price_change = (df['close'].iloc[-1] / df['close'].iloc[-regime_lookback] - 1) * 100
            else:
                price_change = 0
        except Exception as e:
            logger.warning(f"Error calculating price change: {e}")
            price_change = 0
        
        # Calculate trend strength using ADX safely
        try:
            adx_period = min(14, len(df)//2)
            if adx_period < 2: adx_period = 2
            
            adx_indicator = ta.trend.ADXIndicator(
                high=df['high'],
                low=df['low'],
                close=df['close'],
                window=adx_period
            )
            
            # Handle potential NaN or division by zero issues in ADX calculation
            adx_value = adx_indicator.adx()
            if adx_value.iloc[-1] != adx_value.iloc[-1]:  # Check for NaN (NaN != NaN)
                adx = 15  # Default value if NaN
            else:
                adx = adx_value.iloc[-1]
        except Exception as e:
            logger.warning(f"Error calculating ADX: {e}")
            adx = 15  # Default value if calculation fails
        
        # Calculate average directional change
        try:
            df['direction_change'] = df['direction'].diff().abs()
            avg_direction_change = df['direction_change'].tail(regime_lookback).mean()
        except Exception as e:
            logger.warning(f"Error calculating direction changes: {e}")
            avg_direction_change = 0.05  # Default value
        
        # Determine market condition
        is_volatile = recent_volatility > 5.0 or recent_volume_change > 100
        is_trending = abs(price_change) > 15 and adx > 30
        trend_direction = 1 if price_change > 0 else -1 if price_change < 0 else 0
        is_ranging = avg_direction_change > 0.1 and not is_trending
        
        # Get the current trend direction from Supertrend - safely
        try:
            current_supertrend_direction = df['direction'].iloc[-1]
        except Exception as e:
            logger.warning(f"Error getting supertrend direction: {e}")
            current_supertrend_direction = trend_direction or 1  # Default to trend direction or bullish
        
        return {
            'volatile': is_volatile,
            'trending': is_trending,
            'ranging': is_ranging,
            'trend_direction': trend_direction,
            'supertrend_direction': current_supertrend_direction,
            'volatility': recent_volatility,
            'adx': adx,
            'price_change': price_change,
            'volume_change': recent_volume_change
        }
    
    def adjust_parameters(self, df, condition):
        """Dynamically adjust strategy parameters based on market conditions"""
        current_time = time.time()
        
        # Only adjust every adjustment_interval hours
        if current_time - self.last_adjustment_time < self.adjustment_interval * 3600:
            return
            
        # Adjust grid parameters based on volatility and market condition
        if condition['volatile']:
            # Wider grid spacing but fewer levels in volatile markets
            volatility_factor = min(max(condition['volatility'] / 5, 1), 3)
            self.grid_levels = min(int(10 * volatility_factor), self.max_grid_levels)
            self.grid_step_percent = min(self.max_grid_step, 0.65 * volatility_factor)
            
            # Faster EMA periods for volatile markets
            self.ema_short = 3
            self.ema_medium = 15
            
            # Adjust RSI for volatile markets - wider thresholds
            self.rsi_period = 10  # Faster response
            self.rsi_overbought = 75
            self.rsi_oversold = 25
            
            # Adjust VWAP window for faster response
            self.vwap_window = 10
            
            logger.info(f"SOL Strategy: Adjusted for volatile market. Grid levels={self.grid_levels}, step={self.grid_step_percent:.2f}%")
            
        elif condition['trending']:
            trend_dir = condition['trend_direction']
            
            # Adjust based on trend direction and strength
            if trend_dir > 0:  # Uptrend
                # In uptrend, use fewer grid levels but wider spacing
                self.grid_levels = max(int(self.min_grid_levels * 1.5), 12)
                self.grid_step_percent = min(0.8, 0.6 + condition['adx'] / 100)
                
                # Adjust RSI for uptrend bias
                self.rsi_overbought = 75
                self.rsi_oversold = 35
                
                # Adjust stochastic for trend following
                self.stoch_k = 12
                self.stoch_d = 5
                
            else:  # Downtrend
                # In downtrend, use more grid levels with tighter spacing
                self.grid_levels = max(int(self.min_grid_levels * 1.5), 12)
                self.grid_step_percent = min(0.8, 0.6 + condition['adx'] / 100)
                
                # Adjust RSI for downtrend bias
                self.rsi_overbought = 65
                self.rsi_oversold = 25
                
                # Adjust stochastic for trend following
                self.stoch_k = 12
                self.stoch_d = 5
            
            # Adjust EMAs for trend following
            self.ema_short = 8
            self.ema_medium = 21
            self.ema_long = 55
            
            logger.info(f"SOL Strategy: Adjusted for trending market ({trend_dir}). Grid levels={self.grid_levels}, step={self.grid_step_percent:.2f}%")
            
        elif condition['ranging']:
            # More grid levels with tighter spacing in ranging markets
            range_volatility = condition['volatility'] / 2
            self.grid_levels = max(20, int(25 - range_volatility))
            self.grid_step_percent = max(self.min_grid_step, 0.35 + range_volatility * 0.05)
            
            # Adjust Bollinger Bands for range trading
            self.bb_std = 1.8
            
            # Standard RSI for range trading
            self.rsi_overbought = 70
            self.rsi_oversold = 30
            self.rsi_period = 14
            
            # Adjust EMAs for range trading
            self.ema_short = 5
            self.ema_medium = 15
            self.ema_long = 40
            
            logger.info(f"SOL Strategy: Adjusted for ranging market. Grid levels={self.grid_levels}, step={self.grid_step_percent:.2f}%")
            
        else:
            # Default settings for normal markets
            self.grid_levels = 15
            self.grid_step_percent = 0.65
            self.vwap_window = 14
            self.rsi_period = 14
            self.rsi_overbought = 70
            self.rsi_oversold = 30
            self.stoch_k = 14
            self.stoch_d = 3
            self.ema_short = 5
            self.ema_medium = 21
            self.ema_long = 55
            
            logger.info("SOL Strategy: Using default parameters for normal market conditions")
        
        # Ensure parameters are within bounds
        self.grid_levels = max(min(self.grid_levels, self.max_grid_levels), self.min_grid_levels)
        self.grid_step_percent = max(min(self.grid_step_percent, self.max_grid_step), self.min_grid_step)
        
        # Update last adjustment time
        self.last_adjustment_time = current_time
        
        # Periodically run auto-optimization based on trade results
        self.optimization_counter += 1
        if self.optimization_counter >= 10:  # Every 10 adjustments
            self.optimize_from_results()
            self.optimization_counter = 0
    
    def optimize_from_results(self):
        """Auto-optimize parameters based on trade results"""
        # Skip if not enough trades
        if self.trade_results['wins'] + self.trade_results['losses'] < 10:
            return
            
        win_rate = self.trade_results['wins'] / (self.trade_results['wins'] + self.trade_results['losses'])
        
        # Adjust grid parameters based on win rate
        if win_rate < 0.4:  # Poor performance
            # Reduce risk by increasing grid levels and reducing step size
            self.grid_levels = min(self.grid_levels + 2, self.max_grid_levels)
            self.grid_step_percent = max(self.grid_step_percent * 0.9, self.min_grid_step)
            logger.info(f"SOL Strategy: Auto-optimization adjusted parameters due to low win rate ({win_rate:.2f})")
            
        elif win_rate > 0.6:  # Good performance
            # Can be slightly more aggressive
            self.grid_step_percent = min(self.grid_step_percent * 1.1, self.max_grid_step)
            logger.info(f"SOL Strategy: Auto-optimization adjusted parameters due to high win rate ({win_rate:.2f})")
        
        # Reset trade results for next period
        self.trade_results = {'wins': 0, 'losses': 0, 'profit': 0, 'drawdown': 0}
    
    def update_trade_result(self, result):
        """Update trade results for optimization"""
        if result['profit'] > 0:
            self.trade_results['wins'] += 1
            self.trade_results['profit'] += result['profit']
        else:
            self.trade_results['losses'] += 1
            self.trade_results['drawdown'] = min(self.trade_results['drawdown'], result['profit'])
    
    def get_signal(self, klines):
        """Get trading signal based on current market conditions"""
        # Convert klines to dataframe
        df = self.prepare_data(klines)
        
        # Safety check - need minimum data to operate
        if len(df) < 30:
            logger.warning(f"SOL FuturesGrid: Not enough data to generate signal ({len(df)} candles)")
            return None
        
        # Detect market condition
        condition = self.detect_market_condition(df)
        
        # Dynamically adjust parameters based on market conditions
        self.adjust_parameters(df, condition)
        
        # Use safe window periods based on available data
        ema_short = min(self.ema_short, len(df)//2)
        ema_medium = min(self.ema_medium, len(df)//2)
        ema_long = min(self.ema_long, len(df)//2)
        
        if ema_short < 2: ema_short = 2
        if ema_medium < 3: ema_medium = 3
        if ema_long < 5: ema_long = 5
        
        # Calculate indicators with proper error handling
        try:
            # Calculate EMAs for trend identification
            df['ema_short'] = ta.trend.EMAIndicator(
                close=df['close'], 
                window=ema_short
            ).ema_indicator()
            
            df['ema_medium'] = ta.trend.EMAIndicator(
                close=df['close'], 
                window=ema_medium
            ).ema_indicator()
            
            df['ema_long'] = ta.trend.EMAIndicator(
                close=df['close'], 
                window=ema_long
            ).ema_indicator()
            
            # Calculate ATR for volatility assessment - safe period
            atr_period = min(self.atr_period, len(df)//2)
            if atr_period < 2: atr_period = 2
            
            df['atr'] = ta.volatility.AverageTrueRange(
                high=df['high'],
                low=df['low'],
                close=df['close'],
                window=atr_period
            ).average_true_range()
            
            # Calculate normalized ATR (%)
            df['n_atr'] = (df['atr'] / df['close']) * 100
            
            # Calculate Bollinger Bands for dynamic grid - safe period
            bb_period = min(self.bb_period, len(df)//2)
            if bb_period < 2: bb_period = 2
            
            bb_indicator = ta.volatility.BollingerBands(
                close=df['close'],
                window=bb_period,
                window_dev=self.bb_std
            )
            df['bb_high'] = bb_indicator.bollinger_hband()
            df['bb_low'] = bb_indicator.bollinger_lband()
            df['bb_mid'] = bb_indicator.bollinger_mavg()
            df['bb_width'] = (df['bb_high'] - df['bb_low']) / df['bb_mid']
            
            # Calculate RSI for momentum - safe period
            rsi_period = min(self.rsi_period, len(df)//2)
            if rsi_period < 2: rsi_period = 2
            
            df['rsi'] = ta.momentum.RSIIndicator(
                close=df['close'], 
                window=rsi_period
            ).rsi()
            
            # Calculate Stochastic for momentum - safe periods
            stoch_k = min(self.stoch_k, len(df)//2)
            stoch_d = min(self.stoch_d, len(df)//2)
            
            if stoch_k < 2: stoch_k = 2
            if stoch_d < 2: stoch_d = 2
            
            stoch = ta.momentum.StochasticOscillator(
                high=df['high'],
                low=df['low'],
                close=df['close'],
                window=stoch_k,
                smooth_window=stoch_d
            )
            df['stoch_k'] = stoch.stoch()
            df['stoch_d'] = stoch.stoch_signal()
            
            # Order flow approximation using volume delta
            df['volume_delta'] = df.apply(
                lambda x: x['volume'] if x['close'] > x['open'] else -x['volume'], 
                axis=1
            )
            
            # Safe window for rolling operations
            vwap_window = min(self.vwap_window, len(df)//2)
            if vwap_window < 2: vwap_window = 2
            
            df['cum_delta'] = df['volume_delta'].rolling(window=vwap_window).sum()
            df['obv'] = ta.volume.OnBalanceVolumeIndicator(
                close=df['close'],
                volume=df['volume']
            ).on_balance_volume()
            
            # Calculate VWAP (approximation)
            df['typical_price'] = (df['high'] + df['low'] + df['close']) / 3
            df['tp_volume'] = df['typical_price'] * df['volume']
            df['cum_tp_volume'] = df['tp_volume'].rolling(window=vwap_window).sum()
            df['cum_volume'] = df['volume'].rolling(window=vwap_window).sum()
            
            # Handle potential division by zero
            df['vwap'] = df.apply(
                lambda x: x['cum_tp_volume'] / x['cum_volume'] if x['cum_volume'] > 0 else x['close'],
                axis=1
            )
            
        except Exception as e:
            logger.warning(f"Error calculating indicators: {e}")
            return None
        
        # Check for NaN values in key indicators
        key_indicators = ['ema_short', 'ema_medium', 'bb_high', 'bb_low', 'rsi', 'stoch_k', 'vwap']
        for indicator in key_indicators:
            if indicator in df.columns and (df[indicator].isna().iloc[-1] or df[indicator].isna().iloc[-2]):
                logger.warning(f"SOL FuturesGrid: NaN value in {indicator}, skipping signal generation")
                return None
                
        # Ensure we have at least 2 rows of valid data
        if len(df) < 2:
            logger.warning("SOL FuturesGrid: Not enough data points for signal generation")
            return None
            
        # Safe extraction of current and previous values
        try:
            # Current values
            current_price = df['close'].iloc[-1]
            current_ema_short = df['ema_short'].iloc[-1]
            current_ema_medium = df['ema_medium'].iloc[-1]
            current_ema_long = df['ema_long'].iloc[-1]
            current_atr = df['atr'].iloc[-1]
            current_n_atr = df['n_atr'].iloc[-1]
            current_bb_high = df['bb_high'].iloc[-1]
            current_bb_low = df['bb_low'].iloc[-1]
            current_bb_mid = df['bb_mid'].iloc[-1]
            current_bb_width = df['bb_width'].iloc[-1]
            current_rsi = df['rsi'].iloc[-1]
            current_stoch_k = df['stoch_k'].iloc[-1]
            current_stoch_d = df['stoch_d'].iloc[-1]
            current_cum_delta = df['cum_delta'].iloc[-1]
            current_obv = df['obv'].iloc[-1]
            current_vwap = df['vwap'].iloc[-1]
            
            # Previous values
            prev_price = df['close'].iloc[-2]
            prev_ema_short = df['ema_short'].iloc[-2]
            prev_ema_medium = df['ema_medium'].iloc[-2]
            prev_rsi = df['rsi'].iloc[-2]
            prev_stoch_k = df['stoch_k'].iloc[-2]
            prev_stoch_d = df['stoch_d'].iloc[-2]
            prev_cum_delta = df['cum_delta'].iloc[-2]
            prev_obv = df['obv'].iloc[-2]
        except Exception as e:
            logger.warning(f"Error extracting indicator values: {e}")
            return None
        
        # Calculate volatility-adjusted grid levels
        # Higher volatility = wider grid steps
        volatility_factor = min(max(current_n_atr / 2, 0.4), 1.5)  # Constrain volatility factor
        grid_range = current_bb_high - current_bb_low
        
        # Market condition assessment
        trend_strength = abs(current_ema_medium - current_ema_long) / max(current_atr, 0.0001)  # Avoid division by zero
        is_strong_trend = trend_strength > 1.5
        is_uptrend = current_ema_short > current_ema_medium > current_ema_long
        is_downtrend = current_ema_short < current_ema_medium < current_ema_long
        
        # Signal logic with dynamic adjustment based on market conditions
        buy_signal = False
        sell_signal = False
        reason = ""
        
        # Adjust signal logic based on detected market condition
        if condition['trending']:
            if condition['trend_direction'] > 0:  # Uptrend
                # BUY conditions for uptrend - buy pullbacks
                if (current_price < current_ema_medium and 
                    current_price > current_ema_long and
                    current_rsi < 50 and current_rsi > prev_rsi):
                    if current_stoch_k < 40 and current_stoch_k > current_stoch_d:
                        buy_signal = True
                        reason = "Buying pullback in uptrend with stochastic confirmation"
                
                # SELL conditions for uptrend - take profits at resistance
                if (current_price > current_bb_high * 0.98 and
                    current_stoch_k > 80 and current_stoch_k < current_stoch_d):
                    sell_signal = True
                    reason = "Taking profit at resistance in uptrend"
                    
            else:  # Downtrend
                # BUY conditions for downtrend - only strong reversal signals
                if (current_price < current_bb_low * 1.02 and
                    current_price > prev_price and
                    current_rsi < 30 and current_rsi > prev_rsi and
                    current_obv > prev_obv):
                    buy_signal = True
                    reason = "Potential reversal signal in downtrend"
                
                # SELL conditions for downtrend - sell rallies
                if (current_price > current_vwap and
                    current_price < current_bb_mid and
                    current_ema_short < current_ema_medium and
                    current_stoch_k > 60 and current_stoch_k < current_stoch_d):
                    sell_signal = True
                    reason = "Selling rally in downtrend"
                    
        elif condition['ranging']:
            # BUY conditions for ranging market - buy near support with positive order flow
            grid_buy_level = current_bb_low + (grid_range * 0.15)  # Lower 15% of range
            if current_price <= grid_buy_level:
                if current_cum_delta > prev_cum_delta:
                    if current_rsi < self.rsi_oversold + 10 and current_rsi > prev_rsi:
                        buy_signal = True
                        reason = "Range trading buy at support with positive flow"
            
            # SELL conditions for ranging market - sell near resistance with negative order flow
            grid_sell_level = current_bb_high - (grid_range * 0.15)  # Upper 15% of range
            if current_price >= grid_sell_level:
                if current_cum_delta < prev_cum_delta:
                    if current_rsi > self.rsi_overbought - 10 and current_rsi < prev_rsi:
                        sell_signal = True
                        reason = "Range trading sell at resistance with negative flow"
                        
        elif condition['volatile']:
            # BUY conditions for volatile market - more confirmations required
            if (current_ema_short > current_ema_medium and prev_ema_short <= prev_ema_medium):
                if (current_price > current_vwap and 
                    current_obv > prev_obv and 
                    current_cum_delta > prev_cum_delta):
                    buy_signal = True
                    reason = "EMA cross with multiple confirmations in volatile market"
            
            # SELL conditions for volatile market - quicker exit
            if (current_ema_short < current_ema_medium and prev_ema_short >= prev_ema_medium):
                if (current_price < current_vwap or 
                    current_obv < prev_obv):
                    sell_signal = True
                    reason = "Quick exit on EMA cross in volatile market"
                    
        else:
            # Default BUY conditions for normal market
            grid_buy_level = current_bb_low + (grid_range * 0.2)
            if current_price <= grid_buy_level:
                if current_cum_delta > prev_cum_delta and current_obv > prev_obv:
                    if current_rsi < 40 and current_rsi > prev_rsi:
                        buy_signal = True
                        reason = "Grid buy at support with positive order flow"
            
            # Default SELL conditions for normal market
            grid_sell_level = current_bb_high - (grid_range * 0.2)
            if current_price >= grid_sell_level:
                if current_cum_delta < prev_cum_delta and current_obv < prev_obv:
                    if current_rsi > 60 and current_rsi < prev_rsi:
                        sell_signal = True
                        reason = "Grid sell at resistance with negative order flow"
        
        # Generate signals
        if buy_signal:
            logger.info(f"SOL FuturesGrid: BUY signal - {reason} [Condition: {'Trending' if condition['trending'] else 'Ranging' if condition['ranging'] else 'Volatile' if condition['volatile'] else 'Normal'}]")
            return "BUY"
        elif sell_signal:
            logger.info(f"SOL FuturesGrid: SELL signal - {reason} [Condition: {'Trending' if condition['trending'] else 'Ranging' if condition['ranging'] else 'Volatile' if condition['volatile'] else 'Normal'}]")
            return "SELL"
            
        return None


# Update the strategy factory to include the new strategies
def get_strategy(strategy_name):
    """Factory function to get a strategy by name"""
    strategies = {
        'BTC_Scalping': BTCScalpingStrategy(),
        'ETH_StochMACD': ETHStochMACD(),
        'BNB_Grid': BNBGridStrategy(),
        'SOL_Squeeze': SOLSqueezeStrategy(),
        'ADA_EMATrend': ADAEMATrendStrategy(),
        'XRP_Scalping': XRPScalpingStrategy(),
        'DOGE_Scalping': DOGEScalpingStrategy(),
        'SHIB_Breakout': SHIBBreakoutStrategy(),
        'XRP_FuturesGrid': XRPFuturesGridStrategy(),
        'SOL_FuturesGrid': SOLFuturesGridStrategy(),
    }
    
    if strategy_name in strategies:
        return strategies[strategy_name]
    else:
        logger.warning(f"Strategy {strategy_name} not found. Using default ETH_StochMACD strategy.")
        return strategies['ETH_StochMACD']


def get_strategy_for_symbol(symbol, strategy_name=None):
    """Get the appropriate strategy based on the trading symbol"""
    # If a specific strategy is requested, use it
    if strategy_name:
        return get_strategy(strategy_name)
    
    # Otherwise, map symbols to optimized strategies
    symbol = symbol.upper()
    if 'BTCUSDT' in symbol:
        return BTCScalpingStrategy()
    elif 'ETHUSDT' in symbol:
        return ETHStochMACD()
    elif 'BNBUSDT' in symbol:
        return BNBGridStrategy()
    elif 'SOLUSDT' in symbol:
        return SOLFuturesGridStrategy()  # Updated to use the new SOL strategy
    elif 'ADAUSDT' in symbol:
        return ADAEMATrendStrategy()
    elif 'XRPUSDT' in symbol:
        return XRPFuturesGridStrategy()  # Updated to use the new XRP strategy
    elif 'DOGEUSDT' in symbol:
        return DOGEScalpingStrategy()
    elif 'SHIBUSDT' in symbol:
        return SHIBBreakoutStrategy()
    else:
        # Default to ETH_StochMACD for other tokens as a reasonable choice
        return ETHStochMACD()