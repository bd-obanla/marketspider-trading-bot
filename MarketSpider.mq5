//+------------------------------------------------------------------+
//|                                              MarketSpider.mq5    |
//|              Advanced Multi-Market Scalping Robot                |
//|         Strategy: KTL Axis Model + Rare SNR Framework           |
//|         Markets: Forex | Crypto | Stocks | Synthetic Indices    |
//|         Version: 2.0 | Professional Scalping Edition            |
//|         Target: $10 -> $1000+ via precision scalping            |
//+------------------------------------------------------------------+
#property copyright "MarketSpider | KTL Rare SNR Project"
#property link      ""
#property version   "2.00"
#property strict
#property description "MarketSpider - Advanced Multi-Market Scalper"
#property description "Based on KTL Axis Model: Key Level + Time + Liquidity"
#property description "Supports: Forex, Crypto, Stocks, Synthetic Indices"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

CTrade         g_trade;
CPositionInfo  g_pos;
COrderInfo     g_ord;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "======= GENERAL SETTINGS ======="
input long   InpMagicNumber        = 20250101;   // Magic Number
input string InpRobotLabel         = "MarketSpider"; // Robot Label
input bool   InpEnableLogging      = true;        // Enable Log Output
input bool   InpAllowBuy           = true;        // Allow BUY trades
input bool   InpAllowSell          = true;        // Allow SELL trades

input group "======= RISK & MONEY MANAGEMENT ======="
input bool   InpUseAutoRisk        = true;        // Auto Risk Scaling (balance-based)
input double InpRiskPercent        = 1.0;         // Risk % per trade (low balance)
input double InpRiskPercentMid     = 0.75;        // Risk % (mid balance $100-$500)
input double InpRiskPercentHigh    = 0.5;         // Risk % (high balance $500+)
input double InpFixedLot           = 0.01;        // Fixed lot (if auto-risk OFF)
input double InpMaxLotsPerTrade    = 1.0;         // Maximum lots per trade
input double InpMinBalanceToTrade  = 5.0;         // Minimum balance to allow trading
input double InpDailyProfitTarget  = 50.0;        // Daily profit target % (stop trading when hit)
input double InpMaxDailyLoss       = 20.0;        // Max daily loss % (stop trading when hit)
input int    InpMaxOpenTrades      = 3;           // Max simultaneous open trades
input int    InpMaxConsecLosses    = 4;           // Max consecutive losses before pause

input group "======= SCALPING PARAMETERS ======="
input ENUM_TIMEFRAMES InpScalpTF   = PERIOD_M5;   // Scalp Entry Timeframe
input ENUM_TIMEFRAMES InpConfirmTF = PERIOD_M15;  // Confirmation Timeframe
input ENUM_TIMEFRAMES InpBiasTF    = PERIOD_H1;   // Bias Timeframe
input ENUM_TIMEFRAMES InpHTFTF     = PERIOD_H4;   // Higher Timeframe Bias
input double InpScalpRR            = 2.0;         // Reward:Risk Ratio
input double InpMinRRAllowed       = 1.5;         // Minimum R:R to take trade
input int    InpSLBufferPoints     = 5;           // SL Buffer (points beyond SNR)
input bool   InpUseDynamicSL       = true;        // Use dynamic SL (ATR-based)
input double InpATRMultiplierSL    = 1.2;         // ATR multiplier for SL
input int    InpATRPeriod          = 14;          // ATR Period

input group "======= SNR LEVEL SETTINGS ======="
input int    InpSNRLookback        = 150;         // Bars to scan for SNR levels
input int    InpMinTouchCount      = 1;           // Minimum touches for valid level
input bool   InpFreshLevelsOnly    = true;        // Only trade fresh/untested levels
input double InpLevelZonePips      = 5.0;         // Zone size around SNR level (pips)
input bool   InpUseFlippedSNR      = true;        // Trade Flipped SNR (SBR/RBS)
input bool   InpUseQMLPattern      = true;        // Trade QML (Head & Shoulder) pattern
input bool   InpUseFailedQML       = true;        // Trade Failed QML pattern

input group "======= SESSION & TIME FILTERS ======="
input int    InpUTCOffset          = 1;           // UTC Offset (your broker server time)
input bool   InpTradeAsian         = false;       // Trade Asian Session (01:00-07:00)
input bool   InpTradeFrankfurt     = true;        // Trade Frankfurt Kill Zone (07:00-08:00)
input bool   InpTradeLondon        = true;        // Trade London Session (08:00-17:00)
input bool   InpTradeNewYork       = true;        // Trade New York Session (13:00-21:00)
input bool   InpTradeLNOverlap     = true;        // Trade London-NY Overlap (13:00-17:00)
input bool   InpBlockNYLunch       = true;        // Block NY Lunch (17:00-18:00)
input bool   InpTradeSynthetic24   = true;        // Synthetic indices trade 24/7 (bypass session filter)

input group "======= TRADE MANAGEMENT ======="
input bool   InpUseBreakEven       = true;        // Move SL to Break-Even
input double InpBreakEvenTriggerR  = 1.0;         // Move BE when profit reaches X*R
input double InpBreakEvenOffsetPts = 2.0;         // BE offset (points above entry)
input bool   InpUsePartialClose    = true;        // Enable partial close
input double InpPartial1RR         = 1.0;         // Close 30% at 1R
input double InpPartial2RR         = 2.0;         // Close 30% at 2R
input bool   InpUseTrailing        = true;        // Enable trailing stop
input double InpTrailTriggerR      = 1.5;         // Start trailing at X*R profit
input double InpTrailDistPoints    = 15.0;        // Trailing distance (points)

input group "======= SPREAD & EXECUTION ======="
input int    InpMaxSpreadForex     = 25;          // Max spread - Forex (points)
input int    InpMaxSpreadSynth     = 3000;        // Max spread - Synthetic (points)
input int    InpMaxSpreadCFD       = 100;         // Max spread - CFD/Crypto (points)
input int    InpSlippagePoints     = 10;          // Max slippage (points)

input group "======= MULTI-TRADE SCALING ======="
input bool   InpScaleOnWin         = true;        // Increase lot after winning streak
input int    InpScaleWinStreak     = 3;           // Wins needed to scale up
input double InpScaleMultiplier    = 1.2;         // Lot multiplier on scale-up
input bool   InpReduceOnLoss       = true;        // Reduce lot after loss
input double InpLossReduceFactor   = 0.8;         // Lot multiplier after loss

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                     |
//+------------------------------------------------------------------+
enum EMarketType { MKT_FOREX, MKT_CRYPTO, MKT_STOCK, MKT_SYNTHETIC, MKT_CFD };
enum EBiasDir    { BIAS_BULL = 1, BIAS_BEAR = -1, BIAS_NONE = 0 };
enum ESNRType    { SNR_CLASSIC, SNR_FLIPPED, SNR_QML, SNR_FAILED_QML, SNR_GAP };
enum ESessionType{ SES_ASIAN, SES_FRANKFURT, SES_LONDON, SES_NEWYORK, SES_OVERLAP, SES_LUNCH, SES_CLOSED };

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct SMarketProfile
{
   EMarketType type;
   bool        is24_7;
   bool        isSynthetic;
   double      pointValue;
   double      pipValue;
   double      atr;
   double      spreadLimit;
   double      minSLPoints;
   string      description;
};

struct SSessionInfo
{
   bool          asian;
   bool          frankfurt;
   bool          london;
   bool          newYork;
   bool          overlap;
   bool          nyLunch;
   bool          allowed;
   ESessionType  dominant;
};

struct SAsianRange
{
   double   high;
   double   low;
   double   mid;
   datetime startDT;
   datetime endDT;
   bool     highSwept;
   bool     lowSwept;
   bool     valid;
};

struct SSNRLevel
{
   double    price;
   double    zoneTop;
   double    zoneBot;
   bool      isSupport;
   bool      isFresh;
   bool      isFlipped;
   int       touchCount;
   ESNRType  levelType;
   datetime  formedAt;
   int       barShift;
   double    strength;      // 0.0 - 1.0 confluence score
   bool      valid;
};

struct SMarketStructure
{
   double lastSwingHigh;
   double lastSwingLow;
   double prevSwingHigh;
   double prevSwingLow;
   bool   isHHHL;           // Bullish structure
   bool   isLHLL;           // Bearish structure
   bool   structureBroken;
   double bmsLevel;         // Break of market structure level
};

struct STradeSetup
{
   bool      isBuy;
   bool      isSell;
   double    entry;
   double    sl;
   double    tp1;           // TP at 1R
   double    tp2;           // TP at target R:R
   double    tp3;           // TP extended
   double    lots;
   double    slPoints;
   double    rrRatio;
   SSNRLevel snrLevel;
   string    label;
   double    confidence;    // 0.0 - 1.0 setup quality
   bool      valid;
};

