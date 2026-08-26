# Design brief — personal finance app (Ghana)

Design the complete screen set for an existing Flutter mobile app. This is a
**redesign of a shipped product**, not a greenfield concept — the screens, data
and navigation below already exist and must all be accounted for.

---

## 1. What the app is

A personal money manager for someone in Ghana. Every figure is in **GHS**.

It is not a passive expense log. The premise is that a ledger tells you what you
spent but not whether you can afford the thing you are about to do. So the app
leads with a **verdict**, not a total: *safe to spend*, *this bill is not
covered*, *pay this one from Momo, not Fidelity*. An AI coach reads the same
numbers the dashboard does and hands the user buttons to approve rather than
paragraphs to interpret.

**The user:** works, gets paid on a cycle, juggles a bank account or two plus
Mobile Money and cash, sends money to people, and is trying not to be caught
short before payday. Checks the app on a phone, usually at night, usually in
dark mode.

**Tone:** a sharp friend who is good with money. Calm, direct, numerate. Not a
bank. Not a gamified savings toy. No confetti, no streaks, no mascots.

---

## 2. Canvas and deliverable

- **Artboards: 390 × 844** (iPhone-class). Mobile only — no desktop or tablet
  target.
- Deliver **every screen in both light and dark**, dark first. Pair the two
  side by side on the canvas so the palettes can be compared directly.
- Group artboards into rows by area: Auth → Home → Money in/out → Reports →
  Insights → Accounts & setup.
- Include a **components row** at the top of the canvas: the shared pieces in
  §6, drawn once at full size with their states.
- Use realistic Ghanaian data throughout — names like Kwame, Ama, Kojo; amounts
  like GHS 47.00, GHS 1,298.00, GHS 5,400.00; merchants like Melcom, Shoprite,
  Bolt, ECG, Vodafone Cash. Never lorem ipsum, never dollar amounts.

---

## 3. Hard constraints (these come from real defects — do not design past them)

1. **No white text on saturated fills.** The current build renders headline
   figures as white-on-bright-green and white-on-bright-red gradient blocks.
   Three side by side turn the screen into a traffic light, and the numbers are
   genuinely hard to read at night. Use **tinted surfaces** instead — the
   semantic colour at low alpha with a matching border, and the figure drawn in
   a legible tint of that same colour. Colour should classify, not shout.

2. **Currency never truncates.** `GHS 5,400.00` currently renders as `GHS 5,…`
   in a third-width card. Design every figure slot at its **worst case**:
   `-GHS 12,480.00` — minus sign, five significant digits, thousands separator,
   two decimals, and the `GHS ` prefix. If a three-up row cannot hold that,
   design a different layout. Do not design a layout that only works for small
   numbers.

3. **Dark mode is the primary theme.** Design it first and make it good. Light
   is the port, not the other way round.

4. **The thumb reaches the bottom third.** Primary actions live low.

5. **One idea per screen.** Each screen answers a single question, and the
   answer should be readable in under two seconds without tapping.

---

## 4. Current tokens — evolve, do not discard

The brand is a deep teal-green. Keep the identity; retune values for contrast
and calm where they need it.

```
seed / brand     #0E7C66     income   #16A34A     expense  #DC2626
accent (violet)  #8B5CF6     warning  #F59E0B

surface  dark  #0F1413   cards dark  #1A2120
surface  light #F6F8F7   cards light #FFFFFF

Categorical (charts, 12 hues, cycled):
#0E7C66 #F59E0B #8B5CF6 #EF4444 #3B82F6 #EC4899
#14B8A6 #EAB308 #6366F1 #10B981 #F97316 #06B6D4
```

Radii currently run 10 / 14 / 18 / 20 px. Type is a single sans family, weights
500–800, tight letter-spacing on large figures. Propose refinements where they
help, and say what you changed and why.

**Currency format:** `GHS 1,298.00` — symbol first, space, comma thousands,
always two decimals. Negative renders as `-GHS 1,298.00`.

---

## 5. Screens to design

### Auth
1. **Splash** — logo, one line of positioning, Get started / I have an account.
2. **Log in** — email, password, error state.
3. **Sign up** — name, email, password.

### Home (tab 1)
4. **Dashboard** — the most important screen. Top to bottom:
   - Greeting plus first name; refresh and settings icons.
   - **Safe-to-spend hero.** The headline figure, captioned either *"Safe to
     spend before your next income"* or *"…over the next 30 days"*, with three
     supporting stats: **Total balance**, **Committed**, **Per day**. Design a
     variant for the shortfall case, where the figure is negative and the app
     is warning rather than reporting.
   - Wide button: *"I need to pay someone — where from?"*
   - **Alert list** — zero to four cards, severity-ranked, e.g. *"Rent of
     GHS 1,200 is due in 5 days and no account can cover it."* Needs a visual
     severity scale that is not just "everything is red".
   - **Money placement bar** — a horizontal stacked bar splitting balances into
     liquid / committed / protected.
   - **Spending** — this month against last, naming the categories that moved
     and by how much (e.g. *Transportation +518%*).
   - **Recent transactions** — four rows with a *See all* link.

