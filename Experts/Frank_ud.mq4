//+------------------------------------------------------------------+
//|                                                     ôðàíê_óä.mq4 |
//|                     Copyright © 2006, Ðàìèëü Ñàôèóëëîâè÷ Èðãèçîâ |
//|                                                popcorn@aaanet.ru |
//+------------------------------------------------------------------+
#define m  20050611  //MH: magic number
//----
extern int tp = 65;  //MH: trailing profit factor
extern int sh = 41;
//----
datetime lastt; 
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int kol_buy()
  {
   int kol_ob = 0;
//----
   for(int i = 0; i < OrdersTotal(); i++)
     {
       if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false) 
           break;
       //----
       if(OrderType() == OP_BUY)  
           kol_ob++;
     }
   return(kol_ob);
  }    
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int kol_sell()
  {
   int kol_os = 0;
//----
   for(int i = 0; i < OrdersTotal(); i++)
     {
       if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false) 
           break;
       //----
       if(OrderType() == OP_SELL)  
           kol_os++;
     }
   return(kol_os);
  }  
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int start()
  {
   int slip, i, ii, tic, total, kk, gle;
   slip = 0; //MH added
   double lotsi = 0.0;
   bool sob = false, sos = false, scb = false, scs = false;

   int kb, kb_max = 0;
   kb = kol_buy() + 1;
   double M_ob[11][8];
   ArrayResize(M_ob,kb);

   int ks = 0, ks_max = 0;
   ks = kol_sell() + 1;
   double M_os[11][8];
   ArrayResize(M_os,ks);
//----------------------------------------------------------------------------------
   ArrayInitialize(M_ob, 0.0);
   int kbi = 0;
   for(i = 0; i < OrdersTotal(); i++)
     {
       if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false) 
           break;
       //----
       if(OrderSymbol() == Symbol() && OrderType() == OP_BUY)
         {
           kbi++;
           M_ob[kbi][0] = OrderTicket();
           M_ob[kbi][1] = OrderOpenPrice();
           M_ob[kbi][2] = OrderLots();
           M_ob[kbi][3] = OrderType();
           M_ob[kbi][4] = OrderMagicNumber();
           M_ob[kbi][5] = OrderStopLoss();
           M_ob[kbi][6] = OrderTakeProfit();
           M_ob[kbi][7] = OrderProfit();
         }
     } 
   M_ob[0][0] = kb; 
//----------------------------------------------------------------------------------
   double max_lot_b = 0.0;
   for(i = 1; i < kb; i++)
       if(M_ob[i][2] > max_lot_b)
         {
           max_lot_b = M_ob[i][2];
           kb_max = i;
         }
   double buy_lev_min = M_ob[kb_max][1];   
//----------------------------------------------------------------------------------
   ArrayInitialize(M_os,0.0);
   int ksi = 0;
   for(i = 0; i < OrdersTotal(); i++)
     {
       if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false) 
           break;
       //----
       if(OrderSymbol()==Symbol() && OrderType()==OP_SELL)
         {
           ksi++;
           M_os[ksi][0] = OrderTicket();
           M_os[ksi][1] = OrderOpenPrice();
           M_os[ksi][2] = OrderLots();
           M_os[ksi][3] = OrderType();
           M_os[ksi][4] = OrderMagicNumber();
           M_os[ksi][5] = OrderStopLoss();
           M_os[ksi][6] = OrderTakeProfit();
           M_os[ksi][7] = OrderProfit();
         }
     } 
   M_os[0][0] = ks; 
//----------------------------------------------------------------------------------
   double max_lot_s = 0.0;
   for(i = 1;i < ks; i++)
       if(M_os[i][2] > max_lot_s)
         {
           max_lot_s = M_os[i][2];
           ks_max = i;
         }
   double sell_lev_max = M_os[ks_max][1];    
//----------------------------------------------------------------------------------
   if(Bars < 100 || IsTradeAllowed() == false) 
       return(0);
//==================================================================================
//If one of the orders touches the TakeProfit level, open it again after the profit has been fixed, i.e., we make "mistakes" ## 2, 4 and 8 one by one.         
   sob = (kol_buy() < 1 || buy_lev_min - sh*Point > Ask) && 
//            AccountFreeMarginCheck(Symbol(), OP_BUY, Lots_Normalize(2.0*max_lot_b)) > 0;
          AccountFreeMargin() > AccountBalance()*0.5;
   sos = (kol_sell() < 1 || sell_lev_max + sh*Point < Bid) &&
//            AccountFreeMarginCheck(Symbol(), OP_SELL, Lots_Normalize(2.0*max_lot_s)) > 0;
          AccountFreeMargin() > AccountBalance()*0.5;
//----------------------------------------------------------------------------------
   if(M_ob[kb_max][2] > 0.0)
       scb = M_ob[kb_max][7] / (M_ob[kb_max][2]*10) > tp;
