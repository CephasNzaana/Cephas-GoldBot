//+------------------------------------------------------------------+
//|                                 Cephas_GoldBot.mq5              |
//|                                 MEAN REVERSION GOLD BOT         |
//|                                 v6.0 - M1 Pickaxe              |
//+------------------------------------------------------------------+
#property copyright "Cephas GoldBot"
#property link      ""
#property version   "6.0"
#property strict

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                |
//+------------------------------------------------------------------+
input double   Lot_Size = 0.01;           // Fixed lot size
input bool     Use_Risk_Sizing = false;   // OFF until R:R ratio improves
input double   Risk_Percent = 1.0;        // Risk per trade (% of equity) - for future use
input double   Base_Max_Risk = 40.0;      // Base max dollar risk per trade
input double   Volatility_Risk_Multiplier = 1.5; // Allow 1.5x risk in high volatility
input int      Magic_Number = 888000;     // Base magic number
input int      Slippage = 3;              // Slippage in points

input bool     Use_Validation = true;     // Validate stop levels
input int      Min_Stop_Distance = 50;    // Min stop distance in points
input bool     Use_Dynamic_SL = true;     // Use dynamic stop based on price
input double   Risk_to_Entry_Ratio = 0.8; // SL:Entry ratio for validation
input double   ATR_Multiplier = 3.0;      // ATR multiplier for SL (M1: smaller ATR, 3x ≈ same $ distance)
input double   Max_SL_Dollars = 20.0;     // v6.0: Max SL in dollars (tighter per-trade, more trades)

input bool     Use_Smart_Breakeven = false;// OFF - conflicts with mean reversion!
input double   Breakeven_Trigger = 40;    // pips profit (unused when OFF)
input bool     Use_Profit_Trailing = false;// OFF - mean reversion IS the exit!
input double   Trail_Trigger = 50;        // pips profit (unused when OFF)
input double   Trail_Step = 15;           // pips trail step (unused when OFF)

input bool     System_1_Enable = true;    // System 1 (Donchian+EMA mean reversion)
input bool     System_2_Enable = false;   // System 2 OFF until System 1 proven
input string   System1_Comment = "Sys1";  // System 1 comment
input string   System2_Comment = "Sys2";  // System 2 comment

input int      Max_Daily_Trades = 200;    // Max trades per day (more on M1)
input double   Max_Daily_Loss = 100;      // Max daily loss in $
input double   Max_Position_Size = 0.05;  // Max lot size per position
input int      Min_Bars_Between = 10;     // Min bars between trades (10 min on M1)

//--- EXIT STRATEGY
input bool     Use_Mean_Reversion_Exit = true; // Auto exit at mean (Stage 1)
input bool     Use_Extended_Target = true;// Two-stage: BE at mean, run to key level
input double   Fib_Level = 1.618;         // Fibonacci extension level past mean
input double   Fib_Target_Multiplier = 1.5;// Max target = 1.5x Fib distance (tighter on M1)
input double   Psych_Level_Size = 50.0;   // Psychological level interval (gold = $50)
input int      Max_Hold_Bars = 200;       // Max bars to hold position (200 min on M1)
input bool     Use_Emergency_Close = true;// Emergency close if price moves against
input double   Emergency_Close_Pct = 1.0; // Close if moves 1.0% against (tighter on M1)
input double   Min_Swing_For_ET = 3.0;    // v6.0: Min entry-to-mean swing ($) for ET in RANGING

//--- EAGLE'S VIEW: Market Regime Detection (stays on H1)
input bool     Use_Regime_Detection = true;// Adapt strategy to market conditions
input double   ADX_Trending_Threshold = 25.0; // ADX above this = trending market

//--- EQUITY DRAWDOWN MONITORING
input bool     Monitor_Equity_Drawdown = true; // Log unrealized equity drawdowns
input double   Drawdown_Alert_Level_1 = 50.0;  // Alert at $50 drawdown
input double   Drawdown_Alert_Level_2 = 100.0; // Alert at $100 drawdown
input double   Drawdown_Alert_Level_3 = 200.0; // Alert at $200 drawdown
input bool     Log_Equity_Peaks = true;        // Track equity high water marks

//--- TREND FILTER (H1 200 SMA) - DISABLED for mean reversion
input bool     Use_Trend_Filter = false;  // OFF - Mean reversion is counter-trend!
input int      Trend_MA_Period = 200;     // H1 MA period for trend

//--- SESSION FILTER - Trade during active sessions
input bool     Use_Session_Filter = true; // Only trade London/NY
input int      London_Start_Hour = 7;     // London session start (broker time)
input int      London_End_Hour = 17;      // London session end
input int      NY_Start_Hour = 12;        // NY session start (broker time)
input int      NY_End_Hour = 22;          // NY session end

//--- VOLUME CONFIRMATION - Relaxed for more signals
input bool     Use_Volume_Filter = false; // OFF - Don't filter by volume
input double   Volume_Multiplier = 1.0;   // Min volume vs 20-bar average

//--- ENTRY QUALITY FILTERS (kept from v5.1)
input bool     Use_EntryMean_Validation = true;// Mean must be in profitable direction
input double   Min_Entry_Mean_Distance = 50.0; // Min distance entry-to-mean (pips, smaller on M1)
input bool     Use_KeyLevel_Filter = true;     // Block if key level blocks path to mean
input double   KeyLevel_Interval = 100.0;      // Major round number interval ($100)
input double   KeyLevel_Block_Zone = 0.6;      // Block if level in first 60% of path

//--- v6.0: DONCHIAN + EMA ENTRY SYSTEM
input int      Donchian_Period = 20;          // Donchian Channel period (M1 bars = 20 min)
input int      EMA_Period = 50;               // EMA period for mean (M1 bars = 50 min)
input double   Smart_Min_Distance = 1.5;      // Min Donchian width as multiple of M1 ATR(14)

//--- v6.0: H1 HISTORICAL VOLATILITY FILTER
input bool     Use_H1_Vol_Filter = true;      // Block entries when H1 vol too high
input double   H1_Vol_Threshold = 40.0;       // Annualized HV threshold (%)
input int      H1_Vol_Lookback = 24;          // H1 bars for HV calculation (24 = 1 day)

//--- v6.0: PYRAMIDING
input bool     Use_Pyramiding = true;         // Allow adding to winning positions
input int      Max_Pyramid_Levels = 3;        // Max positions in same direction
input double   Pyramid_Min_Profit = 2.0;      // Min $ profit on existing before adding
input double   Pyramid_ATR_Distance = 1.0;    // Min distance between entries (x ATR)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                |
//+------------------------------------------------------------------+
double goldPip = 0.01;
int totalTradesToday = 0;
double dailyPnL = 0;
datetime lastBarTime = 0;
MqlDateTime currentTimeStruct;
datetime currentTime;
double lastPrice = 0;

// Rolling ATR average for dynamic risk
double rollingATRAverage = 0;
int atrSampleCount = 0;

// Market regime: 0=RANGING, 1=TRENDING
int currentRegime = 0;

// Equity monitoring
double equityHighWaterMark = 0;
double maxDrawdownFromPeak = 0;
double currentDrawdown = 0;
bool drawdownLevel1Hit = false;
bool drawdownLevel2Hit = false;
bool drawdownLevel3Hit = false;

// v6.0: H1 Historical Volatility filter
bool h1VolBlockedToday = false;
double h1VolValue = 0;
datetime lastH1VolCheck = 0;

// v6.0: Pyramid tracking
struct PyramidInfo
{
   ulong    tickets[3];       // Up to 3 position tickets per direction
   int      count;            // Current pyramid level (0-3)
   double   lastEntryPrice;   // Price of most recent pyramid entry
   int      direction;        // 1=BUY, -1=SELL
};

PyramidInfo pyramidBuy;
PyramidInfo pyramidSell;

// Systems data
struct SystemInfo
{
   int      magic;
   string   name;
   bool     enabled;
   datetime lastTradeTime;
   int      tradesToday;
   double   profitToday;
};