struct SScalpOpportunity
{
   bool     detected;
   bool     isBuy;
   double   entryZoneHigh;
   double   entryZoneLow;
   double   confirmPrice;
   double   sl;
   double   tp;
   double   confidence;
   string   reason;
};

struct SDailyStats
{
   double startBalance;
   double currentProfit;
   double currentLoss;
   double profitPct;
   double lossPct;
   int    winCount;
   int    lossCount;
   int    breakEvenCount;
   int    consecutiveLosses;
   int    consecutiveWins;
   bool   dailyTargetHit;
   bool   dailyLossLimitHit;
};

//+------------------------------------------------------------------+
//| GLOBAL STATE                                                     |
//+------------------------------------------------------------------+
datetime       g_lastBarTime     = 0;
datetime       g_lastM1BarTime   = 0;
int            g_dayOfYear       = -1;
SDailyStats    g_daily;
bool           g_breakEvenDone   = false;
bool           g_partial1Done    = false;
bool           g_partial2Done    = false;
int            g_atrHandle       = INVALID_HANDLE;
double         g_atrBuffer[];
int            g_consecutiveWins = 0;
double         g_currentLotScale = 1.0;
string         g_dashName        = "MS_DASH";
color          g_dashColor       = clrAqua;

//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   g_atrHandle = iATR(_Symbol, InpScalpTF, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Log("ERROR: Failed to create ATR indicator handle.");
      return INIT_FAILED;
   }

   ArraySetAsSeries(g_atrBuffer, true);
   ResetDailyStats();
   InitDashboard();

   Log("=============================================");
   Log("  MarketSpider v2.0 | KTL Rare SNR Engine  ");
   Log("  Symbol : " + _Symbol);
   Log("  Market : " + MarketTypeToString(DetectMarketType()));
   Log("  Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   Log("  Scalp TF  : " + EnumToString(InpScalpTF));
   Log("  Confirm TF: " + EnumToString(InpConfirmTF));
   Log("  Bias TF   : " + EnumToString(InpBiasTF));
   Log("=============================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINITIALIZATION                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);

   ObjectsDeleteAll(0, g_dashName);
   Log("MarketSpider deinitialized. Reason=" + IntegerToString(reason));
}

//+------------------------------------------------------------------+
//| MAIN TICK - THE ENGINE                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // Always run these on every tick
   ResetDailyStatsIfNewDay();
   RefreshATR();
   ManageOpenTrades();
   UpdateDashboard();

   // Block if daily limits hit
   if(g_daily.dailyTargetHit || g_daily.dailyLossLimitHit)
      return;

   // Block if protected
   if(IsTradingBlocked())
      return;

   // New scalp-bar logic
   if(!IsNewScalpBar())
      return;

   // Full analysis pipeline on each new bar
   SMarketProfile mp = GetMarketProfile();

   // Step 1: Spread check
   if(!IsSpreadOK(mp))
   {
      Log("Spread too wide. Waiting.");
      return;
   }

   // Step 2: Session check (synthetic indices trade 24/7)
   SSessionInfo si = GetSessionInfo();
   if(!mp.is24_7 && !si.allowed)
   {
      Log("Session not active for this market.");
      return;
   }

   // Step 3: Directional bias (top-down KTL analysis)
   int htfBias  = GetBias(InpHTFTF);
   int biasTF   = GetBias(InpBiasTF);
   int combined = GetCombinedBias(htfBias, biasTF);

   Log("Bias | HTF=" + BiasStr(htfBias) + " | Mid=" + BiasStr(biasTF) + " | Combined=" + BiasStr(combined));

   if(combined == BIAS_NONE)
   {
      Log("No aligned bias. Skipping.");
      return;
   }

   // Step 4: Asian range reference
   SAsianRange ar = GetAsianRange();

   // Step 5: Market structure analysis
   SMarketStructure ms = GetMarketStructure(InpBiasTF);

   // Step 6: Scan for SNR levels on scalp timeframe
   SSNRLevel bestLevel;
   bestLevel.valid = false;

   if(combined == BIAS_BULL && InpAllowBuy)
      bestLevel = FindBestSupportLevel(InpScalpTF, InpConfirmTF);

   if(combined == BIAS_BEAR && InpAllowSell)
      bestLevel = FindBestResistanceLevel(InpScalpTF, InpConfirmTF);

   if(!bestLevel.valid)
   {
      Log("No valid SNR level found for current bias.");
      return;
   }

   // Step 7: Scalp opportunity detection
   SScalpOpportunity opp = DetectScalpOpportunity(bestLevel, combined, ar, ms, mp);

   if(!opp.detected)
   {
      Log("No scalp opportunity confirmed at this bar.");
      return;
   }

   // Step 8: Build and validate full trade setup
   STradeSetup setup = BuildTradeSetup(opp, bestLevel, combined, mp);

   if(!setup.valid)
   {
      Log("Trade setup invalid or R:R below minimum.");
      return;
   }

   // Step 9: Axis alignment - all 3 must confirm (KTL)
   if(!IsAxisAligned(setup, ar, si, combined, mp))
   {
      Log("KTL Axis not aligned. No trade. Waiting for precision.");
      return;
   }

   // Step 10: Final entry confirmation (candle close confirmation)
   if(!IsEntryConfirmed(setup, combined))
   {
      Log("Entry not confirmed by candle close. Waiting.");
      return;
   }

   // Step 11: Execute
   ExecuteTrade(setup);
}

//+------------------------------------------------------------------+
//| MARKET PROFILE DETECTION                                         |
//+------------------------------------------------------------------+
EMarketType DetectMarketType()
{
   string s = _Symbol;
   StringToUpper(s);

   // Synthetic / Deriv indices
   if(StringFind(s,"VOLATILITY") >= 0) return MKT_SYNTHETIC;
   if(StringFind(s,"CRASH")      >= 0) return MKT_SYNTHETIC;
   if(StringFind(s,"BOOM")       >= 0) return MKT_SYNTHETIC;
   if(StringFind(s,"STEP")       >= 0) return MKT_SYNTHETIC;
   if(StringFind(s,"JUMP")       >= 0) return MKT_SYNTHETIC;
   if(StringFind(s,"RANGE BREAK")>= 0) return MKT_SYNTHETIC;
   if(StringFind(s,"DEX")        >= 0) return MKT_SYNTHETIC;
   if(StringFind(s,"BEAR")       >= 0) return MKT_SYNTHETIC;  // Bear/Bull market indices
   if(StringFind(s,"BULL")       >= 0) return MKT_SYNTHETIC;

   // Crypto
   if(StringFind(s,"BTC")  >= 0) return MKT_CRYPTO;
   if(StringFind(s,"ETH")  >= 0) return MKT_CRYPTO;
   if(StringFind(s,"XRP")  >= 0) return MKT_CRYPTO;
   if(StringFind(s,"SOL")  >= 0) return MKT_CRYPTO;
   if(StringFind(s,"DOGE") >= 0) return MKT_CRYPTO;
   if(StringFind(s,"LTC")  >= 0) return MKT_CRYPTO;
   if(StringFind(s,"ADA")  >= 0) return MKT_CRYPTO;
   if(StringFind(s,"USDT") >= 0) return MKT_CRYPTO;

   // Forex
   string forexPairs[] = {"EURUSD","GBPUSD","USDJPY","AUDUSD","USDCAD","USDCHF",
                           "NZDUSD","EURGBP","EURJPY","GBPJPY","XAUUSD","XAGUSD",
                           "GBPCHF","AUDCAD","CADJPY","CHFJPY","EURCAD","EURAUD",
                           "AUDNZD","NZDCAD","NZDCHF","NZDJPY","AUDCHF","AUDJPY"};
   for(int i = 0; i < ArraySize(forexPairs); i++)
      if(StringFind(s, forexPairs[i]) >= 0) return MKT_FOREX;

   // Stocks/Indices
   if(StringFind(s,"SPX")   >= 0) return MKT_STOCK;
   if(StringFind(s,"NDX")   >= 0) return MKT_STOCK;
   if(StringFind(s,"DOW")   >= 0) return MKT_STOCK;
   if(StringFind(s,"AAPL")  >= 0) return MKT_STOCK;
   if(StringFind(s,"TSLA")  >= 0) return MKT_STOCK;
   if(StringFind(s,"US30")  >= 0) return MKT_STOCK;
   if(StringFind(s,"US100") >= 0) return MKT_STOCK;
   if(StringFind(s,"GER40") >= 0) return MKT_STOCK;
   if(StringFind(s,"NAS100")>= 0) return MKT_STOCK;

   return MKT_CFD;
}

