//+------------------------------------------------------------------+
//|                                                        WHRea.mq4 |
//|                             Copyright © 2011, WHRoeder@yahoo.com |
//|                                        mailto:WHRoeder@yahoo.com |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2011, WHRoeder@yahoo.com"
#property link      "mailto:WHRoeder@yahoo.com"
#define VERSION     "1.0"
//---- input parameters
extern int      Magic.Number.Base               =20110202;
extern int      MM.Fix0.Mod1.Geo2=2;  // Money Management Mode
#define MMMODE_FIXED        0   // $
#define MMMODE_MODERATE     1   // SQRT(MMM*AB)
#define MMMODE_GEOMETRICAL  2   // MMM*AB
#define MMMODE.MAX      2
extern double   MM.PerChart                     =   0.03;
extern double   MM.MaxRisk                      =   0.05;
extern string   Miscellaneous.Open  = "=======================================";
extern string   Miscellaneous.Exit  = "=======================================";
extern string   Miscellaneous       = "=======================================";
extern int      ATR.Length                      =10;
extern int      Days.Mask=63;          //
#define DAYS_MAX    0x3F    // 1<<6-1=63. (S-F)
extern double   TradeHr.UTC.Start               =  24.0;        //
extern double   TradeHr.UTC.End                 =  24.0;        //
extern int      TEF.Enable01                    =   0;
extern int      TEF.Period                      =  30;
extern bool     Srvr.To.UTC.Auto                = true;
extern int      Srvr.To.UTC.Hours               =   0;
extern string   TC.GV.Name="TradeIsBusy";    // Trade Context Global variable
extern double   Slippage.Pips                   =   3.0;
extern bool     Show.Comments                   = true;
extern bool     Show.Objects                    = true;
extern color    Color.TP                        = MediumSeaGreen;
extern color    Color.SL                        = Crimson;
extern color    Color.Buy                       = Lime;
extern color    Color.Sell                      = Red;
extern color    Color.Open                      = White;

//+------------------------------------------------------------------+
//| expert initialization function                                   |
//+------------------------------------------------------------------+
int     magic.number;                           // Export to ModifyStops
string  TF.text,                                // Export to Decide
trading.disabled;                       // \ Export to
double  oo.lots,                                // / start
at.risk.new;                            // Import from LotSize
                                        //++++ These are adjusted for 5 digit brokers.
int     pips2points;    // slippage  3 pips    3=points    30=points
double  pips2dbl;       // Stoploss 15 pips    0.0015      0.00150
int     Digits.pips;    // DoubleToStr(dbl/pips2dbl, Digits.pips)
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int     init()
  {
   if(Digits==5 || Digits==3)
     {    // Adjust for five (5) digit brokers.
      pips2dbl    =Point*10; pips2points =10;   Digits.pips =1;
        } else {    pips2dbl=Point;    pips2points=1;   Digits.pips=0; 
     }
// OrderSend(... Slippage.Pips * pips2points, Bid - StopLossPips * pips2dbl
/*++++ Constants*/
     {
/*++++ Adjust for the current chart timeframe */
        {
         static
         int     TFperiod[]=
           {
            PERIOD_M1,PERIOD_M5,PERIOD_M15,PERIOD_M30,
            PERIOD_H1,PERIOD_H4,PERIOD_D1,PERIOD_W1,
            PERIOD_MN1  
           }
         ;                      static
         string  TFtext[]=
           {
            "M1","M5","M15","M30",
            "H1","H4","D1","W1",
            "MN1"       
           };
         for(int index=0; TFperiod[index]<Period(); index++){}
         TF.text         = TFtext[index];
         magic.number    = Magic.Number.Base + index;
/*---- Adjust for the current chart timeframe */
        }
      trading.disabled="";
      if(IsTesting() && !IsVisualMode())
        {
         Show.Comments=false;
         Show.Objects=false;    
        }
/*---- Constants*/
     }
   OnInit();
/*++++ Check external variables. */
     {
      if(Srvr.To.UTC.Auto && IsTesting())
        {
         Srvr.To.UTC.Auto = false;
         Alert("Warning, use manual GMToffsets only on backtest.",
               " Automatic GMT offset calculation works only on live/demo trading",
               " and should be set as FALSE for backtests - strategy testing."); 
        }
      if(MM.Fix0.Mod1.Geo2<0
         || MM.Fix0.Mod1.Geo2>MMMODE.MAX)
        {
         trading.disabled=StringConcatenate(
                                            "MM.Fix0.Mod1.Geo2 must be 0-",MMMODE.MAX," Trading disabled.");
         Alert(trading.disabled);    Print(trading.disabled);    
        }
      else 
        {  // Init oo.lots and at.risk.new for start/Comment and verify.
         oo.lots=LotSize(10*pips2dbl); // Arbitrary risk.
         double  percent=100*at.risk.new/AccountBalance();
         if(percent>5)
           {
            trading.disabled=StringConcatenate("MM.PerChart ",percent,
                                               "%/trade?  Trading disabled.");
            Alert(trading.disabled);    Print(trading.disabled);    
           }
        }
/*---- Check external variables. */
     }
   if(!IsDllsAllowed()) Alert(
      "Dll calls must be allowed to compute server time to GMT");
   if(!IsTradeAllowed())
     {
      Alert(WindowExpertName(),": ",VERSION," Tradeing not allowed!");
      Print(WindowExpertName(),": ",VERSION," Tradeing not allowed!"); 
     }
   else
#define DIGITS_USD  2
      Comment(WindowExpertName(),": ",VERSION,
              " waiting for ticks. Will trade $",
              DoubleToStr(at.risk.new,DIGITS_USD));
   return(0);
  }   // init()
void OnInit(){ OnInitSS(); OnInitLotSize(); }
//+------------------------------------------------------------------+
//| Trading System Safey Factor                                      |
//+------------------------------------------------------------------+
double  TEF.value,                                  // Export to start, LotSize
WLR.actual, win.fraction;                   // Export to start
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void    ComputeTEF()
  {
/* Initially I have no historical trades so I want to trade the minimum,
     * but I didn't want to have to trade many positions before starting to use
     * TEF. Also if the EA isn't trading much and the Terminal is set to only
     * show one month of history or a small custom period, then there may never
     * be 20 trades in history! So I slowly ramp the TEF to the actual value by
     * using EMAs. */
   static double   averageWin=10,averageLoss=10,winFraction=0.5;
   double          TEFAlpha=2.0/(TEF.Period+1);
   static datetime lastClose;  datetime lastClosePrev=lastClose;
   for(int pos=0; pos<OrdersHistoryTotal(); pos++) if(
      OrderSelect(pos, SELECT_BY_POS, MODE_HISTORY)   // Only orders w/
      &&  OrderCloseTime()    > lastClosePrev             // not yet processed,
      &&  OrderMagicNumber()  == magic.number             // my magic number
      &&  OrderSymbol()       == Symbol()                 // and my pair.
      && OrderType()<=OP_SELL)
        {    // Avoid cr/bal forum.mql4.com/32363
         lastClose=OrderCloseTime();
         double  pips=OrderProfit()/OrderLots();
         if(pips>=0)
           {
            winFraction+=TEFAlpha*(1-winFraction);
            averageWin+=TEFAlpha*(pips-averageWin); 
           }
         else
           {
            averageLoss+=TEFAlpha*(-pips-averageLoss);
            winFraction-=TEFAlpha*winFraction;  
           }// +=TA(0-wf)
        }
      double  averageWinCur=averageWin,averageLossCur=averageLoss;
   win.fraction=winFraction;
   for(pos=OrdersTotal()-1; pos>=0; pos--) if(
      OrderSelect(pos, SELECT_BY_POS)                 // Only my orders w/
      &&  OrderMagicNumber()  == magic.number             // my magic number
      &&  OrderSymbol()       == Symbol() )
        {              // and my pair.
         pips    = OrderProfit()/OrderLots();
         if(pips>=0)
           {
            win.fraction+=TEFAlpha*(1-win.fraction);
            averageWinCur+=TEFAlpha*(pips-averageWinCur); 
           }
         else
           {
            averageLossCur+=TEFAlpha*(-pips-averageLossCur);
            win.fraction-=TEFAlpha*win.fraction;  
           }// +=TA(0-wf)
        }
      WLR.actual=averageWinCur/averageLossCur; // Win/Loss Ratio.
   if(win.fraction<0.11){   TEF.value=0;    }   // Avoid divide by zero.
   else 
     {
      double
      WLRsafe     = (1.1-win.fraction)/(win.fraction-0.1)+1,
      WLRzero     = (1 - win.fraction)/win.fraction;
      TEF.value   = (WLR.actual-WLRzero)/(WLRsafe-WLRzero);
     }   // win.fraction > 0.15
  }
