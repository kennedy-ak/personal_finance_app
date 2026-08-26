import 'package:intl/intl.dart';

final NumberFormat currencyFmt =
    NumberFormat.currency(locale: 'en_GH', symbol: 'GHS ', decimalDigits: 2);

final NumberFormat _digitsFmt =
    NumberFormat.currency(locale: 'en_GH', symbol: '', decimalDigits: 2);

final DateFormat dateFmt = DateFormat('yyyy-MM-dd');
final DateFormat dateLongFmt = DateFormat('MMM d, yyyy');

/// `12 Sep` — the form the screen set uses wherever a date sits inside a
/// sentence or a stat line.
final DateFormat dayMonthFmt = DateFormat('d MMM');

/// `Aug` — used in the mono captions that name the period being compared.
final DateFormat monthFmt = DateFormat('MMM');

/// `6:42 pm` — the second half of a transaction row's subtitle.
final DateFormat timeFmt = DateFormat('h:mm a');

/// `GHS 1,298.00`, and `-GHS 1,298.00` when negative.
String formatMoney(num value) => currencyFmt.format(value);

/// The currency code, used wherever it is drawn apart from the digits.
const String kCurrencyCode = 'GHS';

/// The figure without its code — `-12,480.00`.
///
/// Splitting the two is what lets a third-width column hold the worst case:
/// the code goes on its own line above, the digits keep the full width, and
/// nothing has to truncate.
String moneyDigits(num value) => _digitsFmt.format(value).trim();
