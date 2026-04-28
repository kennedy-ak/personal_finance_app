import 'package:intl/intl.dart';

final NumberFormat currencyFmt =
    NumberFormat.currency(locale: 'en_GH', symbol: 'GHS ', decimalDigits: 2);

final DateFormat dateFmt = DateFormat('yyyy-MM-dd');
final DateFormat dateLongFmt = DateFormat('MMM d, yyyy');

String formatMoney(num value) => currencyFmt.format(value);
