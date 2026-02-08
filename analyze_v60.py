import re
from collections import defaultdict

logfile = r"d:\TRADING BOTS\GOLD BOT FILES\log - 1 min.txt"

with open(logfile, 'r', encoding='utf-8', errors='replace') as f:
    lines = f.readlines()

# === COUNTERS ===
entries = []  # (date, ticket, direction, regime)
exits_by_type = defaultdict(int)
sl_hits = []  # (date, ticket)
deals = []  # (date, side, deal_num, price)
filter_blocks = defaultdict(int)
sl_caps = []  # (atr_sl, capped_sl)
weak_swings = 0
drawdown_alerts = defaultdict(int)
invalid_sl_blocks = 0
h1_vol_blocks = []  # (date, hv_pct)
pyramid_adds = []  # (date, direction, level)
et_hits = []  # (date, direction, profit)
daily_resets = []  # (date, equity_peak, max_dd)
max_hold_exits = 0
emergency_closes = 0

for line in lines:
    # Extract date
    date_match = re.search(r'(\d{4}\.\d{2}\.\d{2})\s+\d{2}:\d{2}:\d{2}', line)
    date_str = date_match.group(1) if date_match else ""
    month_str = date_str[:7] if date_str else ""

    # Trade opened
    m = re.search(r'Trade opened: Ticket (\d+)', line)
    if m:
        ticket = int(m.group(1))
        entries.append((date_str, ticket))
        continue

    # System signal (direction + regime) - parsed in second pass below
    # skip here for efficiency

    # Exit comments
    m = re.search(r'Position closed: (.+?) - Ticket (\d+)', line)
    if m:
        exits_by_type[m.group(1).strip()] += 1
        continue

    # Stop loss triggered
    m = re.search(r'stop loss triggered #(\d+)', line)
    if m:
        sl_hits.append((date_str, int(m.group(1))))
        continue

    # Deal records
    m = re.search(r'deal #(\d+) (buy|sell) [\d.]+ XAUUSD at ([\d.]+) done', line)
    if m:
        deals.append((date_str, m.group(2), int(m.group(1)), float(m.group(3))))
        continue

    # v6.0 FILTER blocks
    if 'v6.0 FILTER:' in line:
        m = re.search(r'v6\.0 FILTER: (.+)', line)
        if m:
            msg = m.group(1).strip()
            # Categorize
            if 'distance to mean' in msg:
                filter_blocks['Entry-mean distance too small'] += 1
            elif 'Key level' in msg:
                filter_blocks['Key level blocking'] += 1
            elif 'not above entry' in msg or 'not below entry' in msg:
                filter_blocks['Mean direction validation'] += 1
            else:
                filter_blocks[msg] += 1
        continue

    # Invalid stop loss level
    if 'Invalid stop loss level' in line:
        invalid_sl_blocks += 1
        continue

    # H1 Vol filter
    m = re.search(r'v6\.0 H1 VOL FILTER: Annualized HV = ([\d.]+)%', line)
    if m:
        h1_vol_blocks.append((date_str, float(m.group(1))))
        continue

    # Pyramid adds
    m = re.search(r'v6\.0 PYRAMID: Adding (BUY|SELL) level (\d+)/(\d+)', line)
    if m:
        pyramid_adds.append((date_str, m.group(1), int(m.group(2))))
        continue

    # Extended Target hits
    m = re.search(r'Extended Target Hit \((BUY|SELL)\):.*Profit: \$([\d.]+)', line)
    if m:
        et_hits.append((date_str, m.group(1), float(m.group(2))))
        continue

    # Weak swing
    if 'Weak swing' in line or 'Weak Swing' in line:
        if 'Position closed' in line or 'MR exit at mean' in line:
            weak_swings += 1
            continue

    # SL Cap
    m = re.search(r'SL CAP: ATR SL \$([\d.]+) -> capped to \$([\d.]+)', line)
    if m:
        sl_caps.append((float(m.group(1)), float(m.group(2))))
        continue

    # Drawdown alerts
    m = re.search(r'DRAWDOWN LEVEL (\d+):', line)
    if m:
        drawdown_alerts[int(m.group(1))] += 1
        continue

    # Max hold exits
    if 'Max hold' in line or 'max hold' in line:
        max_hold_exits += 1
        continue

    # Emergency close
    if 'EMERGENCY' in line and 'close' in line.lower():
        emergency_closes += 1
        continue

    # Daily reset with equity data
    m = re.search(r'Equity Peak: \$([\d.]+)', line)
    if m and 'DAILY RESET' not in line:
        # Just track the values
        pass

