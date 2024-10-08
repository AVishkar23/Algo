//+------------------------------------------------------------------+
//|                                                     GATOR EA.mq5 |
//|                      Copyright 2024,Avishkar Deshmane Eric Wakho |
//|                        Expert Advisor based on Supply and Demand |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Eric, Avi."
#property link      "https://www.mql5.com"
#property version   "1.00"

// Include the Hull indicator file
int hull_handle;
double hullBuffer[];

// Include the stochTrendHandle indicator file
int stochTrendHandle;
double stochTrendBuffer[];

#include<Trade\Trade.mqh>
CTrade trade;

#include <Arrays\Array.mqh>

#property strict

input const string TelegramBotToken = "";
input const string ChatId = "";
const string TelegramApiUrl = "https://api.telegram.org"; // this allows URLs

const int UrlDefinedError = 4014;

// Define constants for zone types and strengths
#define ZONE_SUPPORT 1
#define ZONE_RESIST  2
#define ZONE_WEAK      0
#define ZONE_TURNCOAT  1
#define ZONE_UNTESTED  2
#define ZONE_VERIFIED  3
#define ZONE_PROVEN    4

#define UP_POINT 1
#define DN_POINT -1

// Input parameters
input ENUM_TIMEFRAMES      Timeframe = PERIOD_CURRENT;         // Timeframe
input int                  BackLimit = 1000;                   // Back Limit
input double               zone_fuzzfactor = 0.75;             // Zone ATR Factor
input bool                 zone_merge = true;                  // Zone Merge
input bool                 zone_extend = true;                 // Zone Extend
input double               fractal_fast_factor = 3.0;          // Fractal Fast Factor
input double               fractal_slow_factor = 6.0;          // Fractal slow Factor

// Enable/Disable Stoch-Trend filter
input bool useStochTrendFilter = true; // Enable/Disable Stoch-Trend filter

input double               atr_multiplier = 0.35;               // ATR multiplier for stop loss
input int                  max_trades = 2;                     // Maximum number of trades allowed
input double               MinRiskRewardRatio = 1.6;           // Minimum acceptable risk-reward ratio
input double               RiskPercentage = 0.6;                 // Minimum risk in %

input double               InitialDailyBalance;                //Enter Initial Balance at the start of the trading day
input double               AcceptableDailyLoss;                //AcceptableDailyLoss % at the start of the trading day

input ENUM_TIMEFRAMES TFrame  = PERIOD_M5;

enum ENUM_TREND_SETTINGS { AGGRESSIVE, BALANCED, CONSERVATIVE };
input ENUM_TREND_SETTINGS TrendSetting = AGGRESSIVE;  // Default Trend setting is "Balanced"
input ENUM_TIMEFRAMES higherTimeframe = PERIOD_D1;  // Higher timeframe for trade-trend bias

// Inputs for drawing settings
input string string_prefix = "SRRR";              // Change prefix to add multiple indicators to chart
input bool zone_show_weak = false;                // Show Weak Zones
input bool zone_show_untested = false;             // Show Untested Zones
input bool zone_show_turncoat = false;             // Show Broken Zones
input bool zone_solid = true;                     // Fill zone with color
input int zone_linewidth = 1;                     // Zone border width
input ENUM_LINE_STYLE zone_style = STYLE_SOLID;   // Zone border style
input color color_support_weak = clrDarkSlateGray;     // Color for weak support zone
input color color_support_untested = clrSeaGreen;      // Color for untested support zone
input color color_support_verified = clrGreen;         // Color for verified support zone
input color color_support_proven = clrLimeGreen;       // Color for proven support zone
input color color_support_turncoat = clrOliveDrab;     // Color for turncoat(broken) support zone
input color color_resist_weak = clrIndigo;             // Color for weak resistance zone
input color color_resist_untested = clrOrchid;         // Color for untested resistance zone
input color color_resist_verified = clrCrimson;        // Color for verified resistance zone
input color color_resist_proven = clrRed;              // Color for proven resistance zone
input color color_resist_turncoat = clrDarkOrange;     // Color for broken resistance zone

string upTrendLineName = "UpTrendLine";
string downTrendLineName = "DownTrendLine";

// MACD settings
//input int InpFastEMA = 12;               // Fast EMA period
//input int InpSlowEMA = 26;               // Slow EMA period
//input int InpSignalSMA = 9;              // Signal SMA period
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE; // Applied price

// Global variables
ENUM_TIMEFRAMES timeframe;
double FastDnPts[], FastUpPts[];
double SlowDnPts[], SlowUpPts[];
double zone_hi[1000], zone_lo[1000];
int    zone_start[1000], zone_hits[1000], zone_type[1000], zone_strength[1000], zone_count = 0;
bool   zone_turn[1000];
string prefix = string_prefix + "#";

int iATR_handle;
double ATR[];
int cnt = 0;
bool try_again = false;

// MACD handles and buffers
int ExtFastMaHandle;
int ExtSlowMaHandle;
double ExtMacdBuffer[];
double ExtSignalBuffer[];

// Nearest zones variables
double ner_lo_zone_P1[];
double ner_lo_zone_P2[];
double ner_hi_zone_P1[];
double ner_hi_zone_P2[];
double ner_hi_zone_strength[];
double ner_lo_zone_strength[];
double ner_price_inside_zone[];
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   EventSetTimer(60);  // Set a timer to call the function every 60 seconds

   if(Timeframe == PERIOD_CURRENT)
      timeframe = Period();
   else
      timeframe = Timeframe;

   iATR_handle = iATR(NULL, timeframe, 7);

   ArraySetAsSeries(SlowDnPts, true);
   ArraySetAsSeries(SlowUpPts, true);
   ArraySetAsSeries(FastDnPts, true);
   ArraySetAsSeries(FastUpPts, true);

   CheckAndDrawTrendLines();  // Initial call to the function

// The Hull indicator
   string hull_name = "hull_"; // Exact name as it appears in directory
   hull_handle = iCustom(_Symbol, PERIOD_CURRENT, hull_name);
   if(hull_handle == INVALID_HANDLE)
     {
      Print("Error: Unable to initialize Hull indicator!");
      return (INIT_FAILED);
     }

// The XK-KEY Stoch-Trend_v2 indicator
   string stochTrendName = "XK-KEY Stoch-Trend_v2"; // Exact name as it appears in directory
   stochTrendHandle = iCustom(_Symbol, PERIOD_CURRENT, stochTrendName);
   if(stochTrendHandle == INVALID_HANDLE)
     {
      Print("Error: Unable to initialize XK-KEY Stoch-Trend_v2 indicator!");
      return (INIT_FAILED);
     }
   return (INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();  // Kill the timer on deinitialization

// Delete trend lines
   ObjectDelete(0, upTrendLineName);
   ObjectDelete(0, downTrendLineName);

// Release Hull indicator handle
   if(hull_handle != INVALID_HANDLE)
     {
      IndicatorRelease(hull_handle);
     }

// Release XK-KEY Stoch-Trend_v2 indicator handle
   if(stochTrendHandle != INVALID_HANDLE)
     {
      IndicatorRelease(stochTrendHandle);
     }
  }

int        ExtDepthBars;
int        MinTrendBars;
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(NewBar() || try_again)
     {
      FastFractals();
      SlowFractals();
      FindZones();
      CheckEntries();
      tradePlaced = false;
      DrawZones();
      UpdateStopLosses();
      CheckMartingale();
      CheckDailyProfitAndRemoveEA();

      switch(TrendSetting)
        {
         case AGGRESSIVE:
            ExtDepthBars = 14;
            MinTrendBars = 10;
            break;
         case BALANCED:
            ExtDepthBars = 21;
            MinTrendBars = 15;
            break;
         case CONSERVATIVE:
            ExtDepthBars = 50;
            MinTrendBars = 20;
            break;
        }
      CheckAndDrawTrendLines(); // Pass the selected values to the function
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   CheckAndDrawTrendLines();  // Call the function on every timer event
  }