### History (tab 2)
5. **History** — searchable, filterable transaction list grouped by day with
   day subtotals. Rows carry a category glyph, description, account and amount
   (green in, red out), plus a transfer variant that reads as neither.
6. **History — filter sheet** — Type, Account, Category.
7. **History — empty** and **History — no search results**.

### Reports (tab 3) — a tab bar with three panes
8. **This week** — the week's net figure, transaction count, Income and Expense
   figures, and a seven-bar daily breakdown chart.
9. **Trends** — month-over-month movement over time.
10. **Detailed** — a week picker, then **Income / Expense / Net** side by side
    *(this is the row that currently truncates — solve it)*, then **By
    category** (share of expenses, ranked, with a colour key) and **By account**
    (money in and out per account, plus net per account).

### Insights (tab 4) — two panes
11. **Overview** — *Needs your attention*, *Make this sharper*, *Your numbers*,
    *Goals*, and a *Today* AI tip card.
12. **Ask AI** — a chat. Design:
    - the intro/header card for the coach;
    - the **empty state with suggested question chips** generated from the
      user's real position (*"Why is Transportation up this month?"*);
    - **user bubble** (right) and **coach bubble** (left) — coach replies are
      markdown and can carry short lists;
    - a **working state** that names what the coach is looking up (*"Checking
      your position…"*) rather than showing a bare spinner;
    - an **action card**: the coach proposing a transfer or a new bill, with
      Approve / Dismiss. Nothing has happened until it is tapped, so the card
      must not read as a completed action;
    - the compose bar, with send and loading states;
    - an error state with Retry.
13. **AI history** — past conversations.

### Accounts (tab 5)
14. **Accounts** — a distribution donut or bar, then account cards: name, kind
    (bank / Mobile Money / cash), balance, liquidity, and a minimum-balance
    floor where one is set. Plus a link through to Commitments & goals. Include
    the **empty / first-run** variant.

### Money in and out (pushed screens)
15. **Add transaction** — a large amount field first, an Expense / Income /
    Transfer segmented control, **quick-add chips**, account (and *To account*
    when transferring), category, date, note. The transfer variant is a
    distinct layout, not a hidden field.
16. **Where should this come from?** — the payment planner. Amount, the account
    it must leave from, category, an optional *"What is it for?"* (e.g.
    *Sending to Kwame*). Then the verdict: the recommended account, **why not
    the others**, what the payment leaves behind, and — where the money has to
    be moved first — an offer to transfer. Also design the **refusal**: the
    money simply is not there.
17. **Commitments** — tabs for **Bills & income** (recurring, with next-due
    dates and a covered / not-covered state) and **Goals** (target, saved,
    progress, target date).

### Setup
18. **Categories** — Spending / Income tabs. Rows with icon, name, a *Built in*
    marker, and per-row actions (rename, hide, delete). Design the **hidden**
    section, the **empty state** with a *Use the default list* action, and the
    **not-set-up-yet** error state.
19. **Settings** — signed-in identity, Your money (commitments, categories),
    Daily reminder, AI tip notification, AI coach (fallback API key, older
    conversations), Sign out.

### Sheets (design as a modal set)
20. Account editor · Category editor (with an icon picker) · Goal editor ·
    Obligation editor · Edit transaction · Delete confirmation.

---

## 6. Components row

Draw each once, with every state:

- **Figure card** — the KPI tile. Show it at one-half and one-third width
  holding `-GHS 12,480.00`.
- **Transaction row** — expense / income / transfer.
- **Alert card** — informational / warning / critical.
- **Chat bubble** — user / coach / coach-with-action.
- **Account card** — bank / Mobile Money / cash, and archived.
- **Progress meter** — for goals and for the money placement bar.
- **Chips** — quick-add, suggested question, filter (selected and unselected).
- **Buttons** — filled, outlined, text, destructive; default / pressed /
  disabled / loading.
- **Text field** — with label, with error, with currency prefix.
- **Bottom nav** — five items (Home, History, Reports, Insights, Accounts) with
  a centre-docked add button sitting in a notch.
- **Empty state** and **error state** patterns.
- **Category glyph** — the circular icon token used across the app.

---

## 7. What to hand back

For each screen, a short note on the decision that drove it, especially where
you changed the current structure. Call out explicitly:

- how the three-up figure row now holds a five-digit negative amount;
- what replaced the saturated gradient blocks, and the contrast ratio of the
  figure against its new background in both themes;
- the severity scale for alerts;
- how a coach action card is made to read as *proposed*, not *done*.

Flag anything in the current structure you think is wrong. This is a redesign —
the existing layout is the starting point, not the requirement.
