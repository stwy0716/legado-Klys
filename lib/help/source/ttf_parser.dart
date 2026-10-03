import 'dart:io';
import 'dart:typed_data';

/// TTF/OTF/WOFF 字体解析：提取「乱码码点 → 真实字符」映射（字体反爬）。
///
/// 原理：反爬字体把真实字符的字形挂在乱码码点上，而 post 表里的字形名
/// （如 "uni4E2D"）通常记录了字形真实的字符编码。据此构建
/// `码点十六进制 -> 真实字符` 的映射，对齐原版 queryTTF 的返回语义。
///
/// 支持：TTF/OTF（00010000/OTTO/true）、TTC 集合、WOFF（zlib）。
/// WOFF2 需 Brotli 解码，暂不支持（返回 null，由调用方回退）。
class TtfFontParser {
  TtfFontParser._();

  /// 解析字体，返回 `{码点hex(小写无前缀): 真实字符}`；解析失败返回 null。
  static Map<String, String>? parse(Uint8List data) {
    try {
      if (data.length < 12) return null;
      final sig = String.fromCharCodes(data.sublist(0, 4));
      switch (sig) {
        case 'wOFF':
          return _parseWoff(data);
        case 'wOF2':
          return null; // WOFF2 需 Brotli，暂不支持
        case 'ttcf':
          if (data.length < 16) return null;
          return _parseSfnt(data, _readU32(data, 12));
        default:
          return _parseSfnt(data, 0);
      }
    } catch (_) {
      return null;
    }
  }

  // ==================== 容器解析 ====================

  static Map<String, String>? _parseWoff(Uint8List data) {
    if (data.length < 44) return null;
    final numTables = _readU16(data, 12);
    final tables = <String, Uint8List>{};
    for (var i = 0; i < numTables; i++) {
      final e = 44 + i * 20;
      if (e + 20 > data.length) break;
      final tag = String.fromCharCodes(data.sublist(e, e + 4));
      final offset = _readU32(data, e + 4);
      final compLength = _readU32(data, e + 8);
      final origLength = _readU32(data, e + 12);
      if (offset + compLength > data.length) continue;
      var raw = Uint8List.sublistView(data, offset, offset + compLength);
      if (compLength < origLength) {
        try {
          raw = Uint8List.fromList(ZLibCodec().decode(raw));
        } catch (_) {
          continue;
        }
      }
      tables[tag] = raw;
    }
    return _fromTables(tables);
  }

  static Map<String, String>? _parseSfnt(Uint8List data, int base) {
    if (base + 12 > data.length) return null;
    final numTables = _readU16(data, base + 4);
    final tables = <String, Uint8List>{};
    for (var i = 0; i < numTables; i++) {
      final e = base + 12 + i * 16;
      if (e + 16 > data.length) break;
      final tag = String.fromCharCodes(data.sublist(e, e + 4));
      final offset = _readU32(data, e + 8);
      final length = _readU32(data, e + 12);
      if (offset + length > data.length) continue;
      tables[tag] = Uint8List.sublistView(data, offset, offset + length);
    }
    return _fromTables(tables);
  }

  // ==================== 表解析 ====================

  static Map<String, String>? _fromTables(Map<String, Uint8List> tables) {
    final cmap = tables['cmap'];
    if (cmap == null || cmap.length < 4) return null;
    final codeToGlyph = _parseCmap(cmap);
    if (codeToGlyph.isEmpty) return null;
    final post = tables['post'];
    final glyphNames =
        post == null ? const <String?>[] : _parsePost(post);
    final out = <String, String>{};
    codeToGlyph.forEach((code, gid) {
      final name = gid >= 0 && gid < glyphNames.length ? glyphNames[gid] : null;
      final real = nameToChar(name);
      if (real != null && real.isNotEmpty) {
        out[code.toRadixString(16)] = real;
      }
    });
    return out;
  }

