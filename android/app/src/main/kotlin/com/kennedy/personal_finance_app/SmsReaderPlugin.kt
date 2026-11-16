package com.kennedy.personal_finance_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Reads the device SMS inbox for the import feature.
///
/// One method, `query`, scoped deliberately: the app never lists every
/// message — only rows whose sender address matches one the user linked in
/// SMS import settings, and never more than `limit` of them. The address list
/// arrives from Dart, so a sender that is never linked is never read.
object SmsReaderPlugin {
    const val channel = "personal_finance/sms"

    fun query(context: Context, call: MethodCall, result: MethodChannel.Result) {
        val addresses = call.argument<List<String>>("addresses") ?: emptyList()
        val since = call.argument<Number>("since")?.toLong() ?: 0L
        val limit = call.argument<Number>("limit")?.toInt() ?: 200

        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_SMS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            result.error("permission", "READ_SMS not granted", null)
            return
        }
        if (addresses.isEmpty()) {
            result.success(emptyList<Map<String, Any>>())
            return
        }

        val placeholders = addresses.joinToString(",") { "?" }
        val selection = "date >= ? AND address IN ($placeholders)"
        val selectionArgs = arrayOf(since.toString(), *addresses.toTypedArray())

        val rows = mutableListOf<Map<String, Any>>()
        try {
            context.contentResolver
                .query(
                    Uri.parse("content://sms/inbox"),
                    arrayOf("_id", "address", "body", "date"),
                    selection,
                    selectionArgs,
                    "date DESC LIMIT $limit",
                )
                ?.use { cursor ->
                    val idCol = cursor.getColumnIndexOrThrow("_id")
                    val addrCol = cursor.getColumnIndexOrThrow("address")
                    val bodyCol = cursor.getColumnIndexOrThrow("body")
                    val dateCol = cursor.getColumnIndexOrThrow("date")
                    while (cursor.moveToNext()) {
                        rows.add(
                            mapOf(
                                "provider_id" to cursor.getLong(idCol).toString(),
                                "address" to (cursor.getString(addrCol) ?: ""),
                                "body" to (cursor.getString(bodyCol) ?: ""),
                                "received_at" to cursor.getLong(dateCol),
                            )
                        )
                    }
                }
        } catch (e: SecurityException) {
            result.error("permission", "SMS access revoked mid-query", null)
            return
        }

        result.success(rows)
    }
}