SMarketProfile GetMarketProfile()
{
   SMarketProfile mp;
   EMarketType mt = DetectMarketType();
   mp.type        = mt;
   mp.isSynthetic = (mt == MKT_SYNTHETIC);
   mp.is24_7      = (mt == MKT_SYNTHETIC || mt == MKT_CRYPTO);
   mp.pointValue  = _Point;
   mp.pipValue    = (mt == MKT_FOREX || mt == MKT_SYNTHETIC) ? _Point * 10 : _Point;

   switch(mt)
   {
      case MKT_FOREX:
         mp.spreadLimit  = InpMaxSpreadForex;
         mp.minSLPoints  = 30;
         mp.description  = "Forex";
         break;
      case MKT_SYNTHETIC:
         mp.spreadLimit  = InpMaxSpreadSynth;
         mp.minSLPoints  = 50;
         mp.description  = "Synthetic Index";
         break;
      case MKT_CRYPTO:
         mp.spreadLimit  = InpMaxSpreadCFD * 5;
         mp.minSLPoints  = 50;
         mp.description  = "Crypto";
         break;
      case MKT_STOCK:
         mp.spreadLimit  = InpMaxSpreadCFD * 2;
         mp.minSLPoints  = 20;
         mp.description  = "Stock/Index";
         break;
      default:
         mp.spreadLimit  = InpMaxSpreadCFD;
         mp.minSLPoints  = 30;
         mp.description  = "CFD";
   }

   // Get current ATR
   mp.atr = GetATRValue();
   return mp;
}

string MarketTypeToString(EMarketType mt)
{
   switch(mt)
   {
      case MKT_FOREX:     return "Forex";
      case MKT_CRYPTO:    return "Crypto";
      case MKT_STOCK:     return "Stock/Index";
      case MKT_SYNTHETIC: return "Synthetic Index";
      default:            return "CFD";
   }
}

//+------------------------------------------------------------------+
//| SESSION ENGINE (UTC + broker offset)                             |
//+------------------------------------------------------------------+
SSessionInfo GetSessionInfo()
{
   SSessionInfo si;
   si.asian = si.frankfurt = si.london = si.newYork = false;
   si.overlap = si.nyLunch = si.allowed = false;
   si.dominant = SES_CLOSED;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour + InpUTCOffset;
   if(h >= 24) h -= 24;
   if(h < 0)   h += 24;

   if(h >= 1  && h < 7)   { si.asian     = true; si.dominant = SES_ASIAN;     }
   if(h >= 7  && h < 8)   { si.frankfurt = true; si.dominant = SES_FRANKFURT;  }
   if(h >= 8  && h < 17)  { si.london    = true; si.dominant = SES_LONDON;     }
   if(h >= 13 && h < 21)  { si.newYork   = true; si.dominant = SES_NEWYORK;    }
   if(h >= 13 && h < 17)  { si.overlap   = true; si.dominant = SES_OVERLAP;    }
   if(h >= 17 && h < 18)  { si.nyLunch   = true; si.dominant = SES_LUNCH;      }

   bool ok = false;
   if(InpTradeAsian     && si.asian)     ok = true;
   if(InpTradeFrankfurt && si.frankfurt) ok = true;
   if(InpTradeLondon    && si.london)    ok = true;
   if(InpTradeNewYork   && si.newYork)   ok = true;
   if(InpTradeLNOverlap && si.overlap)   ok = true;
   if(InpBlockNYLunch   && si.nyLunch)   ok = false; // Hard block

   si.allowed = ok;
   return si;
}

//+------------------------------------------------------------------+
//| ASIAN RANGE ENGINE                                               |
//+------------------------------------------------------------------+
SAsianRange GetAsianRange()
{
   SAsianRange ar;
   ar.high = 0; ar.low = 0; ar.mid = 0;
   ar.highSwept = ar.lowSwept = ar.valid = false;

   MqlRates r[];
   int cnt = CopyRates(_Symbol, PERIOD_H1, 0, 250, r);
   if(cnt < 10) return ar;
   ArraySetAsSeries(r, true);

   MqlDateTime nd;
   TimeToStruct(TimeCurrent(), nd);

   bool found = false;
   double hi = 0, lo = DBL_MAX;

   for(int i = cnt - 1; i >= 0; i--)
   {
      MqlDateTime bd;
      TimeToStruct(r[i].time, bd);
      bool sameDay = (bd.year == nd.year && bd.mon == nd.mon && bd.day == nd.day);
      if(!sameDay) continue;

      int ah = bd.hour + InpUTCOffset;
      if(ah >= 24) ah -= 24;
      if(ah >= 1 && ah < 7)
      {
         if(r[i].high > hi) hi = r[i].high;
         if(r[i].low  < lo) lo = r[i].low;
         if(ar.startDT == 0 || r[i].time < ar.startDT) ar.startDT = r[i].time;
         ar.endDT = r[i].time;
         found = true;
      }
   }

   if(!found || hi == 0 || lo == DBL_MAX) return ar;

   ar.high  = hi;
   ar.low   = lo;
   ar.mid   = (hi + lo) / 2.0;
   ar.valid = true;

   double cp = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ar.highSwept = (cp > hi);
   ar.lowSwept  = (cp < lo);
   return ar;
}

//+------------------------------------------------------------------+
//| ATR ENGINE                                                       |
//+------------------------------------------------------------------+
void RefreshATR()
{
   if(g_atrHandle == INVALID_HANDLE) return;
   CopyBuffer(g_atrHandle, 0, 0, 5, g_atrBuffer);
}

double GetATRValue()
{
   if(ArraySize(g_atrBuffer) < 2) return _Point * 100;
   return g_atrBuffer[1];
}

//+------------------------------------------------------------------+
//| DIRECTIONAL BIAS ENGINE (KTL Top-Down)                          |
//+------------------------------------------------------------------+
int GetBias(ENUM_TIMEFRAMES tf)
{
   MqlRates r[];
   int cnt = CopyRates(_Symbol, tf, 0, 100, r);
   if(cnt < 20) return BIAS_NONE;
   ArraySetAsSeries(r, true);

   // Collect swing highs and lows
   double highs[10], lows[10];
   int    hc = 0, lc = 0;
   int    hShift = 3; // swing detection sensitivity

   for(int i = hShift; i < cnt - hShift && (hc < 5 || lc < 5); i++)
   {
      bool isSwH = true, isSwL = true;
      for(int k = 1; k <= hShift; k++)
      {
         if(r[i].high <= r[i-k].high || r[i].high <= r[i+k].high) isSwH = false;
         if(r[i].low  >= r[i-k].low  || r[i].low  >= r[i+k].low)  isSwL = false;
      }
      if(isSwH && hc < 10) highs[hc++] = r[i].high;
      if(isSwL && lc < 10) lows[lc++]  = r[i].low;
   }

   if(hc < 2 || lc < 2) return BIAS_NONE;

   bool hh = highs[0] > highs[1]; // most recent high > previous
   bool hl = lows[0]  > lows[1];  // most recent low  > previous
   bool lh = highs[0] < highs[1];
   bool ll = lows[0]  < lows[1];

   if(hh && hl) return BIAS_BULL;  // Higher High + Higher Low = Bullish
   if(lh && ll) return BIAS_BEAR;  // Lower High  + Lower Low  = Bearish
   return BIAS_NONE;
}

int GetCombinedBias(int htf, int mid)
{
   if(htf == BIAS_BULL && mid == BIAS_BULL) return BIAS_BULL;
   if(htf == BIAS_BEAR && mid == BIAS_BEAR) return BIAS_BEAR;
   if(htf != BIAS_NONE && mid == BIAS_NONE) return htf;  // HTF dominates if mid neutral
   return BIAS_NONE;
}

string BiasStr(int b)
{
   if(b == BIAS_BULL) return "BULLISH";
   if(b == BIAS_BEAR) return "BEARISH";
   return "NEUTRAL";
}