  /// cmap 子表选择：按 Unicode 覆盖优先级解析，返回 码点 -> glyphId
  static Map<int, int> _parseCmap(Uint8List d) {
    final out = <int, int>{};
    final numTables = _readU16(d, 2);
    final subs = <List<int>>[];
    for (var i = 0; i < numTables; i++) {
      final e = 4 + i * 8;
      if (e + 8 > d.length) break;
      final platform = _readU16(d, e);
      final encoding = _readU16(d, e + 2);
      final subOff = _readU32(d, e + 4);
      subs.add([platform, encoding, subOff]);
    }
    int prio(List<int> s) {
      final p = s[0], en = s[1];
      if ((p == 3 && en == 10) || (p == 0 && (en == 4 || en == 6))) return 0;
      if ((p == 3 && en == 1) || (p == 0 && en == 3)) return 1;
      if (p == 0) return 2;
      return 3;
    }

    subs.sort((a, b) => prio(a).compareTo(prio(b)));
    for (final s in subs) {
      if (s[2] >= d.length) continue;
      _parseCmapSubtable(Uint8List.sublistView(d, s[2]), out);
    }
    return out;
  }

  static void _parseCmapSubtable(Uint8List d, Map<int, int> out) {
    if (d.length < 2) return;
    final format = _readU16(d, 0);
    switch (format) {
      case 0:
        for (var c = 0; c < 256 && 6 + c < d.length; c++) {
          final g = d[6 + c];
          if (g != 0) out[c] = g;
        }
        break;
      case 4:
        if (d.length < 14) return;
        final segCount = _readU16(d, 6) ~/ 2;
        final endBase = 14;
        final startBase = endBase + segCount * 2 + 2; // 跳过 reservedPad
        final deltaBase = startBase + segCount * 2;
        final rangeBase = deltaBase + segCount * 2;
        for (var i = 0; i < segCount; i++) {
          if (rangeBase + i * 2 + 2 > d.length) break;
          final end = _readU16(d, endBase + i * 2);
          final start = _readU16(d, startBase + i * 2);
          final delta = _readU16(d, deltaBase + i * 2);
          final rangeOff = _readU16(d, rangeBase + i * 2);
          if (start == 0xFFFF) continue;
          for (var c = start; c <= end && c != 0xFFFF; c++) {
            int g;
            if (rangeOff == 0) {
              g = (c + delta) & 0xFFFF;
            } else {
              // glyphIdArray 相对 rangeBase 的字节偏移
              final addr = rangeBase + i * 2 + rangeOff + 2 * (c - start);
              if (addr + 2 > d.length) break;
              g = _readU16(d, addr);
              if (g != 0) g = (g + delta) & 0xFFFF;
            }
            if (g != 0) out[c] = g;
          }
        }
        break;
      case 6:
        if (d.length < 10) return;
        final first = _readU16(d, 6);
        final count = _readU16(d, 8);
        for (var i = 0; i < count && 10 + i * 2 + 2 <= d.length; i++) {
          final g = _readU16(d, 10 + i * 2);
          if (g != 0) out[first + i] = g;
        }
        break;
      case 12:
        if (d.length < 16) return;
        final nGroups = _readU32(d, 12);
        for (var i = 0; i < nGroups; i++) {
          final g0 = 16 + i * 12;
          if (g0 + 12 > d.length) break;
          final start = _readU32(d, g0);
          final end = _readU32(d, g0 + 4);
          final startGlyph = _readU32(d, g0 + 8);
          for (var c = start; c <= end && c - start < 0x10000; c++) {
            out[c] = startGlyph + (c - start);
          }
        }
        break;
      default:
        break;
    }
  }