# === PAIR DEALS FOR P/L ===
open_positions = {}
paired_trades = []

for date, side, deal_num, price in deals:
    closed_ticket = None
    for open_deal, info in list(open_positions.items()):
        odate, oside, oprice = info
        if (oside == 'buy' and side == 'sell') or (oside == 'sell' and side == 'buy'):
            if oside == 'buy':
                pnl = (price - oprice) * 0.01 * 100
            else:
                pnl = (oprice - price) * 0.01 * 100
            pnl = round(pnl, 2)
            month = odate[:7]
            paired_trades.append((odate, oside, oprice, date, price, pnl, month))
            closed_ticket = open_deal
            break
    if closed_ticket is not None:
        del open_positions[closed_ticket]
    else:
        open_positions[deal_num] = (date, side, price)

# === MATCH ENTRIES TO SIGNALS ===
# Re-parse for direction+regime matching
trade_signals = []
with open(logfile, 'r', encoding='utf-8', errors='replace') as f:
    pending_signal = None
    for line in f:
        m = re.search(r'System 1: (BUY|SELL) \| Regime: (\w+)', line)
        if m:
            date_match = re.search(r'(\d{4}\.\d{2}\.\d{2})', line)
            date_str = date_match.group(1) if date_match else ""
            pending_signal = (date_str, m.group(1), m.group(2))
        if 'Trade opened: Ticket' in line and pending_signal:
            trade_signals.append(pending_signal)
            pending_signal = None

# === RESULTS ===
print("=" * 65)
print("  v6.0 M1 PICKAXE - BACKTEST ANALYSIS")
print("  Log: 108,650 lines | Period: 2025.01.01 - 2026.02.05")
print("=" * 65)

print(f"\nFinal Balance: $3,836.66 (-$1,163.34)")
print(f"Equity Peak:   $5,065.56 (+$65.56)")
print(f"Max Drawdown:  $1,416.11 (28.0% of peak)")

# --- A. TRADE STATISTICS ---
print(f"\n{'='*65}")
print(f"  A. TRADE STATISTICS")
print(f"{'='*65}")
print(f"Total entries (trades opened):  {len(entries)}")
print(f"Total SL hits:                  {len(sl_hits)}")
print(f"Total paired trades:            {len(paired_trades)}")
print(f"Pyramid adds:                   {len(pyramid_adds)}")

print(f"\nExit Type Breakdown:")
for etype, count in sorted(exits_by_type.items(), key=lambda x: -x[1]):
    print(f"  {etype}: {count}")

print(f"\nWeak Swing MR exits: {weak_swings}")
print(f"Extended Target hits: {len(et_hits)}")
if et_hits:
    avg_et = sum(e[2] for e in et_hits) / len(et_hits)
    print(f"  Avg ET profit: ${avg_et:.2f}")
    print(f"  Total ET profit: ${sum(e[2] for e in et_hits):.2f}")

# Win/Loss
wins = [t for t in paired_trades if t[5] > 0]
losses = [t for t in paired_trades if t[5] < 0]
breakevens = [t for t in paired_trades if t[5] == 0]
total_win = sum(t[5] for t in wins)
total_loss = sum(t[5] for t in losses)

print(f"\nFrom paired deals:")
print(f"  Wins:      {len(wins)} (total: +${total_win:.2f}, avg: +${total_win/max(len(wins),1):.2f})")
print(f"  Losses:    {len(losses)} (total: -${abs(total_loss):.2f}, avg: -${abs(total_loss)/max(len(losses),1):.2f})")
print(f"  Breakeven: {len(breakevens)}")
print(f"  Win rate:  {len(wins)/max(len(paired_trades),1)*100:.1f}%")
print(f"  Net P/L:   ${total_win + total_loss:.2f}")
print(f"  Profit Factor: {abs(total_win/min(total_loss,-0.01)):.2f}")

