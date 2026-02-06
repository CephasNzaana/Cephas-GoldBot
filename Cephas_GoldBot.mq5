//+------------------------------------------------------------------+
//|                                 Cephas_GoldBot_Phase2.mq5       |
//|                                 ENHANCED PROFITABILITY VERSION  |
//|                                 Added trend/session/volume      |
//+------------------------------------------------------------------+
#property copyright "Cephas GoldBot"
#property link      ""
#property version   "3.0"
#property strict

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                |
//+------------------------------------------------------------------+
input double   Lot_Size = 0.01;           // Fixed lot size
input int      Magic_Number = 888000;     // Base magic number
input int      Slippage = 3;              // Slippage in points

input bool     Use_Validation = true;     // Validate stop levels
input int      Min_Stop_Distance = 50;    // Min stop distance in points
input bool     Use_Dynamic_SL = true;     // Use dynamic stop based on price
input double   Risk_to_Entry_Ratio = 0.8; // SL:Entry ratio for validation
input double   ATR_Multiplier = 3.0;      // ATR multiplier for SL (was 1.5)

input bool     Use_Smart_Breakeven = true;// Move to breakeven SMARTLY
input double   Breakeven_Trigger = 15;    // 15 pips profit
input bool     Use_Profit_Trailing = true;// Trail stop when in profit
input double   Trail_Trigger = 25;        // 25 pips profit
input double   Trail_Step = 5;            // 5 pips step

input bool     System_1_Enable = true;    // System 1
input bool     System_2_Enable = true;    // System 2
input string   System1_Comment = "Sys1";  // System 1 comment
input string   System2_Comment = "Sys2";  // System 2 comment

input int      Max_Daily_Trades = 100;    // Max trades per day
input double   Max_Daily_Loss = 100;      // Max daily loss in $
input double   Max_Position_Size = 0.05;  // Max lot size per position
input int      Min_Bars_Between = 3;      // Min bars between trades

input bool     Use_Mean_Reversion_Exit = true; // Auto exit at mean
input int      Max_Hold_Bars = 20;        // Max bars to hold position
input bool     Use_Emergency_Close = true;// Emergency close if price moves against
input double   Emergency_Close_Pct = 1.0; // Close if moves 1% against

//--- NEW: TREND FILTER (H1 200 SMA)
input bool     Use_Trend_Filter = true;   // Only trade with H1 trend
input int      Trend_MA_Period = 200;     // H1 MA period for trend

//--- NEW: SESSION FILTER
input bool     Use_Session_Filter = true; // Only trade London/NY
input int      London_Start_Hour = 8;     // London session start (broker time)
input int      London_End_Hour = 17;      // London session end
input int      NY_Start_Hour = 13;        // NY session start (broker time)
input int      NY_End_Hour = 22;          // NY session end