  /// post 表：返回 glyphId -> 字形名
  static List<String?> _parsePost(Uint8List d) {
    if (d.length < 34) return const [];
    final version = _readU32(d, 0);
    if (version != 0x00020000) return const []; // 3.0 无字形名
    final numGlyphs = _readU16(d, 32);
    final namesStart = 34 + numGlyphs * 2;
    // 先收集自定义字形名（pascal 字符串）
    final custom = <String>[];
    var p = namesStart;
    while (p < d.length) {
      final len = d[p];
      if (p + 1 + len > d.length) break;
      custom.add(String.fromCharCodes(d.sublist(p + 1, p + 1 + len)));
      p += 1 + len;
    }
    final out = List<String?>.filled(numGlyphs, null);
    for (var i = 0; i < numGlyphs && 34 + i * 2 + 2 <= d.length; i++) {
      final gni = _readU16(d, 34 + i * 2);
      if (gni < 258) {
        out[i] = gni < _macGlyphNames.length ? _macGlyphNames[gni] : null;
      } else if (gni - 258 < custom.length) {
        out[i] = custom[gni - 258];
      }
    }
    return out;
  }

  // ==================== 字形名 -> 字符 ====================

  /// 把字形名解码为真实字符：uniXXXX（可连写）/ uXXXXXX / AGL 常用名。
  static String? nameToChar(String? name) {
    if (name == null || name.isEmpty) return null;
    if (name.startsWith('uni')) {
      final rest = name.substring(3);
      if (rest.length >= 4 && rest.length % 4 == 0) {
        final sb = StringBuffer();
        for (var i = 0; i < rest.length; i += 4) {
          final v = int.tryParse(rest.substring(i, i + 4), radix: 16);
          if (v == null) return null;
          sb.writeCharCode(v);
        }
        return sb.toString();
      }
      return null;
    }
    if (name.startsWith('u') && name.length >= 5 && name.length <= 7) {
      final v = int.tryParse(name.substring(1), radix: 16);
      if (v != null) return String.fromCharCode(v);
      return null;
    }
    return _aglNames[name];
  }

  // ==================== 工具 ====================

  static int _readU16(Uint8List d, int i) =>
      i + 2 <= d.length ? (d[i] << 8) | d[i + 1] : 0;

  static int _readU32(Uint8List d, int i) => i + 4 <= d.length
      ? (d[i] << 24) | (d[i + 1] << 16) | (d[i + 2] << 8) | d[i + 3]
      : 0;

  /// Macintosh 标准字形名顺序（post 2.0 前 258 项）
  static const List<String> _macGlyphNames = [
    '.notdef', '.null', 'nonmarkingreturn', 'space', 'exclam', 'quotedbl',
    'numbersign', 'dollar', 'percent', 'ampersand', 'quotesingle',
    'parenleft', 'parenright', 'asterisk', 'plus', 'comma', 'hyphen',
    'period', 'slash', 'zero', 'one', 'two', 'three', 'four', 'five',
    'six', 'seven', 'eight', 'nine', 'colon', 'semicolon', 'less', 'equal',
    'greater', 'question', 'at', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
    'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V',
    'W', 'X', 'Y', 'Z', 'bracketleft', 'backslash', 'bracketright',
    'asciicircum', 'underscore', 'grave', 'a', 'b', 'c', 'd', 'e', 'f',
    'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't',
    'u', 'v', 'w', 'x', 'y', 'z', 'braceleft', 'bar', 'braceright',
    'asciitilde', 'Adieresis', 'Aring', 'Ccedilla', 'Eacute', 'Ntilde',
    'Odieresis', 'Udieresis', 'aacute', 'agrave', 'acircumflex', 'adieresis',
    'atilde', 'aring', 'ccedilla', 'eacute', 'egrave', 'ecircumflex',
    'edieresis', 'iacute', 'igrave', 'icircumflex', 'idieresis', 'ntilde',
    'oacute', 'ograve', 'ocircumflex', 'odieresis', 'otilde', 'uacute',
    'ugrave', 'ucircumflex', 'udieresis', 'dagger', 'degree', 'cent',
    'sterling', 'section', 'bullet', 'paragraph', 'germandbls', 'registered',
    'copyright', 'trademark', 'acute', 'dieresis', 'notequal', 'AE',
    'Oslash', 'infinity', 'plusminus', 'lessequal', 'greaterequal', 'yen',
    'mu', 'partialdiff', 'summation', 'product', 'pi', 'integral',
    'ordfeminine', 'ordmasculine', 'Omega', 'ae', 'oslash', 'questiondown',
    'exclamdown', 'logicalnot', 'radical', 'florin', 'approxequal', 'Delta',
    'guillemotleft', 'guillemotright', 'ellipsis', 'nonbreakingspace',
    'Agrave', 'Atilde', 'Otilde', 'OE', 'oe', 'endash', 'emdash',
    'quotedblleft', 'quotedblright', 'quoteleft', 'quoteright', 'divide',
    'lozenge', 'ydieresis', 'Ydieresis', 'fraction', 'currency',
    'guilsinglleft', 'guilsinglright', 'fi', 'fl', 'daggerdbl',
    'periodcentered', 'quotesinglbase', 'quotedblbase', 'perthousand',
    'Acircumflex', 'Ecircumflex', 'Aacute', 'Edieresis', 'Egrave', 'Iacute',
    'Icircumflex', 'Idieresis', 'Igrave', 'Oacute', 'Ocircumflex', 'apple',
    'Ograve', 'Uacute', 'Ucircumflex', 'Ugrave', 'dotlessi', 'circumflex',
    'tilde', 'macron', 'breve', 'dotaccent', 'ring', 'cedilla',
    'hungarumlaut', 'ogonek', 'caron', 'Lslash', 'lslash', 'Scaron',
    'scaron', 'Zcaron', 'zcaron', 'brokenbar', 'Eth', 'eth', 'Yacute',
    'yacute', 'Thorn', 'thorn', 'minus', 'multiply', 'onesuperior',
    'twosuperior', 'threesuperior', 'onehalf', 'onequarter',
    'threequarters', 'franc', 'Gbreve', 'gbreve', 'Idotaccent', 'Scedilla',
    'scedilla', 'Cacute', 'cacute', 'Ccaron', 'ccaron', 'dcroat',
  ];