//+------------------------------------------------------------------+
//| Adjust variables for trade direction.                            |
//+------------------------------------------------------------------+
// Export to:
string  op.text;                        // Decide ModifyStops start
double  now.open,                       // Decide
now.close,                      //        ModifyStops start
open.to.Bid,                    // Decide
stop.to.Bid,                    //        ModifyStops
DIR;        // +/-1             // Decide ModifyStops start MathMaxDIR
int     op.code;    // OP_BUY/OP_SELL   // Decide                   LotSize
bool    need2refresh;                   // Import from RelTradeContext
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void    SetDIR(int op)
  {
   if(need2refresh){  RefreshRates(); need2refresh=false; }
   op.code=op;   if(op==OP_BUY)
     {
      now.open    = Ask;              open.to.Bid = Bid-Ask;  // Open at Ask.
      now.close   = Bid;              stop.to.Bid = 0;        // Stop at Bid.
      DIR         = +1.;              op.text     = "Buy";
        } else {
      now.open    = Bid;              open.to.Bid = 0;        // Open at Bid.
      now.close   = Ask;              stop.to.Bid = Bid-Ask;  // Stop at Ask.
      DIR         = -1.;              op.text     = "Sell";
     }
  }   // SetDIR
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void    Refresh()
  {
//int   op.code; // OP_BUY/OP_SELL   // Import from SetDIR
   SetDIR(op.code);     return; 
  }          // Refresh and update.
//+------------------------------------------------------------------+
//| Trade context semaphore.                                         |
//+------------------------------------------------------------------+
void    RelTradeContext()
  {      // Set global variable for GetTradeContext = 0
/*bool  need2refresh;           // Export=T to GetTradeContext=R|T|F,
                                // SetDIR=R|F, start=F, ModifyStops=R|F */
   need2refresh=true;        // Assume caller did a OrderSend/Modify/Close.
   while(!(IsTesting() || IsStopped()))
     {
      GlobalVariableSet(TC.GV.Name,0.0); // Unlock the trade context.
      int _GetLastError= GetLastError();
      if(_GetLastError == 0) break;
      Comment("RelTradeContext: GlobalVariableSet('",
              TC.GV.Name,"',0.0)-Error #",_GetLastError);   Sleep(1000);
     }
  }   // void RelTradeContext()
int  Random(int min,int max){  return(MathRand()/32768.0*(max-min+1)+min);  }
#define ERR_146_MIN_WAIT_MSEC    1000   // Trade context busy random delay min
#define ERR_146_MAX_WAIT_MSEC    5000   // Trade context busy random delay max
void RandomSleep(){ Sleep(Random(ERR_146_MIN_WAIT_MSEC,ERR_146_MAX_WAIT_MSEC));}
#define ERR_146_TIMEOUT_MSEC    60000   // Trade context busy maximum delay
#include <stderror.mqh>                 // ERR_GLOBAL_VARIABLE_NOT_FOUND
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int     GetTradeContext(int maxWaitMsec=ERR_146_TIMEOUT_MSEC)
  {
//  bool    need2refresh;               // Import from RelTradeContext
/*Return codes:*/
     {
#define TC_LOCKED        0  //  Success. The global variable TC.GV.Name
      //                                  was set to 1, locking out others.
#define TC_REFRESH+1  //  Success. The trade context was initially
      //                                  busy, but became free. The market info
      //                                  needed to be refreshed. Recompute trade
      //                                  values if necessary.
#define TC_ERROR        -1  //  Error, interrupted by the user. The
      //                                  expert was removed from the chart, the
      //                                  terminal was closed, the chart period
      //                                  and/or symbol was changed, etc.)
#define TC_TIMEOUT      -2  //  Error, the wait limit was exceeded.
/*************************************************************************/
     }
   if(IsTesting())
     {                     // Only one EA runs under the tester
      if(need2refresh) Refresh();
      return(TC_LOCKED);                  // Context always available.
     }
/* If there is no global variable, create it. If the variable == 1 wait
     * until another thread sets it back to 0. Set it to 1. */
   int     startWaitingTime    = GetTickCount(),   // Remember start time.
   GTCreturn           = TC_LOCKED;        // Assume an idle context.
   bool    TC_locked           = false;            // Not yet.
   while(true)
     {
      if(IsStopped())
        {     // The expert was terminated by the user, abort.
         Print("GTC: The expert was terminated by the user!");
         if(TC_locked) RelTradeContext();
         return(TC_ERROR);
        }
      if(!TC_locked) 
        {                           // Set the semaphore.
         if(GlobalVariableSetOnCondition(TC.GV.Name,1.0,0.0))
           {
            TC_locked=true;                     // Semaphore now set.
            continue;                           // Check for non-sema EAs.
           }
         int _GetLastError=GetLastError();   switch(_GetLastError)
           {
            case 0:                             // Variable exists but is
               break;                          // already set. Need to wait.
            case ERR_GLOBAL_VARIABLE_NOT_FOUND:
               GlobalVariableSet(TC.GV.Name,0.0); // Create it.
               _GetLastError=GetLastError();
               if(_GetLastError==0) continue;
               Print("GetTradeContext: GlobalVariableSet(",TC.GV.Name,
                     ", 0.0) Failed: ",_GetLastError);    // Error
               return(TC_ERROR);
            default:
               Print("GetTradeContext:GlobalVariableSetOnCondition('",
                     TC.GV.Name,"',1.0,0.0)-Error #",_GetLastError);
            break;                      // Exit switch, wait and retry.
           }   // switch(_GetLastError)
        }   // Set the semaphore.
      else if(!IsTradeContextBusy())
        {            // Cleanup and return.
         if(GTCreturn == TC_REFRESH)
           {           // Clear the Wait comment
            Comment(WindowExpertName(),": ",VERSION);
            need2refresh=true;
           }
         if(need2refresh) Refresh();
         return(GTCreturn);
        }
      int delay=GetTickCount()-startWaitingTime;
      if(delay>maxWaitMsec)
        {                   // Abort.
         Print("Waiting time (",maxWaitMsec/1000," sec) exceeded!");
         if(TC_locked) RelTradeContext();
         return(TC_TIMEOUT);
        }
      Comment("Wait until another expert finishes trading... ",delay/1000.);
      RandomSleep();
      GTCreturn=TC_REFRESH;                     // Will need to refresh.
     }   // while
/*NOTREACHED*/
  }   // GetTradeContext
//+------------------------------------------------------------------+
//| Skip useless ticks                                               |
//+------------------------------------------------------------------+
double  CA.below,CA.above=0;         // Export to start
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void    CallAgain(double when,string why)
  {
   static string below="",above="";
   if(when>=Bid && CA.above > when){  CA.above = when;    above=why;  }
   if(when<=Bid && CA.below < when){  CA.below = when;    below=why;  }
//Print(below," ",PriceToStr(CA.below),"<CA<",PriceToStr(CA.above)," ",above,
//  " (", why, " ", PriceToStr(when),")");
   return;
  }