# Avg win vs avg loss ratio
avg_win = total_win / max(len(wins), 1)
avg_loss = abs(total_loss) / max(len(losses), 1)
print(f"  Reward/Risk: {avg_win/max(avg_loss, 0.01):.2f}")

# --- B. FILTER ACTIVITY ---
print(f"\n{'='*65}")
print(f"  B. FILTER & BLOCKING ACTIVITY")
print(f"{'='*65}")

total_filter_blocks = sum(filter_blocks.values())
print(f"v6.0 filter blocks:        {total_filter_blocks}")
print(f"Invalid SL level blocks:   {invalid_sl_blocks}")
print(f"H1 Vol filter days:        {len(h1_vol_blocks)}")
print(f"Total blocks (all types):  {total_filter_blocks + invalid_sl_blocks}")

print(f"\nFilter breakdown:")
for msg, count in sorted(filter_blocks.items(), key=lambda x: -x[1]):
    print(f"  {msg}: {count}")

print(f"\nH1 Volatility Filter triggers:")
for date, hv in h1_vol_blocks:
    print(f"  {date}: HV = {hv:.1f}%")

# --- C. PYRAMID ACTIVITY ---
print(f"\n{'='*65}")
print(f"  C. PYRAMID ACTIVITY")
print(f"{'='*65}")
print(f"Total pyramid adds: {len(pyramid_adds)}")
buy_pyramids = [p for p in pyramid_adds if p[1] == 'BUY']
sell_pyramids = [p for p in pyramid_adds if p[1] == 'SELL']
print(f"  BUY pyramids:  {len(buy_pyramids)}")
print(f"  SELL pyramids: {len(sell_pyramids)}")
if pyramid_adds:
    print(f"\nPyramid add dates:")
    for date, direction, level in pyramid_adds:
        print(f"  {date}: {direction} level {level}")

# --- D. MONTHLY BREAKDOWN ---
print(f"\n{'='*65}")
print(f"  D. MONTHLY BREAKDOWN")
print(f"{'='*65}")
monthly = defaultdict(lambda: {'entries': 0, 'wins': 0, 'losses': 0, 'pnl': 0.0, 'sl': 0, 'et': 0})

# Count entries by month
monthly_entries = defaultdict(int)
for date, ticket in entries:
    m = date[:7]
    monthly_entries[m] += 1

# Count SL by month
for date, ticket in sl_hits:
    m = date[:7]
    monthly[m]['sl'] += 1

# Count ET by month
for date, direction, profit in et_hits:
    m = date[:7]
    monthly[m]['et'] += 1

# P/L by month
for t in paired_trades:
    m = t[6]
    monthly[m]['entries'] += 1
    if t[5] > 0:
        monthly[m]['wins'] += 1
    elif t[5] < 0:
        monthly[m]['losses'] += 1
    monthly[m]['pnl'] += t[5]

print(f"{'Month':<10} {'Entries':>8} {'Wins':>6} {'Losses':>8} {'SL':>5} {'ET':>4} {'WinRate':>8} {'Net P/L':>10}")
print("-" * 65)
running = 0
all_months = sorted(set(list(monthly_entries.keys()) + list(monthly.keys())))
for m in all_months:
    d = monthly[m]
    total = d['wins'] + d['losses']
    wr = d['wins'] / max(total, 1) * 100
    running += d['pnl']
    ent = monthly_entries.get(m, d['entries'])
    print(f"{m:<10} {ent:>8} {d['wins']:>6} {d['losses']:>8} {d['sl']:>5} {d['et']:>4} {wr:>7.1f}% ${d['pnl']:>9.2f}")
