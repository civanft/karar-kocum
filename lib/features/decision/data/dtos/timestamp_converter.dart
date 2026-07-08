import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

/// DateTime ↔ Firestore Timestamp dönüşümü (audit Y-4).
///
/// DATA katmanında yaşar (domain saf Dart kalır); mapper açıkça çağırır.
/// fromJson toleranslıdır çünkü üç kaynak var:
///  - Timestamp: normal Firestore okuması
///  - String (ISO): eski JSON/dışa aktarım verisi
///  - null: serverTimestamp bekleyen YEREL yazım snapshot'ı — now() ile
///    doldurulur (iyimser görünüm; sunucu onayı gelince gerçek değer akar)
class TimestampConverter implements JsonConverter<DateTime, Object?> {
  const TimestampConverter();

  @override
  DateTime fromJson(Object? json) => switch (json) {
        final Timestamp t => t.toDate(),
        final String s => DateTime.parse(s),
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
        null => DateTime.now(),
        _ => throw ArgumentError('Beklenmeyen tarih tipi: ${json.runtimeType}'),
      };

  @override
  Object toJson(DateTime date) => Timestamp.fromDate(date);
}