//+------------------------------------------------------------------+
//| MARKET STRUCTURE ANALYSIS                                        |
//+------------------------------------------------------------------+
SMarketStructure GetMarketStructure(ENUM_TIMEFRAMES tf)
{
   SMarketStructure ms;
   ms.lastSwingHigh = ms.lastSwingLow = 0;
   ms.prevSwingHigh = ms.prevSwingLow = 0;
   ms.isHHHL = ms.isLHLL = ms.structureBroken = false;
   ms.bmsLevel = 0;

   MqlRates r[];
   int cnt = CopyRates(_Symbol, tf, 0, 100, r);
   if(cnt < 20) return ms;
   ArraySetAsSeries(r, true);

   double swH[4], swL[4];
   int hc = 0, lc = 0;

   for(int i = 2; i < cnt - 2 && (hc < 4 || lc < 4); i++)
   {
      if(r[i].high > r[i-1].high && r[i].high > r[i-2].high &&
         r[i].high > r[i+1].high && r[i].high > r[i+2].high)
      {
         if(hc < 4) swH[hc++] = r[i].high;
      }
      if(r[i].low < r[i-1].low && r[i].low < r[i-2].low &&
         r[i].low < r[i+1].low && r[i].low < r[i+2].low)
      {
         if(lc < 4) swL[lc++] = r[i].low;
      }
   }

   if(hc >= 2) { ms.lastSwingHigh = swH[0]; ms.prevSwingHigh = swH[1]; }
   if(lc >= 2) { ms.lastSwingLow  = swL[0]; ms.prevSwingLow  = swL[1]; }

   ms.isHHHL = (ms.lastSwingHigh > ms.prevSwingHigh && ms.lastSwingLow > ms.prevSwingLow);
   ms.isLHLL = (ms.lastSwingHigh < ms.prevSwingHigh && ms.lastSwingLow < ms.prevSwingLow);

   // BMS - Break of Market Structure
   double currentClose = r[0].close;
   if(ms.isHHHL && currentClose < ms.lastSwingLow) { ms.structureBroken = true; ms.bmsLevel = ms.lastSwingLow; }
   if(ms.isLHLL && currentClose > ms.lastSwingHigh){ ms.structureBroken = true; ms.bmsLevel = ms.lastSwingHigh;}

   return ms;
}

//+------------------------------------------------------------------+
//| SNR LEVEL SCANNER - FULL IMPLEMENTATION                          |
//| Detects: Classic, Flipped (SBR/RBS), QML, Failed QML, GAP SNR  |
//+------------------------------------------------------------------+
SSNRLevel FindBestSupportLevel(ENUM_TIMEFRAMES scalpTF, ENUM_TIMEFRAMES confirmTF)
{
   SSNRLevel best;
   best.valid = false;
   best.strength = 0;

   MqlRates r[];
   int cnt = CopyRates(_Symbol, scalpTF, 0, InpSNRLookback, r);
   if(cnt < 20) return best;
   ArraySetAsSeries(r, true);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pip = GetPipSize();
   double zoneHalf = InpLevelZonePips * pip;

   for(int i = 3; i < cnt - 3; i++)
   {
      // Classic support: swing low (V-shape on line chart)
      bool swingLow = (r[i].low < r[i-1].low && r[i].low < r[i-2].low &&
                       r[i].low < r[i+1].low && r[i].low < r[i+2].low);

      if(!swingLow) continue;

      double levelPrice = r[i].close; // KTL: SNR is at close, not wick
      double dist = ask - levelPrice;

      // Must be below current price (we're looking for support to buy from)
      if(dist <= 0) continue;

      // Must be within tradeable proximity (not too far)
      double maxDist = GetATRValue() * 3.0;
      if(dist > maxDist) continue;

      // Check minimum distance (not too close)
      double minDist = GetATRValue() * 0.1;
      if(dist < minDist) continue;

      SSNRLevel lv;
      lv.price     = levelPrice;
      lv.zoneTop   = levelPrice + zoneHalf;
      lv.zoneBot   = levelPrice - zoneHalf;
      lv.isSupport = true;
      lv.formedAt  = r[i].time;
      lv.barShift  = i;
      lv.levelType = SNR_CLASSIC;
      lv.valid     = true;

      // Count touches (strength)
      lv.touchCount = CountLevelTouches(r, cnt, levelPrice, zoneHalf);

      // Check freshness
      lv.isFresh = IsLevelFresh(r, cnt, i, levelPrice, true);
      if(InpFreshLevelsOnly && !lv.isFresh) continue;

      // Check if flipped (was resistance, now support - RBS)
      lv.isFlipped = IsLevelFlipped(r, cnt, i, levelPrice, true);
      if(lv.isFlipped) lv.levelType = SNR_FLIPPED;

      // Confluence score
      lv.strength = CalculateLevelStrength(lv, r, cnt, confirmTF);

      // Keep strongest
      if(!best.valid || lv.strength > best.strength)
         best = lv;
   }

   // Also scan for QML and Failed QML
   if(InpUseQMLPattern || InpUseFailedQML)
   {
      SSNRLevel qml = FindQMLSupport(r, cnt, ask);
      if(qml.valid && qml.strength > best.strength)
         best = qml;
   }

   return best;
}

SSNRLevel FindBestResistanceLevel(ENUM_TIMEFRAMES scalpTF, ENUM_TIMEFRAMES confirmTF)
{
   SSNRLevel best;
   best.valid = false;
   best.strength = 0;

   MqlRates r[];
   int cnt = CopyRates(_Symbol, scalpTF, 0, InpSNRLookback, r);
   if(cnt < 20) return best;
   ArraySetAsSeries(r, true);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pip = GetPipSize();
   double zoneHalf = InpLevelZonePips * pip;

   for(int i = 3; i < cnt - 3; i++)
   {
      // Classic resistance: swing high (A-shape on line chart)
      bool swingHigh = (r[i].high > r[i-1].high && r[i].high > r[i-2].high &&
                        r[i].high > r[i+1].high && r[i].high > r[i+2].high);

      if(!swingHigh) continue;

      double levelPrice = r[i].close; // KTL: SNR at close price
      double dist = levelPrice - bid;

      if(dist <= 0) continue;
      double maxDist = GetATRValue() * 3.0;
      if(dist > maxDist) continue;
      double minDist = GetATRValue() * 0.1;
      if(dist < minDist) continue;

      SSNRLevel lv;
      lv.price        = levelPrice;
      lv.zoneTop      = levelPrice + zoneHalf;
      lv.zoneBot      = levelPrice - zoneHalf;
      lv.isSupport    = false;
      lv.formedAt     = r[i].time;
      lv.barShift     = i;
      lv.levelType    = SNR_CLASSIC;
      lv.valid        = true;

      lv.touchCount   = CountLevelTouches(r, cnt, levelPrice, zoneHalf);
      lv.isFresh      = IsLevelFresh(r, cnt, i, levelPrice, false);
      if(InpFreshLevelsOnly && !lv.isFresh) continue;

      lv.isFlipped    = IsLevelFlipped(r, cnt, i, levelPrice, false);
      if(lv.isFlipped) lv.levelType = SNR_FLIPPED;

      lv.strength     = CalculateLevelStrength(lv, r, cnt, confirmTF);

      if(!best.valid || lv.strength > best.strength)
         best = lv;
   }

   if(InpUseQMLPattern || InpUseFailedQML)
   {
      SSNRLevel qml = FindQMLResistance(r, cnt, bid);
      if(qml.valid && qml.strength > best.strength)
         best = qml;
   }

   return best;
}

//+------------------------------------------------------------------+
//| QML PATTERN DETECTION (Head & Shoulder)                         |
//+------------------------------------------------------------------+
SSNRLevel FindQMLSupport(MqlRates &r[], int cnt, double ask)
{
   SSNRLevel lv;
   lv.valid = false;

   double pip = GetPipSize();
   double zone = InpLevelZonePips * pip;

   for(int i = 5; i < cnt - 5; i++)
   {
      // Head and shoulder pattern as support:
      // Low1 (LS) > Low2 (Head) < Low3 (RS), all touching similar level
      double low1 = 0, low2 = 0, low3 = 0;
      int i1 = -1, i2 = -1, i3 = -1;

      // Find 3 swing lows
      int found = 0;
      for(int j = i; j < MathMin(i + 30, cnt - 2) && found < 3; j++)
      {
         if(r[j].low < r[j-1].low && r[j].low < r[j+1].low)
         {
            found++;
            if(found == 1) { low1 = r[j].close; i1 = j; }
            if(found == 2) { low2 = r[j].close; i2 = j; }
            if(found == 3) { low3 = r[j].close; i3 = j; }
         }
      }

      if(found < 3) continue;

      // QML: left shoulder and right shoulder are at similar level, head is lower
      double shoulderLevel = (low1 + low3) / 2.0;
      bool shoulderMatch   = MathAbs(low1 - low3) < zone * 2;
      bool headLower       = low2 < shoulderLevel - zone;

      if(shoulderMatch && headLower)
      {
         // This is a head & shoulder support (QML) - neckline is at shoulder level
         double neckline = shoulderLevel;
         double dist = ask - neckline;
         if(dist > 0 && dist < GetATRValue() * 4)
         {
            lv.price     = neckline;
            lv.zoneTop   = neckline + zone;
            lv.zoneBot   = neckline - zone;
            lv.isSupport = true;
            lv.isFresh   = true;
            lv.isFlipped = false;
            lv.levelType = InpUseQMLPattern ? SNR_QML : SNR_CLASSIC;
            lv.formedAt  = r[i3].time;
            lv.barShift  = i3;
            lv.touchCount= 3;
            lv.strength  = 0.75;
            lv.valid     = true;
            return lv;
         }
      }

      // Failed QML: price attempts breakout below head but fails, bounces
      if(headLower && !shoulderMatch)
      {
         double dist = ask - low2;
         if(dist > 0 && dist < GetATRValue() * 4 && InpUseFailedQML)
         {
            lv.price     = low2;
            lv.zoneTop   = low2 + zone;
            lv.zoneBot   = low2 - zone;
            lv.isSupport = true;
            lv.isFresh   = true;
            lv.isFlipped = false;
            lv.levelType = SNR_FAILED_QML;
            lv.formedAt  = r[i2].time;
            lv.barShift  = i2;
            lv.touchCount= 2;
            lv.strength  = 0.70;
            lv.valid     = true;
            return lv;
         }
      }
   }
   return lv;
}