print("-" * 65)
total_trades = len(paired_trades)
print(f"{'TOTAL':<10} {len(entries):>8} {len(wins):>6} {len(losses):>8} {len(sl_hits):>5} {len(et_hits):>4} {len(wins)/max(total_trades,1)*100:>7.1f}% ${total_win+total_loss:>9.2f}")
print(f"\nRunning balance check: $5000 + ${total_win+total_loss:.2f} = ${5000+total_win+total_loss:.2f}")

# --- E. REGIME BREAKDOWN ---
print(f"\n{'='*65}")
print(f"  E. REGIME BREAKDOWN")
print(f"{'='*65}")
regime_stats = defaultdict(lambda: {'entries': 0, 'wins': 0, 'losses': 0, 'pnl': 0.0})
direction_stats = defaultdict(lambda: {'entries': 0, 'wins': 0, 'losses': 0, 'pnl': 0.0})

for i, (date, direction, regime) in enumerate(trade_signals):
    regime_stats[regime]['entries'] += 1
    direction_stats[direction]['entries'] += 1
    if i < len(paired_trades):
        pnl = paired_trades[i][5]
        if pnl > 0:
            regime_stats[regime]['wins'] += 1
            direction_stats[direction]['wins'] += 1
        elif pnl < 0:
            regime_stats[regime]['losses'] += 1
            direction_stats[direction]['losses'] += 1
        regime_stats[regime]['pnl'] += pnl
        direction_stats[direction]['pnl'] += pnl

print(f"\nBy Regime:")
print(f"{'Regime':<12} {'Entries':>8} {'Wins':>6} {'Losses':>8} {'WinRate':>8} {'Net P/L':>10}")
print("-" * 55)
for regime in sorted(regime_stats.keys()):
    d = regime_stats[regime]
    total = d['wins'] + d['losses']
    wr = d['wins'] / max(total, 1) * 100
    print(f"{regime:<12} {d['entries']:>8} {d['wins']:>6} {d['losses']:>8} {wr:>7.1f}% ${d['pnl']:>9.2f}")

print(f"\nBy Direction:")
print(f"{'Direction':<12} {'Entries':>8} {'Wins':>6} {'Losses':>8} {'WinRate':>8} {'Net P/L':>10}")
print("-" * 55)
for direction in sorted(direction_stats.keys()):
    d = direction_stats[direction]
    total = d['wins'] + d['losses']
    wr = d['wins'] / max(total, 1) * 100
    print(f"{direction:<12} {d['entries']:>8} {d['wins']:>6} {d['losses']:>8} {wr:>7.1f}% ${d['pnl']:>9.2f}")

# --- F. SL CAP & LOSS DISTRIBUTION ---
print(f"\n{'='*65}")
print(f"  F. SL CAP & LOSS DISTRIBUTION")
print(f"{'='*65}")
print(f"Times SL was dollar-capped: {len(sl_caps)}")
if sl_caps:
    avg_atr = sum(c[0] for c in sl_caps) / len(sl_caps)
    print(f"Average ATR SL before cap: ${avg_atr:.2f}")
    print(f"Max ATR SL before cap: ${max(c[0] for c in sl_caps):.2f}")
    print(f"Min ATR SL before cap: ${min(c[0] for c in sl_caps):.2f}")

loss_amounts = [abs(t[5]) for t in paired_trades if t[5] < 0]
if loss_amounts:
    print(f"\nLoss Distribution:")
    brackets = [(0, 5), (5, 10), (10, 15), (15, 20), (20, 25), (25, 30), (30, 50), (50, 100)]
    print(f"{'Range':<15} {'Count':>8} {'Total':>10} {'Avg':>8}")
    for lo, hi in brackets:
        in_bracket = [l for l in loss_amounts if lo <= l < hi]
        if in_bracket:
            print(f"${lo}-${hi:<10} {len(in_bracket):>8} ${sum(in_bracket):>9.2f} ${sum(in_bracket)/len(in_bracket):>7.2f}")
    big = [l for l in loss_amounts if l >= 100]
    if big:
        print(f"$100+{'':>10} {len(big):>8} ${sum(big):>9.2f} ${sum(big)/len(big):>7.2f}")

