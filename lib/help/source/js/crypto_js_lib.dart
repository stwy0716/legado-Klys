/// 纯 JS 摘要算法库（MD5 / SHA-1 / SHA-256 / SHA-512），供桥内同步调用。
///
/// 与 aes_js_lib.dart 同理，本库在无头 WebView 创建后注入到全局作用域，
/// 暴露 `globalThis.__legadoCrypto`，legado_bridge_js.dart 里的
/// `java.md5Encode / digestHex / digestBase64Str / HMac*` 依赖它同步求值。
///
/// 说明：书源脚本大量以「同步表达式」方式调用（`java.md5Encode(x)` 直接取值），
/// 因此这里全部用纯 JS 同步实现，不能走异步的 Web Crypto（且 Web Crypto 不支持 MD5）。
class CryptoJsLib {
  static const String code = r'''
(function () {
  if (globalThis.__legadoCrypto) return;
  var C = {};

  // ============================ 基础工具 ============================

  function utf8Bytes(s) {
    return new Uint8Array(new TextEncoder().encode(String(s == null ? "" : s)));
  }

  function bytesToHex(bytes) {
    var h = "";
    for (var i = 0; i < bytes.length; i++) {
      h += ("0" + (bytes[i] & 0xff).toString(16)).slice(-2);
    }
    return h;
  }

  function bytesToBase64(bytes) {
    var bin = "";
    var chunk = 0x8000;
    for (var i = 0; i < bytes.length; i += chunk) {
      var end = Math.min(i + chunk, bytes.length);
      bin += String.fromCharCode.apply(null, Array.prototype.slice.call(bytes, i, end));
    }
    return btoa(bin);
  }

  function hexToBytes(hex) {
    var s = String(hex || "").replace(/[^0-9a-fA-F]/g, "");
    var out = new Uint8Array(Math.floor(s.length / 2));
    for (var i = 0; i < out.length; i++) out[i] = parseInt(s.substr(i * 2, 2), 16);
    return out;
  }

  function rotr(x, n) { return (x >>> n) | (x << (32 - n)); }
  function rotl(x, n) { return (x << n) | (x >>> (32 - n)); }

  // ============================ MD5 ============================

  function md5(bytes) {
    var len = bytes.length;
    var bitLen = len * 8;
    var paddedLen = len + 1;
    while (paddedLen % 64 !== 56) paddedLen++;
    paddedLen += 8;
    var buf = new Uint8Array(paddedLen);
    buf.set(bytes);
    buf[len] = 0x80;
    var dv = new DataView(buf.buffer);
    dv.setUint32(paddedLen - 8, bitLen >>> 0, true);
    dv.setUint32(paddedLen - 4, Math.floor(bitLen / 0x100000000), true);

    var S = [
      7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
      5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
      4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
      6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    ];
    var K = new Array(64);
    for (var i = 0; i < 64; i++) {
      K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 0x100000000);
    }

    var a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;

    for (var off = 0; off < paddedLen; off += 64) {
      var M = new Array(16);
      for (var j = 0; j < 16; j++) M[j] = dv.getUint32(off + j * 4, true);
      var A = a0, B = b0, C = c0, D = d0;
      for (var i = 0; i < 64; i++) {
        var F, g;
        if (i < 16) { F = (B & C) | (~B & D); g = i; }
        else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; }
        else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) % 16; }
        else { F = C ^ (B | ~D); g = (7 * i) % 16; }
        var tmp = (A + F + K[i] + M[g]) >>> 0;
        var tmp2 = D;
        D = C;
        C = B;
        B = (B + rotl(tmp, S[i])) >>> 0;
        A = tmp2;
      }
      a0 = (a0 + A) >>> 0;
      b0 = (b0 + B) >>> 0;
      c0 = (c0 + C) >>> 0;
      d0 = (d0 + D) >>> 0;
    }

    var out = new Uint8Array(16);
    var odv = new DataView(out.buffer);
    odv.setUint32(0, a0, true);
    odv.setUint32(4, b0, true);
    odv.setUint32(8, c0, true);
    odv.setUint32(12, d0, true);
    return bytesToHex(out);
  }

  // ============================ SHA-1 ============================

  function sha1(bytes) {
    var len = bytes.length;
    var bitLen = len * 8;
    var paddedLen = len + 1;
    while (paddedLen % 64 !== 56) paddedLen++;
    paddedLen += 8;
    var buf = new Uint8Array(paddedLen);
    buf.set(bytes);
    buf[len] = 0x80;
    var dv = new DataView(buf.buffer);
    dv.setUint32(paddedLen - 8, Math.floor(bitLen / 0x100000000), false);
    dv.setUint32(paddedLen - 4, bitLen >>> 0, false);

    var h0 = 0x67452301, h1 = 0xefcdab89, h2 = 0x98badcfe, h3 = 0x10325476, h4 = 0xc3d2e1f0;

    for (var off = 0; off < paddedLen; off += 64) {
      var w = new Array(80);
      for (var j = 0; j < 16; j++) w[j] = dv.getUint32(off + j * 4, false);
      for (var j = 16; j < 80; j++) w[j] = rotl(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16], 1);
      var a = h0, b = h1, c = h2, d = h3, e = h4;
      for (var j = 0; j < 80; j++) {
        var f, k;
        if (j < 20) { f = (b & c) | (~b & d); k = 0x5a827999; }
        else if (j < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
        else if (j < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc; }
        else { f = b ^ c ^ d; k = 0xca62c1d6; }
        var temp = (rotl(a, 5) + f + e + k + w[j]) >>> 0;
        e = d; d = c; c = rotl(b, 30); b = a; a = temp;
      }
      h0 = (h0 + a) >>> 0; h1 = (h1 + b) >>> 0; h2 = (h2 + c) >>> 0; h3 = (h3 + d) >>> 0; h4 = (h4 + e) >>> 0;
    }

    var out = new Uint8Array(20);
    var odv = new DataView(out.buffer);
    odv.setUint32(0, h0, false); odv.setUint32(4, h1, false); odv.setUint32(8, h2, false);
    odv.setUint32(12, h3, false); odv.setUint32(16, h4, false);
    return bytesToHex(out);
  }

  // ============================ SHA-256 ============================

  var K256 = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ];

  function sha256(bytes) {
    var len = bytes.length;
    var bitLen = len * 8;
    var paddedLen = len + 1;
    while (paddedLen % 64 !== 56) paddedLen++;
    paddedLen += 8;
    var buf = new Uint8Array(paddedLen);
    buf.set(bytes);
    buf[len] = 0x80;
    var dv = new DataView(buf.buffer);
    dv.setUint32(paddedLen - 8, Math.floor(bitLen / 0x100000000), false);
    dv.setUint32(paddedLen - 4, bitLen >>> 0, false);

    var H = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];

    for (var off = 0; off < paddedLen; off += 64) {
      var w = new Array(64);
      for (var j = 0; j < 16; j++) w[j] = dv.getUint32(off + j * 4, false);
      for (var j = 16; j < 64; j++) {
        var s0 = rotr(w[j - 15], 7) ^ rotr(w[j - 15], 18) ^ (w[j - 15] >>> 3);
        var s1 = rotr(w[j - 2], 17) ^ rotr(w[j - 2], 19) ^ (w[j - 2] >>> 10);
        w[j] = (w[j - 16] + s0 + w[j - 7] + s1) >>> 0;
      }
      var a = H[0], b = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
      for (var j = 0; j < 64; j++) {
        var S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        var ch = (e & f) ^ (~e & g);
        var temp1 = (h + S1 + ch + K256[j] + w[j]) >>> 0;
        var S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        var maj = (a & b) ^ (a & c) ^ (b & c);
        var temp2 = (S0 + maj) >>> 0;
        h = g; g = f; f = e; e = (d + temp1) >>> 0; d = c; c = b; b = a; a = (temp1 + temp2) >>> 0;
      }
      H[0] = (H[0] + a) >>> 0; H[1] = (H[1] + b) >>> 0; H[2] = (H[2] + c) >>> 0; H[3] = (H[3] + d) >>> 0;
      H[4] = (H[4] + e) >>> 0; H[5] = (H[5] + f) >>> 0; H[6] = (H[6] + g) >>> 0; H[7] = (H[7] + h) >>> 0;
    }

    var out = new Uint8Array(32);
    var odv = new DataView(out.buffer);
    for (var j = 0; j < 8; j++) odv.setUint32(j * 4, H[j], false);
    return bytesToHex(out);
  }

  // ============================ SHA-512 ============================

  var K512 = [
    "428a2f98d728ae22", "7137449123ef65cd", "b5c0fbcfec4d3b2f", "e9b5dba58189dbbc",
    "3956c25bf348b538", "59f111f1b605d019", "923f82a4af194f9b", "ab1c5ed5da6d8118",
    "d807aa98a3030242", "12835b0145706fbe", "243185be4ee4b28c", "550c7dc3d5ffb4e2",
    "72be5d74f27b896f", "80deb1fe3b1696b1", "9bdc06a725c71235", "c19bf174cf692694",
    "e49b69c19ef14ad2", "efbe4786384f25e3", "0fc19dc68b8cd5b5", "240ca1cc77ac9c65",
    "2de92c6f592b0275", "4a7484aa6ea6e483", "5cb0a9dcbd41fbd4", "76f988da831153b5",
    "983e5152ee66dfab", "a831c66d2db43210", "b00327c898fb213f", "bf597fc7beef0ee4",
    "c6e00bf33da88fc2", "d5a79147930aa725", "06ca6351e003826f", "142929670a0e6e70",
    "27b70a8546d22ffc", "2e1b21385c26c926", "4d2c6dfc5ac42aed", "53380d139d95b3df",
    "650a73548baf63de", "766a0abb3c77b2a8", "81c2c92e47edaee6", "92722c851482353b",
    "a2bfe8a14cf10364", "a81a664bbc423001", "c24b8b70d0f89791", "c76c51a30654be30",
    "d192e819d6ef5218", "d69906245565a910", "f40e35855771202a", "106aa07032bbd1b8",
    "19a4c116b8d2d0c8", "1e376c085141ab53", "2748774cdf8eeb99", "34b0bcb5e19b48a8",
    "391c0cb3c5c95a63", "4ed8aa4ae3418acb", "5b9cca4f7763e373", "682e6ff3d6b2b8a3",
    "748f82ee5defb2fc", "78a5636f43172f60", "84c87814a1f0ab72", "8cc702081a6439ec",
    "90befffa23631e28", "a4506cebde82bde9", "bef9a3f7b2c67915", "c67178f2e372532b",
    "ca273eceea26619c", "d186b8c721c0c207", "eada7dd6cde0eb1e", "f57d4f7fee6ed178",
    "06f067aa72176fba", "0a637dc5a2c898a6", "113f9804bef90dae", "1b710b35131c471b",
    "28db77f523047d84", "32caab7b40c72493", "3c9ebe0a15c9bebc", "431d67c49c100d4c",
    "4cc5d4becb3e42b6", "597f299cfc657e2a", "5fcb6fab3ad6faec", "6c44198c4a475817"
  ].map(function (h) { return BigInt("0x" + h); });

  function sha512(bytes) {
    var len = bytes.length;
    var bitLen = BigInt(len) * 8n;
    var paddedLen = len + 1;
    while (paddedLen % 128 !== 112) paddedLen++;
    paddedLen += 16;
    var buf = new Uint8Array(paddedLen);
    buf.set(bytes);
    buf[len] = 0x80;
    var dv = new DataView(buf.buffer);
    // 128-bit 长度（高 64 位为 0，低 64 位为 bitLen）
    for (var i = 0; i < 8; i++) dv.setUint8(paddedLen - 1 - i, 0);
    var low = bitLen & 0xffffffffffffffffn;
    for (var i = 0; i < 8; i++) {
      dv.setUint8(paddedLen - 8 + i, Number((low >> BigInt(8 * (7 - i))) & 0xffn));
    }

    var H = [
      "6a09e667f3bcc908", "bb67ae8584caa73b", "3c6ef372fe94f82b", "a54ff53a5f1d36f1",
      "510e527fade682d1", "9b05688c2b3e6c1f", "1f83d9abfb41bd6b", "5be0cd19137e2179"
    ].map(function (h) { return BigInt("0x" + h); });

    var mask64 = 0xffffffffffffffffn;

    for (var off = 0; off < paddedLen; off += 128) {
      var w = new Array(80);
      for (var j = 0; j < 16; j++) {
        var v = 0n;
        for (var k = 0; k < 8; k++) v = (v << 8n) | BigInt(dv.getUint8(off + j * 8 + k));
        w[j] = v;
      }
      for (var j = 16; j < 80; j++) {
        var s0 = rotr64(w[j - 15], 1) ^ rotr64(w[j - 15], 8) ^ (w[j - 15] >> 7n);
        var s1 = rotr64(w[j - 2], 19) ^ rotr64(w[j - 2], 61) ^ (w[j - 2] >> 6n);
        w[j] = (w[j - 16] + s0 + w[j - 7] + s1) & mask64;
      }
      var a = H[0], b = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
      for (var j = 0; j < 80; j++) {
        var S1 = rotr64(e, 14) ^ rotr64(e, 18) ^ rotr64(e, 41);
        var ch = (e & f) ^ (~e & g);
        var temp1 = (h + S1 + ch + K512[j] + w[j]) & mask64;
        var S0 = rotr64(a, 28) ^ rotr64(a, 34) ^ rotr64(a, 39);
        var maj = (a & b) ^ (a & c) ^ (b & c);
        var temp2 = (S0 + maj) & mask64;
        h = g; g = f; f = e; e = (d + temp1) & mask64; d = c; c = b; b = a; a = (temp1 + temp2) & mask64;
      }
      for (var j = 0; j < 8; j++) H[j] = (H[j] + [a, b, c, d, e, f, g, h][j]) & mask64;
    }

    var out = new Uint8Array(64);
    for (var j = 0; j < 8; j++) {
      var hv = H[j];
      for (var k = 0; k < 8; k++) {
        out[j * 8 + k] = Number((hv >> BigInt(8 * (7 - k))) & 0xffn);
      }
    }
    return bytesToHex(out);
  }

  function rotr64(x, n) {
    return ((x >> BigInt(n)) | (x << BigInt(64 - n))) & 0xffffffffffffffffn;
  }

  // ============================ DES / 3DES ============================

  var DES_IP = [58,50,42,34,26,18,10,2,60,52,44,36,28,20,12,4,62,54,46,38,30,22,14,6,64,56,48,40,32,24,16,8,57,49,41,33,25,17,9,1,59,51,43,35,27,19,11,3,61,53,45,37,29,21,13,5,63,55,47,39,31,23,15,7];
  var DES_FP = [40,8,48,16,56,24,64,32,39,7,47,15,55,23,63,31,38,6,46,14,54,22,62,30,37,5,45,13,53,21,61,29,36,4,44,12,52,20,60,28,35,3,43,11,51,19,59,27,34,2,42,10,50,18,58,26,33,1,41,9,49,17,57,25];
  var DES_E = [32,1,2,3,4,5,4,5,6,7,8,9,8,9,10,11,12,13,12,13,14,15,16,17,16,17,18,19,20,21,20,21,22,23,24,25,24,25,26,27,28,29,28,29,30,31,32,1];
  var DES_P = [16,7,20,21,29,12,28,17,1,15,23,26,5,18,31,10,2,8,24,14,32,27,3,9,19,13,30,6,22,11,4,25];
  var DES_PC1 = [57,49,41,33,25,17,9,1,58,50,42,34,26,18,10,2,59,51,43,35,27,19,11,3,60,52,44,36,63,55,47,39,31,23,15,7,62,54,46,38,30,22,14,6,61,53,45,37,29,21,13,5,28,20,12,4];
  var DES_PC2 = [14,17,11,24,1,5,3,28,15,6,21,10,23,19,12,4,26,8,16,7,27,20,13,2,41,52,31,37,47,55,30,40,51,45,33,48,44,49,39,56,34,53,46,42,50,36,29,32];
  var DES_SHIFTS = [1,1,2,2,2,2,2,2,1,2,2,2,2,2,2,1];
  var DES_SBOX = [
    [14,4,13,1,2,15,11,8,3,10,6,12,5,9,0,7,0,15,7,4,14,2,13,1,10,6,12,11,9,5,3,8,4,1,14,8,13,6,2,11,15,12,9,7,3,10,5,0,15,12,8,2,4,9,1,7,5,11,3,14,10,0,6,13],
    [15,1,8,14,6,11,3,4,9,7,2,13,12,0,5,10,3,13,4,7,15,2,8,14,12,0,1,10,6,9,11,5,0,14,7,11,10,4,13,1,5,8,12,6,9,3,2,15,13,8,10,1,3,15,4,2,11,6,7,12,0,5,14,9],
    [10,0,9,14,6,3,15,5,1,13,12,7,11,4,2,8,13,7,0,9,3,4,6,10,2,8,5,14,12,11,15,1,13,6,4,9,8,15,3,0,11,1,2,12,5,10,14,7,1,10,13,0,6,9,8,7,4,15,14,3,11,5,2,12],
    [7,13,14,3,0,6,9,10,1,2,8,5,11,12,4,15,13,8,11,5,6,15,0,3,4,7,2,12,1,10,14,9,10,6,9,0,12,11,7,13,15,1,3,14,5,2,8,4,3,15,0,6,10,1,13,8,9,4,5,11,12,7,2,14],
    [2,12,4,1,7,10,11,6,8,5,3,15,13,0,14,9,14,11,2,12,4,7,13,1,5,0,15,10,3,9,8,6,4,2,1,11,10,13,7,8,15,9,12,5,6,3,0,14,11,8,12,7,1,14,2,13,6,15,0,9,10,4,5,3],
    [12,1,10,15,9,2,6,8,0,13,3,4,14,7,5,11,10,15,4,2,7,12,9,5,6,1,13,14,0,11,3,8,9,14,15,5,2,8,12,3,7,0,4,10,1,13,11,6,4,3,2,12,9,5,15,10,11,14,1,7,6,0,8,13],
    [4,11,2,14,15,0,8,13,3,12,9,7,5,10,6,1,13,0,11,7,4,9,1,10,14,3,5,12,2,15,8,6,1,4,11,13,12,3,7,14,10,15,6,8,0,5,9,2,6,11,13,8,1,4,10,7,9,5,0,15,14,2,3,12],
    [13,2,8,4,6,15,11,1,10,9,3,14,5,0,12,7,1,15,13,8,10,3,7,4,12,5,6,11,0,14,9,2,7,11,4,1,9,12,14,2,0,6,10,13,15,3,5,8,2,1,14,7,4,10,8,13,15,12,9,0,3,5,6,11]
  ];

  function __desPermute(data, table, n) {
    var out = new Array(n);
    for (var i = 0; i < n; i++) out[i] = data[table[i] - 1];
    return out;
  }

  function __desKeySchedule(key8) {
    var k = [];
    for (var i = 0; i < 8; i++) for (var j = 0; j < 8; j++) k.push((key8[i] >> (7 - j)) & 1);
    var pc1 = __desPermute(k, DES_PC1, 56);
    var C = pc1.slice(0, 28), D = pc1.slice(28);
    var keys = [];
    for (var round = 0; round < 16; round++) {
      var shift = DES_SHIFTS[round];
      C = C.slice(shift).concat(C.slice(0, shift));
      D = D.slice(shift).concat(D.slice(0, shift));
      var cd = C.concat(D);
      keys.push(__desPermute(cd, DES_PC2, 48));
    }
    return keys;
  }

  function __desCryptBlock(block, keys, encrypt) {
    var bits = [];
    for (var i = 0; i < 8; i++) for (var j = 0; j < 8; j++) bits.push((block[i] >> (7 - j)) & 1);
    var ip = __desPermute(bits, DES_IP, 64);
    var L = ip.slice(0, 32), R = ip.slice(32);
    var order = encrypt ? [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15] : [15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0];
    for (var r = 0; r < 16; r++) {
      var key = keys[order[r]];
      var er = __desPermute(R, DES_E, 48);
      var x = new Array(48);
      for (var i = 0; i < 48; i++) x[i] = er[i] ^ key[i];
      var sOut = new Array(32);
      var sPos = 0;
      for (var s = 0; s < 8; s++) {
        var row = (x[s*6] << 1) | x[s*6+5];
        var col = (x[s*6+1] << 3) | (x[s*6+2] << 2) | (x[s*6+3] << 1) | x[s*6+4];
        var v = DES_SBOX[s][row*16 + col];
        for (var b = 3; b >= 0; b--) sOut[sPos++] = (v >> b) & 1;
      }
      var p = __desPermute(sOut, DES_P, 32);
      var newR = new Array(32);
      for (var i = 0; i < 32; i++) newR[i] = L[i] ^ p[i];
      L = R;
      R = newR;
    }
    var pre = R.concat(L);
    var fp = __desPermute(pre, DES_FP, 64);
    var out = new Uint8Array(8);
    for (var i = 0; i < 8; i++) {
      var byte = 0;
      for (var j = 0; j < 8; j++) byte = (byte << 1) | fp[i*8+j];
      out[i] = byte;
    }
    return out;
  }

  function __desCrypt(dataBytes, keyBytes, ivBytes, mode, encrypt) {
    var isCbc = String(mode || "").toUpperCase().indexOf("CBC") >= 0;
    var blockSize = 8;
    var padded = new Uint8Array(dataBytes.length + (encrypt ? (blockSize - (dataBytes.length % blockSize)) : 0));
    padded.set(dataBytes);
    if (encrypt) {
      var pad = blockSize - (dataBytes.length % blockSize);
      for (var i = dataBytes.length; i < padded.length; i++) padded[i] = pad;
    }
    var keys = __desKeySchedule(keyBytes);
    var out = new Uint8Array(padded.length);
    var prev = ivBytes ? ivBytes.slice(0, blockSize) : new Uint8Array(blockSize);
    for (var off = 0; off < padded.length; off += blockSize) {
      var block = padded.slice(off, off + blockSize);
      if (isCbc) {
        if (encrypt) {
          for (var i = 0; i < blockSize; i++) block[i] ^= prev[i];
          var enc = __desCryptBlock(block, keys, true);
          prev = enc;
          out.set(enc, off);
        } else {
          var dec = __desCryptBlock(block, keys, false);
          for (var i = 0; i < blockSize; i++) dec[i] ^= prev[i];
          prev = block;
          out.set(dec, off);
        }
      } else {
        var r = __desCryptBlock(block, keys, encrypt);
        out.set(r, off);
      }
    }
    if (!encrypt) {
      var last = out[out.length - 1];
      if (last > 0 && last <= blockSize) out = out.slice(0, out.length - last);
    }
    return out;
  }

  function __tripleDesCrypt(dataBytes, keyBytes, ivBytes, mode, encrypt) {
    var k1 = keyBytes.slice(0, 8), k2 = keyBytes.slice(8, 16), k3 = keyBytes.length >= 24 ? keyBytes.slice(16, 24) : k1;
    var isCbc = String(mode || "").toUpperCase().indexOf("CBC") >= 0;
    var blockSize = 8;
    var padded = new Uint8Array(dataBytes.length + (encrypt ? (blockSize - (dataBytes.length % blockSize)) : 0));
    padded.set(dataBytes);
    if (encrypt) {
      var pad = blockSize - (dataBytes.length % blockSize);
      for (var i = dataBytes.length; i < padded.length; i++) padded[i] = pad;
    }
    var keys1 = __desKeySchedule(k1), keys2 = __desKeySchedule(k2), keys3 = __desKeySchedule(k3);
    var out = new Uint8Array(padded.length);
    var prev = ivBytes ? ivBytes.slice(0, blockSize) : new Uint8Array(blockSize);
    for (var off = 0; off < padded.length; off += blockSize) {
      var block = padded.slice(off, off + blockSize);
      var result;
      if (isCbc) {
        if (encrypt) {
          for (var i = 0; i < blockSize; i++) block[i] ^= prev[i];
          result = __desCryptBlock(__desCryptBlock(__desCryptBlock(block, keys1, true), keys2, false), keys3, true);
          prev = result;
        } else {
          var dec = __desCryptBlock(__desCryptBlock(__desCryptBlock(block, keys3, false), keys2, true), keys1, false);
          for (var i = 0; i < blockSize; i++) dec[i] ^= prev[i];
          prev = block;
          result = dec;
        }
      } else {
        result = encrypt
          ? __desCryptBlock(__desCryptBlock(__desCryptBlock(block, keys1, true), keys2, false), keys3, true)
          : __desCryptBlock(__desCryptBlock(__desCryptBlock(block, keys3, false), keys2, true), keys1, false);
      }
      out.set(result, off);
    }
    if (!encrypt) {
      var last = out[out.length - 1];
      if (last > 0 && last <= blockSize) out = out.slice(0, out.length - last);
    }
    return out;
  }

  // ============================ HMAC ============================

  function hmacBytes(hashFn, blockSize, keyBytes, dataBytes) {
    if (keyBytes.length > blockSize) {
      keyBytes = hashFn(keyBytes);
    }
    var ipad = new Uint8Array(blockSize), opad = new Uint8Array(blockSize);
    for (var i = 0; i < blockSize; i++) {
      ipad[i] = 0x36; opad[i] = 0x5c;
    }
    var ik = new Uint8Array(blockSize), ok = new Uint8Array(blockSize);
    for (var i = 0; i < keyBytes.length; i++) { ik[i] = keyBytes[i]; ok[i] = keyBytes[i]; }
    for (var i = 0; i < blockSize; i++) { ik[i] ^= ipad[i]; ok[i] ^= opad[i]; }
    var inner = new Uint8Array(ik.length + dataBytes.length);
    inner.set(ik); inner.set(dataBytes, ik.length);
    var innerHash = hexToBytes(hashFn(inner));
    var outer = new Uint8Array(ok.length + innerHash.length);
    outer.set(ok); outer.set(innerHash, ok.length);
    return hexToBytes(hashFn(outer));
  }

  // ============================ 导出 ============================

  C.utf8Bytes = utf8Bytes;
  C.bytesToHex = bytesToHex;
  C.bytesToBase64 = bytesToBase64;
  C.hexToBytes = hexToBytes;
  C.md5 = function (s) { return md5(utf8Bytes(s)); };
  C.sha1 = function (s) { return sha1(utf8Bytes(s)); };
  C.sha256 = function (s) { return sha256(utf8Bytes(s)); };
  C.sha512 = function (s) { return sha512(utf8Bytes(s)); };
  C.hmac = function (s, key, algo) {
    var dataBytes = utf8Bytes(s);
    var keyBytes = utf8Bytes(key);
    var a = String(algo || "").toUpperCase();
    if (a === "SHA-1" || a === "SHA1") return bytesToHex(hmacBytes(sha1, 64, keyBytes, dataBytes));
    if (a === "SHA-256" || a === "SHA256") return bytesToHex(hmacBytes(sha256, 64, keyBytes, dataBytes));
    if (a === "SHA-512" || a === "SHA512") return bytesToHex(hmacBytes(sha512, 128, keyBytes, dataBytes));
    if (a === "MD5") return bytesToHex(hmacBytes(md5, 64, keyBytes, dataBytes));
    return "";
  };

  function b64ToBytes(s) {
    var bin = atob(String(s));
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  function bytesToUtf8(b) { return new TextDecoder("utf-8").decode(b); }

  // DES 加解密：data 解密时为 base64，加密时为明文；key/iv 为字符串；返回 base64(加密)/明文(解密)
  C.des = function (data, key, iv, transformation, encrypt) {
    var dataBytes = encrypt ? utf8Bytes(data) : b64ToBytes(data);
    var keyBytes = utf8Bytes(key);
    var ivBytes = (iv === undefined || iv === null || iv === "") ? null : utf8Bytes(iv);
    var out = __desCrypt(dataBytes, keyBytes, ivBytes, transformation, !!encrypt);
    return encrypt ? bytesToBase64(out) : bytesToUtf8(out);
  };
  C.tripleDes = function (data, key, iv, transformation, encrypt) {
    var dataBytes = encrypt ? utf8Bytes(data) : b64ToBytes(data);
    var keyBytes = utf8Bytes(key);
    var ivBytes = (iv === undefined || iv === null || iv === "") ? null : utf8Bytes(iv);
    var out = __tripleDesCrypt(dataBytes, keyBytes, ivBytes, transformation, !!encrypt);
    return encrypt ? bytesToBase64(out) : bytesToUtf8(out);
  };

  // RSA（PKCS#1 v1.5 公钥加密 / 私钥解密），modulus/exponent 为十六进制
  function modPow(base, exp, mod) {
    var r = 1n;
    base = base % mod;
    while (exp > 0n) {
      if (exp & 1n) r = (r * base) % mod;
      base = (base * base) % mod;
      exp >>= 1n;
    }
    return r;
  }
  C.rsaEncrypt = function (dataBytes, modulusHex, exponentHex) {
    var k = Math.ceil(modulusHex.length / 2);
    var em = new Uint8Array(k);
    em[0] = 0x00; em[1] = 0x02;
    var psLen = k - 3 - dataBytes.length;
    if (psLen < 8) throw new Error("RSA 明文过长");
    for (var i = 0; i < psLen; i++) {
      var r;
      do { r = Math.floor(Math.random() * 255) + 1; } while (r === 0);
      em[2 + i] = r;
    }
    em[2 + psLen] = 0x00;
    em.set(dataBytes, 3 + psLen);
    var m = BigInt("0x" + bytesToHex(em));
    var e = BigInt("0x" + (exponentHex || "010001"));
    var n = BigInt("0x" + modulusHex);
    var c = modPow(m, e, n);
    var ch = c.toString(16);
    if (ch.length % 2) ch = "0" + ch;
    return ch;
  };
  C.rsaDecrypt = function (cipherHex, modulusHex, exponentHex) {
    var c = BigInt("0x" + cipherHex);
    var d = BigInt("0x" + exponentHex);
    var n = BigInt("0x" + modulusHex);
    var m = modPow(c, d, n);
    var k = Math.ceil(modulusHex.length / 2);
    var mh = m.toString(16);
    while (mh.length < k * 2) mh = "0" + mh;
    var em = hexToBytes(mh);
    // PKCS#1 v1.5 去填充：跳过 0x00 0x02 PS 0x00
    var i = 2;
    while (i < em.length && em[i] !== 0) i++;
    if (i >= em.length) return "";
    return bytesToUtf8(em.slice(i + 1));
  };

  globalThis.__legadoCrypto = C;
})();
''';
}