SystemInfo systems[2];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   goldPip = 0.01;
   currentTime = TimeCurrent();
   TimeToStruct(currentTime, currentTimeStruct);

   // Initialize equity monitoring
   equityHighWaterMark = AccountInfoDouble(ACCOUNT_EQUITY);
   maxDrawdownFromPeak = 0;
   currentDrawdown = 0;

   // Initialize H1 vol filter
   h1VolBlockedToday = false;
   h1VolValue = 0;
   lastH1VolCheck = 0;

   // Initialize pyramid tracking
   pyramidBuy.count = 0;
   pyramidBuy.direction = 1;
   pyramidBuy.lastEntryPrice = 0;
   for (int p = 0; p < 3; p++) pyramidBuy.tickets[p] = 0;

   pyramidSell.count = 0;
   pyramidSell.direction = -1;
   pyramidSell.lastEntryPrice = 0;
   for (int p = 0; p < 3; p++) pyramidSell.tickets[p] = 0;

   // Initialize systems
   systems[0].magic = Magic_Number;
   systems[0].name = "System1";
   systems[0].enabled = System_1_Enable;
   systems[0].lastTradeTime = 0;
   systems[0].tradesToday = 0;
   systems[0].profitToday = 0;

   systems[1].magic = Magic_Number + 1000;
   systems[1].name = "System2";
   systems[1].enabled = System_2_Enable;
   systems[1].lastTradeTime = 0;
   systems[1].tradesToday = 0;
   systems[1].profitToday = 0;

   Print("==================================================");
   Print("CEPHAS GOLD BOT v6.0 - M1 Pickaxe");
   Print("==================================================");
   Print("ENTRY SYSTEM (v6.0):");
   Print("  Donchian Channel = ", Donchian_Period, " bars (M1)");
   Print("  EMA Mean = ", EMA_Period, " bars (M1)");
   Print("  Smart Min Distance = ", Smart_Min_Distance, "x ATR(14)");
   Print("EXIT STRATEGY:");
   if (Use_Extended_Target)
   {
      Print("  Two-Stage Exit = ON (regime-adaptive)");
      Print("  RANGING: Stage 1 -> BE at mean -> run to extended target");
      Print("  TRENDING: Close at mean (proven approach)");
      Print("  Fib Extension = ", Fib_Level, " (cap ", Fib_Target_Multiplier, "x)");
      Print("  Psych Levels = $", Psych_Level_Size, " intervals");
      Print("  Min Swing for ET (RANGING) = $", Min_Swing_For_ET);
   }
   else
   {
      Print("  Standard MR Exit = ", Use_Mean_Reversion_Exit ? "ON" : "OFF");
   }
   Print("  Max Hold Bars = ", Max_Hold_Bars, " (", Max_Hold_Bars, " min)");
   Print("  Emergency Close = ", Emergency_Close_Pct, "%");
   Print("EAGLE'S VIEW:");
   Print("  Regime Detection = ", Use_Regime_Detection ? "ON" : "OFF");
   Print("  ADX Trending Threshold = ", ADX_Trending_Threshold);
   Print("RISK MANAGEMENT:");
   if (Use_Risk_Sizing)
      Print("  Dynamic Sizing = ON (", Risk_Percent, "% equity, max $", Base_Max_Risk, ")");
   else
      Print("  Fixed Lot = ", Lot_Size, " | Risk Gate = $", Base_Max_Risk);
   Print("  ATR SL Multiplier = ", ATR_Multiplier, "x");
   Print("  Max SL Dollars = $", Max_SL_Dollars);
   Print("H1 VOLATILITY FILTER:");
   Print("  Active = ", Use_H1_Vol_Filter ? "ON" : "OFF",
         " (threshold ", H1_Vol_Threshold, "%, lookback ", H1_Vol_Lookback, " H1 bars)");
   Print("PYRAMIDING:");
   Print("  Active = ", Use_Pyramiding ? "ON" : "OFF",
         " (max ", Max_Pyramid_Levels, " levels, min $", Pyramid_Min_Profit,
         " profit, ", Pyramid_ATR_Distance, "x ATR spacing)");
   Print("ENTRY FILTERS:");
   Print("  Entry-Mean Validation = ", Use_EntryMean_Validation ? "ON" : "OFF",
         " (min ", Min_Entry_Mean_Distance, " pips)");
   Print("  Key Level Filter = ", Use_KeyLevel_Filter ? "ON" : "OFF",
         " ($", KeyLevel_Interval, " intervals)");
   Print("EQUITY MONITORING:");
   Print("  Active = ", Monitor_Equity_Drawdown ? "ON" : "OFF");
   Print("  Alert Levels: $", Drawdown_Alert_Level_1, " / $", Drawdown_Alert_Level_2, " / $", Drawdown_Alert_Level_3);
   Print("FILTERS:");
   Print("  Session = ", Use_Session_Filter ? "ON (London/NY)" : "OFF");
   Print("  System 1 = ", System_1_Enable ? "ON" : "OFF");
   Print("  System 2 = ", System_2_Enable ? "ON" : "OFF");
   Print("==================================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== EA STOPPED ===");
   Print("Trades today: ", totalTradesToday);
   Print("Daily P/L: $", DoubleToString(dailyPnL, 2));
   Print("Max Equity Peak: $", DoubleToString(equityHighWaterMark, 2));
   Print("Max Drawdown: $", DoubleToString(maxDrawdownFromPeak, 2));
   Print("H1 Vol Today: ", DoubleToString(h1VolValue, 1), "%",
         h1VolBlockedToday ? " (BLOCKED)" : "");
   Print("==================================================");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar (M1)
   datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
   if (currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;

   // Update time
   currentTime = TimeCurrent();
   TimeToStruct(currentTime, currentTimeStruct);

   // Check daily reset
   CheckDailyReset();

   // Update rolling ATR average for dynamic risk calculation
   UpdateRollingATRAverage();

   // Update market regime (Eagle's View - stays on H1)
   if (Use_Regime_Detection)
      currentRegime = DetectMarketRegime();

   // Monitor equity drawdowns
   if (Monitor_Equity_Drawdown)
      MonitorEquityDrawdown();

   // Check H1 Historical Volatility filter (v6.0)
   if (Use_H1_Vol_Filter && !h1VolBlockedToday)
      CheckH1Volatility();

   // Update pyramid tracking
   UpdatePyramidTracking();

   // Manage existing positions
   ManagePositions();

   // Check for entry signals
   CheckEntrySignals();

   // Update P&L tracking
   UpdateDailyStats();
}

//+------------------------------------------------------------------+
//| EAGLE'S VIEW: DETECT MARKET REGIME                               |
//| Uses H1 ADX to classify: RANGING (0) vs TRENDING (1)            |
//| Mean reversion thrives in ranging, needs quick exits in trending |
//+------------------------------------------------------------------+
int DetectMarketRegime()
{
   double adxArray[];
   ArraySetAsSeries(adxArray, true);
   int adxHandle = iADX(_Symbol, PERIOD_H1, 14);
   if (adxHandle == INVALID_HANDLE) return 0; // Default to ranging

   if (CopyBuffer(adxHandle, 0, 0, 1, adxArray) > 0)
   {
      double adxValue = adxArray[0];
      IndicatorRelease(adxHandle);

      if (adxValue >= ADX_Trending_Threshold)
         return 1; // TRENDING
      else
         return 0; // RANGING
   }

   IndicatorRelease(adxHandle);
   return 0; // Default to ranging
}

//+------------------------------------------------------------------+
//| MONITOR EQUITY DRAWDOWN                                          |
//| Tracks unrealized losses from equity peak - logging only         |
//+------------------------------------------------------------------+
void MonitorEquityDrawdown()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   if (currentEquity > equityHighWaterMark)
   {
      equityHighWaterMark = currentEquity;
      currentDrawdown = 0;
      drawdownLevel1Hit = false;
      drawdownLevel2Hit = false;
      drawdownLevel3Hit = false;

      if (Log_Equity_Peaks)
         Print("NEW EQUITY PEAK: $", DoubleToString(equityHighWaterMark, 2));
   }
   else
   {
      currentDrawdown = equityHighWaterMark - currentEquity;

      if (currentDrawdown > maxDrawdownFromPeak)
         maxDrawdownFromPeak = currentDrawdown;

      if (currentDrawdown >= Drawdown_Alert_Level_3 && !drawdownLevel3Hit)
      {
         drawdownLevel3Hit = true;
         Print("DRAWDOWN LEVEL 3: $", DoubleToString(currentDrawdown, 2),
               " (Peak: $", DoubleToString(equityHighWaterMark, 2),
               " | Current: $", DoubleToString(currentEquity, 2), ")");
      }
      else if (currentDrawdown >= Drawdown_Alert_Level_2 && !drawdownLevel2Hit)
      {
         drawdownLevel2Hit = true;
         Print("DRAWDOWN LEVEL 2: $", DoubleToString(currentDrawdown, 2),
               " (Peak: $", DoubleToString(equityHighWaterMark, 2),
               " | Current: $", DoubleToString(currentEquity, 2), ")");
      }
      else if (currentDrawdown >= Drawdown_Alert_Level_1 && !drawdownLevel1Hit)
      {
         drawdownLevel1Hit = true;
         Print("DRAWDOWN LEVEL 1: $", DoubleToString(currentDrawdown, 2),
               " (Peak: $", DoubleToString(equityHighWaterMark, 2),
               " | Current: $", DoubleToString(currentEquity, 2), ")");
      }
   }
}