# Win distribution
win_amounts = [t[5] for t in paired_trades if t[5] > 0]
if win_amounts:
    print(f"\nWin Distribution:")
    brackets = [(0, 1), (1, 2), (2, 3), (3, 5), (5, 10), (10, 20), (20, 50)]
    print(f"{'Range':<15} {'Count':>8} {'Total':>10} {'Avg':>8}")
    for lo, hi in brackets:
        in_bracket = [w for w in win_amounts if lo <= w < hi]
        if in_bracket:
            print(f"${lo}-${hi:<10} {len(in_bracket):>8} ${sum(in_bracket):>9.2f} ${sum(in_bracket)/len(in_bracket):>7.2f}")
    big = [w for w in win_amounts if w >= 50]
    if big:
        print(f"$50+{'':>11} {len(big):>8} ${sum(big):>9.2f} ${sum(big)/len(big):>7.2f}")

# --- G. DRAWDOWN TIMELINE ---
print(f"\n{'='*65}")
print(f"  G. DRAWDOWN ALERTS")
print(f"{'='*65}")
for level in sorted(drawdown_alerts.keys()):
    thresholds = {1: 50, 2: 100, 3: 200}
    thresh = thresholds.get(level, '?')
    print(f"  Level {level} (${thresh}): triggered {drawdown_alerts[level]} times")

# --- H. EQUITY CURVE MILESTONES ---
print(f"\n{'='*65}")
print(f"  H. EQUITY CURVE (from paired P/L)")
print(f"{'='*65}")
balance = 5000.0
peak = 5000.0
max_dd = 0.0
peak_date = ""
max_dd_date = ""
monthly_balance = {}

for t in paired_trades:
    balance += t[5]
    if balance > peak:
        peak = balance
        peak_date = t[3]  # close date
    dd = peak - balance
    if dd > max_dd:
        max_dd = dd
        max_dd_date = t[3]
    # Track monthly end balance
    month = t[6]
    monthly_balance[month] = balance

print(f"Starting balance: $5,000.00")
print(f"Calculated peak:  ${peak:.2f} (on {peak_date})")
print(f"Calculated max DD: ${max_dd:.2f} (on {max_dd_date})")
print(f"Final balance:    ${balance:.2f}")

print(f"\nMonthly end balance:")
running_bal = 5000.0
for m in sorted(monthly_balance.keys()):
    print(f"  {m}: ${monthly_balance[m]:.2f}")

# --- I. WORST STREAKS ---
print(f"\n{'='*65}")
print(f"  I. STREAKS ANALYSIS")
print(f"{'='*65}")
# Consecutive losses
max_loss_streak = 0
current_streak = 0
worst_streak_start = ""
worst_streak_end = ""
temp_start = ""

for t in paired_trades:
    if t[5] < 0:
        if current_streak == 0:
            temp_start = t[0]
        current_streak += 1
        if current_streak > max_loss_streak:
            max_loss_streak = current_streak
            worst_streak_start = temp_start
            worst_streak_end = t[3]
    else:
        current_streak = 0

# Consecutive wins
max_win_streak = 0
current_streak = 0
for t in paired_trades:
    if t[5] > 0:
        current_streak += 1
        max_win_streak = max(max_win_streak, current_streak)
    else:
        current_streak = 0

print(f"Max consecutive losses: {max_loss_streak} ({worst_streak_start} to {worst_streak_end})")
print(f"Max consecutive wins:   {max_win_streak}")

# Worst single day
daily_pnl = defaultdict(float)
daily_trades_count = defaultdict(int)
for t in paired_trades:
    day = t[0]  # open date
    daily_pnl[day] += t[5]
    daily_trades_count[day] += 1

if daily_pnl:
    worst_day = min(daily_pnl.items(), key=lambda x: x[1])
    best_day = max(daily_pnl.items(), key=lambda x: x[1])
    print(f"\nWorst day: {worst_day[0]} = ${worst_day[1]:.2f} ({daily_trades_count[worst_day[0]]} trades)")
    print(f"Best day:  {best_day[0]} = +${best_day[1]:.2f} ({daily_trades_count[best_day[0]]} trades)")

    # Days with > $20 loss
    bad_days = [(d, pnl) for d, pnl in daily_pnl.items() if pnl < -20]
    print(f"\nDays with > $20 loss: {len(bad_days)}")
    for d, pnl in sorted(bad_days, key=lambda x: x[1])[:10]:
        print(f"  {d}: ${pnl:.2f} ({daily_trades_count[d]} trades)")