bool tradePlaced = false;
//+------------------------------------------------------------------+
//| CheckEntries()                                                   |
//+------------------------------------------------------------------+
int zoneTradeCount[];
bool stopLossTriggeredInZone[];
int maxTradesPerZone = 1; // Define the maximum number of trades allowed per zone

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| CheckEntries()                                                   |
//+------------------------------------------------------------------+
void CheckEntries()
  {
   double Close[];
   ArraySetAsSeries(Close, true);
   int bars = Bars(Symbol(), timeframe);
   CopyClose(Symbol(), timeframe, 0, bars, Close); // Copy all available bars into Close

   double atr = iATR(NULL, timeframe, 14);

   if(bars < 100)   // Check if there are enough bars for calculations
      return;

// Initialize arrays to avoid out of range errors
   if(ArraySize(zoneTradeCount) != zone_count)
     {
      ArrayResize(zoneTradeCount, zone_count);
      ArrayInitialize(zoneTradeCount, 0);
     }
   if(ArraySize(stopLossTriggeredInZone) != zone_count)
     {
      ArrayResize(stopLossTriggeredInZone, zone_count);
      ArrayInitialize(stopLossTriggeredInZone, false);
     }

   double hmaBuffer[];
   bool hmaBuySignal = false;
   bool hmaSellSignal = false;
   bool stochTrendBuySignal = false;
   bool stochTrendSellSignal = false;

   if(CopyBuffer(hull_handle, 0, 0, 3, hmaBuffer) <= 0)
     {
      Print("Error copying Hull indicator buffer");
      return;
     }

// Ensure the buffer has at least 2 elements
   if(ArraySize(hmaBuffer) < 2)
     {
      Print("HMA buffer size is less than 2");
      return;
     }

// Check for HMA signals
   if(hmaBuffer[0] > hmaBuffer[1])
      hmaBuySignal = true;
   if(hmaBuffer[0] < hmaBuffer[1])
      hmaSellSignal = true;

   if(useStochTrendFilter)
     {
      //double stochTrendBuffer[];
      if(CopyBuffer(stochTrendHandle, 0, 0, 3, stochTrendBuffer) <= 0)
        {
         Print("Error copying XK-KEY Stoch-Trend_v2 indicator buffer");
         return;
        }

      // Ensure the buffer has at least 1 element
      if(ArraySize(stochTrendBuffer) < 1)
        {
         Print("Stoch-Trend buffer size is less than 1");
         return;
        }

      // Check for Stoch-Trend signals
      if(stochTrendBuffer[0] > 0)
         stochTrendBuySignal = true;
      if(stochTrendBuffer[0] < 0)
         stochTrendSellSignal = true;
     }

   for(int i = 0; i < zone_count; i++)
     {
      // Ensure the zone arrays have sufficient elements
      if(i >= ArraySize(zone_lo) || i >= ArraySize(zone_hi) || i >= ArraySize(zone_strength) || i >= ArraySize(zone_type))
        {
         Print("Zone arrays are not properly sized");
         return;
        }

      if(Close[0] >= zone_lo[i] && Close[0] < zone_hi[i] && zone_strength[i] == ZONE_VERIFIED)
        {
         if(!tradePlaced)
           {
            if(zone_type[i] == ZONE_SUPPORT && hmaBuySignal)
              {
               if((!useStochTrendFilter || (useStochTrendFilter && stochTrendBuySignal)) && zoneTradeCount[i] < maxTradesPerZone && !stopLossTriggeredInZone[i])
                 {
                  PlaceTrade(ORDER_TYPE_BUY, Close[0], atr, zone_lo[i], i);
                  tradePlaced = true;
                  zoneTradeCount[i]++;
                 }
              }
            else
               if(zone_type[i] == ZONE_RESIST && hmaSellSignal)
                 {
                  if((!useStochTrendFilter || (useStochTrendFilter && stochTrendSellSignal)) && zoneTradeCount[i] < maxTradesPerZone && !stopLossTriggeredInZone[i])
                    {
                     PlaceTrade(ORDER_TYPE_SELL, Close[0], atr, zone_hi[i], i);
                     tradePlaced = true;
                     zoneTradeCount[i]++;
                    }
                 }
           }

         if(tradePlaced)
           {
            ChartRedraw(); // Make sure the chart is up to date
            ChartScreenShot(0, "MyScreenshot.png", 1024, 768, ALIGN_RIGHT);

            string message = "New " + ((zone_type[i] == ZONE_SUPPORT) ? "BUY" : "SELL") + " trade placed for " + Symbol() + "\n" +
                             "Your Current Profit = $" + (string)AccountInfoDouble(ACCOUNT_BALANCE) + "\n" +
                             TimeToString(TimeLocal());

            SendTelegramMessage(TelegramApiUrl, TelegramBotToken, ChatId, message);
            SendTelegramMessage(TelegramApiUrl, TelegramBotToken, ChatId, message, "MyScreenshot.png");
           }
        }
     }
  }
//+------------------------------------------------------------------+
//|CalculateSMA                                                      |
//+------------------------------------------------------------------+
void CalculateSMA(double &inputBuffer[], double &outputBuffer[], int length, int period)
  {
   for(int i = 0; i < length; i++)
     {
      double sum = 0;
      int count = 0;
      for(int j = i; j < i + period && j < length; j++)
        {
         sum += inputBuffer[j];
         count++;
        }
      if(count > 0)
        {
         outputBuffer[i] = sum / count;
        }
     }
  }
//+------------------------------------------------------------------+
//| Calculate slopes for trade management                            |
//+------------------------------------------------------------------+
void CalculateSlopes(double &upperSlope, double &lowerSlope)
  {
   int higherLastHighIndex = iHighest(NULL, higherTimeframe, MODE_HIGH, ExtDepthBars, 0);
   int higherLastLowIndex = iLowest(NULL, higherTimeframe, MODE_LOW, ExtDepthBars, 0);
   datetime higherLastHighTime = iTime(NULL, higherTimeframe, higherLastHighIndex);
   datetime higherLastLowTime = iTime(NULL, higherTimeframe, higherLastLowIndex);

   double higherLastHighPrice = iHigh(NULL, higherTimeframe, higherLastHighIndex);
   double higherLastLowPrice = iLow(NULL, higherTimeframe, higherLastLowIndex);

   upperSlope = (higherLastHighPrice - iHigh(NULL, higherTimeframe, iHighest(NULL, higherTimeframe, MODE_HIGH, ExtDepthBars, higherLastHighIndex + 1))) /
                ((TimeCurrent() - higherLastHighTime) / 3600.0); // Slope in USD/hour
   lowerSlope = (higherLastLowPrice - iLow(NULL, higherTimeframe, iLowest(NULL, higherTimeframe, MODE_LOW, ExtDepthBars, higherLastLowIndex + 1))) /
                ((TimeCurrent() - higherLastLowTime) / 3600.0); // Slope in USD/hour
  }


// Constants for Stochastic Trend overbought/oversold levels
input double STOCH_OVERBOUGHT_LEVEL = 60.0;
input double STOCH_OVERSOLD_LEVEL = 40.0;

double trailingStopDistance; // Actual trailing stop distance in pips
double stopLossArray[]; // Array to store stop-loss prices