//----------------------------------------------------------------------------------
   if(M_os[ks_max][2] > 0.0)
       scs = M_os[ks_max][7] / (M_os[ks_max][2]*10) > tp;
   kk = 0;
   ii = 0;
//----------------------------------------------------------------------------------
   if(scb)
     {
       while(kol_buy() > 0 && kk < 3)
         {
           for(i = 1; i <= kb; i++)
             {
               ii = M_ob[i][0];
               //----
               if(!OrderClose(ii,M_ob[i][2],Bid,slip,White)) 
                 {
                   gle = GetLastError();
                   kk++;
                   Print("Îøèáêà ¹", gle, " ïðè close buy ", kk);
                   Sleep(6000);
                   RefreshRates();  
                 }
             }
           kk++;
         }
     }
   kk = 0;  
   ii = 0; 
//----------------------------------------------------------------------------------
   if(scs)
     {
       while(kol_sell() > 0 && kk < 3)
         {
           for(i = 1; i <= ks; i++)
             {
               ii = M_os[i][0];
               //----
               if(!OrderClose(ii,M_os[i][2], Ask, slip, White))
                 {
                   gle = GetLastError();
                   kk++;
                   Print("Îøèáêà ¹", gle, " ïðè close sell ", kk);
                   Sleep(6000);
                   RefreshRates();  
                 }
             }
           kk++;
         }
     }

//==================================================================================
//We will open two opposite orders at the same time to be executed instantly, i.e., we make mistakes #1 and #7. 
   kk = 0; 
   tic = -1;  

   if(sob) 
     {
       if(max_lot_b == 0.0)
           lotsi = 0.1;       //set minimum lotsize
       else 
           lotsi = 2.0*max_lot_b;
   lotsi = Lots_Normalize(lotsi);                          /*MH: Ensure lots is a multiple of allowed lotsize */

       while(tic == -1 && kk < 3)
         {   
           tic = OrderSend(Symbol(), OP_BUY, lotsi, Ask, slip, 0, Ask + (tp + 25)*Point, " ", m, 0, Yellow);   //MH: Stoploss = 0
           Print("tic_buy=", tic);
           //----
           if(tic==-1)
             {
               gle = GetLastError();
               kk++;               
               Print("Îøèáêà ¹", gle, " ïðè buy ", kk);
               Sleep(6000);
               RefreshRates();   
             }
         }   
       lastt = CurTime();
       return;
     }
//----------------------------------------------------------------------------------
   tic = -1;
   kk = 0;  

   if(sos) 
     {
       if(max_lot_s == 0.0)
           lotsi = 0.1;
       else 
           lotsi = 2.0*max_lot_s;
   lotsi = Lots_Normalize(lotsi);                          /*MH: Ensure lots is a multiple of allowed lotsize */

       while(tic == -1 && kk < 3)
         {
           tic = OrderSend(Symbol(), OP_SELL, lotsi, Bid, slip, 0, Bid - (tp + 25)*Point, " ", m, 0, Red);  //MH: Stoploss = 0
           Print("tic_sell=", tic);
           //----
           if(tic == -1)
             {
               gle = GetLastError();
               kk++;               
               Print("Îøèáêà ¹", gle, " ïðè sell ", kk);
               Sleep(6000);
               RefreshRates();   
             }
          }
       lastt = CurTime();
       return;
     }        
  }
//==================================================================================

//-----------------------------------------------------------------------------------------------------------------------------------------
// Normalise Lots to ensure valid number of lots
//-----------------------------------------------------------------------------------------------------------------------------------------
double Lots_Normalize(double LotsRequired)
{
   double LotStep = MarketInfo(_Symbol, MODE_LOTSTEP);

//#ifdef _DEBUG Print("Lots required = ", LotsRequired, ".  LotStep = ", LotStep); #endif
   LotsRequired = MathRound(LotsRequired/LotStep) * LotStep;   /* ensure LotsRequired is a multiple of LotsRequiredtep */
//#ifdef _DEBUG Print("LotsRequired = MathRound(LotsRequired/LotStep) * LotStep: ", LotsRequired); #endif

//ensure LotsRequired are within min and max allowed
   double MinLot = MarketInfo(_Symbol, MODE_MINLOT);
   double MaxLot = MarketInfo(_Symbol, MODE_MAXLOT);
   if (LotsRequired < MinLot)
   {
      LotsRequired = MinLot;
//#ifdef _DEBUG Print("LotsRequired < MinLot, setting LotsRequired to MinLot: ", LotsRequired); #endif
   }
   else if (LotsRequired > MaxLot)
   {
      LotsRequired = MaxLot;
//#ifdef _DEBUG Print("LotsRequired > MaxLot, setting LotsRequired to MaxLot: ", LotsRequired); #endif
   }
   return(LotsRequired);
}
