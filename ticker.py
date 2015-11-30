# Give me a list of symbols in the S&P500 that are down more than 10% in one day.
# 
# Joey <jmcdice@gmail.com>
# pip install yahoo-finance
# pip install finsymbols

from finsymbols import get_sp500_symbols
from yahoo_finance import Share

sp500 = get_sp500_symbols()

for d in sp500:
    symbol = d['symbol']
    #print "Checking: %s" % symbol
    stockblob = Share(symbol)
    close = stockblob.get_prev_close()
    close = float(close)
    change = stockblob.get_change()
    change = float(change)

    if change < 0:  # Negative number (stock is down)
        change = abs(change)
        percent = (change / close) * 100
        if percent > 10: # Down more than 10%, looks interesting.
            print "%s is down %s" % (symbol, percent)