//+------------------------------------------------------------------+
//| Place trade function                                             |
//+------------------------------------------------------------------+
void PlaceTrade(int order_type, double price, double atr, double zone_border, int zone_index)
  {
   double stop_loss, take_profit;
   int current_trades = PositionsTotal();

   double AccountBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   double lot = AdjustLotSizeBasedOnEquityAndRisk(order_type, price, atr, zone_border, zone_index, AccountBalance);

   if(current_trades >= max_trades)
     {
      string zone_str = (zone_type[zone_index] == ZONE_SUPPORT) ? "Support" : "Resistance";
      Print("Maximum trades reached. Check " + zone_str + " zone at index " + IntegerToString(zone_index));
      return;
     }
   string symbol = _Symbol;

   int total_positions = PositionsTotal();

   double risk_reward_ratio = MinRiskRewardRatio * (total_positions + 1);

   if(order_type == ORDER_TYPE_BUY)
     {
      double askPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
      stop_loss = zone_border - (atr * atr_multiplier); //zone_border;
      take_profit = FindZoneWithRiskReward(zone_index, ZONE_RESIST, order_type, price, stop_loss);
      if(take_profit == 0)
         take_profit = askPrice + ((askPrice - stop_loss) * risk_reward_ratio);

      if(!trade.Buy(lot, NULL, askPrice, stop_loss, take_profit, "Bought at Demand"))
        {
         Print("Error opening buy trade: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        }
      else
        {
         Print("Buy trade placed successfully.");
         if(PositionsTotal() > 0)
           {
            ArrayResize(stopLossArray, PositionsTotal());
            stopLossArray[PositionsTotal() - 1] = stop_loss; // Store stop-loss price
           }
         else
           {
            Print("No positions to store stop loss for.");
           }
        }
     }
   else
      if(order_type == ORDER_TYPE_SELL)
        {
         double bidPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
         stop_loss = zone_border + (atr * atr_multiplier);//zone_border;
         take_profit = FindZoneWithRiskReward(zone_index, ZONE_SUPPORT, order_type, price, stop_loss);
         if(take_profit == 0)
            take_profit = bidPrice - ((stop_loss - bidPrice) * risk_reward_ratio);

         if(!trade.Sell(lot, NULL, bidPrice, stop_loss, take_profit, "Sold at Supply"))
           {
            Print("Error opening sell trade: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
           }
         else
           {
            Print("Sell trade placed successfully.");
            if(PositionsTotal() > 0)
              {
               ArrayResize(stopLossArray, PositionsTotal());
               stopLossArray[PositionsTotal() - 1] = stop_loss; // Store stop-loss price
              }
            else
              {
               Print("No positions to store stop loss for.");
              }
           }
        }
   UpdateStopLosses();
  }
//+------------------------------------------------------------------+
//| Adjust stop loss based on price movement                         |
//+------------------------------------------------------------------+
void AdjustStopLoss(int position_index, double entry_price, double take_profit)
  {
   if(position_index < 0 || position_index >= ArraySize(stopLossArray))
     {
      // Handle the error appropriately
      return;
     }

   ulong ticket = PositionGetTicket(position_index);
   if(PositionSelectByTicket(ticket))
     {
      double current_price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double stop_loss = stopLossArray[position_index]; // Get the stored stop-loss price

      double newStopLoss = stop_loss;
      bool inZone = false;

      double distance_to_tp = MathAbs(take_profit - entry_price);
      double trailing_increment = distance_to_tp * 0.1; // 10% of the take-profit distance

      // Check if the price enters any zone
      for(int i = 0; i < zone_count; i++)
        {
         if(i >= ArraySize(zone_lo) || i >= ArraySize(zone_hi))
           {
            // Handle the error appropriately
            return;
           }

         if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && current_price >= zone_lo[i] && current_price < zone_hi[i]) ||
            (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && current_price <= zone_hi[i] && current_price > zone_lo[i]))
           {
            newStopLoss = entry_price + ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 10 * _Point : -10 * _Point);
            inZone = true;
            break;
           }
        }

      // If the price is in a zone, move stop loss a few pips above break-even
      if(inZone)
        {
         newStopLoss = entry_price + ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 10 * _Point : -10 * _Point);
        }

      // If the price keeps moving up, move the stop loss to halfway between the current price and the entry price
      if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && current_price > entry_price) ||
         (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && current_price < entry_price))
        {
         double halfway_price = (current_price + entry_price) / 2.0;
         if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && current_price >= halfway_price) ||
            (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && current_price <= halfway_price))
           {
            newStopLoss = halfway_price;
           }
        }

      // Ensure the stop loss is incremented by 10% as the price continues to move favorably
      if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && current_price > entry_price) ||
         (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && current_price < entry_price))
        {
         double distance_moved = MathAbs(current_price - entry_price);
         int increments = (int)MathFloor(distance_moved / trailing_increment); // Ensure no loss of data due to type conversion
         newStopLoss = entry_price + ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? increments * trailing_increment : -increments * trailing_increment);
        }

      // Update the stop loss if a new stop loss is better
      if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && newStopLoss > stop_loss) ||
         (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && newStopLoss < stop_loss))
        {
         trade.PositionModify(ticket, newStopLoss, take_profit);
         stopLossArray[position_index] = newStopLoss; // Update the stop-loss price in the array
        }
     }
  }
//+------------------------------------------------------------------+
//| Update stop losses for all positions                             |
//+------------------------------------------------------------------+
void UpdateStopLosses()
  {
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double take_profit = PositionGetDouble(POSITION_TP);
         AdjustStopLoss(i, entry_price, take_profit);
        }
     }
  }