//+------------------------------------------------------------------+
//| expert start function                                            |
//+------------------------------------------------------------------+
int         oo.ticket,  oo.count;           // \  Import
double      oo.price,   equity.at.risk,     //  \ from
oo.SL,      chart.at.risk,      //  / ModifyStops
oo.TP,                          // /
oo.PO,                          // Import from SetStops
oo.OP,                          // Import from Decide
slippage.ave;                   // Import from Decide
string      EA.status="";                   // Import from Decide/LotSize
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int     start()
  {
/*double    TEF.value;                      // \  Import from
//          WLR.actual, win.fraction        // /  ComputeTEF
//double    now.close,                      // \  Import
//double    DIR;    // +/-1                 //  > from
//string    op.text                         // /  SetDIR
//double    CA.below, CA.above;             // Import from CallAgain=R|Set
//bool      need2refresh;                   // Import from RelTradeContext=F
//double    at.risk.new,                    // Import from LotSize
//double    oo.lots,                        // Import from ModifyStops/Init
//string    trading.disabled;               // Import from Init         */
   static datetime Time0;                              #define INF 0x7FFFFFFF
   if(Time0!=Time[0] || Bid<CA.below || Bid>CA.above)
     {  // Important
      CA.below=0;   CA.above=INF;     Time0=Time[0];
      if(trading.disabled!=""){    Comment(trading.disabled);  return(0); }
      need2refresh    = false;                // New tick, data is fresh.
      Analyze();                              // Affects ModifyStop and Decide
      static double bal.at.risk;              // e.a.r changes here only.
      bal.at.risk=AccountEquity()-equity.at.risk-AccountBalance();
     }   // Important
   if(Show.Comments) 
     {
      string
      line1=StringConcatenate(WindowExpertName(),"-",VERSION
                              ," Digits: ",Digits
                              ," Spread: ",DeltaToPips(Ask-Bid)
                              ," Ave. Slippage: ",DeltaToPips(slippage.ave),
                              IfS(" (Bad)"," (Good)",slippage.ave)),
                              line2=StringConcatenate(
                              TimeToStr(TimeGMT(),TIME_MINUTES|TIME_SECONDS)," UTC",
                              IfS(" ("+SDoubleToStr(Srvr.To.UTC.Hours,0)+")"
                              ,"",Srvr.To.UTC.Hours!=0)
                              ," Account Balance: $"
                              ,DoubleToStr(AccountBalance(),DIGITS_USD)
                              ,IfS(SDoubleToStr(bal.at.risk,DIGITS_USD)
                              ,"",bal.at.risk!=0.) ),
                              line3   = StringConcatenate("Risking=$"
                              ,DoubleToStr(chart.at.risk,DIGITS_USD)
                              ,IfS(SDoubleToStr(at.risk.new,DIGITS_USD)
                              ,"",at.risk.new!=0)
                              ," ",EA.status
                              ,IfS(StringConcatenate(" Cnfrm ",
                              PriceToStr(oo.OP)," (",DeltaToPips(
                              MathAbs(oo.OP-Bid)),
                              ")")
                              ,"",oo.OP)
                              ),
                              line4=IfS(StringConcatenate(op.text," ",oo.lots
                              ,IfS("/"+DoubleToStr(oo.count,0),"",oo.count>1)
                              ," " , PriceToStr(oo.price), " ("
                              ,DeltaToPips((Bid-oo.price)*DIR)
                              ,") Order ",oo.ticket),"",oo.count),
                              line5=IfS(StringConcatenate("TP=",PriceToStr(oo.TP)," ("
                              ,DeltaToPips((oo.TP+stop.to.Bid-Bid)*DIR)
                              ,") "),"",oo.TP)
      +IfS(StringConcatenate("PO=",PriceToStr(oo.PO)," ("
           ,DeltaToPips((oo.PO+stop.to.Bid-Bid)*DIR)
           ,") "),"",oo.PO)
      +IfS(StringConcatenate("SL=",PriceToStr(oo.SL)," ("
           ,DeltaToPips((Bid-(oo.SL-stop.to.Bid))*DIR)
           ,") "),"",oo.SL),
           line6=StringConcatenate("TEF=",SDoubleToStr(TEF.value,2)
           ," $W/$L=",DoubleToStr(WLR.actual,1)
           ," ",DoubleToStr(win.fraction*100,0),"%wins"),
           spaces=IfS("                                ","",oo.count);
      Comment(spaces+line1+"\n",spaces+line2+"\n"
              ,spaces+line3+"\n",spaces+line4+"\n"
              ,spaces+line5+"\n",spaces+line6);  
     }
   return(0);
  }   // start
//+------------------------------------------------------------------+
//| Analyze current market                                           |
//+------------------------------------------------------------------+
double  atr;                                            // Export to SetStops
datetime    Time.last.open;                             // Import from Decide
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void    Analyze()
  {              // Analyze determines direction, entry and exits
   oo.OP           = 0;                                        // Remove from
   at.risk.new     = 0;                                        // comment.
   atr=iATR(NULL,0,ATR.Length,1);
  }   // Analyze
double      pattern.trigger,                            // \ Export to
pattern.PO,                                 // / SetStops
pattern.ISL;                                // \ Export to
int         pattern.type;                               // / Decide/SetStops
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void NewPattern(string cmn,int pat,double op,double po,double iSL,int bar)
  {
   int shift=MathMaxI(bar-1,0);
   if(pat != PATT_NONE && Time.last.open > Time[shift])   return;
   if(oo.count!=0) ModifyStops();  // if prev order closed oo.count changes
   else                DIR=0;
   Decide(cmn);
   HLine("Confirmation",oo.OP,Color.Open);
   return;
  }