SSNRLevel FindQMLResistance(MqlRates &r[], int cnt, double bid)
{
   SSNRLevel lv;
   lv.valid = false;

   double pip  = GetPipSize();
   double zone = InpLevelZonePips * pip;

   for(int i = 5; i < cnt - 5; i++)
   {
      double high1 = 0, high2 = 0, high3 = 0;
      int found = 0;

      for(int j = i; j < MathMin(i + 30, cnt - 2) && found < 3; j++)
      {
         if(r[j].high > r[j-1].high && r[j].high > r[j+1].high)
         {
            found++;
            if(found == 1) high1 = r[j].close;
            if(found == 2) high2 = r[j].close;
            if(found == 3) { high3 = r[j].close; }
         }
      }

      if(found < 3) continue;

      double shoulderLevel = (high1 + high3) / 2.0;
      bool shoulderMatch   = MathAbs(high1 - high3) < zone * 2;
      bool headHigher      = high2 > shoulderLevel + zone;

      if(shoulderMatch && headHigher)
      {
         double neckline = shoulderLevel;
         double dist = neckline - bid;
         if(dist > 0 && dist < GetATRValue() * 4)
         {
            lv.price     = neckline;
            lv.zoneTop   = neckline + zone;
            lv.zoneBot   = neckline - zone;
            lv.isSupport = false;
            lv.isFresh   = true;
            lv.isFlipped = false;
            lv.levelType = InpUseQMLPattern ? SNR_QML : SNR_CLASSIC;
            lv.touchCount= 3;
            lv.strength  = 0.75;
            lv.valid     = true;
            return lv;
         }
      }

      if(headHigher && !shoulderMatch && InpUseFailedQML)
      {
         double dist = high2 - bid;
         if(dist > 0 && dist < GetATRValue() * 4)
         {
            lv.price     = high2;
            lv.zoneTop   = high2 + zone;
            lv.zoneBot   = high2 - zone;
            lv.isSupport = false;
            lv.isFresh   = true;
            lv.levelType = SNR_FAILED_QML;
            lv.touchCount= 2;
            lv.strength  = 0.70;
            lv.valid     = true;
            return lv;
         }
      }
   }
   return lv;
}

//+------------------------------------------------------------------+
//| SNR LEVEL UTILITY FUNCTIONS                                      |
//+------------------------------------------------------------------+
int CountLevelTouches(MqlRates &r[], int cnt, double levelPrice, double zone)
{
   int touches = 0;
   for(int i = 0; i < cnt; i++)
   {
      if(r[i].low  <= levelPrice + zone && r[i].low  >= levelPrice - zone) { touches++; continue; }
      if(r[i].high <= levelPrice + zone && r[i].high >= levelPrice - zone) { touches++; continue; }
      if(r[i].close<= levelPrice + zone && r[i].close>= levelPrice - zone) { touches++; }
   }
   return touches;
}

bool IsLevelFresh(MqlRates &r[], int cnt, int levelBarShift, double levelPrice, bool isSupport)
{
   double zone = InpLevelZonePips * GetPipSize() * 2;
   // Fresh = price has NOT closed significantly through this level since it formed
   for(int i = 0; i < levelBarShift; i++)
   {
      if(isSupport  && r[i].close < levelPrice - zone) return false;
      if(!isSupport && r[i].close > levelPrice + zone) return false;
   }
   return true;
}

bool IsLevelFlipped(MqlRates &r[], int cnt, int levelBarShift, double levelPrice, bool isSupport)
{
   // Flipped: level was previously broken (acted as opposite type) - classic SBR / RBS
   double zone = InpLevelZonePips * GetPipSize();
   for(int i = levelBarShift + 1; i < cnt - 1; i++)
   {
      if(isSupport  && r[i].close < levelPrice - zone) return true;  // Was once below = it was resistance, now flipped to support
      if(!isSupport && r[i].close > levelPrice + zone) return true;  // Was once above = it was support, now flipped to resistance
   }
   return false;
}

double CalculateLevelStrength(SSNRLevel &lv, MqlRates &r[], int cnt, ENUM_TIMEFRAMES confirmTF)
{
   double score = 0.0;

   // Touch count (more touches = stronger)
   if(lv.touchCount >= 1) score += 0.15;
   if(lv.touchCount >= 2) score += 0.10;
   if(lv.touchCount >= 3) score += 0.10;

   // Freshness
   if(lv.isFresh) score += 0.20;

   // Flipped level (stronger - supply/demand flip)
   if(lv.isFlipped) score += 0.20;

   // QML patterns
   if(lv.levelType == SNR_QML)        score += 0.25;
   if(lv.levelType == SNR_FAILED_QML) score += 0.20;

   // Check if confirmed on higher confirmation TF
   MqlRates cr[];
   if(CopyRates(_Symbol, confirmTF, 0, 50, cr) > 10)
   {
      ArraySetAsSeries(cr, true);
      double zone = InpLevelZonePips * GetPipSize() * 2;
      for(int i = 0; i < 50; i++)
      {
         if(MathAbs(cr[i].close - lv.price) <= zone ||
            MathAbs(cr[i].low   - lv.price) <= zone ||
            MathAbs(cr[i].high  - lv.price) <= zone)
         {
            score += 0.20;  // HTF confluence
            break;
         }
      }
   }

   return MathMin(score, 1.0);
}

