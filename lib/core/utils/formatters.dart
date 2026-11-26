import 'dart:convert';
import 'dart:typed_data';

/// Форматирует длительность в `mm:ss` или `h:mm:ss`.
String formatDurationMs(int durationMs) {
  if (durationMs <= 0) return '0:00';
  final totalSeconds = durationMs ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final secondsPadded = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final minutesPadded = minutes.toString().padLeft(2, '0');
    return '$hours:$minutesPadded:$secondsPadded';
  }
  return '$minutes:$secondsPadded';
}

/// Русское склонение счётчика треков (`1 трек`, `2 трека`, `5 треков`).
String formatTrackCount(int count) {
  final mod100 = count % 100;
  final mod10 = count % 10;
  if (mod100 >= 11 && mod100 <= 14) {
    return '$count треков';
  }
  if (mod10 == 1) {
    return '$count трек';
  }
  if (mod10 >= 2 && mod10 <= 4) {
    return '$count трека';
  }
  return '$count треков';
}

/// Детерминированный 64-битный FNV-1a хеш строки (в виде 16-символьного hex)
/// без зависимости от сторонних криптопакетов.
String stableHexHash(String input) {
  return stableBytesHash(Uint8List.fromList(utf8.encode(input)));
}

/// Детерминированный хеш байтов для дедупликации кэшированных обложек.
String stableBytesHash(Uint8List bytes) {
  var h1 = 0x811c9dc5;
  var h2 = 0x9e3779b9;
  for (final byte in bytes) {
    h1 ^= byte;
    h1 = (h1 * 0x01000193) & 0xFFFFFFFF;
    h2 ^= (byte + 0x55) & 0xFF;
    h2 = (h2 * 0x85ebca6b) & 0xFFFFFFFF;
  }
  return '${h1.toRadixString(16).padLeft(8, '0')}'
      '${h2.toRadixString(16).padLeft(8, '0')}';
}

/// Сравнение строк от А до Я с приоритетом:
/// 1) латиница (A–Z), 2) кириллица (А–Я, с корректным местом «Ё» после «Е»),
/// 3) цифры и прочие символы.
int compareLatinThenCyrillic(String a, String b) {
  final normA = a.trim().toLowerCase();
  final normB = b.trim().toLowerCase();

  final itA = normA.runes.iterator;
  final itB = normB.runes.iterator;

  while (true) {
    final hasA = itA.moveNext();
    final hasB = itB.moveNext();
    if (!hasA && !hasB) {
      return a.compareTo(b);
    }
    if (!hasA) return -1;
    if (!hasB) return 1;

    final weightA = _runeSortWeight(itA.current);
    final weightB = _runeSortWeight(itB.current);
    if (weightA != weightB) {
      return weightA.compareTo(weightB);
    }
  }
}

int _runeSortWeight(int rune) {
  if (rune == 0x0020) {
    return -1;
  }
  // Латиница A–Z (включая расширенную латиницу с диакритикой).
  if (rune >= 0x0061 && rune <= 0x007A) {
    return rune - 0x0061;
  }
  if (rune >= 0x00C0 && rune <= 0x024F && rune != 0x00D7 && rune != 0x00F7) {
    return 0x0100 + rune;
  }
  // Русский алфавит А–Е, Ё, Ж–Я.
  if (rune >= 0x0430 && rune <= 0x0435) {
    return 0x100000 + (rune - 0x0430) * 2;
  }
  if (rune == 0x0451) {
    return 0x100000 + 11;
  }
  if (rune >= 0x0436 && rune <= 0x044F) {
    return 0x100000 + (rune - 0x0430) * 2;
  }
  if (rune >= 0x0400 && rune <= 0x04FF) {
    return 0x101000 + rune;
  }
  // Цифры 0–9.
  if (rune >= 0x0030 && rune <= 0x0039) {
    return 0x200000 + (rune - 0x0030);
  }
  // Прочие символы и знаки препинания.
  return 0x300000 + rune;
}