//+------------------------------------------------------------------+
//| Open a new trade?                                                |
//+------------------------------------------------------------------+
void    Decide(string cmn)
  {                 // Decide new open order price/dir.
/*double    oo.OP                           // Export to start
//datetime  Time.last.open;                 // Export to Analyze
//string    op.text                         // \   Import
//double    now.open,                       //  >  from
//          DIR;    // +/-1                 // /   SetDIR */
/*++++ Day/Time allowed to open*/
     {
      datetime    now = TimeGMT();
      int         DOW = TimeDayOfWeek(now),   /* forum.mql4.com/33851
    // reports DayOfWeek() always returns 5 in the tester. No refresh?*/
      DayMask=1<<DOW;
      //                      #define DAYS_MAX    0x3F// 1<<6-1=63. (S-F)
      //extern int      Days.Mask               =  55;      // Not Wed
      if(Days.Mask  &DayMask==0){  StrApnd(EA.status," Day=",DOW); return; }
      //extern double   TradeHr.UTC.Start   =   7.3;    // London-1
      //extern double   TradeHr.UTC.End     =  12.9;    // NY open
      int secStart    = 3600*TradeHr.UTC.Start,
      secEnd      = 3600*TradeHr.UTC.End,
      hrBeg       = (now-secStart+86400)%86400,
      hrEnd       = (now-secEnd  +86400)%86400;
      if(hrBeg>hrEnd)
        {
         double Tminus=hrBeg/3600.-24;
         StrApnd(EA.status," HR",DoubleToStr(Tminus,2));    return; 
        }
/*---- Day/Time allowed to open*/
     }
#define NO_SL 0 // Compute estimated lot size before confirmation for commnt
#define NO_TP 0 // Recompute lot size after confirmation for exact size.
   double  atRiskNewPrev=at.risk.new,// Save in case not closer.
   newSL           = NO_SL, NU;    SetStops(newSL, NU, NU);
   double  risk            = MathAbs(openNow -open.to.Bid - newSL),
   RRR=profit/MathMax(risk,Point);   // If I open now
   if(RRR<RRRatio.Open)
     {
      if(!oo.OP)
        {                            // Display reason for no opens
         StrApnd(EA.status," ",cmn,"(RRR=",DoubleToStr(RRR,2),
                 "<",DoubleToStr(RRRatio.Open,2),")");
        }
      return;
     }   // RRR
   double  lotsNew=LotSize(risk);
   if(lotsNew<=0.0)
     {                                // Open orders use most
      at.risk.new=atRiskNewPrev;    return;         // available margin.
     }
   if((Bid-pattern.trigger)*DIR <= 0.0)
     {                      // Still below.
      if(MathAbs(oo.OP-Bid) > MathAbs(pattern.trigger-Bid))
        { // I'm closest.
         CallAgain(pattern.trigger,"pt3");                   // Wait.
                                                             // Hysterisis before switching.
         CallAgain((pattern.trigger+oo.OP*2.)/3.,"pt4");
         EA.status   =cmn;
         oo.OP=pattern.trigger;                      // Show line.
        }
      else    CallAgain((pattern.trigger*2.+oo.OP)/3.,"pt5");
      return;
     }   ////////////////////////////////////////////////////////// Open new ordr
   oo.OP           = 0;                                        // Unshow line
   at.risk.new     = 0;                                        // Remove commnt
   pattern.type    = PATT_NONE;                                // No retrigger.
/* Put the magic number in the "Comment" field so you can see it on the
     * Metatrader terminal. This way you can figure out what is what as magic
     * numbers are not available in the user-interface. --LibOrderReliable */
   string  order.comment=StringConcatenate(WindowExpertName()," ",
                                           Symbol(),",",TF.text," (",magic.number,")");
   color   op.color=IfI(Color.Buy,Color.Sell);
// If a trade size is bigger than maxlot, it must be split.
   double  lotStep         = MarketInfo(Symbol(), MODE_LOTSTEP),   //IBFX= 0.01
   maxLot          = MarketInfo(Symbol(), MODE_MAXLOT );   //IBFX=50.00
   for(int split=MathCeil(lotsNew/maxLot);         //  99.99=50.00+49.99
       split>0; split--) 
     {                         // 100.01=33.34+33.33+33.33
      double size=MathCeil(lotsNew/split/lotStep)*lotStep;
      lotsNew-=size;                    #define NO_EXPIRATION 0
      if(GetTradeContext()<TC_LOCKED)
        {
         CallAgain(Bid,"gtc");   break;  
        }
      oo.ticket=OrderSend(Symbol(),op.code,size,
                          now.open,Slippage.Pips*pips2points,
                          NO_SL,NO_TP,order.comment,
                          magic.number,NO_EXPIRATION,op.color);
      if(oo.ticket<0)
        {
         Alert("OrderSend(type=",op.code,
               " (",op.text,"), lots=",size,
               ", price=",PriceToStr(now.open),
               " (",DeltaToPips(now.open-Bid),
               "), SL=0, TP=0, '",order.comment,"', ...) failed: ",
               GetLastError());
         RelTradeContext();      // After GetLastError
         if(!IsTradeAllowed()) Alert("Trading NOT allowed!");
         EA.status="OrderSend Failed"; break; 
        }
      RelTradeContext();          // After GetLastError
      if(!OrderSelect(oo.ticket,SELECT_BY_TICKET))
         Print("OrderSelect(",oo.ticket,",Ticket) failed: ",
               GetLastError());
      else
        {
         static int newCount=0;  if(newCount<20) newCount++;
         double                                  // No refresh.
         slippage        = (OrderOpenPrice() - now.open)*DIR;
         slippage.ave   += (slippage - slippage.ave)/newCount;
         Time.last.open  = OrderOpenTime();
         StrApnd(EA.status," Opened ",op.text," #",oo.ticket,
                 " at ",TimeToStr(Time.last.open,TIME_MINUTES|TIME_SECONDS));
        }
     }   // for(split)
   ModifyStops();                                      // Set TP/SL ASAP
  }   // Decide
string  VWSMA.name; void OnInitSS(){ VWSMA.name="VWSMA("+VWMA.Length+")"; }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void    SetStops(double &SL,double &TP,double &size,double OP=0)
  {
/*
//double    atr                                     // /   Analyze.
//int       oo.count                                // Import from ModifyStops.
//double    oo.PO,                                  // Export to start. */
   if(SL==NO_SL)
     {
      SL=pattern.ISL -stop.to.Bid -DIR *SL.Init.ATR*atr;
      if(OP==0) return;                             // Computing lotsize
     }
/*++++ Disconnection protection*/
     {
      if(TP==NO_TP) TP=now.close;
      double  goal    = (TP - now.close)*DIR,
      pips5   = 5.*pips2dbl,
      atr5    = pips5;    while(atr5 < atr)   atr5 += pips5;
/**/ if(goal<=1.0*atr) TP=MathCeilDIR((now.close+DIR*2.0*atr)/atr5)*atr5;
      else if(goal>=3.0*atr) TP=MathCeilDIR((now.close+DIR*1.5*atr)/atr5)*atr5;
      CallAgain(TP -DIR*atr,"dp1");
      CallAgain(TP -DIR*atr*3.0,"dp2");
/*---- Disconnection protection*/
     }
/* IFTA: VWMA is better then SMA, moves quicker, crosses 2 bars earlier.
     * Trailing stop = Close- nATR will be stopped on a quick spike, use
     * instead: TSL = VWMA - nATR.
     * Nison - cross MA for trail stops */
   double  vwma=VWSMA(VWMA.Length,1);
   Polyline(VWSMA.name,vwma,Color.Open,1);
   double  ma=MathMinDIR(Bid,vwma);    // Handle reversal opens.
   MaximizeDIR(SL,ma -DIR *Stop.MvHd.ATR*atr -stop.to.Bid);
  } // SetStops