# --- J. COMPARISON ---
print(f"\n{'='*65}")
print(f"  J. VERSION COMPARISON")
print(f"{'='*65}")
print(f"{'Metric':<28} {'v5.0':>10} {'v5.1':>10} {'v6.0':>10}")
print("-" * 65)
print(f"{'Final Balance':<28} {'$5,298':>10} {'$5,053':>10} {'$3,837':>10}")
print(f"{'Net Profit':<28} {'+$298':>10} {'+$53':>10} {'-$1,163':>10}")
print(f"{'Total Entries':<28} {'477':>10} {'195':>10} {str(len(entries)):>10}")
print(f"{'SL Losses':<28} {'188':>10} {'35':>10} {str(len(sl_hits)):>10}")
print(f"{'Win Rate':<28} {'~50%':>10} {'64.6%':>10} {f'{len(wins)/max(len(paired_trades),1)*100:.1f}%':>10}")
print(f"{'ET Hits':<28} {'41':>10} {'6':>10} {str(len(et_hits)):>10}")
print(f"{'Pyramid Adds':<28} {'N/A':>10} {'N/A':>10} {str(len(pyramid_adds)):>10}")
print(f"{'H1 Vol Days Blocked':<28} {'N/A':>10} {'N/A':>10} {str(len(h1_vol_blocks)):>10}")
print(f"{'Invalid SL Blocks':<28} {'N/A':>10} {'N/A':>10} {str(invalid_sl_blocks):>10}")
print(f"{'Filter Blocks':<28} {'0':>10} {'463':>10} {str(total_filter_blocks):>10}")
print(f"{'Max Drawdown':<28} {'~$250':>10} {'$234':>10} {'$1,416':>10}")
v60_avg_loss = abs(total_loss) / max(len(losses), 1)
print(f"{'Avg Loss':<28} {'$13.04':>10} {'~$8':>10} {f'${v60_avg_loss:.2f}':>10}")
v60_avg_win = total_win / max(len(wins), 1)
print(f"{'Avg Win':<28} {'~$5':>10} {'~$3':>10} {f'${v60_avg_win:.2f}':>10}")

# --- K. KEY INSIGHTS ---
print(f"\n{'='*65}")
print(f"  K. KEY DIAGNOSTIC QUESTIONS")
print(f"{'='*65}")
sl_rate = len(sl_hits) / max(len(entries), 1) * 100
print(f"1. SL hit rate: {sl_rate:.1f}% ({len(sl_hits)} of {len(entries)} trades)")
print(f"2. Avg loss (${v60_avg_loss:.2f}) vs Avg win (${v60_avg_win:.2f}) = R:R {v60_avg_win/max(v60_avg_loss,0.01):.2f}")
print(f"3. Entry-mean distance filter blocked: {filter_blocks.get('Entry-mean distance too small', 0)} signals")
print(f"4. Invalid SL level blocked: {invalid_sl_blocks} signals")
print(f"5. Trades per day: ~{len(entries)/365:.1f}")

# Check: are most SL losses coming from one direction?
sl_by_direction = defaultdict(int)
for date, ticket in sl_hits:
    # Find the deal for this ticket to determine direction
    for d_date, side, d_num, price in deals:
        if d_num == ticket:
            sl_by_direction[side] += 1
            break
print(f"6. SL hits by direction: BUY={sl_by_direction.get('buy',0)}, SELL={sl_by_direction.get('sell',0)}")

# Check: most losses happening in which regime?
if trade_signals:
    regime_sl = defaultdict(int)
    for i, (date, direction, regime) in enumerate(trade_signals):
        if i < len(paired_trades) and paired_trades[i][5] < 0:
            regime_sl[regime] += 1
    print(f"7. Losses by regime: {dict(regime_sl)}")