//+------------------------------------------------------------------+
//| SCALP OPPORTUNITY DETECTOR                                       |
//| Confirms price IS at the SNR level and shows rejection signal   |
//+------------------------------------------------------------------+
SScalpOpportunity DetectScalpOpportunity(SSNRLevel &snr, int bias,
                                          SAsianRange &ar, SMarketStructure &ms,
                                          SMarketProfile &mp)
{
   SScalpOpportunity opp;
   opp.detected   = false;
   opp.confidence = 0.0;

   MqlRates r[];
   int cnt = CopyRates(_Symbol, InpScalpTF, 0, 20, r);
   if(cnt < 5) return opp;
   ArraySetAsSeries(r, true);

   double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pip      = GetPipSize();
   double zoneSize = InpLevelZonePips * pip * 2;

   // --- BUY OPPORTUNITY: Price at support, showing bullish rejection ---
   if(bias == BIAS_BULL && snr.isSupport)
   {
      // Price must be touching the zone
      bool atZone = (bid >= snr.zoneBot && bid <= snr.zoneTop + zoneSize);
      if(!atZone) return opp;

      // Candle rejection signals (KTL storyline: rejection + breakout)
      bool pinBarLow    = (r[1].close > r[1].open) &&                             // bullish candle
                          ((r[1].open - r[1].low) > (r[1].close - r[1].open));    // long lower wick
      bool engulf       = (r[0].close > r[0].open) &&                             // current bullish
                          (r[0].open  < r[1].close) &&                            // opened below prev close
                          (r[0].close > r[1].open);                               // closed above prev open
      bool doji         = MathAbs(r[1].close - r[1].open) < (r[1].high - r[1].low) * 0.25;
      bool priceClosed  = r[1].close > snr.price;                                 // closed above level

      if(!pinBarLow && !engulf && !doji) return opp;

      double conf = snr.strength;
      if(pinBarLow)   conf += 0.15;
      if(engulf)      conf += 0.20;
      if(doji)        conf += 0.10;
      if(priceClosed) conf += 0.10;

      // Asian range confluence
      if(ar.valid)
      {
         bool nearAL = MathAbs(bid - ar.low) < GetATRValue() * 1.5;
         bool nearAM = MathAbs(bid - ar.mid) < GetATRValue();
         if(nearAL || nearAM) conf += 0.15;
      }

      // Market structure confluence
      if(ms.isHHHL) conf += 0.10;

      opp.detected       = true;
      opp.isBuy          = true;
      opp.entryZoneLow   = bid;
      opp.entryZoneHigh  = ask;
      opp.confirmPrice   = ask;
      opp.sl             = snr.zoneBot - (InpSLBufferPoints * _Point);
      opp.tp             = ask + (MathAbs(ask - opp.sl) * InpScalpRR);
      opp.confidence     = MathMin(conf, 1.0);
      opp.reason         = "BUY@Support " + DoubleToString(snr.price, _Digits) +
                           " Type=" + SNRTypeStr(snr.levelType) +
                           " Conf=" + DoubleToString(conf * 100, 0) + "%";
   }

   // --- SELL OPPORTUNITY: Price at resistance, showing bearish rejection ---
   if(bias == BIAS_BEAR && !snr.isSupport)
   {
      bool atZone = (ask <= snr.zoneTop && ask >= snr.zoneBot - zoneSize);
      if(!atZone) return opp;

      bool pinBarHigh = (r[1].close < r[1].open) &&
                        ((r[1].high - r[1].open) > (r[1].open - r[1].close));
      bool engulf     = (r[0].close < r[0].open) &&
                        (r[0].open  > r[1].close) &&
                        (r[0].close < r[1].open);
      bool doji       = MathAbs(r[1].close - r[1].open) < (r[1].high - r[1].low) * 0.25;
      bool priceClosed= r[1].close < snr.price;

      if(!pinBarHigh && !engulf && !doji) return opp;

      double conf = snr.strength;
      if(pinBarHigh)  conf += 0.15;
      if(engulf)      conf += 0.20;
      if(doji)        conf += 0.10;
      if(priceClosed) conf += 0.10;

      if(ar.valid)
      {
         bool nearAH = MathAbs(ask - ar.high) < GetATRValue() * 1.5;
         bool nearAM = MathAbs(ask - ar.mid)  < GetATRValue();
         if(nearAH || nearAM) conf += 0.15;
      }

      if(ms.isLHLL) conf += 0.10;

      opp.detected       = true;
      opp.isBuy          = false;
      opp.entryZoneLow   = bid;
      opp.entryZoneHigh  = ask;
      opp.confirmPrice   = bid;
      opp.sl             = snr.zoneTop + (InpSLBufferPoints * _Point);
      opp.tp             = bid - (MathAbs(opp.sl - bid) * InpScalpRR);
      opp.confidence     = MathMin(conf, 1.0);
      opp.reason         = "SELL@Resistance " + DoubleToString(snr.price, _Digits) +
                           " Type=" + SNRTypeStr(snr.levelType) +
                           " Conf=" + DoubleToString(conf * 100, 0) + "%";
   }

   return opp;
}

string SNRTypeStr(ESNRType t)
{
   switch(t)
   {
      case SNR_CLASSIC:    return "Classic";
      case SNR_FLIPPED:    return "Flipped";
      case SNR_QML:        return "QML";
      case SNR_FAILED_QML: return "FailedQML";
      case SNR_GAP:        return "Gap";
      default:             return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| KTL AXIS ALIGNMENT CHECK                                         |
//| All 3 pillars must align: Key Level + Time + Liquidity           |
//+------------------------------------------------------------------+
bool IsAxisAligned(STradeSetup &setup, SAsianRange &ar, SSessionInfo &si,
                   int bias, SMarketProfile &mp)
{
   // Pillar 1 - KEY LEVEL: must have valid SNR level (already confirmed)
   if(!setup.snrLevel.valid) return false;

   // Pillar 2 - TIME: session must be active (unless synthetic 24/7)
   if(!mp.is24_7 && !si.allowed)
   {
      Log("Axis FAIL: Time filter - session not active.");
      return false;
   }

   // Pillar 3 - LIQUIDITY: check if a liquidity sweep preceded the move
   bool liquidityConfirm = false;

   if(!ar.valid)
   {
      // If no Asian range data, accept the setup on SNR + bias alone
      liquidityConfirm = true;
   }
   else
   {
      double cp = setup.isBuy ?
                  SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                  SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double atr = GetATRValue();

      if(setup.isBuy)
      {
         // For BUY: Asian low was swept (liquidity grab below), price now bouncing
         bool asianLowSwept = ar.lowSwept || (cp > ar.low && MathAbs(cp - ar.low) < atr * 2);
         bool nearMidline   = MathAbs(cp - ar.mid) < atr * 1.5;
         liquidityConfirm   = asianLowSwept || nearMidline;
      }
      else
      {
         // For SELL: Asian high was swept (liquidity grab above), price now dropping
         bool asianHighSwept = ar.highSwept || (cp < ar.high && MathAbs(cp - ar.high) < atr * 2);
         bool nearMidline    = MathAbs(cp - ar.mid) < atr * 1.5;
         liquidityConfirm    = asianHighSwept || nearMidline;
      }
   }

   if(!liquidityConfirm)
      Log("Axis: Liquidity not perfectly aligned - proceeding with SNR+Bias confluence only.");

   // Direction alignment
   if(setup.isBuy  && bias != BIAS_BULL) return false;
   if(setup.isSell && bias != BIAS_BEAR) return false;

   // R:R check
   if(setup.rrRatio < InpMinRRAllowed)
   {
      Log("Axis FAIL: R:R " + DoubleToString(setup.rrRatio, 2) + " below minimum " + DoubleToString(InpMinRRAllowed, 2));
      return false;
   }

   Log("AXIS ALIGNED: " + setup.label + " | Confidence=" + DoubleToString(setup.confidence * 100, 0) + "%");
   return true;
}

//+------------------------------------------------------------------+
//| ENTRY CONFIRMATION (Candle Close - KTL Storyline)               |
//| "Wait for rejection + breakout" before executing                 |
//+------------------------------------------------------------------+
bool IsEntryConfirmed(STradeSetup &setup, int bias)
{
   MqlRates r[];
   int cnt = CopyRates(_Symbol, InpScalpTF, 0, 5, r);
   if(cnt < 3) return false;
   ArraySetAsSeries(r, true);

   // Bar 1 is the last closed bar
   double bodySize  = MathAbs(r[1].close - r[1].open);
   double wickSize  = r[1].high - r[1].low;
   double halfWick  = wickSize * 0.5;

   if(setup.isBuy)
   {
      // Confirmation: bullish close above SNR level
      bool bullishClose  = r[1].close > r[1].open;
      bool closedAboveSNR= r[1].close > setup.snrLevel.price;
      bool strongBody    = bodySize > halfWick * 0.3; // body is at least 30% of range

      // Additional: consecutive confirmation bar also bullish
      bool bar2Bullish   = r[0].close > r[0].open;

      return (bullishClose && closedAboveSNR) || (bullishClose && strongBody && bar2Bullish);
   }

   if(setup.isSell)
   {
      bool bearishClose  = r[1].close < r[1].open;
      bool closedBelowSNR= r[1].close < setup.snrLevel.price;
      bool strongBody    = bodySize > halfWick * 0.3;
      bool bar2Bearish   = r[0].close < r[0].open;

      return (bearishClose && closedBelowSNR) || (bearishClose && strongBody && bar2Bearish);
   }

   return false;
}

//+------------------------------------------------------------------+
//| BUILD FULL TRADE SETUP                                           |
//+------------------------------------------------------------------+
STradeSetup BuildTradeSetup(SScalpOpportunity &opp, SSNRLevel &snr, int bias, SMarketProfile &mp)
{
   STradeSetup setup;
   setup.valid = false;
   setup.snrLevel = snr;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Dynamic SL using ATR
   double atr = GetATRValue();
   double slDist = 0;

   if(setup.isBuy || opp.isBuy)
   {
      setup.isBuy   = true;
      setup.isSell  = false;
      setup.entry   = ask;

      if(InpUseDynamicSL)
         slDist = MathMax(MathAbs(ask - opp.sl), atr * InpATRMultiplierSL);
      else
         slDist = MathAbs(ask - opp.sl);

      setup.sl  = ask - slDist;
      setup.tp1 = ask + slDist;               // 1R
      setup.tp2 = ask + slDist * InpScalpRR;  // Target R:R
      setup.tp3 = ask + slDist * (InpScalpRR + 1.0); // Extended
   }
   else
   {
      setup.isBuy   = false;
      setup.isSell  = true;
      setup.entry   = bid;

      if(InpUseDynamicSL)
         slDist = MathMax(MathAbs(opp.sl - bid), atr * InpATRMultiplierSL);
      else
         slDist = MathAbs(opp.sl - bid);

      setup.sl  = bid + slDist;
      setup.tp1 = bid - slDist;
      setup.tp2 = bid - slDist * InpScalpRR;
      setup.tp3 = bid - slDist * (InpScalpRR + 1.0);
   }

   setup.slPoints = slDist / _Point;

   // Minimum SL distance check
   if(setup.slPoints < mp.minSLPoints)
   {
      Log("SL too small: " + DoubleToString(setup.slPoints, 0) + " points. Min=" + DoubleToString(mp.minSLPoints, 0));
      return setup;
   }

   // R:R calculation
   double tpDist = MathAbs(setup.tp2 - setup.entry);
   setup.rrRatio = (slDist > 0) ? tpDist / slDist : 0;

   // Lot size calculation
   setup.lots      = CalculateLotSize(slDist, mp);
   setup.confidence= opp.confidence;
   setup.label     = (setup.isBuy ? "BUY" : "SELL") + "_" + SNRTypeStr(snr.levelType);

   if(setup.lots <= 0) return setup;
   setup.valid = true;

   Log("Setup Built: " + setup.label +
       " | Entry=" + DoubleToString(setup.entry, _Digits) +
       " | SL=" + DoubleToString(setup.sl, _Digits) +
       " | TP=" + DoubleToString(setup.tp2, _Digits) +
       " | Lots=" + DoubleToString(setup.lots, 2) +
       " | R:R=" + DoubleToString(setup.rrRatio, 2));

   return setup;
}

//+------------------------------------------------------------------+
//| INTELLIGENT LOT SIZE CALCULATOR                                  |
//| Scales automatically as balance grows ($10 -> $1000+)           |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance, SMarketProfile &mp)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(!InpUseAutoRisk)
   {
      double fl = InpFixedLot * g_currentLotScale;
      return NormalizeLot(fl, minLot, MathMin(maxLot, InpMaxLotsPerTrade), lotStep);
   }

   if(slDistance <= 0) return minLot;

   // Adaptive risk % based on balance tier
   double riskPct;
   if(balance < 100.0)       riskPct = InpRiskPercent;      // Micro: 1% per trade
   else if(balance < 500.0)  riskPct = InpRiskPercentMid;   // Small: 0.75%
   else                      riskPct = InpRiskPercentHigh;  // Growing: 0.5%

   double riskMoney = balance * (riskPct / 100.0);

   // Minimum meaningful risk
   if(riskMoney < 0.01) riskMoney = 0.01;

   // Get pip/point value per lot
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0 || tickSize <= 0) return minLot;

   double valuePerPoint = tickValue * (_Point / tickSize);
   if(valuePerPoint <= 0) return minLot;

   double slPoints = slDistance / _Point;
   double lots     = riskMoney / (slPoints * valuePerPoint);

   // Apply scaling factor (win/loss streak adjustment)
   lots *= g_currentLotScale;

   // Cap at max allowed
   lots = MathMin(lots, InpMaxLotsPerTrade);

   return NormalizeLot(lots, minLot, MathMin(maxLot, InpMaxLotsPerTrade), lotStep);
}