//+------------------------------------------------------------------+
//| Modify the stops for all open orders.                            |
//+------------------------------------------------------------------+
double      balance.at.risk;                //  Export to Lotsize
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void    ModifyStops()
  {
/*string    op.text                         // \  Import
//double    now.close,                      //  \ from
//          stop.to.Bid,                    //  / SetDIR
//          DIR;    // +/-1                 // /
//////////////////////////////////////////////X
//double    oo.price,       oo.TP,  oo.PO   // \  Export
//          oo.lots,        oo.SL,          //  \ to
//          equity.at.risk, chart.at.risk   //  / start
//int       oo.ticket,      oo.count        // /
*/
/* A TP or SL can be not closer to the order price (open, limit, or stop) or
     * closing price (filled order) than this amount. A pending order price can
     * be no closer to the current price than this amount. On IBFX it's equal to
     * 30 (3.0 pips.) */
   double  minGapStop=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point,
/* If the current price is closer than this to the TP, SL, (or pending
     * price,) then the existing order can not be modified, closed, or deleted.
     * On IBFX it's equal to zero (in tester,) but I still can't change it if
     * market is closer than minGapStop either. */
   minGapChange=MathMax(minGapStop,
                        MarketInfo(Symbol(),MODE_FREEZELEVEL)*Point),
                        perLotPerPoint  = PointValuePerLot();
   string  symbolChart     = Symbol();
   bool again=true;  while(again)
     {
      again=false;    // Partial/Full Close.
      equity.at.risk  = 0;            // \    Export to   All orders, all chrt
      balance.at.risk = 0;            //  >   to          \ Only orders
      chart.at.risk   = 0;            // X    Lotsize.    / below BE.
      oo.ticket       = 0;            //  \   Export
      oo.TP           = 0;            //   \  to
      oo.SL           = 0;            //    > start
      oo.price        = 0;            //   /  for
      oo.PO           = 0;            //  /   comment     Set by SetStops.
      oo.lots         = 0;            // X    display.    Summed for multiple
      oo.count        = 0;            // _>               open orders.
      double  plTPf=-1,   plSLf=-1,   // Draw one TP/SL
      plTPt=-1,   plSLt=-1;   // line per level.
      DIR             = 0;            // SetDIR if my chart/my orders.
      for(int pos=OrdersTotal()-1; pos>=0; pos--) if(
         OrderSelect(pos,SELECT_BY_POS))
           {
            if(OrderSymbol()==symbolChart)
              {        // My pair
               SetDIR(OrderType());
               if(OrderMagicNumber()==magic.number)
                 {    // My magic number
                  double size = OrderLots();          oo.lots += size;
                  oo.ticket   = OrderTicket();        oo.count++;
                  oo.TP       = OrderTakeProfit();
                  oo.SL       = OrderStopLoss();  oo.price = OrderOpenPrice();
                  if(oo.SL!=NO_SL && (now.close-oo.SL)*DIR<=-pips2dbl)
                    {
/* Do not assume that in a real-money EA that a stop
                         * loss or take profit will actually be executed if the
                         * price has gone through that value. Yes, they are un-
                         * ethical and mean. --LibOrderReliable
                         * IBFX has variable spreads. I see price just below the
                         * SL, but when I try to close I get 4108, unknown
                         * ticket, so I check at -1*pips instead of zero. */
                     Alert("Order #",oo.ticket," ",op.text,
                           " did not stop. Forcing closed. Now="+now.close,
                           ", TP="+oo.TP,", SL="+oo.SL);
                     if(CloseOrder()){  again=true; continue;   }
                     CallAgain(Bid,"gap");
                    }   // Through SL
/**/ if(oo.SL!=NO_SL
SL)*DIR<minGapChange
SL)*DIR>=0)
                    {
                     CallAgain(oo.SL+stop.to.Bid
                               +DIR*(minGapChange+Point),"nSL"); 
                    }
                  else if(oo.TP!=NO_TP
                     && (oo.TP-now.close)*DIR<minGapChange
                     && (oo.TP-now.close)*DIR>=0)
                       {
                        CallAgain(oo.TP+stop.to.Bid
                                  -DIR*(minGapChange+Point),"nTP"); 
                       }
                     else
                       {   // Can modify stops.
                        double  SLorig=oo.SL,TPorig=oo.TP,LSorig=size;
                        SetStops(oo.SL,oo.TP,size,oo.price);
                        if(oo.TP!=TPorig)
                          {                   // Handle TP
                           double  TPmin=now.close+DIR *minGapStop;
                           if((oo.TP-TPmin)*DIR<0)
                             {         // Below min?
                              oo.TP=TPmin;                  // Can't.
                              CallAgain(oo.TP+stop.to.Bid
                                        -DIR*(minGapChange+Point),"mTP");
                             }
                           //if ((TPorig != NO_TP) && (oo.TP-TPorig)*DIR < Point)
                           //  oo.TP = TPorig;                 // TP up only.
                          }
                        if(oo.SL!=SLorig)
                          {                   // Handle SL
                           double  SLmax=now.close -DIR *minGapStop;
                           if((oo.SL-SLmax)*DIR>0)
                             {         // Above max?
                              oo.SL=SLmax;                  // Can't.
                              CallAgain(SLmax+stop.to.Bid
                                        +DIR*(minGapChange+Point),"mSL");
                             }
                           if((SLorig!=NO_SL) && (oo.SL-SLorig)*DIR<Point)
                              oo.SL=SLorig;                 // SL up only.
                          }
                        if(oo.SL!=SLorig || oo.TP!=TPorig)
                          {    // Set Stops
                           if(GetTradeContext()<TC_LOCKED)
                             {
                              CallAgain(Bid,"gtc");
                              oo.SL=SLorig; oo.TP=TPorig; 
                             }
                           else if(!OrderModify(oo.ticket,oo.price,
                              oo.SL,oo.TP,0))
                                {
                                 Alert("OrderModify(ticket=",oo.ticket,
                                       ", price=",PriceToStr(oo.price),
                                       " (",DeltaToPips((now.close-oo.price)*DIR),
                                       "), SL=",PriceToStr(oo.SL),
                                       " (", DeltaToPips((now.close-oo.SL)*DIR),
                                       "), TP=",PriceToStr(oo.TP),
                                       " (",DeltaToPips((oo.TP-now.close)*DIR),
                                       "), ...) failed: ",GetLastError(),
                                       ", bid=",PriceToStr(Bid));
                                 CallAgain(Bid,"OMf");
                                 oo.SL=SLorig; oo.TP=TPorig;
                                }
                              RelTradeContext();      // After GetLastError
                           OrderSelect(oo.ticket,SELECT_BY_TICKET);   // a.r.e
                                                                      //PauseTest();                                                                  //whr moved SL
                          }   // Set stops.
                        if(LSorig!=size)
                          {    // Compiler bug, don't combine
                           if(CloseOrder(oo.ticket,LSorig-size)) // with &&
                              again=true;
                          }
                       }       // Can modify stops.
                  if((plSLf!=SLorig || plSLt!=oo.SL)
                     && oo.SL>0)
                    {
                     plSLf=SLorig; plSLt=oo.SL;
                     double ooSLbid=oo.SL+stop.to.Bid;
                     Polyline("SL"+RJust(oo.ticket%1000,3),ooSLbid,Color.SL);
                     CallAgain(MathMinDIR(Bid,ooSLbid),"SL");
                    }
                  if((plTPf!=TPorig || plTPt!=oo.TP)
                     && oo.TP>0)
                    {
                     plTPf=TPorig; plTPt=oo.TP;
                     double ooTPbid=oo.TP+stop.to.Bid;
                     Polyline("TP"+RJust(oo.ticket%1000,3),ooTPbid,Color.TP);
                     CallAgain(MathMaxDIR(Bid,ooTPbid),"TP");
                    }
                  // Max loss to balance due to this chart
                  double  eRisk=(oo.price-oo.SL)*DIR;
                  if(eRisk>0.) chart.at.risk+=eRisk*size*perLotPerPoint;
                 }   // My magic number (my time frame.)
              }   // My pair
            // All charts, not just my chart, no SetDIR here.
            double  DIRection=Direction(OrderType());
            // Max loss to balance due to all charts
            eRisk=(OrderOpenPrice()-OrderStopLoss())*DIRection;
            if(eRisk>0.) balance.at.risk+=eRisk*OrderLots()*perLotPerPoint;
            // Max loss to equity due to all charts
            eRisk=(OrderClosePrice()-OrderStopLoss())*DIRection;
            equity.at.risk+=eRisk *OrderLots()*perLotPerPoint;
           }   // For OrderSelect
         double AFM=AccountFreeMargin();           // This should never occur.
      if(oo.count>0 && AFM<equity.at.risk && !again)
        {    // EA's race?
         Alert("AccountFreeMargin=",AFM," < ",equity.at.risk
               ,"=Equity Risk, Closing first open order #",oo.ticket
               ," to prevent a margin call");
         if(CloseOrder(oo.ticket)) again=true;
        }
     }   // While(again)
  }   // ModifyStops