  /// AGL（Adobe Glyph List）常用名子集：用于非 uni 前缀字形名的回退解码
  static const Map<String, String> _aglNames = {
    'space': ' ', 'exclam': '!', 'quotedbl': '"', 'numbersign': '#',
    'dollar': r'$', 'percent': '%', 'ampersand': '&', 'quotesingle': "'",
    'parenleft': '(', 'parenright': ')', 'asterisk': '*', 'plus': '+',
    'comma': ',', 'hyphen': '-', 'period': '.', 'slash': '/', 'zero': '0',
    'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5',
    'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'colon': ':',
    'semicolon': ';', 'less': '<', 'equal': '=', 'greater': '>',
    'question': '?', 'at': '@', 'bracketleft': '[', 'backslash': '\\',
    'bracketright': ']', 'asciicircum': '^', 'underscore': '_',
    'grave': '`', 'braceleft': '{', 'bar': '|', 'braceright': '}',
    'asciitilde': '~',
    'A': 'A', 'B': 'B', 'C': 'C', 'D': 'D', 'E': 'E', 'F': 'F', 'G': 'G',
    'H': 'H', 'I': 'I', 'J': 'J', 'K': 'K', 'L': 'L', 'M': 'M', 'N': 'N',
    'O': 'O', 'P': 'P', 'Q': 'Q', 'R': 'R', 'S': 'S', 'T': 'T', 'U': 'U',
    'V': 'V', 'W': 'W', 'X': 'X', 'Y': 'Y', 'Z': 'Z',
    'a': 'a', 'b': 'b', 'c': 'c', 'd': 'd', 'e': 'e', 'f': 'f', 'g': 'g',
    'h': 'h', 'i': 'i', 'j': 'j', 'k': 'k', 'l': 'l', 'm': 'm', 'n': 'n',
    'o': 'o', 'p': 'p', 'q': 'q', 'r': 'r', 's': 's', 't': 't', 'u': 'u',
    'v': 'v', 'w': 'w', 'x': 'x', 'y': 'y', 'z': 'z',
  };
}