double NormalizeLot(double lots, double minLot, double maxLot, double step)
{
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   lots = MathFloor(lots / step) * step;
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| EXECUTE TRADE                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(STradeSetup &setup)
{
   if(!setup.valid || setup.lots <= 0) return;

   // Check max open trades limit
   if(CountOpenTrades() >= InpMaxOpenTrades)
   {
      Log("Max open trades (" + IntegerToString(InpMaxOpenTrades) + ") reached. Skipping.");
      return;
   }

   string comment = InpRobotLabel + "_" + setup.label;
   bool   result  = false;

   if(setup.isBuy)
      result = g_trade.Buy(setup.lots, _Symbol, setup.entry, setup.sl, setup.tp2, comment);
   else
      result = g_trade.Sell(setup.lots, _Symbol, setup.entry, setup.sl, setup.tp2, comment);

   if(result)
   {
      g_breakEvenDone = false;
      g_partial1Done  = false;
      g_partial2Done  = false;

      Log(">>> TRADE OPENED: " + comment +
          " | Lots=" + DoubleToString(setup.lots, 2) +
          " | Entry=" + DoubleToString(setup.entry, _Digits) +
          " | SL=" + DoubleToString(setup.sl, _Digits) +
          " | TP=" + DoubleToString(setup.tp2, _Digits) +
          " | R:R=" + DoubleToString(setup.rrRatio, 2) +
          " | Confidence=" + DoubleToString(setup.confidence * 100, 0) + "%");
   }
   else
   {
      Log("TRADE FAILED | Code=" + IntegerToString((int)g_trade.ResultRetcode()) +
          " | " + g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| MANAGE OPEN TRADES (Called on every tick)                        |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL     = PositionGetDouble(POSITION_SL);
      double curTP     = PositionGetDouble(POSITION_TP);
      double curPrice  = (ptype == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double slDist = MathAbs(openPrice - curSL);
      if(slDist <= 0) continue;

      // --- BREAK-EVEN ---
      if(InpUseBreakEven && !g_breakEvenDone)
      {
         double beLevel = InpBreakEvenTriggerR * slDist;
         double bePts   = InpBreakEvenOffsetPts * _Point;

         if(ptype == POSITION_TYPE_BUY && curPrice >= openPrice + beLevel)
         {
            double newSL = openPrice + bePts;
            if(newSL > curSL)
            {
               g_trade.PositionModify(ticket, newSL, curTP);
               g_breakEvenDone = true;
               Log("Break-Even applied BUY #" + IntegerToString((int)ticket) +
                   " | NewSL=" + DoubleToString(newSL, _Digits));
            }
         }
         if(ptype == POSITION_TYPE_SELL && curPrice <= openPrice - beLevel)
         {
            double newSL = openPrice - bePts;
            if(newSL < curSL)
            {
               g_trade.PositionModify(ticket, newSL, curTP);
               g_breakEvenDone = true;
               Log("Break-Even applied SELL #" + IntegerToString((int)ticket) +
                   " | NewSL=" + DoubleToString(newSL, _Digits));
            }
         }
      }

      // --- PARTIAL CLOSE 1 (30% at 1R) ---
      if(InpUsePartialClose && !g_partial1Done)
      {
         double trigDist = InpPartial1RR * slDist;
         bool   triggered = false;

         if(ptype == POSITION_TYPE_BUY  && curPrice >= openPrice + trigDist) triggered = true;
         if(ptype == POSITION_TYPE_SELL && curPrice <= openPrice - trigDist) triggered = true;

         if(triggered)
         {
            double curLots = PositionGetDouble(POSITION_VOLUME);
            double closeLots = NormalizeLot(curLots * 0.30,
                                            SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                                            curLots,
                                            SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
            if(closeLots > 0)
            {
               if(ptype == POSITION_TYPE_BUY)
                  g_trade.Sell(closeLots, _Symbol, 0, 0, 0, "Partial1_30pct");
               else
                  g_trade.Buy(closeLots, _Symbol, 0, 0, 0, "Partial1_30pct");

               g_partial1Done = true;
               Log("Partial Close 1 (30%) executed at 1R.");
            }
         }
      }

      // --- PARTIAL CLOSE 2 (30% at 2R) ---
      if(InpUsePartialClose && g_partial1Done && !g_partial2Done)
      {
         double trigDist = InpPartial2RR * slDist;
         bool   triggered = false;

         if(ptype == POSITION_TYPE_BUY  && curPrice >= openPrice + trigDist) triggered = true;
         if(ptype == POSITION_TYPE_SELL && curPrice <= openPrice - trigDist) triggered = true;

         if(triggered)
         {
            double curLots = PositionGetDouble(POSITION_VOLUME);
            double closeLots = NormalizeLot(curLots * 0.30,
                                            SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                                            curLots,
                                            SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
            if(closeLots > 0)
            {
               if(ptype == POSITION_TYPE_BUY)
                  g_trade.Sell(closeLots, _Symbol, 0, 0, 0, "Partial2_30pct");
               else
                  g_trade.Buy(closeLots, _Symbol, 0, 0, 0, "Partial2_30pct");

               g_partial2Done = true;
               Log("Partial Close 2 (30%) executed at 2R.");
            }
         }
      }

      // --- TRAILING STOP ---
      if(InpUseTrailing && g_partial1Done)
      {
         double trailTrigger = InpTrailTriggerR * slDist;
         double trailDist    = InpTrailDistPoints * _Point;

         if(ptype == POSITION_TYPE_BUY && curPrice >= openPrice + trailTrigger)
         {
            double newSL = curPrice - trailDist;
            if(newSL > curSL && newSL > openPrice)
            {
               g_trade.PositionModify(ticket, newSL, curTP);
               Log("Trail updated BUY: SL=" + DoubleToString(newSL, _Digits));
            }
         }
         if(ptype == POSITION_TYPE_SELL && curPrice <= openPrice - trailTrigger)
         {
            double newSL = curPrice + trailDist;
            if(newSL < curSL && newSL < openPrice)
            {
               g_trade.PositionModify(ticket, newSL, curTP);
               Log("Trail updated SELL: SL=" + DoubleToString(newSL, _Digits));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION HANDLER (Track wins/losses)                   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC)  != InpMagicNumber) return;
   if(HistoryDealGetString (trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY)  != DEAL_ENTRY_OUT) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                   HistoryDealGetDouble(trans.deal, DEAL_SWAP)   +
                   HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   if(profit > 0)
   {
      g_daily.winCount++;
      g_daily.consecutiveWins++;
      g_daily.consecutiveLosses = 0;
      g_daily.currentProfit    += profit;

      // Scale up lots after consecutive wins
      if(InpScaleOnWin && g_daily.consecutiveWins >= InpScaleWinStreak)
      {
         g_currentLotScale = MathMin(g_currentLotScale * InpScaleMultiplier, 3.0);
         Log("Win streak " + IntegerToString(g_daily.consecutiveWins) +
             " | LotScale=" + DoubleToString(g_currentLotScale, 2));
      }

      Log("WIN +$" + DoubleToString(profit, 2) +
          " | Total today: +$" + DoubleToString(g_daily.currentProfit, 2));
   }
   else if(profit < 0)
   {
      g_daily.lossCount++;
      g_daily.consecutiveLosses++;
      g_daily.consecutiveWins = 0;
      g_daily.currentLoss    += MathAbs(profit);

      // Reduce lots after loss
      if(InpReduceOnLoss)
         g_currentLotScale = MathMax(g_currentLotScale * InpLossReduceFactor, 0.5);

      Log("LOSS -$" + DoubleToString(MathAbs(profit), 2) +
          " | ConsecLoss=" + IntegerToString(g_daily.consecutiveLosses));
   }

   // Update daily stats
   double startBal = g_daily.startBalance;
   if(startBal > 0)
   {
      double netProfit = g_daily.currentProfit - g_daily.currentLoss;
      g_daily.profitPct = (netProfit / startBal) * 100.0;
      g_daily.lossPct   = (g_daily.currentLoss / startBal) * 100.0;

      // Check daily targets
      if(g_daily.profitPct >= InpDailyProfitTarget)
      {
         g_daily.dailyTargetHit = true;
         Log(">>> DAILY PROFIT TARGET HIT: +" + DoubleToString(g_daily.profitPct, 1) + "% | Trading stopped for today.");
      }
      if(g_daily.lossPct >= InpMaxDailyLoss)
      {
         g_daily.dailyLossLimitHit = true;
         Log(">>> DAILY LOSS LIMIT HIT: -" + DoubleToString(g_daily.lossPct, 1) + "% | Trading stopped for today.");
      }
   }
}

//+------------------------------------------------------------------+
//| DAILY STATS MANAGEMENT                                           |
//+------------------------------------------------------------------+
void ResetDailyStats()
{
   g_daily.startBalance       = AccountInfoDouble(ACCOUNT_BALANCE);
   g_daily.currentProfit      = 0;
   g_daily.currentLoss        = 0;
   g_daily.profitPct          = 0;
   g_daily.lossPct            = 0;
   g_daily.winCount           = 0;
   g_daily.lossCount          = 0;
   g_daily.breakEvenCount     = 0;
   g_daily.consecutiveLosses  = 0;
   g_daily.consecutiveWins    = 0;
   g_daily.dailyTargetHit     = false;
   g_daily.dailyLossLimitHit  = false;
   g_breakEvenDone            = false;
   g_partial1Done             = false;
   g_partial2Done             = false;
   g_currentLotScale          = 1.0; // Reset scale each day
}

void ResetDailyStatsIfNewDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_year != g_dayOfYear)
   {
      g_dayOfYear = dt.day_of_year;
      ResetDailyStats();
      Log("New Day | Balance=" + DoubleToString(g_daily.startBalance, 2));
   }
}

//+------------------------------------------------------------------+
//| PROTECTION FILTERS                                               |
//+------------------------------------------------------------------+
bool IsTradingBlocked()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(balance < InpMinBalanceToTrade)
   {
      Log("BLOCK: Balance $" + DoubleToString(balance, 2) + " < minimum $" + DoubleToString(InpMinBalanceToTrade, 2));
      return true;
   }
   if(g_daily.consecutiveLosses >= InpMaxConsecLosses)
   {
      Log("BLOCK: " + IntegerToString(InpMaxConsecLosses) + " consecutive losses.");
      return true;
   }
   if(g_daily.dailyTargetHit)
   {
      Log("BLOCK: Daily target hit.");
      return true;
   }
   if(g_daily.dailyLossLimitHit)
   {
      Log("BLOCK: Daily loss limit hit.");
      return true;
   }
   return false;
}

bool IsSpreadOK(SMarketProfile &mp)
{
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > mp.spreadLimit)
   {
      Log("Spread=" + DoubleToString(spread, 0) + " > limit=" + DoubleToString(mp.spreadLimit, 0));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| NEW BAR DETECTION                                                |
//+------------------------------------------------------------------+
bool IsNewScalpBar()
{
   datetime bt = iTime(_Symbol, InpScalpTF, 0);
   if(bt != g_lastBarTime)
   {
      g_lastBarTime = bt;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| UTILITY FUNCTIONS                                                |
//+------------------------------------------------------------------+
double GetPipSize()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 5 || digits == 3) return _Point * 10;
   if(digits == 2 || digits == 0) return _Point * 100;
   return _Point * 10;
}

int CountOpenTrades()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionSelectByTicket(t))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            (long)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            count++;
   }
   return count;
}

void Log(string msg)
{
   if(InpEnableLogging)
      Print("[" + InpRobotLabel + "] ", msg);
}

//+------------------------------------------------------------------+
//| DASHBOARD (On-Chart Display)                                    |
//+------------------------------------------------------------------+
void InitDashboard()
{
   string objs[] = {g_dashName + "_BG", g_dashName + "_TXT"};
   for(int i = 0; i < ArraySize(objs); i++)
      if(ObjectFind(0, objs[i]) >= 0)
         ObjectDelete(0, objs[i]);
}

void UpdateDashboard()
{
   string name = g_dashName + "_TXT";

   SMarketProfile mp = GetMarketProfile();
   int htfB = GetBias(InpHTFTF);
   int midB = GetBias(InpBiasTF);
   int comb = GetCombinedBias(htfB, midB);
   SSessionInfo si = GetSessionInfo();

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double netDay  = g_daily.currentProfit - g_daily.currentLoss;

   string session = "CLOSED";
   if(mp.is24_7)  session = "24/7";
   else if(si.overlap)   session = "LN-Overlap";
   else if(si.london)    session = "London";
   else if(si.newYork)   session = "New York";
   else if(si.frankfurt) session = "Frankfurt";
   else if(si.asian)     session = "Asian";
   else if(si.nyLunch)   session = "NY Lunch(blk)";

   string text = "--- MarketSpider v2.0 ---\n";
   text += "Symbol  : " + _Symbol + "\n";
   text += "Market  : " + mp.description + "\n";
   text += "Session : " + session + "\n";
   text += "HTF Bias: " + BiasStr(htfB) + "\n";
   text += "Mid Bias: " + BiasStr(midB) + "\n";
   text += "Combined: " + BiasStr(comb) + "\n";
   text += "Balance : $" + DoubleToString(balance, 2) + "\n";
   text += "Equity  : $" + DoubleToString(equity, 2) + "\n";
   text += "Day P/L : $" + DoubleToString(netDay, 2) + " (" + DoubleToString(g_daily.profitPct, 1) + "%)\n";
   text += "Trades  : W=" + IntegerToString(g_daily.winCount) + " L=" + IntegerToString(g_daily.lossCount) + "\n";
   text += "LotScale: " + DoubleToString(g_currentLotScale, 2) + "x\n";
   text += "Open    : " + IntegerToString(CountOpenTrades()) + "/" + IntegerToString(InpMaxOpenTrades);

   if(g_daily.dailyTargetHit)   text += "\n[TARGET HIT - DONE FOR DAY]";
   if(g_daily.dailyLossLimitHit)text += "\n[LOSS LIMIT - DONE FOR DAY]";

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  9);
      ObjectSetString (0, name, OBJPROP_FONT,      "Consolas");
   }

   color dashColor = clrAqua;
   if(comb == BIAS_BULL) dashColor = clrLime;
   if(comb == BIAS_BEAR) dashColor = clrOrangeRed;
   if(g_daily.dailyTargetHit || g_daily.dailyLossLimitHit) dashColor = clrGold;

   ObjectSetInteger(0, name, OBJPROP_COLOR, dashColor);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| END OF MARKETSPIDER v2.0                                        |
//+------------------------------------------------------------------+