//+------------------------------------------------------------------+
//| v6.0: CHECK H1 HISTORICAL VOLATILITY                             |
//| Calculates annualized std dev of H1 returns over lookback period  |
//| If above threshold, blocks ALL new entries for rest of day        |
//+------------------------------------------------------------------+
void CheckH1Volatility()
{
   // Only check once per H1 bar (avoid redundant calculation)
   datetime currentH1Bar = iTime(_Symbol, PERIOD_H1, 0);
   if (currentH1Bar == lastH1VolCheck)
      return;
   lastH1VolCheck = currentH1Bar;

   double closeArray[];
   ArraySetAsSeries(closeArray, true);

   // Need H1_Vol_Lookback + 1 bars to calculate H1_Vol_Lookback returns
   int barsNeeded = H1_Vol_Lookback + 1;
   if (CopyClose(_Symbol, PERIOD_H1, 0, barsNeeded, closeArray) < barsNeeded)
      return;

   // Calculate log returns
   double returns[];
   ArrayResize(returns, H1_Vol_Lookback);
   for (int i = 0; i < H1_Vol_Lookback; i++)
   {
      if (closeArray[i + 1] > 0)
         returns[i] = MathLog(closeArray[i] / closeArray[i + 1]);
      else
         returns[i] = 0;
   }

   // Calculate standard deviation of returns
   double sumReturns = 0;
   for (int i = 0; i < H1_Vol_Lookback; i++)
      sumReturns += returns[i];
   double meanReturn = sumReturns / H1_Vol_Lookback;

   double sumSqDiff = 0;
   for (int i = 0; i < H1_Vol_Lookback; i++)
      sumSqDiff += MathPow(returns[i] - meanReturn, 2);
   double stdDev = MathSqrt(sumSqDiff / (H1_Vol_Lookback - 1));

   // Annualize: multiply by sqrt(trading hours per year)
   // ~252 trading days * 24 H1 bars = 6048 H1 bars/year
   double annualizedVol = stdDev * MathSqrt(6048.0) * 100.0; // as percentage

   h1VolValue = annualizedVol;

   if (annualizedVol >= H1_Vol_Threshold)
   {
      h1VolBlockedToday = true;
      Print("v6.0 H1 VOL FILTER: Annualized HV = ", DoubleToString(annualizedVol, 1),
            "% >= ", DoubleToString(H1_Vol_Threshold, 1),
            "% | ENTRIES BLOCKED for rest of day");
   }
}

//+------------------------------------------------------------------+
//| v6.0: GET SMART MINIMUM DISTANCE                                  |
//| Returns minimum Donchian channel width for valid entry            |
//| = Smart_Min_Distance * current M1 ATR(14)                        |
//+------------------------------------------------------------------+
double GetSmartMinDistance()
{
   double atrArray[];
   ArraySetAsSeries(atrArray, true);
   int atrHandle = iATR(_Symbol, PERIOD_M1, 14);
   if (atrHandle == INVALID_HANDLE) return 0;

   double result = 0;
   if (CopyBuffer(atrHandle, 0, 0, 1, atrArray) > 0)
      result = atrArray[0] * Smart_Min_Distance;
   IndicatorRelease(atrHandle);
   return result;
}