//+------------------------------------------------------------------+
//| Lot size computation.                                            |
//+------------------------------------------------------------------+
void    OnInitLotSize()
  {
   equity.at.risk=0; balance.at.risk=0;  chart.at.risk=0;  
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double  LotSize(double risk)
  {
/*double    at.risk.new;                        // Export to init/start
//double    TEF.value,                          // Import from ComputeTEF
//          equity.at.risk                      // \ Import from
//double    chart.at.risk,  balance.at.risk;    // / ModifyStops
//int       op.code; // OP_BUY/OP_SELL          // Import from SetDIR */
/* This function computes the lot size for a trade.
     * Explicit inputs are SL relative to bid/ask (E.G. SL=30*points,)
     * Implicit inputs are the MM mode, the MM multiplier, count currently
     * filled orders by all EA's vs this EA/pair/period count and history.
     * Implicit inputs are all used to reduce available balance the maximum
     * dollar risk allowed. StopLoss determines the maximum dollar risk possible
     * per lot. Lots=maxRisk/maxRiskPerLot
     **************************************************************************/
/*++++ Compute lot size based on account balance and MM mode*/
     {
      double  ab=AccountEquity()-equity.at.risk;
      switch(MM.Fix0.Mod1.Geo2)
        {
         case MMMODE_FIXED:                                              double
            perChrt = MM.PerChart,
            maxRisk = MM.MaxRisk;
            break;
         case MMMODE_MODERATE:
            // See http://articles.mql4.com/631 Fallacies, Part 1: Money
            // Management is Secondary and Not Very Important.
            maxRisk = MathSqrt(MM.MaxRisk  * ab);
            perChrt = MathSqrt(MM.PerChart * ab);
            break;
         case MMMODE_GEOMETRICAL:
            perChrt = MM.PerChart * ab;
            maxRisk = MM.MaxRisk  * ab;
            break;
        }
      ComputeTEF();
      double  minLot  = MarketInfo(Symbol(), MODE_MINLOT),
      lotStep = MarketInfo(Symbol(), MODE_LOTSTEP),
      perLotPerPoint  = PointValuePerLot(),
      maxLossPerLot   = (risk+Slippage.Pips*pips2dbl) * perLotPerPoint,
      size=perChrt/maxLossPerLot; // Must still round to lotStep.
/*---- Compute lot size based on account balance and MM mode*/
     }
/* The broker doesn't care about the at.risk/account balance. They care
     * about margin. Margin used=lots used*marginPerLot and that must be less
     * than free margin available. Using the lesser of size vs
     * AccountFreeMargin / MODE_MARGINREQUIRED should have been sufficient, but
     * the tester was generating error 134 even when marginFree should have been
     * OK. So I also use AccountFreeMarginCheck < 0 which agrees with the
     * tester. Reported at http://forum.mql4.com/35056
     *
     * Second problem, after opening the new order, if free margin then drops to
     * zero we get a margin call. In the tester, the test stops with: "EA:
     * stopped because of Stop Out" So I make sure that the free margin
     * after is larger then the equity risk so I never get a margin call. */
   string status="SL>AE";                            // Assume size < minLot
   while(true)
     {   // Adjust for broker, test for margin, combine with TEF...
      size=MathFloor(MathMax(0,size)/lotStep)*lotStep;
      at.risk.new=size*maxLossPerLot;             // Export for Comment
      if(size<minLot){ at.risk.new=0;    EA.status=status; return(0); }

/* equity.at.risk  += Direction( OrderType() )
         *                  * (OrderClosePrice()-OrderStopLoss())*perPoint;
         * Summed for all open orders.
         * balance.at.risk   += Direction( OrderType() )
         *                  * (OrderOpenPrice()-OrderStopLoss())*perPoint;
         * Summed for all open orders below BE.
         * chart.at.risk is summed for all open orders below BE, this pair/TF */
      if(at.risk.new+chart.at.risk > perChrt)
        {           // one pair, one TF
         size =(perChrt-chart.at.risk)/maxLossPerLot;   // Re-adjust lotStep
         status="PerChrt";     continue;   
        }

      if(at.risk.new+balance.at.risk>maxRisk)
        {           // All charts
         size=(maxRisk-balance.at.risk)/maxLossPerLot;
         status="MaxRisk";     continue;   
        }

      double  AFMC    = AccountFreeMarginCheck(Symbol(), op.code, size),
      eRisk   = equity.at.risk + at.risk.new;
      if(AFMC*0.99<=eRisk)
        {
         size*=0.95;   status="Free Margin";
         continue;   
        }   // Prevent margin call if new trade goes against us.
      break;
     }
   if(TEF.Enable01>0)
     {
      size=MathFloor(size*MathMin(1,TEF.value)/lotStep)*lotStep;
      if(oo.count==0 && size<minLot) size=minLot;  // Not below min
      at.risk.new=size*maxLossPerLot;                 // Export for Comment
      if(size<minLot)
        {
         at.risk.new=0;  EA.status="TEF = "+TEF.value;
         return(0); 
        }
     }
   return(size);   // We're good to go.
  }   // LotSize
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double  PointValuePerLot() 
  { // Value in account currency of a Point of Symbol.
/* In tester I had a sale: open=1.35883 close=1.35736 (0.00147)
     * gain$=97.32/6.62 lots/147 points=$0.10/point or $1.00/pip.
     * IBFX demo/mini       EURUSD TICKVALUE=0.1 MAXLOT=50 LOTSIZE=10,000
     * IBFX demo/standard   EURUSD TICKVALUE=1.0 MAXLOT=50 LOTSIZE=100,000
     *                                  $1.00/point or $10.00/pip.
     *
     * http://forum.mql4.com/33975 CB: MODE_TICKSIZE will usually return the
     * same value as MODE_POINT (or Point for the current symbol), however, an
     * example of where to use MODE_TICKSIZE would be as part of a ratio with
     * MODE_TICKVALUE when performing money management calculations which need
     * to take account of the pair and the account currency. The reason I use
     * this ratio is that although TV and TS may constantly be returned as
     * something like 7.00 and 0.00001 respectively, I've seen this
     * (intermittently) change to 14.00 and 0.00002 respectively (just example
     * tick values to illustrate). */
   return(  MarketInfo(Symbol(), MODE_TICKVALUE)
          /MarketInfo(Symbol(),MODE_TICKSIZE)); // Not Point.
  }
//+------------------------------------------------------------------+
//| Partial order close.                                             |
//+------------------------------------------------------------------+
bool    CloseOrder(int ticket=EMPTY,double size=INF)
  {  // INF == entire.
/**/ if(ticket==EMPTY) ticket=OrderTicket();
   else if(!OrderSelect(ticket,SELECT_BY_TICKET))
     {
      Alert("OrderSelect(",ticket,",ticket) failed: "+GetLastError());
      return(false); 
     }
   double  minLot      = MarketInfo(Symbol(), MODE_MINLOT),
   lotStep     = MarketInfo(Symbol(), MODE_LOTSTEP),
   sizeCurr    = OrderLots(),
   sizeClose   = MathFloor(size/lotStep)*lotStep,
   sizeRem     = sizeCurr - sizeClose;
   if(sizeClose < minLot)                                     return(false);
   if(sizeRem<minLot)
     {
      sizeClose=sizeCurr;   // Close all
      color   op.color=IfI(Color.Buy,Color.Sell);   
     }
   else        op.color= Aqua;
   if(GetTradeContext() < TC_LOCKED)                          return(false);
   if(OrderClose(ticket,sizeClose,now.close,Slippage.Pips*pips2points
      ,op.color)){    RelTradeContext();          return(true);  }
   Alert("OrderClose(ticket=",ticket,", ...) [1] failed: ",GetLastError());
   RelTradeContext();      // After GetLastError
   return(false);
  }
//+------------------------------------------------------------------+
//| EA equivalent of indicator buffers                               |
//+------------------------------------------------------------------+
/*  Example 1:
 *  if (...) Ordermodify(...);
 *  Polyline("SL"+(oo.ticket%99), oo.SL, Color.SL, 0);
 *
 *  Example 2:
 *  double  ELineCurr = iMA(NULL,0, ELine.Period, 0, MODE_EMA, PRICE_CLOSE, 1);
 *  string pln=Polyline("ELine", ELineCurr, Color.ELine, 1);
 *      ObjectSet(pln, OBJPROP_STYLE, STYLE_DOT);
 *      ObjectSetText(pln, "ELine="+DoubleToStr(ELineCurr,Digits), 10);
 ******************************************************************************/
#define POLYLINE_MAX 20 // Must match priceXX[]
string  lineName[POLYLINE_MAX]; // Common to Polyline and PolyLineDelete.
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string  Polyline(string name,double price,color clr,int shift=0)
  {
   if(!Show.Objects) return("");         // Return the actual object name for
   static int           LRU[POLYLINE_MAX]; // further modifications, E.G. style
   for(int idx=0; idx<POLYLINE_MAX; idx++)
     {
      bool new=lineName[idx]!=name;   if(!new) break;    
     }
   if(new)
     {
      for(idx=0; idx<POLYLINE_MAX; idx++) LRU[idx]++;
      idx=ArrayMaximum(LRU);  lineName[idx]=name; 
     }
   LRU[idx]=0;
   double  price00[],price01[],price02[],price03[],price04[],
   price05[],price06[],price07[],price08[],price09[],
   price10[],price11[],price12[],price13[],price14[],
   price15[],price16[],price17[],price18[],price19[];
   switch(idx)
     {
      case  0: return(PLHelper(name, price, clr, idx, new, shift, price00));
      case  1: return(PLHelper(name, price, clr, idx, new, shift, price01));
      case  2: return(PLHelper(name, price, clr, idx, new, shift, price02));
      case  3: return(PLHelper(name, price, clr, idx, new, shift, price03));
      case  4: return(PLHelper(name, price, clr, idx, new, shift, price04));
      case  5: return(PLHelper(name, price, clr, idx, new, shift, price05));
      case  6: return(PLHelper(name, price, clr, idx, new, shift, price06));
      case  7: return(PLHelper(name, price, clr, idx, new, shift, price07));
      case  8: return(PLHelper(name, price, clr, idx, new, shift, price08));
      case  9: return(PLHelper(name, price, clr, idx, new, shift, price09));
      case 10: return(PLHelper(name, price, clr, idx, new, shift, price10));
      case 11: return(PLHelper(name, price, clr, idx, new, shift, price11));
      case 12: return(PLHelper(name, price, clr, idx, new, shift, price12));
      case 13: return(PLHelper(name, price, clr, idx, new, shift, price13));
      case 14: return(PLHelper(name, price, clr, idx, new, shift, price14));
      case 15: return(PLHelper(name, price, clr, idx, new, shift, price15));
      case 16: return(PLHelper(name, price, clr, idx, new, shift, price16));
      case 17: return(PLHelper(name, price, clr, idx, new, shift, price17));
      case 18: return(PLHelper(name, price, clr, idx, new, shift, price18));
      case 19: return(PLHelper(name, price, clr, idx, new, shift, price19));
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string  PLHelper(string name,double price,color clr,int idx,bool new
                 ,int shift,double &mem[])
  {
   datetime    t0=Time[shift];  static datetime timeL[POLYLINE_MAX];
   if(timeL[idx]<Time[shift+1]) new=true; // Missing bar(s), leave a gap.
/**/ if(new)
     {
      if(!ResizeBuffer(mem,2)) return("");
      mem[1]      = price;                static datetime timeF[POLYLINE_MAX];
      timeF[idx]  = t0;                   static color    clrLn[POLYLINE_MAX];
      clrLn[idx]  = clr;                  static int      segNo[POLYLINE_MAX];
      segNo[idx]++;   
     }
   else if(clrLn[idx]!=clr)
     {
      ArrayResize(mem,2);    // Series==true;
      mem[1]      = mem[0];
      timeF[idx]  = timeL[idx];
      clrLn[idx]  = clr;
      segNo[idx]++;   
     }
   else if(timeL[idx]<t0)
     {                      // New bar, remember point.
      if(!ResizeBuffer(mem, ArraySize(mem)+1))               return("");
     }
   mem[0]      = price;        string objName  = name+"_"+RJust(segNo[idx],3);
   timeL[idx]  = t0;           int firstBar    = ArraySize(mem)-1;
   if(t0!=timeF[idx])
      TLine(objName,timeF[idx],mem[firstBar],t0,price,clrLn[idx]);
   else    TLine(objName, t0-Period()*60, mem[firstBar]    // One bar wide
         , t0, price,      clrLn[idx]);     // to be visual

   double maxError=0;  for(int pos=1; pos<firstBar; pos++)
     {
      double
      error=MathAbs(ObjectGetValueByShift(objName,pos+shift)-mem[pos]);
      if(error>maxError){  maxError=error; int maxBar=pos; }
     }
   if(maxError>=pips2dbl)
     {  // Split the line into two segments at max.
      TLine(objName,timeF[idx],mem[firstBar],
            Time[shift+maxBar],mem[maxBar],clrLn[idx]);
      ArrayResize(mem,maxBar+1);     // Drop firstBar..(maxBar+1)
      timeF[idx]=Time[shift+maxBar];
      segNo[idx]++; objName=name+"_"+RJust(segNo[idx],3);
      TLine(objName,timeF[idx],mem[maxBar],t0,price,clrLn[idx]);
     }   // Split the line into two segments at the max.
   return(objName);
  }   // PLHelper
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/*void    PolyLineDelete(string name){
    for (int idx=0; idx < POLYLINE_MAX; idx++) if (lineName[idx] == name){
        lineName[idx] = ""; break;  }
    for(int obj=ObjectsTotal()-1; obj >= 0; obj--){
        string objectName = ObjectName(obj);
        if (StringFind(objectName, name) == 0)  ObjectDelete(objectName);
}   }*/
bool    ResizeBuffer(double &buffer[],int size)
  {
   if(ArraySize(buffer)!=size)
     {
      ArraySetAsSeries(buffer,false);    // Shift values B[2]=B[1]; B[1]=B[0]
      if(ArrayResize(buffer,size)<=0)
        {
         trading.disabled="ArrayResize [1] failed: "+GetLastError()
                          +" Trading disabled.";
         Alert(trading.disabled);    Print(trading.disabled);
         return(false);  
        }
      ArraySetAsSeries(buffer,true);
     }
   return(true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TLine(string name,datetime T0,double P0,datetime T1,double P1
           ,color clr,bool ray=false)
  {
#define WINDOW_MAIN 0
   if(!Show.Objects)  return;
/**/ if(ObjectMove(name,0,T0,P0)) ObjectMove(name,1,T1,P1);
   else if(!ObjectCreate(name,OBJ_TREND,WINDOW_MAIN,T0,P0,T1,P1))
      Alert("ObjectCreate(",name,",TREND) failed: ",GetLastError());
   else if(!ObjectSet(name,OBJPROP_RAY,ray))
      Alert("ObjectSet(",name,",Ray) failed: ",GetLastError());
   if(!ObjectSet(name,OBJPROP_COLOR,clr)) // Allow color change
      Alert("ObjectSet(",name,",Color) [2] failed: ",GetLastError());
   string  P0t = PriceToStr(P0);           if(MathAbs(P0 - P1) >= Point)
   P0t = StringConcatenate(P0t, " to ", PriceToStr(P1));
   if(!ObjectSetText(name,P0t,10))
      Alert("ObjectSetText(",name,") [2] failed: ",GetLastError());
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void HLine(string name,double P0,color clr)
  {  //      #define WINDOW_MAIN 0
   if(!Show.Objects)  return;
/**/ if(ObjectMove(name,0,Time[0],P0)){}
   else if(!ObjectCreate(name,OBJ_HLINE,WINDOW_MAIN,Time[0],P0))
      Alert("ObjectCreate(",name,",HLINE) failed: ",GetLastError());
   if(!ObjectSet(name,OBJPROP_COLOR,clr)) // Allow color change
      Alert("ObjectSet(",name,",Color) [1] failed: ",GetLastError());
   if(!ObjectSetText(name,PriceToStr(P0),10))
      Alert("ObjectSetText(",name,") [1] failed: ",GetLastError());
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/*bool  DtResizeBuffer(datetime& buffer[], int size){
    if (ArraySize(buffer) != size){
        ArraySetAsSeries(buffer, false);    // Shift values B[2]=B[1]; B[1]=B[0]
        if (ArrayResize(buffer, size) <= 0){
            trading.disabled    = "ArrayResize [2] failed: "+GetLastError()
                                + " Trading disabled.");
            Alert(trading.disabled);    Print(trading.disabled);
            return(false);  }
        ArraySetAsSeries(buffer, true);
    }
    return(true);
}*/
//+------------------------------------------------------------------+
//| expert deinitialization function                                 |
//+------------------------------------------------------------------+
int     deinit()
  {
   RelTradeContext();  // Just in case.
   Comment(WindowExpertName()," exited");
   return(0);
  }
//+------------------------------------------------------------------+
//| GMT Time                                                         |
//+------------------------------------------------------------------+
datetime TimeGMT()
  { // TimeCurrent to GMT
   datetime    now=TimeCurrent();                // Under tester, TimeLocal
   if(Srvr.To.UTC.Auto && (!IsTesting()))        // and TimeCurrent are equal
      Srvr.To.UTC.Hours=(LocalTimeGMT()-now+1800)/3600;
   return (now + Srvr.To.UTC.Hours*3600);
  }
#import "kernel32.dll"
int  GetTimeZoneInformation(int &TZInfoArray[]);
#import
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime LocalTimeGMT()
  {    // TimeLocal to GMT
   int TZInfoArray[43];
   int tz=GetTimeZoneInformation(TZInfoArray);      #define DAYLIGHT 2
   int GMTshift=TZInfoArray[0];   /* GetTimeZoneInformation will return
                                         * the right Bias even when it returns
                                         * UNKNOWN==0 */
   if(tz==DAYLIGHT) GMTshift+=TZInfoArray[42];
   return (TimeLocal() + GMTshift*60);
  }
//+------------------------------------------------------------------+
//| Find a local extreme bar value                                   |
//+------------------------------------------------------------------+
int     LocalExtreme(int WS,int LEbar=0,double d=EMPTY_VALUE)
  {
   while(true)
     {
      int LEbarPrev=LEbar;      LEbar=MaximalBar(WS,LEbarPrev,d);
      if(LEbar == LEbarPrev)     return(LEbar);
     }
//NOTREACHED
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int     MaximalBar(int length,int start,double d=EMPTY_VALUE,int mode=EMPTY)
  {
   if(d==EMPTY_VALUE) d=DIR;
   if(mode== EMPTY) mode    = IfI(MODE_HIGH,MODE_LOW,d);  // or MODE_CLOSE
   if(length <  0)
     {
      length  = -length;                  // start..st-(ln-1).
      start  -=(length - 1);             // st-(ln-1)..start.
      if(start < 0){ length += start;    start = 0;  }   // Reduce length.
     }                                                       // start..st+(ln-1).
   if(start+length>Bars) length=Bars-start;
   if(d > 0)  return( Highest(NULL, 0, mode, length, start) );
   else        return(  Lowest(NULL, 0, mode, length, start) );
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/*double MaximalPrice(int length, int start, double d=EMPTY_VALUE,int mode=EMPTY){
    if (d == EMPTY_VALUE)   d   = DIR;
    if (mode == EMPTY)  mode    = IfI(MODE_HIGH, MODE_LOW, d);  // or MODE_CLOSE
    int LE = MaximalBar(length, start, d, mode);
    switch(mode){
        case MODE_OPEN:     return(  Open[LE]);
        case MODE_LOW:      return(   Low[LE]);
        case MODE_HIGH:     return(  High[LE]);
        case MODE_CLOSE:    return( Close[LE]);
        case MODE_VOLUME:   return(Volume[LE]);
    }
}*/
//+------------------------------------------------------------------+
//| Miscellaneous functions                                          |
//+------------------------------------------------------------------+
double  bodySMA(int length,int shift)
  {     // SMA of |O-C|
   double  E.OC=0;
   int     limit=MathMinI(Bars,shift+length),count=MathMaxI(1,limit-shift);
   for(; shift<limit; shift++) E.OC+=MathAbs(Close[shift]-Open[shift]);
   return(E.OC/count);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double  VWSMA(int length,int shift)
  {       // Volume Weighted Moving Average
   double E.VC=0,E.V=0.0001;
   for(int limit=MathMinI(Bars,shift+length); shift<limit; shift++)
     {
      E.V+=Volume[shift];   E.VC+=Volume[shift] *Close[shift];   
     }
   return(E.VC/E.V);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double  MathMaxDIR(double a,double b,double d=EMPTY_VALUE)
  {
   if(d==EMPTY_VALUE) d=DIR;
   if(d>0) return(MathMax(a,b));   return(MathMin(a,b));  
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double  MathMinDIR(double a,double b,double d=EMPTY_VALUE)
  {
   if(d==EMPTY_VALUE) d=DIR;
   if(d>0) return(MathMin(a,b));   return(MathMax(a,b));  
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double  MathCeilDIR(double a,double d=EMPTY_VALUE)
  {
   if(d==EMPTY_VALUE) d=DIR;
   if(d>0) return(MathCeil(a));    return(MathFloor(a));  
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double  IfD(double b,double s,double d=EMPTY_VALUE)
  {
   if(d==EMPTY_VALUE) d=DIR;
   if(d>0) return(b);              return(s);             
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string  IfS(string b,string s,double d=EMPTY_VALUE)
  {
   if(d==EMPTY_VALUE) d=DIR;
   if(d>0) return(b);              return(s);             
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int     IfI(int b,int s,double d=EMPTY_VALUE)
  {
   if(d==EMPTY_VALUE) d=DIR;
   if(d>0) return(b);              return(s);             
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double  MaxPrice(int shift,double d=EMPTY_VALUE)
  {
   if(d==EMPTY_VALUE) d=DIR;
   if(d>0) return(High[shift]);    return(Low[shift]);    
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int     MathMinI(int a,int b)
  {
   if(a<b) return(a);              return(b);             
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int     MathMaxI(int a,int b)
  {
   if(a>b) return(a);              return(b);             
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string  SDoubleToStr(double p,int d)
  {
   return(IfS("+","",p>=0)+DoubleToStr(p,d));     
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string  RJust(string s,int size,string fill="0")
  {
   while(StringLen(s)<size) s=fill+s;       return(s);             
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string  DeltaToPips(double d)
  {
   if(d>0) string sign="+";  else    sign="";
   double pips = d / pips2dbl;
   string dPip = sign + DoubleToStr(pips, 0);  if(Digits.pips==0) return(dPip);
   string dFrc = sign + DoubleToStr(pips, Digits.pips);
   if(dPip+".0"==dFrc) return(dPip);           return(dFrc);          
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string  PriceToStr(double p)
  {
   string pFrc = DoubleToStr(p, Digits);       if(Digits.pips==0) return(pFrc);
   string pPip = DoubleToStr(p, Digits-1);
   if(pPip+"0"==pFrc) return(pPip);           return(pFrc);          
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void    MaximizeDIR(double &a,double b,double d=EMPTY_VALUE)
  {
   a=MathMaxDIR(a,b,d);        return;    
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void    MinimizeDIR(double &a,double b,double d=EMPTY_VALUE)
  {
   a=MathMinDIR(a,b,d);        return;    
  }
double  Sign(double d){ if(d>0) return(+1.);            return(-1.);           }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int     Operation(double d)
  {
   if(d>0) return(OP_BUY);         return(OP_SELL);       
  }
double  Direction(int op_xxx){  return(1.-2. *(op_xxx%2));                }
void    StrApnd(string &v,string a,string b="",string c="",string d="",
                string e="", string f="", string g="", string h="", string i="",
                string j="", string k="", string l="", string m="", string n="")
  {   v=StringConcatenate(v,a,b,c,d,e,f,g,h,i,j,k,l,m,n);   return;}
/* Unused miscellaneous functions
double  MathFloorDIR(double a, double d=EMPTY_VALUE){
    if (d == EMPTY_VALUE) d=DIR;
                        if(d>0) return(MathFloor(a));   return(MathCeil(a));   }
*/
/*double  Fractal(int& LEbar, double& atLeast, double d=EMPTY_VALUE){
    if (d == EMPTY_VALUE)   d=DIR;
    LEbar += 2;
        int hist = MathMinI(500, Bars);
    while(LEbar < hist){
        int LEbarPrev = LEbar;  LEbar = MaximalBar(5, LEbarPrev-2, d);
        if (d > 0){ double  LEprice = High[LEbar];
            if (LEprice < atLeast){     LEbar = LEbarPrev+3;    continue;   }
        }
        else{               LEprice = Low[LEbar];
            if (LEprice > atLeast){     LEbar = LEbarPrev+3;    continue;   }
        }
        atLeast = LEprice;
        if (LEbar == LEbarPrev) break;
        if (LEbar < LEbarPrev)  LEbar = LEbarPrev+3;
    }
    return(atLeast);
}
*/
/*                                          PauseTest
// http://forum.mql4.com/35112 */
#include <WinUser32.mqh>
#import "user32.dll"
int GetAncestor(int,int);
#import
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void PauseTest()
  {
   datetime now=TimeCurrent();   static datetime oncePerTick;
   if(IsTesting() && IsVisualMode() && IsDllsAllowed() && oncePerTick!=now)
     {
      oncePerTick=now;
      for(int i=0; i<200000; i++)
        {        // Delay required for speed=32 (max)
         int main=GetAncestor(WindowHandle(Symbol(),Period()),2 /* GA_ROOT */);
         if(i==0) PostMessageA(main,WM_COMMAND,0x57a,0); // 1402. Pause
        }
     }
  }
//+------------------------------------------------------------------+
