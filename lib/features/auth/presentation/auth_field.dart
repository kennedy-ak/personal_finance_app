import 'package:flutter/material.dart';

import '../../../core/design/components.dart';
import '../../../core/theme.dart';

/// The text field from the components row: label above, filled box below.
///
/// The label sits outside the field rather than floating inside it. A floating
/// label moves while you type and changes size while you read it; a static one
/// stays where the eye left it.
class AuthField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;

  /// Paints the error border without printing a message — used when the
  /// explanation is already shown in a banner under the form.
  final bool hasError;

  final TextInputType? keyboardType;
  final List<String>? autofillHints;
  final String? Function(String?)? validator;
  final VoidCallback? onToggleObscure;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization textCapitalization;

  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.hasError = false,
    this.keyboardType,
    this.autofillHints,
    this.validator,
    this.onToggleObscure,
    this.onSubmitted,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = hasError ? t.fieldBorderError : t.fieldBorder;

    return LabeledField(
      label: label,
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        validator: validator,
        onFieldSubmitted: onSubmitted,
        textCapitalization: textCapitalization,
        textInputAction:
            onSubmitted != null ? TextInputAction.done : TextInputAction.next,
        style: AppType.body.copyWith(fontSize: 15, height: 1.2, color: t.ink),
        cursorColor: t.brandInk,
        decoration: InputDecoration(
          hintText: hint,
          // Dark mode tints the whole field on error; light mode keeps it
          // white and lets the border do the work, exactly as drawn.
          fillColor: hasError && dark ? t.fieldError : t.field,
          enabledBorder: OutlineInputBorder(
            borderRadius: Radii.sm,
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: Radii.sm,
            borderSide: BorderSide(
                color: hasError ? t.fieldBorderError : t.brandInk, width: 1.4),
          ),
          suffixIcon: onToggleObscure == null
              ? null
              : IconButton(
                  onPressed: onToggleObscure,
                  icon: Icon(
                    obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: t.inkMuted,
                  ),
                ),
        ),
      ),
    );
  }
}