//+------------------------------------------------------------------+
//| v6.0: UPDATE PYRAMID TRACKING                                     |
//| Scans open positions and refreshes pyramid state                  |
//+------------------------------------------------------------------+
void UpdatePyramidTracking()
{
   // Reset counts
   pyramidBuy.count = 0;
   pyramidBuy.lastEntryPrice = 0;
   for (int p = 0; p < 3; p++) pyramidBuy.tickets[p] = 0;

   pyramidSell.count = 0;
   pyramidSell.lastEntryPrice = 0;
   for (int p = 0; p < 3; p++) pyramidSell.tickets[p] = 0;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket > 0 && PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         int sysIdx = GetSystemIndex((int)PositionGetInteger(POSITION_MAGIC));
         if (sysIdx < 0) continue;

         ENUM_POSITION_TYPE pType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double entryP = PositionGetDouble(POSITION_PRICE_OPEN);

         if (pType == POSITION_TYPE_BUY && pyramidBuy.count < 3)
         {
            pyramidBuy.tickets[pyramidBuy.count] = ticket;
            pyramidBuy.count++;
            if (entryP > 0)
               pyramidBuy.lastEntryPrice = entryP;
         }
         else if (pType == POSITION_TYPE_SELL && pyramidSell.count < 3)
         {
            pyramidSell.tickets[pyramidSell.count] = ticket;
            pyramidSell.count++;
            if (entryP > 0)
               pyramidSell.lastEntryPrice = entryP;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| v6.0: CHECK IF PYRAMID ENTRY IS ALLOWED                           |
//| Returns true if conditions met to add to existing position        |
//+------------------------------------------------------------------+
bool CanPyramid(int signal)
{
   if (!Use_Pyramiding) return false;

   int count = (signal == 1) ? pyramidBuy.count : pyramidSell.count;
   double lastEntry = (signal == 1) ? pyramidBuy.lastEntryPrice : pyramidSell.lastEntryPrice;

   // Check max levels
   if (count >= Max_Pyramid_Levels) return false;
   if (count == 0) return true; // First entry always OK (not a pyramid)

   // Check minimum profit on existing positions
   double totalProfit = 0;
   if (signal == 1)
   {
      for (int i = 0; i < pyramidBuy.count; i++)
      {
         if (pyramidBuy.tickets[i] > 0 && PositionSelectByTicket(pyramidBuy.tickets[i]))
            totalProfit += PositionGetDouble(POSITION_PROFIT);
      }
   }
   else
   {
      for (int i = 0; i < pyramidSell.count; i++)
      {
         if (pyramidSell.tickets[i] > 0 && PositionSelectByTicket(pyramidSell.tickets[i]))
            totalProfit += PositionGetDouble(POSITION_PROFIT);
      }
   }
   if (totalProfit < Pyramid_Min_Profit) return false;

   // Check minimum distance from last entry
   double currentPrice = (signal == 1) ?
      SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
      SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double atrArray[];
   ArraySetAsSeries(atrArray, true);
   int atrHandle = iATR(_Symbol, PERIOD_M1, 14);
   if (atrHandle == INVALID_HANDLE) return false;

   double minDist = 0;
   if (CopyBuffer(atrHandle, 0, 0, 1, atrArray) > 0)
      minDist = atrArray[0] * Pyramid_ATR_Distance;
   IndicatorRelease(atrHandle);

   double distFromLast = MathAbs(currentPrice - lastEntry);
   if (distFromLast < minDist) return false;

   return true;
}

//+------------------------------------------------------------------+
//| v6.0: CLOSE ALL PYRAMID POSITIONS (basket close)                  |
//+------------------------------------------------------------------+
void CloseAllPyramidPositions(int direction, string comment)
{
   if (direction == 1)
   {
      for (int i = 0; i < pyramidBuy.count; i++)
      {
         if (pyramidBuy.tickets[i] > 0)
            ClosePositionWithComment(pyramidBuy.tickets[i], comment);
      }
      pyramidBuy.count = 0;
      pyramidBuy.lastEntryPrice = 0;
      for (int p = 0; p < 3; p++) pyramidBuy.tickets[p] = 0;
   }
   else
   {
      for (int i = 0; i < pyramidSell.count; i++)
      {
         if (pyramidSell.tickets[i] > 0)
            ClosePositionWithComment(pyramidSell.tickets[i], comment);
      }
      pyramidSell.count = 0;
      pyramidSell.lastEntryPrice = 0;
      for (int p = 0; p < 3; p++) pyramidSell.tickets[p] = 0;
   }
}

//+------------------------------------------------------------------+
//| UPDATE ROLLING ATR AVERAGE                                       |
//+------------------------------------------------------------------+
void UpdateRollingATRAverage()
{
   double atrArray[];
   ArraySetAsSeries(atrArray, true);
   int atrHandle = iATR(_Symbol, PERIOD_M1, 14);
   if (atrHandle != INVALID_HANDLE)
   {
      if (CopyBuffer(atrHandle, 0, 0, 20, atrArray) > 0)
      {
         double sum = 0;
         for (int i = 0; i < 20; i++)
            sum += atrArray[i];
         rollingATRAverage = sum / 20.0;
         atrSampleCount++;
      }
      IndicatorRelease(atrHandle);
   }
}

//+------------------------------------------------------------------+
//| GET DYNAMIC MAX RISK                                             |
//+------------------------------------------------------------------+
double GetDynamicMaxRisk()
{
   if (rollingATRAverage <= 0 || atrSampleCount < 20)
      return Base_Max_Risk;

   double atrArray[];
   ArraySetAsSeries(atrArray, true);
   int atrHandle = iATR(_Symbol, PERIOD_M1, 14);
   if (atrHandle == INVALID_HANDLE)
      return Base_Max_Risk;

   if (CopyBuffer(atrHandle, 0, 0, 1, atrArray) > 0)
   {
      double currentATR = atrArray[0];
      IndicatorRelease(atrHandle);

      double volatilityRatio = currentATR / rollingATRAverage;

      if (volatilityRatio > 1.3)
      {
         double dynamicRisk = Base_Max_Risk * Volatility_Risk_Multiplier;
         return dynamicRisk;
      }
   }
   else
   {
      IndicatorRelease(atrHandle);
   }

   return Base_Max_Risk;
}

//+------------------------------------------------------------------+
//| v5.1 ENTRY FILTER: VALIDATE ENTRY-MEAN DIRECTION (kept)         |
//| 1. Mean must be in profitable direction from entry                |
//| 2. Distance from entry to mean must exceed minimum                |
//+------------------------------------------------------------------+
bool ValidateEntryMeanDirection(int signal)
{
   if (!Use_EntryMean_Validation)
      return true;

   double maArray[];
   ArraySetAsSeries(maArray, true);
   int maHandle = iMA(_Symbol, PERIOD_M1, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if (maHandle == INVALID_HANDLE) return true;

   if (CopyBuffer(maHandle, 0, 0, 1, maArray) > 0)
   {
      double mean = maArray[0];
      IndicatorRelease(maHandle);

      double entryPrice = 0;
      if (signal == 1)
         entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      else
         entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Check 1: Mean must be in profitable direction
      if (signal == 1 && mean <= entryPrice)
      {
         Print("v6.0 FILTER: BUY blocked - Mean ($", DoubleToString(mean, 2),
               ") not above entry ($", DoubleToString(entryPrice, 2), ")");
         return false;
      }
      if (signal == -1 && mean >= entryPrice)
      {
         Print("v6.0 FILTER: SELL blocked - Mean ($", DoubleToString(mean, 2),
               ") not below entry ($", DoubleToString(entryPrice, 2), ")");
         return false;
      }

      // Check 2: Minimum distance from entry to mean
      double distanceToMean = MathAbs(entryPrice - mean);
      double minDistance = Min_Entry_Mean_Distance * goldPip;

      if (distanceToMean < minDistance)
      {
         Print("v6.0 FILTER: Entry blocked - distance to mean: ",
               DoubleToString(distanceToMean / goldPip, 1),
               " pips (min: ", Min_Entry_Mean_Distance, ")");
         return false;
      }

      return true;
   }
   else
   {
      IndicatorRelease(maHandle);
   }

   return true;
}

//+------------------------------------------------------------------+
//| ENTRY FILTER: CHECK KEY LEVEL BLOCKING (kept from v5.1)          |
//| Returns true to BLOCK if a major round number ($100 interval)     |
//| sits between entry and mean in the first 60% of the path         |
//+------------------------------------------------------------------+
bool CheckKeyLevelBlocking(int signal, double entryPrice, double mean)
{
   if (!Use_KeyLevel_Filter)
      return false;

   double totalPath = MathAbs(mean - entryPrice);
   if (totalPath < goldPip)
      return false;

   if (signal == 1) // BUY: entry below mean, price needs to go UP
   {
      double blockZoneTop = entryPrice + totalPath * KeyLevel_Block_Zone;
      double firstLevel = MathCeil(entryPrice / KeyLevel_Interval) * KeyLevel_Interval;

      for (double level = firstLevel; level < mean; level += KeyLevel_Interval)
      {
         if (level > entryPrice && level <= blockZoneTop)
         {
            Print("v6.0 FILTER: BUY blocked - Key level $", DoubleToString(level, 0),
                  " blocks path ($", DoubleToString(entryPrice, 2),
                  " -> $", DoubleToString(mean, 2), ")");
            return true;
         }
      }
   }
   else if (signal == -1) // SELL: entry above mean, price needs to go DOWN
   {
      double blockZoneBottom = entryPrice - totalPath * KeyLevel_Block_Zone;
      double firstLevel = MathFloor(entryPrice / KeyLevel_Interval) * KeyLevel_Interval;

      for (double level = firstLevel; level > mean; level -= KeyLevel_Interval)
      {
         if (level < entryPrice && level >= blockZoneBottom)
         {
            Print("v6.0 FILTER: SELL blocked - Key level $", DoubleToString(level, 0),
                  " blocks path ($", DoubleToString(entryPrice, 2),
                  " -> $", DoubleToString(mean, 2), ")");
            return true;
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| MANAGE POSITIONS                                                |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong positionTicket = PositionGetTicket(i);
      if (positionTicket > 0)
      {
         if (PositionSelectByTicket(positionTicket))
         {
            string positionSymbol = PositionGetString(POSITION_SYMBOL);
            if (positionSymbol == _Symbol)
            {
               long positionMagic = PositionGetInteger(POSITION_MAGIC);
               int systemIndex = GetSystemIndex((int)positionMagic);

               if (systemIndex >= 0)
               {
                  ManageSinglePosition(positionTicket, systemIndex);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MANAGE SINGLE POSITION - v6.0 M1 Pickaxe                        |
//| RANGING: Two-stage exit (BE at mean, run to extended target)     |
//|   v6.0: Only run for ET if swing > Min_Swing_For_ET             |
//| TRENDING: Close at mean immediately                              |
//| v6.0: Basket close for pyramid positions                         |
//+------------------------------------------------------------------+
void ManageSinglePosition(ulong ticket, int systemIndex)
{
   if (PositionSelectByTicket(ticket))
   {
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double currentSL = PositionGetDouble(POSITION_SL);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double profitPips = 0;
      if (posType == POSITION_TYPE_BUY)
         profitPips = (currentPrice - entryPrice) / goldPip;
      else if (posType == POSITION_TYPE_SELL)
         profitPips = (entryPrice - currentPrice) / goldPip;

      datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);

      // 1. Check emergency close (always active, overrides everything)
      if (Use_Emergency_Close)
      {
         double adverseMove = 0;
         if (posType == POSITION_TYPE_BUY)
            adverseMove = ((entryPrice - currentPrice) / entryPrice) * 100;
         else if (posType == POSITION_TYPE_SELL)
            adverseMove = ((currentPrice - entryPrice) / entryPrice) * 100;

         if (adverseMove >= Emergency_Close_Pct)
         {
            int dir = (posType == POSITION_TYPE_BUY) ? 1 : -1;
            if (Use_Pyramiding)
               CloseAllPyramidPositions(dir, "Emergency Close - Adverse Move");
            else
               ClosePositionWithComment(ticket, "Emergency Close - Adverse Move");
            return;
         }
      }

      // 2. Check max hold time (M1: 1 minute per bar)
      int barsHeld = (int)((TimeCurrent() - entryTime) / (1 * 60));
      if (barsHeld >= Max_Hold_Bars)
      {
         ClosePositionWithComment(ticket, "Max Hold Time Reached");
         return;
      }

      // 3. Two-stage exit with extended targets (main exit logic)
      if (Use_Extended_Target && barsHeld > 2)
      {
         // Get current mean (EMA on M1)
         double maArray[];
         ArraySetAsSeries(maArray, true);
         int maHandle = iMA(_Symbol, PERIOD_M1, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
         if (maHandle == INVALID_HANDLE) return;

         if (CopyBuffer(maHandle, 0, 0, 1, maArray) > 0)
         {
            double mean = maArray[0];
            IndicatorRelease(maHandle);

            // Detect stage: Stage 2 = SL moved to breakeven (at or past entry)
            bool isStage2 = false;
            if (posType == POSITION_TYPE_BUY)
               isStage2 = (currentSL >= entryPrice);
            else if (posType == POSITION_TYPE_SELL)
               isStage2 = (currentSL <= entryPrice && currentSL > 0);

            if (isStage2)
            {
               // === STAGE 2: Zero-risk runner targeting extended level ===
               double target = CalculateExtendedTarget(entryPrice, mean, posType);

               if (posType == POSITION_TYPE_BUY && currentPrice >= target)
               {
                  double profit = (currentPrice - entryPrice);
                  Print("Extended Target Hit (BUY): Target $", DoubleToString(target, 2),
                        " | Entry $", DoubleToString(entryPrice, 2),
                        " | Profit: $", DoubleToString(profit, 2));
                  int dir = 1;
                  if (Use_Pyramiding)
                     CloseAllPyramidPositions(dir, "Extended Target Exit");
                  else
                     ClosePositionWithComment(ticket, "Extended Target Exit");
                  return;
               }
               else if (posType == POSITION_TYPE_SELL && currentPrice <= target)
               {
                  double profit = (entryPrice - currentPrice);
                  Print("Extended Target Hit (SELL): Target $", DoubleToString(target, 2),
                        " | Entry $", DoubleToString(entryPrice, 2),
                        " | Profit: $", DoubleToString(profit, 2));
                  int dir = -1;
                  if (Use_Pyramiding)
                     CloseAllPyramidPositions(dir, "Extended Target Exit");
                  else
                     ClosePositionWithComment(ticket, "Extended Target Exit");
                  return;
               }
               // Stage 2: keep holding - BE SL protects at zero risk
            }
            else
            {
               // === STAGE 1: Waiting for mean reversion (original SL active) ===
               bool reachedMean = false;
               if (posType == POSITION_TYPE_BUY)
                  reachedMean = (currentPrice >= mean);
               else if (posType == POSITION_TYPE_SELL)
                  reachedMean = (currentPrice <= mean);

               if (reachedMean)
               {
                  int dir = (posType == POSITION_TYPE_BUY) ? 1 : -1;

                  // EAGLE'S VIEW: Adapt behavior to market regime
                  if (Use_Regime_Detection && currentRegime == 1)
                  {
                     // TRENDING: Close at mean immediately
                     double profit = MathAbs(currentPrice - entryPrice);
                     Print("TRENDING regime: MR exit at mean ($", DoubleToString(mean, 2),
                           ") | Profit: $", DoubleToString(profit, 2));
                     if (Use_Pyramiding)
                        CloseAllPyramidPositions(dir, "Mean Reversion Exit (Trending)");
                     else
                        ClosePositionWithComment(ticket, "Mean Reversion Exit (Trending)");
                     return;
                  }

                  // v6.0 RANGING SWEET SPOT: Only run for ET if swing was meaningful
                  double entryToMean = MathAbs(mean - entryPrice);
                  if (entryToMean < Min_Swing_For_ET)
                  {
                     double profit = MathAbs(currentPrice - entryPrice);
                     Print("v6.0 RANGING: Weak swing ($", DoubleToString(entryToMean, 2),
                           " < $", DoubleToString(Min_Swing_For_ET, 2),
                           ") - MR exit at mean");
                     if (Use_Pyramiding)
                        CloseAllPyramidPositions(dir, "Mean Reversion Exit (Weak Swing)");
                     else
                        ClosePositionWithComment(ticket, "Mean Reversion Exit (Weak Swing)");
                     return;
                  }

                  // RANGING with strong swing: Try to transition to Stage 2
                  double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
                  double beSL = 0;

                  if (posType == POSITION_TYPE_BUY)
                     beSL = entryPrice + spread + 2 * _Point;
                  else
                     beSL = entryPrice - spread - 2 * _Point;

                  // Check if BE SL can actually be placed (price far enough away)
                  bool canPlaceBE = false;
                  if (posType == POSITION_TYPE_BUY)
                     canPlaceBE = (beSL > currentSL) && CheckBrokerStopDistance(beSL, posType);
                  else
                     canPlaceBE = (beSL < currentSL || currentSL == 0) && CheckBrokerStopDistance(beSL, posType);

                  if (canPlaceBE)
                  {
                     if (ModifyPositionSL(ticket, NormalizeDouble(beSL, _Digits)))
                     {
                        double target = CalculateExtendedTarget(entryPrice, mean, posType);
                        Print("Stage 1->2: Mean reached ($", DoubleToString(mean, 2),
                              ") | BE SL = $", DoubleToString(beSL, _Digits),
                              " | Target: $", DoubleToString(target, 2));
                     }
                  }
                  else
                  {
                     // BE CAN'T be placed - fall back to MR exit
                     double profit = MathAbs(currentPrice - entryPrice);
                     Print("MR Exit (BE unavailable): Mean $", DoubleToString(mean, 2),
                           " | Profit: $", DoubleToString(profit, 2));
                     if (Use_Pyramiding)
                        CloseAllPyramidPositions(dir, "Mean Reversion Exit");
                     else
                        ClosePositionWithComment(ticket, "Mean Reversion Exit");
                     return;
                  }
               }
               // Stage 1: keep waiting for mean, original SL protects
            }
         }
         else
         {
            IndicatorRelease(maHandle);
         }
         return; // Extended target mode handles all exits above
      }

      // 4. Standard mean reversion exit (when extended target is OFF)
      if (Use_Mean_Reversion_Exit && barsHeld > 2)
      {
         CheckMeanReversionExit(ticket, entryPrice, currentPrice, posType);
         return;
      }

      // 5. Legacy breakeven/trailing (OFF by default)
      if (Use_Smart_Breakeven && profitPips >= Breakeven_Trigger)
      {
         MoveToBreakeven(ticket, entryPrice, currentSL, posType);
      }
      if (Use_Profit_Trailing && profitPips >= Trail_Trigger)
      {
         TrailStopLoss(ticket, entryPrice, currentPrice, currentSL, posType);
      }
   }
}

//+------------------------------------------------------------------+
//| MOVE TO BREAKEVEN (Legacy - for non-extended-target use)        |
//+------------------------------------------------------------------+
void MoveToBreakeven(ulong ticket, double entry, double currentSL, ENUM_POSITION_TYPE type)
{
   double newSL = 0;
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = spread + 2 * _Point;

   if (type == POSITION_TYPE_BUY)
   {
      newSL = entry + buffer;
      if (newSL > currentSL)
      {
         if (CheckBrokerStopDistance(newSL, type))
         {
            if (ModifyPositionSL(ticket, newSL))
               Print("Breakeven: ticket ", ticket, " SL moved to ", DoubleToString(newSL, _Digits));
         }
      }
   }
   else if (type == POSITION_TYPE_SELL)
   {
      newSL = entry - buffer;
      if (newSL < currentSL || currentSL == 0)
      {
         if (CheckBrokerStopDistance(newSL, type))
         {
            if (ModifyPositionSL(ticket, newSL))
               Print("Breakeven: ticket ", ticket, " SL moved to ", DoubleToString(newSL, _Digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| TRAIL STOP LOSS                                                 |
//+------------------------------------------------------------------+
void TrailStopLoss(ulong ticket, double entry, double current, double currentSL, ENUM_POSITION_TYPE type)
{
   double newSL = 0;
   double trailAmount = Trail_Step * goldPip;

   if (type == POSITION_TYPE_BUY)
   {
      newSL = current - trailAmount;
      if (newSL > currentSL && newSL > entry)
      {
         if (CheckBrokerStopDistance(newSL, type))
         {
            if (ModifyPositionSL(ticket, newSL))
               Print("Trail: ticket ", ticket, " SL moved to ", DoubleToString(newSL, _Digits));
         }
      }
   }
   else if (type == POSITION_TYPE_SELL)
   {
      newSL = current + trailAmount;
      if (newSL < currentSL && newSL < entry)
      {
         if (CheckBrokerStopDistance(newSL, type))
         {
            if (ModifyPositionSL(ticket, newSL))
               Print("Trail: ticket ", ticket, " SL moved to ", DoubleToString(newSL, _Digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK BROKER MINIMUM STOP DISTANCE                              |
//+------------------------------------------------------------------+
bool CheckBrokerStopDistance(double slPrice, ENUM_POSITION_TYPE type)
{
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if (stopsLevel == 0) stopsLevel = 10;
   double minDist = stopsLevel * _Point;

   if (type == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if (slPrice >= bid - minDist)
         return false;
   }
   else
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if (slPrice <= ask + minDist)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| MODIFY POSITION STOP LOSS                                       |
//+------------------------------------------------------------------+
bool ModifyPositionSL(ulong ticket, double newSL)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   if (PositionSelectByTicket(ticket))
   {
      double currentTP = PositionGetDouble(POSITION_TP);
      long positionMagic = PositionGetInteger(POSITION_MAGIC);

      request.action = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.symbol = _Symbol;
      request.sl = NormalizeDouble(newSL, _Digits);
      request.tp = currentTP;
      request.magic = positionMagic;

      bool success = OrderSend(request, result);
      if (success && result.retcode == TRADE_RETCODE_DONE)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| VALIDATE STOP LOSS                                              |
//+------------------------------------------------------------------+
bool ValidateStopLoss(double slPrice, double entryPrice, ENUM_POSITION_TYPE type)
{
   if (!Use_Validation) return true;

   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minStopDistance = Min_Stop_Distance * _Point;

   if (type == POSITION_TYPE_BUY)
   {
      if (slPrice >= currentBid - minStopDistance)
      {
         Print("Invalid SL for BUY: Too close to current price");
         return false;
      }
      if (slPrice >= entryPrice * (1 - Risk_to_Entry_Ratio * 0.001))
      {
         Print("Invalid SL for BUY: Too close to entry");
         return false;
      }
   }
   else if (type == POSITION_TYPE_SELL)
   {
      if (slPrice <= currentAsk + minStopDistance)
      {
         Print("Invalid SL for SELL: Too close to current price");
         return false;
      }
      if (slPrice <= entryPrice * (1 + Risk_to_Entry_Ratio * 0.001))
      {
         Print("Invalid SL for SELL: Too close to entry");
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| CHECK MEAN REVERSION EXIT                                       |
//+------------------------------------------------------------------+
void CheckMeanReversionExit(ulong ticket, double entry, double current, ENUM_POSITION_TYPE type)
{
   double maArray[];
   ArraySetAsSeries(maArray, true);
   int maHandle = iMA(_Symbol, PERIOD_M1, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if (maHandle == INVALID_HANDLE) return;

   if (CopyBuffer(maHandle, 0, 0, 1, maArray) > 0)
   {
      double mean = maArray[0];
      IndicatorRelease(maHandle);

      if (type == POSITION_TYPE_BUY)
      {
         if (current >= mean)
         {
            int dir = 1;
            if (Use_Pyramiding)
               CloseAllPyramidPositions(dir, "Mean Reversion Exit");
            else
               ClosePositionWithComment(ticket, "Mean Reversion Exit");
            double profit = (current - entry);
            Print("BUY mean reversion complete - Profit: $", DoubleToString(profit, 2));
         }
      }
      else if (type == POSITION_TYPE_SELL)
      {
         if (current <= mean)
         {
            int dir = -1;
            if (Use_Pyramiding)
               CloseAllPyramidPositions(dir, "Mean Reversion Exit");
            else
               ClosePositionWithComment(ticket, "Mean Reversion Exit");
            double profit = (entry - current);
            Print("SELL mean reversion complete - Profit: $", DoubleToString(profit, 2));
         }
      }
   }
   else
   {
      IndicatorRelease(maHandle);
   }
}

//+------------------------------------------------------------------+
//| CALCULATE EXTENDED TARGET (v5.0 - SELL bug fixed)               |
//| Uses Fib 1.618 as MINIMUM, takes furthest reasonable target     |
//| Caps at Fib_Target_Multiplier x Fib DISTANCE (not raw price)    |
//+------------------------------------------------------------------+
double CalculateExtendedTarget(double entry, double mean, ENUM_POSITION_TYPE type)
{
   double swingDist = MathAbs(mean - entry);
   if (swingDist < goldPip) swingDist = goldPip;

   // 1. Fibonacci 1.618 extension (MINIMUM target)
   double fibDist = swingDist * (Fib_Level - 1.0);
   double fibTarget = 0;
   if (type == POSITION_TYPE_BUY)
      fibTarget = mean + fibDist;
   else
      fibTarget = mean - fibDist;

   // 2. Nearest psychological level past the mean
   double psychTarget = 0;
   if (type == POSITION_TYPE_BUY)
      psychTarget = MathCeil((mean + 0.01) / Psych_Level_Size) * Psych_Level_Size;
   else
      psychTarget = MathFloor((mean - 0.01) / Psych_Level_Size) * Psych_Level_Size;

   // 3. Opposite Bollinger Band (uses EMA period to match mean)
   double bbTarget = 0;
   double upperBB[], lowerBB[];
   ArraySetAsSeries(upperBB, true);
   ArraySetAsSeries(lowerBB, true);
   int bbHandle = iBands(_Symbol, PERIOD_M1, EMA_Period, 0, 2.0, PRICE_CLOSE);
   if (bbHandle != INVALID_HANDLE)
   {
      if (CopyBuffer(bbHandle, 1, 0, 1, upperBB) > 0 &&
          CopyBuffer(bbHandle, 2, 0, 1, lowerBB) > 0)
      {
         if (type == POSITION_TYPE_BUY)
            bbTarget = upperBB[0];
         else
            bbTarget = lowerBB[0];
      }
      IndicatorRelease(bbHandle);
   }

   // 4. ATR-based target: mean + 1x ATR
   double atrTarget = 0;
   double atrArray[];
   ArraySetAsSeries(atrArray, true);
   int atrHandle = iATR(_Symbol, PERIOD_M1, 14);
   if (atrHandle != INVALID_HANDLE)
   {
      if (CopyBuffer(atrHandle, 0, 0, 1, atrArray) > 0)
      {
         if (type == POSITION_TYPE_BUY)
            atrTarget = mean + atrArray[0];
         else
            atrTarget = mean - atrArray[0];
      }
      IndicatorRelease(atrHandle);
   }

   // Use Fib as minimum, take furthest valid target
   // Cap using DISTANCE from mean (works correctly for both BUY and SELL)
   double maxDist = fibDist * Fib_Target_Multiplier;
   double target = fibTarget;

   if (type == POSITION_TYPE_BUY)
   {
      double maxTarget = mean + maxDist;
      if (psychTarget > fibTarget && psychTarget <= maxTarget)
         target = MathMax(target, psychTarget);
      if (bbTarget > fibTarget && bbTarget <= maxTarget)
         target = MathMax(target, bbTarget);
      if (atrTarget > fibTarget && atrTarget <= maxTarget)
         target = MathMax(target, atrTarget);
   }
   else
   {
      double minTarget = mean - maxDist;
      if (psychTarget < fibTarget && psychTarget >= minTarget)
         target = MathMin(target, psychTarget);
      if (bbTarget < fibTarget && bbTarget >= minTarget)
         target = MathMin(target, bbTarget);
      if (atrTarget < fibTarget && atrTarget >= minTarget)
         target = MathMin(target, atrTarget);
   }

   return NormalizeDouble(target, _Digits);
}

//+------------------------------------------------------------------+
//| CLOSE POSITION WITH COMMENT                                     |
//+------------------------------------------------------------------+
void ClosePositionWithComment(ulong ticket, string comment)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   if (PositionSelectByTicket(ticket))
   {
      double volume = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      long positionMagic = PositionGetInteger(POSITION_MAGIC);

      request.action = TRADE_ACTION_DEAL;
      request.position = ticket;
      request.symbol = _Symbol;
      request.volume = volume;
      request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      request.price = (request.type == ORDER_TYPE_SELL) ?
                     SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                     SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      request.deviation = Slippage;
      request.magic = positionMagic;
      request.comment = comment;

      if (OrderSend(request, result))
      {
         Print("Position closed: ", comment, " - Ticket ", ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK ENTRY SIGNALS - v6.0 with Donchian+EMA + pyramid          |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
   if (totalTradesToday >= Max_Daily_Trades)
      return;

   if (dailyPnL <= -Max_Daily_Loss)
      return;

   if (Use_Session_Filter && !IsValidSession())
      return;

   if (Use_Volume_Filter && !IsVolumeConfirmed())
      return;

   // v6.0: H1 Historical Volatility daily block
   if (Use_H1_Vol_Filter && h1VolBlockedToday)
      return;

   for (int i = 0; i < 2; i++)
   {
      if (systems[i].enabled)
      {
         if (CanSystemTrade(i))
         {
            int signal = GetSystemSignal(i);
            if (signal != 0)
            {
               if (Use_Trend_Filter && !IsTrendAligned(signal))
                  continue;

               // Entry-Mean validation (direction + distance)
               if (!ValidateEntryMeanDirection(signal))
                  continue;

               // Key level blocking path to mean
               double filterEntryPrice = (signal == 1) ?
                  SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                  SymbolInfoDouble(_Symbol, SYMBOL_BID);

               double filterMaArray[];
               ArraySetAsSeries(filterMaArray, true);
               int filterMaHandle = iMA(_Symbol, PERIOD_M1, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
               if (filterMaHandle != INVALID_HANDLE)
               {
                  if (CopyBuffer(filterMaHandle, 0, 0, 1, filterMaArray) > 0)
                  {
                     double filterMean = filterMaArray[0];
                     IndicatorRelease(filterMaHandle);

                     if (CheckKeyLevelBlocking(signal, filterEntryPrice, filterMean))
                        continue;
                  }
                  else
                  {
                     IndicatorRelease(filterMaHandle);
                  }
               }

               // v6.0: Pyramid logic - check if this is an add-on or new position
               if (signal == 1 && pyramidSell.count > 0)
                  continue; // Don't hedge: have SELL positions, skip BUY
               if (signal == -1 && pyramidBuy.count > 0)
                  continue; // Don't hedge: have BUY positions, skip SELL

               if (signal == 1 && pyramidBuy.count > 0)
               {
                  // Already have BUY positions - check pyramid conditions
                  if (!CanPyramid(signal))
                     continue;
                  Print("v6.0 PYRAMID: Adding BUY level ", pyramidBuy.count + 1,
                        "/", Max_Pyramid_Levels);
               }
               else if (signal == -1 && pyramidSell.count > 0)
               {
                  if (!CanPyramid(signal))
                     continue;
                  Print("v6.0 PYRAMID: Adding SELL level ", pyramidSell.count + 1,
                        "/", Max_Pyramid_Levels);
               }

               // All filters passed - execute trade
               ExecuteTrade(i, signal);
               systems[i].lastTradeTime = TimeCurrent();
               systems[i].tradesToday++;
               totalTradesToday++;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CAN SYSTEM TRADE                                                |
//+------------------------------------------------------------------+
bool CanSystemTrade(int systemIndex)
{
   if (TimeCurrent() - systems[systemIndex].lastTradeTime < Min_Bars_Between * 1 * 60)
      return false;

   if (systems[systemIndex].tradesToday >= Max_Daily_Trades / 2)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| GET SYSTEM SIGNAL - v6.0 Donchian + EMA                         |
//+------------------------------------------------------------------+
int GetSystemSignal(int systemIndex)
{
   // System 1: Donchian Channel + EMA mean reversion (v6.0)
   if (systemIndex == 0)
   {
      // 1. Get EMA (the "mean")
      double emaArray[];
      ArraySetAsSeries(emaArray, true);
      int emaHandle = iMA(_Symbol, PERIOD_M1, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
      if (emaHandle == INVALID_HANDLE) return 0;

      if (CopyBuffer(emaHandle, 0, 0, 1, emaArray) <= 0)
      {
         IndicatorRelease(emaHandle);
         return 0;
      }
      double mean = emaArray[0];
      IndicatorRelease(emaHandle);

      // 2. Get Donchian Channel (manual calculation - MQL5 has no built-in)
      double highArray[], lowArray[];
      ArraySetAsSeries(highArray, true);
      ArraySetAsSeries(lowArray, true);

      // Use bars 1..Donchian_Period (completed bars, not current)
      if (CopyHigh(_Symbol, PERIOD_M1, 1, Donchian_Period, highArray) < Donchian_Period)
         return 0;
      if (CopyLow(_Symbol, PERIOD_M1, 1, Donchian_Period, lowArray) < Donchian_Period)
         return 0;

      double donchianUpper = highArray[0];
      double donchianLower = lowArray[0];
      for (int i = 1; i < Donchian_Period; i++)
      {
         if (highArray[i] > donchianUpper) donchianUpper = highArray[i];
         if (lowArray[i] < donchianLower) donchianLower = lowArray[i];
      }

      double channelWidth = donchianUpper - donchianLower;

      // 3. Smart minimum distance check
      double minWidth = GetSmartMinDistance();
      if (channelWidth < minWidth)
         return 0; // Channel too narrow, skip

      // 4. Check last completed bar for touch/break of Donchian bands
      double lastHigh[], lastLow[], lastClose[];
      ArraySetAsSeries(lastHigh, true);
      ArraySetAsSeries(lastLow, true);
      ArraySetAsSeries(lastClose, true);
      if (CopyHigh(_Symbol, PERIOD_M1, 1, 1, lastHigh) <= 0) return 0;
      if (CopyLow(_Symbol, PERIOD_M1, 1, 1, lastLow) <= 0) return 0;
      if (CopyClose(_Symbol, PERIOD_M1, 1, 1, lastClose) <= 0) return 0;

      double price = lastClose[0];

      // BUY: last bar touches/breaks below Donchian lower AND close below EMA (stretched)
      if (lastLow[0] <= donchianLower && price < mean)
         return 1;

      // SELL: last bar touches/breaks above Donchian upper AND close above EMA (stretched)
      if (lastHigh[0] >= donchianUpper && price > mean)
         return -1;

      return 0;
   }

   // System 2: Bollinger Bands + MACD (disabled, updated to M1)
   if (systemIndex == 1)
   {
      double middleBB[], upperBB[], lowerBB[];
      ArraySetAsSeries(middleBB, true);
      ArraySetAsSeries(upperBB, true);
      ArraySetAsSeries(lowerBB, true);
      int bbHandle = iBands(_Symbol, PERIOD_M1, 20, 0, 2.0, PRICE_CLOSE);
      if (bbHandle == INVALID_HANDLE) return 0;

      if (CopyBuffer(bbHandle, 0, 0, 1, middleBB) > 0 &&
          CopyBuffer(bbHandle, 1, 0, 1, upperBB) > 0 &&
          CopyBuffer(bbHandle, 2, 0, 1, lowerBB) > 0)
      {
         double currentArray[];
         ArraySetAsSeries(currentArray, true);
         if (CopyClose(_Symbol, PERIOD_M1, 0, 1, currentArray) > 0)
         {
            double current = currentArray[0];
            double bandWidth = upperBB[0] - lowerBB[0];
            double lowerZone = lowerBB[0] + bandWidth * 0.05;
            double upperZone = upperBB[0] - bandWidth * 0.05;

            double macdMain[], macdSignal[];
            ArraySetAsSeries(macdMain, true);
            ArraySetAsSeries(macdSignal, true);
            int macdHandle = iMACD(_Symbol, PERIOD_M1, 12, 26, 9, PRICE_CLOSE);
            if (macdHandle == INVALID_HANDLE)
            {
               IndicatorRelease(bbHandle);
               return 0;
            }

            if (CopyBuffer(macdHandle, 0, 0, 1, macdMain) > 0 &&
                CopyBuffer(macdHandle, 1, 0, 1, macdSignal) > 0)
            {
               double macd = macdMain[0];
               double signal = macdSignal[0];

               IndicatorRelease(bbHandle);
               IndicatorRelease(macdHandle);

               if (current <= lowerZone && macd > signal)
                  return 1;

               if (current >= upperZone && macd < signal)
                  return -1;
            }
            else
            {
               IndicatorRelease(macdHandle);
            }
         }
      }
      IndicatorRelease(bbHandle);
   }

   return 0;
}

//+------------------------------------------------------------------+
//| EXECUTE TRADE - v6.0 with M1 ATR SL + dollar cap + pyramid      |
//+------------------------------------------------------------------+
void ExecuteTrade(int systemIndex, int signal)
{
   double entryPrice = 0;
   double slPrice = 0;
   ENUM_ORDER_TYPE orderType;

   if (signal == 1) // BUY
   {
      orderType = ORDER_TYPE_BUY;
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if (Use_Dynamic_SL)
      {
         double atrArray[];
         ArraySetAsSeries(atrArray, true);
         int atrHandle = iATR(_Symbol, PERIOD_M1, 14);
         if (atrHandle != INVALID_HANDLE)
         {
            if (CopyBuffer(atrHandle, 0, 0, 1, atrArray) > 0)
               slPrice = entryPrice - (atrArray[0] * ATR_Multiplier);
            IndicatorRelease(atrHandle);
         }
         else
            slPrice = entryPrice - (200 * goldPip);
      }
      else
         slPrice = entryPrice - (200 * goldPip);
   }
   else // SELL
   {
      orderType = ORDER_TYPE_SELL;
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if (Use_Dynamic_SL)
      {
         double atrArray[];
         ArraySetAsSeries(atrArray, true);
         int atrHandle = iATR(_Symbol, PERIOD_M1, 14);
         if (atrHandle != INVALID_HANDLE)
         {
            if (CopyBuffer(atrHandle, 0, 0, 1, atrArray) > 0)
               slPrice = entryPrice + (atrArray[0] * ATR_Multiplier);
            IndicatorRelease(atrHandle);
         }
         else
            slPrice = entryPrice + (200 * goldPip);
      }
      else
         slPrice = entryPrice + (200 * goldPip);
   }

   if (!ValidateStopLoss(slPrice, entryPrice, (signal == 1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL))
   {
      Print("Trade blocked: Invalid stop loss level");
      return;
   }

   entryPrice = NormalizeDouble(entryPrice, _Digits);
   slPrice = NormalizeDouble(slPrice, _Digits);

   // v6.0: Dollar cap on SL - tighten SL if dollar risk exceeds Max_SL_Dollars
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if (contractSize <= 0) contractSize = 100;
   double slDistance = MathAbs(entryPrice - slPrice);
   double dollarRiskRaw = slDistance * Lot_Size * contractSize;

   if (Max_SL_Dollars > 0 && dollarRiskRaw > Max_SL_Dollars)
   {
      double maxSlDistance = Max_SL_Dollars / (Lot_Size * contractSize);
      if (signal == 1)
         slPrice = entryPrice - maxSlDistance;
      else
         slPrice = entryPrice + maxSlDistance;

      slPrice = NormalizeDouble(slPrice, _Digits);
      slDistance = MathAbs(entryPrice - slPrice);
      Print("v6.0 SL CAP: ATR SL $", DoubleToString(dollarRiskRaw, 2),
            " -> capped to $", DoubleToString(Max_SL_Dollars, 2),
            " | SL: $", DoubleToString(slPrice, 2));
   }

   // Risk gate
   double maxRiskAllowed = GetDynamicMaxRisk();
   double tradeRisk = slDistance * Lot_Size * contractSize;
   if (slDistance > 0 && maxRiskAllowed > 0)
   {
      if (tradeRisk > maxRiskAllowed)
      {
         Print("Trade SKIPPED: Risk $", DoubleToString(tradeRisk, 2),
               " exceeds max $", DoubleToString(maxRiskAllowed, 2));
         return;
      }
   }

   double lotSize;
   if (Use_Risk_Sizing && slDistance > 0)
   {
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if (minLot <= 0) minLot = 0.01;
      if (lotStep <= 0) lotStep = 0.01;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskAmount = MathMin(equity * Risk_Percent / 100.0, maxRiskAllowed);
      lotSize = riskAmount / (slDistance * contractSize);

      lotSize = MathFloor(lotSize / lotStep) * lotStep;
      lotSize = MathMax(lotSize, minLot);
      lotSize = MathMin(lotSize, Max_Position_Size);
   }
   else
   {
      lotSize = MathMin(Lot_Size, Max_Position_Size);
   }

   double actualRisk = slDistance * lotSize * contractSize;
   string regimeStr = (currentRegime == 1) ? "TRENDING" : "RANGING";
   Print("System ", systemIndex + 1, ": ", (signal == 1 ? "BUY" : "SELL"),
         " | Regime: ", regimeStr);
   Print("  Entry: $", DoubleToString(entryPrice, 2),
         " | SL: $", DoubleToString(slPrice, 2),
         " | Risk: $", DoubleToString(actualRisk, 2),
         " | Lot: ", DoubleToString(lotSize, 2));

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = orderType;
   request.price = entryPrice;
   request.sl = slPrice;
   request.deviation = Slippage;
   request.magic = (long)systems[systemIndex].magic;
   request.comment = systems[systemIndex].name;

   if (OrderSend(request, result))
   {
      Print("Trade opened: Ticket ", result.order);

      // v6.0: Track pyramid entry
      if (signal == 1)
      {
         if (pyramidBuy.count < 3)
         {
            pyramidBuy.tickets[pyramidBuy.count] = result.order;
            pyramidBuy.count++;
            pyramidBuy.lastEntryPrice = entryPrice;
         }
      }
      else
      {
         if (pyramidSell.count < 3)
         {
            pyramidSell.tickets[pyramidSell.count] = result.order;
            pyramidSell.count++;
            pyramidSell.lastEntryPrice = entryPrice;
         }
      }
   }
   else
   {
      Print("Failed to open trade: Error ", result.retcode);
   }
}

//+------------------------------------------------------------------+
//| GET SYSTEM INDEX                                                |
//+------------------------------------------------------------------+
int GetSystemIndex(int magic)
{
   for (int i = 0; i < 2; i++)
   {
      if (systems[i].magic == magic)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| CHECK DAILY RESET                                               |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   static int lastDay = -1;

   if (currentTimeStruct.day != lastDay)
   {
      totalTradesToday = 0;
      dailyPnL = 0;
      rollingATRAverage = 0;
      atrSampleCount = 0;

      // Reset drawdown alert flags daily (keep tracking peak)
      drawdownLevel1Hit = false;
      drawdownLevel2Hit = false;
      drawdownLevel3Hit = false;

      // v6.0: Reset H1 vol filter daily
      h1VolBlockedToday = false;
      h1VolValue = 0;
      lastH1VolCheck = 0;

      // v6.0: Reset pyramid tracking (positions survive, tracker re-scans)
      pyramidBuy.count = 0;
      pyramidBuy.lastEntryPrice = 0;
      for (int p = 0; p < 3; p++) pyramidBuy.tickets[p] = 0;
      pyramidSell.count = 0;
      pyramidSell.lastEntryPrice = 0;
      for (int p = 0; p < 3; p++) pyramidSell.tickets[p] = 0;

      for (int i = 0; i < 2; i++)
      {
         systems[i].tradesToday = 0;
         systems[i].profitToday = 0;
      }

      Print("=== DAILY RESET ===");
      Print("Date: ", TimeToString(TimeCurrent(), TIME_DATE));
      Print("Equity Peak: $", DoubleToString(equityHighWaterMark, 2));
      Print("Max Drawdown: $", DoubleToString(maxDrawdownFromPeak, 2));
      lastDay = currentTimeStruct.day;
   }
}

//+------------------------------------------------------------------+
//| UPDATE DAILY STATS                                              |
//+------------------------------------------------------------------+
void UpdateDailyStats()
{
   dailyPnL = 0;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong positionTicket = PositionGetTicket(i);
      if (positionTicket > 0)
      {
         if (PositionSelectByTicket(positionTicket))
         {
            if (PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
               long positionMagic = PositionGetInteger(POSITION_MAGIC);
               int systemIndex = GetSystemIndex((int)positionMagic);

               if (systemIndex >= 0)
               {
                  double profit = PositionGetDouble(POSITION_PROFIT);
                  systems[systemIndex].profitToday += profit;
                  dailyPnL += profit;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK H1 TREND ALIGNMENT                                        |
//+------------------------------------------------------------------+
bool IsTrendAligned(int signal)
{
   double maArray[];
   ArraySetAsSeries(maArray, true);
   int maHandle = iMA(_Symbol, PERIOD_H1, Trend_MA_Period, 0, MODE_SMA, PRICE_CLOSE);
   if (maHandle == INVALID_HANDLE) return true;

   if (CopyBuffer(maHandle, 0, 0, 1, maArray) > 0)
   {
      double h1MA = maArray[0];
      IndicatorRelease(maHandle);

      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if (signal == 1 && currentPrice < h1MA)
         return false;

      if (signal == -1 && currentPrice > h1MA)
         return false;
   }
   else
   {
      IndicatorRelease(maHandle);
   }

   return true;
}

//+------------------------------------------------------------------+
//| CHECK IF WITHIN VALID TRADING SESSION                           |
//+------------------------------------------------------------------+
bool IsValidSession()
{
   int currentHour = currentTimeStruct.hour;
   bool inLondon = (currentHour >= London_Start_Hour && currentHour < London_End_Hour);
   bool inNY = (currentHour >= NY_Start_Hour && currentHour < NY_End_Hour);
   return (inLondon || inNY);
}

//+------------------------------------------------------------------+
//| CHECK VOLUME CONFIRMATION                                       |
//+------------------------------------------------------------------+
bool IsVolumeConfirmed()
{
   long volumeArray[];
   ArraySetAsSeries(volumeArray, true);

   if (CopyTickVolume(_Symbol, PERIOD_M1, 0, 21, volumeArray) < 21)
      return true;

   double avgVolume = 0;
   for (int i = 1; i <= 20; i++)
      avgVolume += (double)volumeArray[i];
   avgVolume /= 20.0;

   double currentVolume = (double)volumeArray[0];

   if (currentVolume < avgVolume * Volume_Multiplier)
      return false;

   return true;
}

//+------------------------------------------------------------------+