//--- NEW: VOLUME CONFIRMATION
input bool     Use_Volume_Filter = true;  // Require volume confirmation
input double   Volume_Multiplier = 1.2;   // Min volume vs 20-bar average

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
   Print("CEPHAS GOLD BOT v3.0 - ENHANCED PROFITABILITY");
   Print("NEW FEATURES:");
   Print("1. H1 Trend Filter (", Trend_MA_Period, " SMA) = ", Use_Trend_Filter ? "ON" : "OFF");
   Print("2. Session Filter (London/NY) = ", Use_Session_Filter ? "ON" : "OFF");
   Print("3. Volume Confirmation (", Volume_Multiplier, "x avg) = ", Use_Volume_Filter ? "ON" : "OFF");
   Print("4. ATR Stop Loss Multiplier = ", ATR_Multiplier, "x");
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
   Print("==================================================");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar (M5)
   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
   if (currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;
   
   // Update time
   currentTime = TimeCurrent();
   TimeToStruct(currentTime, currentTimeStruct);
   
   // Check daily reset
   CheckDailyReset();
   
   // Manage existing positions
   ManagePositions();
   
   // Check for entry signals
   CheckEntrySignals();
   
   // Update P&L tracking
   UpdateDailyStats();
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
//| MANAGE SINGLE POSITION                                          |
//+------------------------------------------------------------------+
void ManageSinglePosition(ulong ticket, int systemIndex)
{
   if (PositionSelectByTicket(ticket))
   {
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double currentSL = PositionGetDouble(POSITION_SL);
      double profitUSD = PositionGetDouble(POSITION_PROFIT);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      double profitPips = 0;
      if (posType == POSITION_TYPE_BUY)
         profitPips = (currentPrice - entryPrice) / goldPip;
      else if (posType == POSITION_TYPE_SELL)
         profitPips = (entryPrice - currentPrice) / goldPip;
      
      datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
      
      // 1. Check emergency close
      if (Use_Emergency_Close)
      {
         double adverseMove = 0;
         if (posType == POSITION_TYPE_BUY)
            adverseMove = ((entryPrice - currentPrice) / entryPrice) * 100;
         else if (posType == POSITION_TYPE_SELL)
            adverseMove = ((currentPrice - entryPrice) / entryPrice) * 100;
         
         if (adverseMove >= Emergency_Close_Pct)
         {
            ClosePositionWithComment(ticket, "Emergency Close - Adverse Move");
            return;
         }
      }
      
      // 2. Check max hold time
      int barsHeld = (int)((TimeCurrent() - entryTime) / (5 * 60));
      if (barsHeld >= Max_Hold_Bars)
      {
         ClosePositionWithComment(ticket, "Max Hold Time Reached");
         return;
      }
      
      // 3. Smart breakeven movement
      if (Use_Smart_Breakeven && profitPips >= Breakeven_Trigger)
      {
         MoveToBreakeven(ticket, entryPrice, currentSL, posType);
      }
      
      // 4. Profit trailing
      if (Use_Profit_Trailing && profitPips >= Trail_Trigger)
      {
         TrailStopLoss(ticket, entryPrice, currentPrice, currentSL, posType);
      }
      
      // 5. Mean reversion exit
      if (Use_Mean_Reversion_Exit && barsHeld > 2)
      {
         CheckMeanReversionExit(ticket, entryPrice, currentPrice, posType);
      }
   }
}

//+------------------------------------------------------------------+
//| MOVE TO BREAKEVEN                                               |
//+------------------------------------------------------------------+
void MoveToBreakeven(ulong ticket, double entry, double currentSL, ENUM_POSITION_TYPE type)
{
   double newSL = 0;
   double buffer = Min_Stop_Distance * _Point * 2;
   
   if (type == POSITION_TYPE_BUY)
   {
      newSL = entry - buffer;
      // Validate: new SL must be better than current AND above entry
      if (newSL > currentSL && newSL < entry)
      {
         if (ValidateStopLoss(newSL, entry, type))
         {
            if (ModifyPositionSL(ticket, newSL))
               Print("✓ Breakeven move applied to ticket ", ticket);
         }
      }
   }
   else if (type == POSITION_TYPE_SELL)
   {
      newSL = entry + buffer;
      // Validate: new SL must be better than current AND below entry
      if (newSL < currentSL && newSL > entry)
      {
         if (ValidateStopLoss(newSL, entry, type))
         {
            if (ModifyPositionSL(ticket, newSL))
               Print("✓ Breakeven move applied to ticket ", ticket);
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
      // Validate: new SL must be better than current AND above entry
      if (newSL > currentSL && newSL > entry)
      {
         if (ValidateStopLoss(newSL, entry, type))
         {
            if (ModifyPositionSL(ticket, newSL))
               Print("✓ Trailing stop applied to ticket ", ticket);
         }
      }
   }
   else if (type == POSITION_TYPE_SELL)
   {
      newSL = current + trailAmount;
      // Validate: new SL must be better than current AND below entry
      if (newSL < currentSL && newSL < entry)
      {
         if (ValidateStopLoss(newSL, entry, type))
         {
            if (ModifyPositionSL(ticket, newSL))
               Print("✓ Trailing stop applied to ticket ", ticket);
         }
      }
   }
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
   
   // Check minimum distance from current price
   if (type == POSITION_TYPE_BUY)
   {
      if (slPrice >= currentBid - minStopDistance)
      {
         Print("❌ Invalid SL for BUY: Too close to current price");
         return false;
      }
      if (slPrice >= entryPrice * (1 - Risk_to_Entry_Ratio * 0.001))
      {
         Print("❌ Invalid SL for BUY: Too close to entry");
         return false;
      }
   }
   else if (type == POSITION_TYPE_SELL)
   {
      if (slPrice <= currentAsk + minStopDistance)
      {
         Print("❌ Invalid SL for SELL: Too close to current price");
         return false;
      }
      if (slPrice <= entryPrice * (1 + Risk_to_Entry_Ratio * 0.001))
      {
         Print("❌ Invalid SL for SELL: Too close to entry");
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
   // Calculate current mean (20-period SMA)
   double maArray[];
   ArraySetAsSeries(maArray, true);
   int maHandle = iMA(_Symbol, PERIOD_M5, 20, 0, MODE_SMA, PRICE_CLOSE);
   if (maHandle == INVALID_HANDLE) return;
   
   if (CopyBuffer(maHandle, 0, 0, 1, maArray) > 0)
   {
      double mean = maArray[0];
      IndicatorRelease(maHandle);
      
      if (type == POSITION_TYPE_BUY)
      {
         // Exit BUY when price returns to or above mean
         if (current >= mean)
         {
            ClosePositionWithComment(ticket, "Mean Reversion Exit");
            double profit = (current - entry) / goldPip * goldPip;
            Print("✅ BUY mean reversion complete - Profit: $", DoubleToString(profit, 2));
         }
      }
      else if (type == POSITION_TYPE_SELL)
      {
         // Exit SELL when price returns to or below mean
         if (current <= mean)
         {
            ClosePositionWithComment(ticket, "Mean Reversion Exit");
            double profit = (entry - current) / goldPip * goldPip;
            Print("✅ SELL mean reversion complete - Profit: $", DoubleToString(profit, 2));
         }
      }
   }
   else
   {
      IndicatorRelease(maHandle);
   }
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
         Print("✓ Position closed: ", comment, " - Ticket ", ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK ENTRY SIGNALS                                             |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
   // Check daily limits
   if (totalTradesToday >= Max_Daily_Trades)
   {
      Print("⚠ Daily trade limit reached: ", totalTradesToday, "/", Max_Daily_Trades);
      return;
   }

   // Check daily loss limit
   if (dailyPnL <= -Max_Daily_Loss)
   {
      Print("⚠ Daily loss limit reached: $", DoubleToString(dailyPnL, 2));
      return;
   }

   // NEW: Check session filter
   if (Use_Session_Filter && !IsValidSession())
   {
      return; // Outside trading sessions
   }

   // NEW: Check volume filter
   if (Use_Volume_Filter && !IsVolumeConfirmed())
   {
      return; // Volume too low
   }

   // Check each system
   for (int i = 0; i < 2; i++)
   {
      if (systems[i].enabled)
      {
         if (CanSystemTrade(i))
         {
            int signal = GetSystemSignal(i);
            if (signal != 0)
            {
               // NEW: Apply trend filter - only trade with trend
               if (Use_Trend_Filter && !IsTrendAligned(signal))
               {
                  continue; // Skip counter-trend signals
               }

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
   // Check time between trades
   if (TimeCurrent() - systems[systemIndex].lastTradeTime < Min_Bars_Between * 5 * 60)
      return false;
   
   // Check max trades per system
   if (systems[systemIndex].tradesToday >= Max_Daily_Trades / 2)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| GET SYSTEM SIGNAL                                               |
//+------------------------------------------------------------------+
int GetSystemSignal(int systemIndex)
{
   // System 1: Price deviation from mean with RSI confirmation
   if (systemIndex == 0)
   {
      // Get MA value
      double maArray[];
      ArraySetAsSeries(maArray, true);
      int maHandle = iMA(_Symbol, PERIOD_M5, 20, 0, MODE_SMA, PRICE_CLOSE);
      if (maHandle == INVALID_HANDLE) return 0;
      
      if (CopyBuffer(maHandle, 0, 0, 1, maArray) > 0)
      {
         double mean = maArray[0];
         IndicatorRelease(maHandle);
         
         // Get current price
         double currentArray[];
         ArraySetAsSeries(currentArray, true);
         if (CopyClose(_Symbol, PERIOD_M5, 0, 1, currentArray) > 0)
         {
            double current = currentArray[0];
            double deviation = (current - mean) / mean * 100;
            
            // Get RSI values
            double rsiArray[];
            ArraySetAsSeries(rsiArray, true);
            int rsiHandle = iRSI(_Symbol, PERIOD_M5, 14, PRICE_CLOSE);
            if (rsiHandle == INVALID_HANDLE) return 0;
            
            if (CopyBuffer(rsiHandle, 0, 0, 2, rsiArray) > 0)
            {
               double rsi = rsiArray[0];
               double rsiPrev = rsiArray[1];
               IndicatorRelease(rsiHandle);
               
               // Oversold with bullish divergence
               if (deviation < -0.3 && rsi < 30 && rsi > rsiPrev)
                  return 1; // BUY
               
               // Overbought with bearish divergence
               if (deviation > 0.3 && rsi > 70 && rsi < rsiPrev)
                  return -1; // SELL
            }
            IndicatorRelease(rsiHandle);
         }
      }
      IndicatorRelease(maHandle);
   }
   
   // System 2: Bollinger Bands + MACD
   if (systemIndex == 1)
   {
      // Get Bollinger Bands
      double upperBB[], lowerBB[];
      ArraySetAsSeries(upperBB, true);
      ArraySetAsSeries(lowerBB, true);
      int bbHandle = iBands(_Symbol, PERIOD_M5, 20, 0, 2.0, PRICE_CLOSE);
      if (bbHandle == INVALID_HANDLE) return 0;
      
      if (CopyBuffer(bbHandle, 1, 0, 1, upperBB) > 0 && 
          CopyBuffer(bbHandle, 2, 0, 1, lowerBB) > 0)
      {
         // Get current price
         double currentArray[];
         ArraySetAsSeries(currentArray, true);
         if (CopyClose(_Symbol, PERIOD_M5, 0, 1, currentArray) > 0)
         {
            double current = currentArray[0];
            
            // Get MACD values
            double macdMain[], macdSignal[];
            ArraySetAsSeries(macdMain, true);
            ArraySetAsSeries(macdSignal, true);
            int macdHandle = iMACD(_Symbol, PERIOD_M5, 12, 26, 9, PRICE_CLOSE);
            if (macdHandle == INVALID_HANDLE) 
            {
               IndicatorRelease(bbHandle);
               return 0;
            }
            
            if (CopyBuffer(macdHandle, 0, 0, 2, macdMain) > 0 &&
                CopyBuffer(macdHandle, 1, 0, 2, macdSignal) > 0)
            {
               double macd = macdMain[0];
               double macdPrev = macdMain[1];
               double signal = macdSignal[0];
               double signalPrev = macdSignal[1];
               
               IndicatorRelease(bbHandle);
               IndicatorRelease(macdHandle);
               
               // Buy: Price touches lower BB, MACD bullish crossover
               if (current <= lowerBB[0] && macd > signal && macdPrev <= signalPrev)
                  return 1;
               
               // Sell: Price touches upper BB, MACD bearish crossover
               if (current >= upperBB[0] && macd < signal && macdPrev >= signalPrev)
                  return -1;
            }
            IndicatorRelease(macdHandle);
         }
      }
      IndicatorRelease(bbHandle);
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| EXECUTE TRADE                                                   |
//+------------------------------------------------------------------+
void ExecuteTrade(int systemIndex, int signal)
{
   double entryPrice, slPrice;
   ENUM_ORDER_TYPE orderType;
   
   if (signal == 1) // BUY
   {
      orderType = ORDER_TYPE_BUY;
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // Dynamic stop loss
      if (Use_Dynamic_SL)
      {
         double atrArray[];
         ArraySetAsSeries(atrArray, true);
         int atrHandle = iATR(_Symbol, PERIOD_M5, 14);
         if (atrHandle != INVALID_HANDLE)
         {
            if (CopyBuffer(atrHandle, 0, 0, 1, atrArray) > 0)
            {
               slPrice = entryPrice - (atrArray[0] * ATR_Multiplier);
            }
            IndicatorRelease(atrHandle);
         }
         else
         {
            slPrice = entryPrice - (200 * goldPip);
         }
      }
      else
      {
         slPrice = entryPrice - (200 * goldPip); // 200 pips SL
      }
   }
   else // SELL
   {
      orderType = ORDER_TYPE_SELL;
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // Dynamic stop loss
      if (Use_Dynamic_SL)
      {
         double atrArray[];
         ArraySetAsSeries(atrArray, true);
         int atrHandle = iATR(_Symbol, PERIOD_M5, 14);
         if (atrHandle != INVALID_HANDLE)
         {
            if (CopyBuffer(atrHandle, 0, 0, 1, atrArray) > 0)
            {
               slPrice = entryPrice + (atrArray[0] * ATR_Multiplier);
            }
            IndicatorRelease(atrHandle);
         }
         else
         {
            slPrice = entryPrice + (200 * goldPip);
         }
      }
      else
      {
         slPrice = entryPrice + (200 * goldPip); // 200 pips SL
      }
   }
   
   // Validate stop loss before opening
   if (!ValidateStopLoss(slPrice, entryPrice, (signal == 1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL))
   {
      Print("❌ Trade blocked: Invalid stop loss level");
      return;
   }
   
   // Calculate lot size
   double lotSize = MathMin(Lot_Size, Max_Position_Size);
   
   // Normalize prices
   entryPrice = NormalizeDouble(entryPrice, _Digits);
   slPrice = NormalizeDouble(slPrice, _Digits);
   
   Print("System ", systemIndex + 1, ": ", (signal == 1 ? "BUY" : "SELL"));
   Print("  Entry: $", DoubleToString(entryPrice, 2));
   Print("  Safety SL: $", DoubleToString(slPrice, 2));
   Print("  Lot: ", DoubleToString(lotSize, 2));
   
   // Open trade
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
      Print("✅ Trade opened: Ticket ", result.order);
   }
   else
   {
      Print("❌ Failed to open trade: Error ", result.retcode);
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
      // Reset daily counters
      totalTradesToday = 0;
      dailyPnL = 0;
      
      for (int i = 0; i < 2; i++)
      {
         systems[i].tradesToday = 0;
         systems[i].profitToday = 0;
      }
      
      Print("=== DAILY RESET ===");
      Print("Date: ", TimeToString(TimeCurrent(), TIME_DATE));
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
//| Only BUY if price > H1 200 SMA (uptrend)                        |
//| Only SELL if price < H1 200 SMA (downtrend)                     |
//+------------------------------------------------------------------+
bool IsTrendAligned(int signal)
{
   double maArray[];
   ArraySetAsSeries(maArray, true);
   int maHandle = iMA(_Symbol, PERIOD_H1, Trend_MA_Period, 0, MODE_SMA, PRICE_CLOSE);
   if (maHandle == INVALID_HANDLE) return true; // Allow trade if indicator fails

   if (CopyBuffer(maHandle, 0, 0, 1, maArray) > 0)
   {
      double h1MA = maArray[0];
      IndicatorRelease(maHandle);

      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // BUY only in uptrend (price above H1 200 SMA)
      if (signal == 1 && currentPrice < h1MA)
      {
         Print("⚠ BUY blocked: Price below H1 ", Trend_MA_Period, " SMA (downtrend)");
         return false;
      }

      // SELL only in downtrend (price below H1 200 SMA)
      if (signal == -1 && currentPrice > h1MA)
      {
         Print("⚠ SELL blocked: Price above H1 ", Trend_MA_Period, " SMA (uptrend)");
         return false;
      }
   }
   else
   {
      IndicatorRelease(maHandle);
   }

   return true;
}

//+------------------------------------------------------------------+
//| CHECK IF WITHIN VALID TRADING SESSION                           |
//| London: 08:00-17:00, NY: 13:00-22:00 (broker time)             |
//+------------------------------------------------------------------+
bool IsValidSession()
{
   int currentHour = currentTimeStruct.hour;

   // Check London session
   bool inLondon = (currentHour >= London_Start_Hour && currentHour < London_End_Hour);

   // Check NY session
   bool inNY = (currentHour >= NY_Start_Hour && currentHour < NY_End_Hour);

   return (inLondon || inNY);
}

//+------------------------------------------------------------------+
//| CHECK VOLUME CONFIRMATION                                       |
//| Current volume must be > Volume_Multiplier * 20-bar average    |
//+------------------------------------------------------------------+
bool IsVolumeConfirmed()
{
   long volumeArray[];
   ArraySetAsSeries(volumeArray, true);

   if (CopyTickVolume(_Symbol, PERIOD_M5, 0, 21, volumeArray) < 21)
      return true; // Allow trade if can't get volume

   // Calculate 20-bar average (excluding current bar)
   double avgVolume = 0;
   for (int i = 1; i <= 20; i++)
   {
      avgVolume += (double)volumeArray[i];
   }
   avgVolume /= 20.0;

   double currentVolume = (double)volumeArray[0];

   if (currentVolume < avgVolume * Volume_Multiplier)
   {
      return false; // Volume too low
   }

   return true;
}

//+------------------------------------------------------------------+