//+------------------------------------------------------------------+
//| CheckMartingale()                                                |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| CheckMartingale()                                                |
//+------------------------------------------------------------------+
void CheckMartingale()
  {
   double atr = iATR(NULL, PERIOD_CURRENT, 14); // Calculate ATR for the current timeframe

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i); // Get the ticket number of the position
      if(PositionSelectByTicket(ticket))   // Select the position by its ticket number
        {
         double stop_loss_price = PositionGetDouble(POSITION_SL); // Get the stop loss price of the position
         double current_price = PositionGetDouble(POSITION_PRICE_OPEN); // Get the opening price of the position
         int order_type = (int)PositionGetInteger(POSITION_TYPE); // Get the type of the position (buy/sell)

         // Check if stop loss is hit
         if((order_type == POSITION_TYPE_BUY && SymbolInfoDouble(Symbol(), SYMBOL_BID) <= stop_loss_price) ||
            (order_type == POSITION_TYPE_SELL && SymbolInfoDouble(Symbol(), SYMBOL_ASK) >= stop_loss_price))
           {
            double lot_size = PositionGetDouble(POSITION_VOLUME) * 2; // Double the lot size for Martingale
            double new_risk_reward_ratio = MinRiskRewardRatio / 2;    // Halve the risk-reward ratio
            double new_stop_loss, new_take_profit;

            if(order_type == POSITION_TYPE_BUY)
              {
               // For a BUY position, place a SELL Martingale trade
               double new_price = SymbolInfoDouble(Symbol(), SYMBOL_BID); // Get current bid price
               new_stop_loss = new_price + (atr * atr_multiplier); // Calculate new stop loss
               new_take_profit = new_price - ((new_stop_loss - new_price) * new_risk_reward_ratio); // Calculate new take profit
               if(!trade.Sell(lot_size, Symbol(), new_price, new_stop_loss, new_take_profit, "Martingale Sell"))
                  Print("Error opening Martingale sell trade: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
              }
            else
               if(order_type == POSITION_TYPE_SELL)
                 {
                  // For a SELL position, place a BUY Martingale trade
                  double new_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK); // Get current ask price
                  new_stop_loss = new_price - (atr * atr_multiplier); // Calculate new stop loss
                  new_take_profit = new_price + ((new_price - new_stop_loss) * new_risk_reward_ratio); // Calculate new take profit
                  if(!trade.Buy(lot_size, Symbol(), new_price, new_stop_loss, new_take_profit, "Martingale Buy"))
                     Print("Error opening Martingale buy trade: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
                 }

            Print("Martingale trade placed successfully.");
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Function to find zone with risk reward                           |
//+------------------------------------------------------------------+
double FindZoneWithRiskReward(int current_index, int target_zone_type, int order_type, double entry_price, double stop_loss)
  {
   double risk_reward_ratio = MinRiskRewardRatio;
   for(int i = 0; i < zone_count; i++)
     {
      if(zone_type[i] == target_zone_type)
        {
         double potential_take_profit = (target_zone_type == ZONE_SUPPORT) ? zone_lo[i] : zone_hi[i];
         double potential_risk_reward = (order_type == ORDER_TYPE_BUY) ?
                                        (potential_take_profit - entry_price) / (entry_price - stop_loss) :
                                        (entry_price - potential_take_profit) / (stop_loss - entry_price);

         if(potential_risk_reward >= risk_reward_ratio)
           {
            return potential_take_profit;
           }
        }
     }
   return 0; // Default value if no suitable zone found
  }

//+------------------------------------------------------------------+
//| Find zones function                                              |
//+------------------------------------------------------------------+
void FindZones()
  {
   int i, j, shift, bustcount = 0, testcount = 0;
   double hival, loval;
   bool turned = false, hasturned = false;
   double temp_hi[1000], temp_lo[1000];
   int temp_start[1000], temp_hits[1000], temp_strength[1000], temp_count = 0;
   bool temp_turn[1000], temp_merge[1000];
   int merge1[1000], merge2[1000], merge_count = 0;

   shift = MathMin(Bars(Symbol(), timeframe) - 1, BackLimit + cnt);
   shift = MathMin(shift, ArraySize(FastUpPts) - 1);
   double Close[], High[], Low[];
   ArraySetAsSeries(Close, true);
   CopyClose(Symbol(), timeframe, 0, shift + 1, Close);
   ArraySetAsSeries(High, true);
   CopyHigh(Symbol(), timeframe, 0, shift + 1, High);
   ArraySetAsSeries(Low, true);
   CopyLow(Symbol(), timeframe, 0, shift + 1, Low);
   ArraySetAsSeries(ATR, true);

   if(CopyBuffer(iATR_handle, 0, 0, shift + 1, ATR) == -1)
     {
      try_again = true;
      return;
     }
   else
     {
      try_again = false;
     }

   for(int ii = shift; ii > cnt + 5; ii--)
     {
      double atr = ATR[ii];
      double fu = atr / 2 * zone_fuzzfactor;
      bool isWeak;
      bool touchOk = false;
      bool isBust = false;

      if(FastUpPts[ii] > 0.001)
        {
         isWeak = true;
         if(SlowUpPts[ii] > 0.001)
            isWeak = false;
         hival = High[ii];
         if(zone_extend == true)
            hival += fu;
         loval = MathMax(MathMin(Close[ii], High[ii] - fu), High[ii] - fu * 2);
         turned = false;
         hasturned = false;
         isBust = false;
         bustcount = 0;
         testcount = 0;

         for(i = ii - 1; i >= cnt + 0; i--)
           {
            if((turned == false && FastUpPts[i] >= loval && FastUpPts[i] <= hival) ||
               (turned == true && FastDnPts[i] <= hival && FastDnPts[i] >= loval))
              {
               touchOk = true;
               for(j = i + 1; j < i + 11; j++)
                 {
                  if((turned == false && FastUpPts[j] >= loval && FastUpPts[j] <= hival) ||
                     (turned == true && FastDnPts[j] <= hival && FastDnPts[j] >= loval))
                    {
                     touchOk = false;
                     break;
                    }
                 }
               if(touchOk == true)
                 {
                  bustcount = 0;
                  testcount++;
                 }
              }
            if((turned == false && High[i] > hival) ||
               (turned == true && Low[i] < loval))
              {
               bustcount++;
               if(bustcount > 1 || isWeak == true)
                 {
                  isBust = true;
                  break;
                 }
               if(turned == true)
                  turned = false;
               else
                  if(turned == false)
                     turned = true;
               hasturned = true;
               testcount = 0;
              }
           }
         if(isBust == false)
           {
            temp_hi[temp_count] = hival;
            temp_lo[temp_count] = loval;
            temp_turn[temp_count] = hasturned;
            temp_hits[temp_count] = testcount;
            temp_start[temp_count] = ii;
            temp_merge[temp_count] = false;

            if(testcount > 3)
               temp_strength[temp_count] = ZONE_PROVEN;
            else
               if(testcount > 0)
                  temp_strength[temp_count] = ZONE_VERIFIED;
               else
                  if(hasturned == true)
                     temp_strength[temp_count] = ZONE_TURNCOAT;
                  else
                     if(isWeak == false)
                        temp_strength[temp_count] = ZONE_UNTESTED;
                     else
                        temp_strength[temp_count] = ZONE_WEAK;

            temp_count++;
           }
        }
      else
         if(FastDnPts[ii] > 0.001)
           {
            isWeak = true;
            if(SlowDnPts[ii] > 0.001)
               isWeak = false;
            loval = Low[ii];
            if(zone_extend == true)
               loval -= fu;
            hival = MathMin(MathMax(Close[ii], Low[ii] + fu), Low[ii] + fu * 2);
            turned = false;
            hasturned = false;
            bustcount = 0;
            testcount = 0;
            isBust = false;

            for(i = ii - 1; i >= cnt + 0; i--)
              {
               if((turned == true && FastUpPts[i] >= loval && FastUpPts[i] <= hival) ||
                  (turned == false && FastDnPts[i] <= hival && FastDnPts[i] >= loval))
                 {
                  touchOk = true;
                  for(j = i + 1; j < i + 11; j++)
                    {
                     if((turned == true && FastUpPts[j] >= loval && FastUpPts[j] <= hival) ||
                        (turned == false && FastDnPts[j] <= hival && FastDnPts[j] >= loval))
                       {
                        touchOk = false;
                        break;
                       }
                    }
                  if(touchOk == true)
                    {
                     bustcount = 0;
                     testcount++;
                    }
                 }
               if((turned == true && High[i] > hival) ||
                  (turned == false && Low[i] < loval))
                 {
                  bustcount++;
                  if(bustcount > 1 || isWeak == true)
                    {
                     isBust = true;
                     break;
                    }
                  if(turned == true)
                     turned = false;
                  else
                     if(turned == false)
                        turned = true;
                  hasturned = true;
                  testcount = 0;
                 }
              }
            if(isBust == false)
              {
               temp_hi[temp_count] = hival;
               temp_lo[temp_count] = loval;
               temp_turn[temp_count] = hasturned;
               temp_hits[temp_count] = testcount;
               temp_start[temp_count] = ii;
               temp_merge[temp_count] = false;

               if(testcount > 3)
                  temp_strength[temp_count] = ZONE_PROVEN;
               else
                  if(testcount > 0)
                     temp_strength[temp_count] = ZONE_VERIFIED;
                  else
                     if(hasturned == true)
                        temp_strength[temp_count] = ZONE_TURNCOAT;
                     else
                        if(isWeak == false)
                           temp_strength[temp_count] = ZONE_UNTESTED;
                        else
                           temp_strength[temp_count] = ZONE_WEAK;

               temp_count++;
              }
           }
     }

   if(zone_merge == true)
     {
      merge_count = 1;
      int iterations = 0;
      while(merge_count > 0 && iterations < 3)
        {
         merge_count = 0;
         iterations++;
         for(i = 0; i < temp_count; i++)
            temp_merge[i] = false;
         for(i = 0; i < temp_count - 1; i++)
           {
            if(temp_hits[i] == -1 || temp_merge[i] == true)
               continue;
            for(j = i + 1; j < temp_count; j++)
              {
               if(temp_hits[j] == -1 || temp_merge[j] == true)
                  continue;
               if((temp_hi[i] >= temp_lo[j] && temp_hi[i] <= temp_hi[j]) ||
                  (temp_lo[i] <= temp_hi[j] && temp_lo[i] >= temp_lo[j]) ||
                  (temp_hi[j] >= temp_lo[i] && temp_hi[j] <= temp_hi[i]) ||
                  (temp_lo[j] <= temp_hi[i] && temp_lo[j] >= temp_lo[i]))
                 {
                  merge1[merge_count] = i;
                  merge2[merge_count] = j;
                  temp_merge[i] = true;
                  temp_merge[j] = true;
                  merge_count++;
                 }
              }
           }
         for(i = 0; i < merge_count; i++)
           {
            int target = merge1[i];
            int source = merge2[i];
            temp_hi[target] = MathMax(temp_hi[target], temp_hi[source]);
            temp_lo[target] = MathMin(temp_lo[target], temp_lo[source]);
            temp_hits[target] += temp_hits[source];
            temp_start[target] = MathMax(temp_start[target], temp_start[source]);
            temp_strength[target] = MathMax(temp_strength[target], temp_strength[source]);

            if(temp_hits[target] > 3)
               temp_strength[target] = ZONE_PROVEN;
            if(temp_hits[target] == 0 && temp_turn[target] == false)
              {
               temp_hits[target] = 1;
               if(temp_strength[target] < ZONE_VERIFIED)
                  temp_strength[target] = ZONE_VERIFIED;
              }
            if(temp_turn[target] == false || temp_turn[source] == false)
               temp_turn[target] = false;
            if(temp_turn[target] == true)
               temp_hits[target] = 0;
            temp_hits[source] = -1;
           }
        }
     }

   zone_count = 0;

   for(i = 0; i < temp_count; i++)
     {
      if(temp_hits[i] >= 0 && zone_count < 1000)
        {
         if(temp_strength[i] == ZONE_PROVEN || temp_strength[i] == ZONE_VERIFIED || temp_strength[i] == ZONE_UNTESTED)
           {
            zone_hi[zone_count] = temp_hi[i];
            zone_lo[zone_count] = temp_lo[i];
            zone_hits[zone_count] = temp_hits[i];
            zone_turn[zone_count] = temp_turn[i];
            zone_start[zone_count] = temp_start[i];
            zone_strength[zone_count] = temp_strength[i];

            if(zone_hi[zone_count] < Close[cnt + 0])
               zone_type[zone_count] = ZONE_SUPPORT;
            else
               if(zone_lo[zone_count] > Close[cnt + 0])
                  zone_type[zone_count] = ZONE_RESIST;
               else
                 {
                  int sh = MathMin(Bars(Symbol(), timeframe) - 1, BackLimit + cnt);
                  for(j = cnt + 1; j < sh; j++)
                    {
                     if(Close[j] < zone_lo[zone_count])
                       {
                        zone_type[zone_count] = ZONE_RESIST;
                        break;
                       }
                     else
                        if(Close[j] > zone_hi[zone_count])
                          {
                           zone_type[zone_count] = ZONE_SUPPORT;
                           break;
                          }
                    }
                  if(j == sh)
                     zone_type[zone_count] = ZONE_SUPPORT;
                 }
            zone_count++;
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Detects if a new bar has formed                                  |
//+------------------------------------------------------------------+
bool NewBar()
  {
   static datetime LastTime;
   if(iTime(Symbol(), timeframe, 0) != LastTime)
     {
      LastTime = iTime(Symbol(), timeframe, 0);
      return (true);
     }
   else
      return (false);
  }
//+------------------------------------------------------------------+
//| Fast fractals calculation                                        |
//+------------------------------------------------------------------+
void FastFractals()
  {
   int shift;
   int limit = MathMin(Bars(Symbol(), timeframe) - 1, BackLimit + cnt);
   limit = MathMin(limit, BackLimit + cnt);
   int P1 = int(timeframe * fractal_fast_factor);

   double High[], Low[];
   ArrayResize(FastUpPts, limit + 1);
   ArrayResize(FastDnPts, limit + 1);

   ArraySetAsSeries(High, true);
   CopyHigh(Symbol(), timeframe, 0, limit + 1, High);
   ArraySetAsSeries(Low, true);
   CopyLow(Symbol(), timeframe, 0, limit + 1, Low);

   FastUpPts[0] = 0.0;
   FastUpPts[1] = 0.0;
   FastDnPts[0] = 0.0;
   FastDnPts[1] = 0.0;

   for(shift = limit; shift > cnt + 1; shift--)
     {
      if(Fractal(UP_POINT, P1, shift) == true)
         FastUpPts[shift] = High[shift];
      else
         FastUpPts[shift] = 0.0;

      if(Fractal(DN_POINT, P1, shift) == true)
         FastDnPts[shift] = Low[shift];
      else
         FastDnPts[shift] = 0.0;
     }
  }
//+------------------------------------------------------------------+
//| Slow fractals calculation                                        |
//+------------------------------------------------------------------+
void SlowFractals()
  {
   int shift;
   int limit = MathMin(Bars(Symbol(), timeframe) - 1, BackLimit + cnt);
   limit = MathMin(limit, BackLimit + cnt);
   int P2 = int(timeframe * fractal_slow_factor);

   double High[], Low[];
   ArrayResize(SlowUpPts, limit + 1);
   ArrayResize(SlowDnPts, limit + 1);

   ArraySetAsSeries(High, true);
   CopyHigh(Symbol(), timeframe, 0, limit + 1, High);
   ArraySetAsSeries(Low, true);
   CopyLow(Symbol(), timeframe, 0, limit + 1, Low);

   SlowUpPts[0] = 0.0;
   SlowUpPts[1] = 0.0;
   SlowDnPts[0] = 0.0;
   SlowDnPts[1] = 0.0;

   for(shift = limit; shift > cnt + 1; shift--)
     {
      if(Fractal(UP_POINT, P2, shift) == true)
         SlowUpPts[shift] = High[shift];
      else
         SlowUpPts[shift] = 0.0;

      if(Fractal(DN_POINT, P2, shift) == true)
         SlowDnPts[shift] = Low[shift];
      else
         SlowDnPts[shift] = 0.0;
     }
  }
//+------------------------------------------------------------------+
//| Fractal function                                                 |
//+------------------------------------------------------------------+
bool Fractal(int M, int P, int shift)
  {
   if(timeframe > P)
      P = timeframe;
   P = int(P / int(timeframe) * 2 + MathCeil(P / timeframe / 2));
   if(shift < P)
      return false;
   if(shift > Bars(Symbol(), timeframe) - P - 1)
      return false;

   double High[], Low[];

   ArraySetAsSeries(High, true);
   ArraySetAsSeries(Low, true);

   int copiedHigh = CopyHigh(Symbol(), timeframe, 0, shift + P + 1, High);
   int copiedLow = CopyLow(Symbol(), timeframe, 0, shift + P + 1, Low);

   if(copiedHigh <= 0 || copiedLow <= 0)
      return false;

   for(int i = 1; i <= P; i++)
     {
      if(M == UP_POINT)
        {
         if(High[shift + i] > High[shift])
            return false;
         if(High[shift - i] >= High[shift])
            return false;
        }
      if(M == DN_POINT)
        {
         if(Low[shift + i] < Low[shift])
            return false;
         if(Low[shift - i] <= Low[shift])
            return false;
        }
     }
   return true;
  }
//+------------------------------------------------------------------+
//| DrawZones function to draw support and resistance zones          |
//+------------------------------------------------------------------+
string mycomment="Updating Chart...";
void DrawZones()
  {
   ArrayResize(ner_hi_zone_P1, zone_count);
   ArrayResize(ner_hi_zone_P2, zone_count);
   ArrayResize(ner_lo_zone_P1, zone_count);
   ArrayResize(ner_lo_zone_P2, zone_count);
   ArrayResize(ner_hi_zone_strength, zone_count);
   ArrayResize(ner_lo_zone_strength, zone_count);
   ArrayResize(ner_price_inside_zone, zone_count);

   double lower_nerest_zone_P1 = 0;
   double lower_nerest_zone_P2 = 0;
   double higher_nerest_zone_P1 = 99999;
   double higher_nerest_zone_P2 = 99999;
   double higher_zone_type = 0;
   double higher_zone_strength = 0;
   double lower_zone_type = 0;
   double lower_zone_strength = 0;

   for(int i = 0; i < zone_count; i++)
     {
      if(zone_strength[i] == ZONE_WEAK && !zone_show_weak)
         continue;
      if(zone_strength[i] == ZONE_UNTESTED && !zone_show_untested)
         continue;
      if(zone_strength[i] == ZONE_TURNCOAT && !zone_show_turncoat)
         continue;

      string s;
      if(zone_type[i] == ZONE_SUPPORT)
         s = prefix + "S" + string(i) + " Strength=";
      else
         s = prefix + "R" + string(i) + " Strength=";

      if(zone_strength[i] == ZONE_PROVEN)
         s = s + "Proven, Test Count=" + string(zone_hits[i]);
      else
         if(zone_strength[i] == ZONE_VERIFIED)
            s = s + "Verified, Test Count=" + string(zone_hits[i]);
         else
            if(zone_strength[i] == ZONE_UNTESTED)
               s = s + "Untested";
            else
               if(zone_strength[i] == ZONE_TURNCOAT)
                  s = s + "Turncoat";
               else
                  s = s + "Weak";

      datetime Time[];
      if(CopyTime(Symbol(), timeframe, 0, zone_start[i] + 1, Time) == -1)
        {
         Comment(mycomment);
         return;
        }
      else
        {
         if(StringFind(ChartGetString(0, CHART_COMMENT), mycomment) >= 0)
            Comment("");
        }
      ArraySetAsSeries(Time, true);
      datetime current_time, start_time;
      current_time = iTime(NULL, 0, 0);
      start_time = (iTime(NULL, 0, TerminalInfoInteger(TERMINAL_MAXBARS) - 1) > Time[zone_start[i]]) ? iTime(NULL, 0, TerminalInfoInteger(TERMINAL_MAXBARS) - 1) : Time[zone_start[i]];

      ObjectCreate(0, s, OBJ_RECTANGLE, 0, 0, 0, 0, 0);
      ObjectSetInteger(0, s, OBJPROP_TIME, 0, start_time);
      ObjectSetInteger(0, s, OBJPROP_TIME, 1, current_time);
      ObjectSetDouble(0, s, OBJPROP_PRICE, 0, zone_hi[i]);
      ObjectSetDouble(0, s, OBJPROP_PRICE, 1, zone_lo[i]);
      ObjectSetInteger(0, s, OBJPROP_BACK, true);
      ObjectSetInteger(0, s, OBJPROP_FILL, zone_solid);
      ObjectSetInteger(0, s, OBJPROP_WIDTH, zone_linewidth);
      ObjectSetInteger(0, s, OBJPROP_STYLE, zone_style);

      if(zone_type[i] == ZONE_SUPPORT)
        {
         if(zone_strength[i] == ZONE_TURNCOAT)
            ObjectSetInteger(0, s, OBJPROP_COLOR, color_support_turncoat);
         else
            if(zone_strength[i] == ZONE_PROVEN)
               ObjectSetInteger(0, s, OBJPROP_COLOR, color_support_proven);
            else
               if(zone_strength[i] == ZONE_VERIFIED)
                  ObjectSetInteger(0, s, OBJPROP_COLOR, color_support_verified);
               else
                  if(zone_strength[i] == ZONE_UNTESTED)
                     ObjectSetInteger(0, s, OBJPROP_COLOR, color_support_untested);
                  else
                     ObjectSetInteger(0, s, OBJPROP_COLOR, color_support_weak);
        }
      else
        {
         if(zone_strength[i] == ZONE_TURNCOAT)
            ObjectSetInteger(0, s, OBJPROP_COLOR, color_resist_turncoat);
         else
            if(zone_strength[i] == ZONE_PROVEN)
               ObjectSetInteger(0, s, OBJPROP_COLOR, color_resist_proven);
            else
               if(zone_strength[i] == ZONE_VERIFIED)
                  ObjectSetInteger(0, s, OBJPROP_COLOR, color_resist_verified);
               else
                  if(zone_strength[i] == ZONE_UNTESTED)
                     ObjectSetInteger(0, s, OBJPROP_COLOR, color_resist_untested);
                  else
                     ObjectSetInteger(0, s, OBJPROP_COLOR, color_resist_weak);
        }

      if(zone_strength[i] != ZONE_TURNCOAT)
        {
         double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         if(zone_lo[i] > lower_nerest_zone_P2 && price > zone_lo[i])
           {
            lower_nerest_zone_P1 = zone_hi[i];
            lower_nerest_zone_P2 = zone_lo[i];
            higher_zone_type = zone_type[i];
            lower_zone_strength = zone_strength[i];
           }
         if(zone_hi[i] < higher_nerest_zone_P1 && price < zone_hi[i])
           {
            higher_nerest_zone_P1 = zone_hi[i];
            higher_nerest_zone_P2 = zone_lo[i];
            lower_zone_type = zone_type[i];
            higher_zone_strength = zone_strength[i];
           }
        }
     }

   ArrayResize(ner_hi_zone_P1, 1);
   ArrayResize(ner_hi_zone_P2, 1);
   ArrayResize(ner_lo_zone_P1, 1);
   ArrayResize(ner_lo_zone_P2, 1);
   ArrayResize(ner_hi_zone_strength, 1);
   ArrayResize(ner_lo_zone_strength, 1);
   ArrayResize(ner_price_inside_zone, 1);

   ner_hi_zone_P1[0] = higher_nerest_zone_P1;
   ner_hi_zone_P2[0] = higher_nerest_zone_P2;
   ner_lo_zone_P1[0] = lower_nerest_zone_P1;
   ner_lo_zone_P2[0] = lower_nerest_zone_P2;
   ner_hi_zone_strength[0] = higher_zone_strength;
   ner_lo_zone_strength[0] = lower_zone_strength;
   if(ner_hi_zone_P1[0] == ner_lo_zone_P1[0])
      ner_price_inside_zone[0] = higher_zone_type;
   else
      ner_price_inside_zone[0] = 0;
  }
//+------------------------------------------------------------------+
//|AdjustLotSizeBasedOnEquityAndRisk                                 |
//+------------------------------------------------------------------+
double AdjustLotSizeBasedOnEquityAndRisk(int order_type, double price, double atr, double zone_border, int zone_index, double AccountBalance)
  {
   double riskPerTrade = AccountBalance * (RiskPercentage / 100.0);

   double stopLossDistance;

   if(order_type == ORDER_TYPE_BUY)
     {
      stopLossDistance = (zone_border - (atr * atr_multiplier)) - price;
     }
   else
      if(order_type == ORDER_TYPE_SELL)
        {
         stopLossDistance = price - (zone_border + (atr * atr_multiplier));
        }
      else
        {
         return 0.0;
        }

   stopLossDistance = MathAbs(stopLossDistance);

   if(StringFind(_Symbol, "JPY") > -1)
     {
      stopLossDistance *= 10;
     }

   double ContractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   if(ContractSize <= 0)
     {
      Print("Error: Unable to fetch contract size for symbol ", _Symbol);
     }
   double maxLotPerTrade = riskPerTrade / (stopLossDistance * ContractSize);

//double maxLotPerTrade = riskPerTrade / (stopLossDistance * ContractSize);

   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double actualLotSize = MathFloor(maxLotPerTrade / lotStep) * lotStep;

   double minLotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   actualLotSize = MathMax(actualLotSize, minLotSize);

   return actualLotSize;
  }

// Declare global variables
int periodRSI;
int periodMA;
int avgBodyPeriod;
int handleRSI;
int handleMA;


bool isBullishEngulfing;
bool isBearishEngulfing;
//+------------------------------------------------------------------+
//| CheckEngulfingPattern                                            |
//+------------------------------------------------------------------+
bool CheckEngulfingPattern()
  {
   bool patternDetected = false;
   isBullishEngulfing = false;
   isBearishEngulfing = false;



   double open1 = iOpen(NULL, 0, 1);
   double open2 = iOpen(NULL, 0, 2);
   double close1 = iClose(NULL, 0, 1);
   double close2 = iClose(NULL, 0, 2);
   double body1 = MathAbs(close1 - open1);
   double body2 = MathAbs(close2 - open2);
   double avgBody = AvgBody(1, avgBodyPeriod);

   if((open2 < close2) && (open1 > close1) &&
      (body1 > avgBody) && (body1 > body2 * 1.5) &&
      (close1 < open2) && (open1 > close2))
     {
      patternDetected = true;
      isBearishEngulfing = true;
      Print("Bearish Engulfing detected");
     }
   else
      if((open2 > close2) && (open1 < close1) &&
         (body1 > avgBody) && (body1 > body2 * 1.5) &&
         (close1 > open2) && (open1 < close2))
        {
         patternDetected = true;
         isBullishEngulfing = true;
         Print("Bullish Engulfing detected");
        }

   return patternDetected;
  }
//+------------------------------------------------------------------+
//| Draw trend lines and determine trend strength                    |
//+------------------------------------------------------------------+
void CheckAndDrawTrendLines()
  {
   if(ChartPeriod() != TFrame || Symbol() != _Symbol)
     {
      return;
     }

   if(Bars(_Symbol, TFrame) < ExtDepthBars)
     {
      return;
     }

   int lastHighIndex = iHighest(NULL, TFrame, MODE_HIGH, ExtDepthBars, 0);
   int lastLowIndex = iLowest(NULL, TFrame, MODE_LOW, ExtDepthBars, 0);

   datetime lastHighTime = iTime(NULL, TFrame, lastHighIndex);
   double lastHighPrice = iHigh(NULL, TFrame, lastHighIndex);

   datetime lastLowTime = iTime(NULL, TFrame, lastLowIndex);
   double lastLowPrice = iLow(NULL, TFrame, lastLowIndex);

   if(lastHighIndex > lastLowIndex && (Bars(_Symbol, TFrame) - lastHighIndex >= MinTrendBars))
     {
      int upperTrendLineIndex = ObjectFind(0, upTrendLineName);
      if(upperTrendLineIndex == -1)
        {
         ObjectCreate(0, upTrendLineName, OBJ_TREND, 0, lastHighTime, lastHighPrice, TimeCurrent(), lastHighPrice);
         ObjectSetInteger(0, upTrendLineName, OBJPROP_COLOR, clrRed);
        }
      else
        {
         ObjectMove(0, upTrendLineName, 0, lastHighTime, lastHighPrice);
         ObjectMove(0, upTrendLineName, 1, TimeCurrent(), lastHighPrice);
        }

      double upperSlope = (lastHighPrice - iHigh(NULL, TFrame, iHighest(NULL, TFrame, MODE_HIGH, ExtDepthBars, lastHighIndex + 1))) /
                          ((TimeCurrent() - lastHighTime) / 3600.0); // Slope in USD/hour
      string upperSlopeText = StringFormat("Upper Slope: %.4f", upperSlope);
      ObjectCreate(0, "UpperTrendSlope", OBJ_TEXT, 0, lastHighTime, lastHighPrice + (10 * Point()));
      ObjectSetString(0, "UpperTrendSlope", OBJPROP_TEXT, upperSlopeText);
      ObjectSetInteger(0, "UpperTrendSlope", OBJPROP_COLOR, clrRed);

      double lowerSlope = (lastLowPrice - iLow(NULL, TFrame, iLowest(NULL, TFrame, MODE_LOW, ExtDepthBars, lastLowIndex + 1))) /
                          ((TimeCurrent() - lastLowTime) / 3600.0); // Slope in USD/hour
      string lowerSlopeText = StringFormat("Lower Slope: %.4f", lowerSlope);
      ObjectCreate(0, "LowerTrendSlope", OBJ_TEXT, 0, lastLowTime, lastLowPrice);
      ObjectSetString(0, "LowerTrendSlope", OBJPROP_TEXT, lowerSlopeText);
      ObjectSetInteger(0, "LowerTrendSlope", OBJPROP_COLOR, clrGreen);

      DetermineTrendStrength(upperSlope, lowerSlope);

      int lowerTrendLineIndex = ObjectFind(0, downTrendLineName);
      if(lowerTrendLineIndex == -1)
        {
         ObjectCreate(0, downTrendLineName, OBJ_TREND, 0, lastLowTime, lastLowPrice, TimeCurrent(), lastLowPrice);
         ObjectSetInteger(0, downTrendLineName, OBJPROP_COLOR, clrGreen);
        }
      else
        {
         ObjectMove(0, downTrendLineName, 0, lastLowTime, lastLowPrice);
         ObjectMove(0, downTrendLineName, 1, TimeCurrent(), lastLowPrice);
        }
     }

   if(lastLowIndex > lastHighIndex && (Bars(_Symbol, TFrame) - lastLowIndex >= MinTrendBars))
     {
      int upperTrendLineIndex = ObjectFind(0, upTrendLineName);
      if(upperTrendLineIndex == -1)
        {
         ObjectCreate(0, upTrendLineName, OBJ_TREND, 0, lastHighTime, lastHighPrice, TimeCurrent(), lastHighPrice);
         ObjectSetInteger(0, upTrendLineName, OBJPROP_COLOR, clrRed);
        }
      else
        {
         ObjectMove(0, upTrendLineName, 0, lastHighTime, lastHighPrice);
         ObjectMove(0, upTrendLineName, 1, TimeCurrent(), lastHighPrice);
        }

      double upperSlope = (lastHighPrice - iHigh(NULL, TFrame, iHighest(NULL, TFrame, MODE_HIGH, ExtDepthBars, lastHighIndex + 1))) /
                          ((TimeCurrent() - lastHighTime) / 3600.0); // Slope in USD/hour
      string upperSlopeText = StringFormat("Upper Slope: %.4f", upperSlope);
      ObjectCreate(0, "UpperTrendSlope", OBJ_TEXT, 0, lastHighTime, lastHighPrice + (10 * Point()));
      ObjectSetString(0, "UpperTrendSlope", OBJPROP_TEXT, upperSlopeText);
      ObjectSetInteger(0, "UpperTrendSlope", OBJPROP_COLOR, clrWhite);

      int lowerTrendLineIndex = ObjectFind(0, downTrendLineName);
      if(lowerTrendLineIndex == -1)
        {
         ObjectCreate(0, downTrendLineName, OBJ_TREND, 0, lastLowTime, lastLowPrice, TimeCurrent(), lastLowPrice);
         ObjectSetInteger(0, downTrendLineName, OBJPROP_COLOR, clrGreen);
        }
      else
        {
         ObjectMove(0, downTrendLineName, 0, lastLowTime, lastLowPrice);
         ObjectMove(0, downTrendLineName, 1, TimeCurrent(), lastLowPrice);
        }

      double lowerSlope = (lastLowPrice - iLow(NULL, TFrame, iLowest(NULL, TFrame, MODE_LOW, ExtDepthBars, lastLowIndex + 1))) /
                          ((TimeCurrent() - lastLowTime) / 3600.0); // Slope in USD/hour
      string lowerSlopeText = StringFormat("Lower Slope: %.4f", lowerSlope);
      ObjectCreate(0, "LowerTrendSlope", OBJ_TEXT, 0, lastLowTime, lastLowPrice);
      ObjectSetString(0, "LowerTrendSlope", OBJPROP_TEXT, lowerSlopeText);
      ObjectSetInteger(0, "LowerTrendSlope", OBJPROP_COLOR, clrWhite);

      DetermineTrendStrength(upperSlope, lowerSlope);
     }
  }
//+------------------------------------------------------------------+
//| Calculate adaptive thresholds based on ATR                       |
//+------------------------------------------------------------------+
double CalculateAdaptiveThreshold(int period, double multiplier)
  {
   double atr = iATR(NULL, PERIOD_CURRENT, period);
   return atr * multiplier;
  }

//+------------------------------------------------------------------+
//| Determine trend strength                                         |
//+------------------------------------------------------------------+
void DetermineTrendStrength(double upperSlope, double lowerSlope)
  {
   double absUpperSlope = MathAbs(upperSlope);
   double absLowerSlope = MathAbs(lowerSlope);

// Calculate adaptive thresholds
   double adaptiveThreshold = CalculateAdaptiveThreshold(14, 0.1); // Example: 10% of ATR

   if(absUpperSlope > absLowerSlope)
     {
      if(upperSlope >= adaptiveThreshold)   // Adaptive threshold for strong uptrend
        {
         Print("Strong uptrend detected");
        }
      else
        {
         Print("No trend detected");
        }
     }
   else
     {
      if(lowerSlope <= -adaptiveThreshold)   // Adaptive threshold for strong downtrend
        {
         Print("Strong downtrend detected");
        }
      else
        {
         Print("No trend detected");
        }
     }
  }

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Additional utility functions                                     |
//+------------------------------------------------------------------+
double Open(int index) { return iOpen(_Symbol, _Period, index); }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Close(int index) { return iClose(_Symbol, _Period, index); }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Low(int index) { return iLow(_Symbol, _Period, index); }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double High(int index) { return iHigh(_Symbol, _Period, index); }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double MidOpenClose(int index) { return (Open(index) + Close(index)) / 2.; }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double MidPoint(int index) { return (High(index) + Low(index)) / 2.; }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double AvgBody(int index, int period)
  {
   double sum = 0;
   for(int i = index; i < index + period; i++)
     {
      sum += MathAbs(Open(i) - Close(i));
     }
   return sum / period;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double RSI(int index, int handle)
  {
   double indicator_values[];
   if(CopyBuffer(handle, 0, index, 1, indicator_values) < 0)
     {
      PrintFormat("Failed to copy data from the RSI indicator, error code %d", GetLastError());
      return EMPTY_VALUE;
     }
   return indicator_values[0];
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CloseAvg(int index, int handle)
  {
   double indicator_values[];
   if(CopyBuffer(handle, 0, index, 1, indicator_values) < 0)
     {
      PrintFormat("Failed to copy data from the Simple Moving Average indicator, error code %d", GetLastError());
      return EMPTY_VALUE;
     }
   return indicator_values[0];
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckIfAllPositionsClosed() { return PositionsTotal() == 0; }
bool isClosingTrades = false;
bool TradingEnabled = true;
void CheckDailyProfitAndRemoveEA()
  {
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyProfitPercentage = ((currentBalance - InitialDailyBalance) / InitialDailyBalance) * 100.0;

   if(dailyProfitPercentage <= -AcceptableDailyLoss)
     {
      Print("Daily loss limit exceeded. Closing all positions and removing EA.");
      TradingEnabled = false;
      CloseAllPositions();

      Sleep(1000);

      if(PositionsTotal() == 0)
        {
         Print("Loss Exceeded Acceptable Daily Loss: ", AcceptableDailyLoss, "%. Removing EA.");
         ExpertRemove();
        }
     }
  }
bool allPositionsClosed = true;
void CloseAllPositions()
  {
   if(isClosingTrades)
     {
      return;
     }

   isClosingTrades = true;
   allPositionsClosed = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionSelectByTicket(PositionGetTicket(i)))
        {
         int ticket = (int)PositionGetTicket(i);
         trade.PositionClose(ticket);
        }
     }

   isClosingTrades = false;
   allPositionsClosed = CheckIfAllPositionsClosed();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// Function to close two positions
void CloseTwoPositions()
  {
   if(isClosingTrades)
     {
      return;
     }

   isClosingTrades = true;
   allPositionsClosed = false;

   double maxProfit = -DBL_MAX;
   double minProfit = DBL_MAX;
   ulong maxProfitTicket = 0;
   ulong minProfitTicket = 0;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         double profit = PositionGetDouble(POSITION_PROFIT);

         if(profit > maxProfit)
           {
            maxProfit = profit;
            maxProfitTicket = ticket;
           }

         if(profit < minProfit)
           {
            minProfit = profit;
            minProfitTicket = ticket;
           }
        }
     }

   bool losingTradeClosed = false;

   if(maxProfitTicket != 0)
     {
      trade.PositionClose(maxProfitTicket);
     }

   if(minProfitTicket != 0)
     {
      trade.PositionClose(minProfitTicket);
      losingTradeClosed = true;
     }

// If a losing trade was closed, move the SL for remaining trades to break even + 100 points
   if(losingTradeClosed)
     {
      for(int i = 0; i < PositionsTotal(); i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
           {
            double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double newStopLoss = entryPrice + 100 * _Point; // Move SL to break even + 100 points

            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
              {
               trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP));
              }
            else
               if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                 {
                  trade.PositionModify(ticket, entryPrice - 100 * _Point, PositionGetDouble(POSITION_TP));
                 }
           }
        }
     }

   isClosingTrades = false;
   allPositionsClosed = CheckIfAllPositionsClosed();
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool SendTelegramMessage(string url, string token, string chat, string text, string fileName = "")
  {
   string headers    = "";
   string requestUrl = "";
   char   postData[];
   char   resultData[];
   string resultHeaders;
   int    timeout = 20000;
   ResetLastError();
   if(fileName == "")
     {
      requestUrl = StringFormat("%s/bot%s/sendmessage?chat_id=%s&text=%s", url, token, chat, text);
     }
   else
     {
      requestUrl = StringFormat("%s/bot%s/sendPhoto", url, token);
      if(!GetPostData(postData, headers, chat, text, fileName))
        {
         return (false);
        }
     }
   ResetLastError();
   int response = WebRequest("POST", requestUrl, headers, timeout, postData, resultData, resultHeaders);
   switch(response)
     {
      case -1:
        {
         int errorCode = GetLastError();
         Print("Error in WebRequest. Error code  =", errorCode);
         if(errorCode == UrlDefinedError)
           {
            PrintFormat("Add the address '%s' in the list of allowed URLs", url);
           }
         break;
        }
      case 200:
         Print("The message has been successfully sent");
         break;
      default:
        {
         string result = CharArrayToString(resultData);
         PrintFormat("Unexpected Response '%i', '%s'", response, result);
         break;
        }
     }
   return (response == 200);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool GetPostData(char &postData[], string &headers, string chat, string text, string fileName)
  {
   ResetLastError();
   if(!FileIsExist(fileName))
     {
      PrintFormat("File '%s' does not exist", fileName);
      return (false);
     }
   int flags = FILE_READ | FILE_BIN;
   int file  = FileOpen(fileName, flags);
   if(file == INVALID_HANDLE)
     {
      int err = GetLastError();
      PrintFormat("Could not open file '%s', error=%i", fileName, err);
      return (false);
     }
   int   fileSize = (int)FileSize(file);
   uchar photo[];
   ArrayResize(photo, fileSize);
   FileReadArray(file, photo, 0, fileSize);
   FileClose(file);
   string hash = "";
   AddPostData(postData, hash, "chat_id", chat);
   if(StringLen(text) > 0)
     {
      AddPostData(postData, hash, "caption", text);
     }
   AddPostData(postData, hash, "photo", photo, fileName);
   ArrayCopy(postData, "--" + hash + "--\r\n");
   headers = "Content-Type: multipart/form-data; boundary=" + hash + "\r\n";
   return (true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void AddPostData(uchar &data[], string &hash, string key = "", string value = "")
  {
   uchar valueArr[];
   StringToCharArray(value, valueArr, 0, StringLen(value));
   AddPostData(data, hash, key, valueArr);
   return;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void AddPostData(uchar &data[], string &hash, string key, uchar &value[], string fileName = "")
  {
   if(hash == "")
     {
      hash = Hash();
     }
   ArrayCopy(data, "\r\n");
   ArrayCopy(data, "--" + hash + "\r\n");
   if(fileName == "")
     {
      ArrayCopy(data, "Content-Disposition: form-data; name=\"" + key + "\"\r\n");
     }
   else
     {
      ArrayCopy(data, "Content-Disposition: form-data; name=\"" + key + "\"; filename=\"" +
                fileName + "\"\r\n");
     }
   ArrayCopy(data, "\r\n");
   ArrayCopy(data, value, ArraySize(data));
   ArrayCopy(data, "\r\n");
   return;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ArrayCopy(uchar &dst[], string src)
  {
   uchar srcArray[];
   StringToCharArray(src, srcArray, 0, StringLen(src));
   ArrayCopy(dst, srcArray, ArraySize(dst), 0, ArraySize(srcArray));
   return;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string Hash()
  {
   uchar  tmp[];
   string seed = IntegerToString(TimeCurrent());
   int    len  = StringToCharArray(seed, tmp, 0, StringLen(seed));
   string hash = "";
   for(int i = 0; i < len; i++)
      hash += StringFormat("%02X", tmp[i]);
   hash = StringSubstr(hash, 0, 16);
   return (hash);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
