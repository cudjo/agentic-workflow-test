/* px.js — общий рантайм макетов (только mockups, не игровой код).
   Рисует пиксель-арт на canvas 480x270 без сглаживания: спрайты из ASCII, сцены, освещение
   (Bayer-дизеринг, квантованные ступени), целочисленное масштабирование. */
(function () {
  'use strict';
  var W = 480, H = 270;

  /* ---------- Палитра (SPEC §6.1 + производные оттенки) ---------- */
  var C = {
    void: '#0b0c10',
    night9: '#10131c', night: '#1a1f2e', night3: '#262c3e', night5: '#323a4c',
    green9: '#161e14', green: '#1f2a1c', green3: '#2e3d2a',
    brown9: '#2a2018', brown: '#3b2e22', brown3: '#54402f',
    stone9: '#303035', stone: '#4a4a4f', stone3: '#6b6b70', stone5: '#9a9a9c',
    bone: '#d6c9a8',
    gold9: '#7d5a28', gold: '#c08a3e', gold3: '#e0b56a',
    blood9: '#4a1a17', blood: '#7a2a24', blood3: '#b5483c',
    steel9: '#2f4350', steel: '#4f6b7a', steel3: '#7f9aa8'
  };
  var PAL = {
    k: C.void, H: C.green, h: C.green3, s: '#8a6a4f', a: C.steel, A: C.steel3,
    b: C.brown3, B: C.brown, g: C.gold, G: C.gold9, r: C.blood, R: C.blood3,
    e: C.bone, w: C.stone5, n: C.stone, N: C.stone9, y: C.gold3, p: C.stone3,
    t: C.steel9, u: C.night3, v: C.night9, d: C.brown9
  };

  /* ---------- Спрайты (ASCII → canvas) ---------- */
  var SPR = {
    hero: [
      '......kkkk......',
      '.....kHHHHk.....',
      '....kHHhhHHk....',
      '....kHhhhhHk....',
      '....kHhsssHk....',
      '....kHhskssk....',
      '.....kHsssk.....',
      '.....kkhhhkk....',
      '....kHHhhhHHk...',
      '...kHhhAaahhHk.A',
      '...kHhaAaaahhkAA',
      '..ksskaaaaakAkA.',
      '..kskkbbggbkAk..',
      '...kk.bbbbbgk...',
      '......kbbbbk....',
      '......khhhhk....',
      '......khhhhk....',
      '.....kHhhhhHk...',
      '.....kHhhhhHk...',
      '.....kHh..hHk...',
      '.....kbb..bbk...',
      '....kbbb..bbbk..',
      '....kkkk..kkkk..'
    ],
    hollow: [
      '......kkkk......',
      '.....kwwwwk.....',
      '....kwwwwwwk....',
      '....kwRkwRwk....',
      '....kwwwwwwk....',
      '.....kwkkwk.....',
      '.....kkwwkk.....',
      '....kNnnnnNk....',
      '...kNnnNNnnNk...',
      '..kwNnNnnNnNk...',
      '..kwkNnnnnNkwk..',
      '.kwk.kNnnNk.kwk.',
      '.kwk.kNNnNk.kwk.',
      '.kk..kNnnNk..kk.',
      '......kNnNk.....',
      '......kNnNk.....',
      '.....kNNkkNNk...',
      '.....kNk..kNk...',
      '.....kwk..kwk...',
      '....kwwk..kwwk..',
      '....kkkk..kkkk..'
    ],
    keeper: [
      '......kkkk....g.',
      '.....kBBBBk..kgk',
      '....kBbbbbBk.kbk',
      '....kBbwwbBk.kbk',
      '....kBbsskBk.kbk',
      '....kBeeeeBk.kbk',
      '.....kBeeBk..kbk',
      '....kBBeeBBk.kbk',
      '...kBbbBBbbBkkbk',
      '..kBbbbBBbbbBkbk',
      '..kBbbbbbbbbBkbk',
      '.kssBbbbbbbbBkbk',
      '.kskBbbbbbbBbkbk',
      '..kkBbbbbbbBbkbk',
      '...kBbbbbbbBbkbk',
      '...kBbbbbbbbBkbk',
      '...kBbbbbbbbBkbk',
      '...kBBbbbbbBBkbk',
      '...kBbbbbbbbBkbk',
      '...kBBbbbbbBBkbk',
      '...kBBBBBBBBBkbk',
      '....kkkkkkkkkkkk'
    ],
    face: [
      '..kkkkkkkk..',
      '.kHHHHHHHHk.',
      'kHHhhhhhhHHk',
      'kHhhhhhhhhHk',
      'kHhsssssshHk',
      'kHhsskssskHk',
      'kHhssssssshk',
      'kHhhsssshhHk',
      '.kHhhsshhHk.',
      '..kkHHHHkk..'
    ],
    logs: [
      '..bbbbbbbbb..',
      '.bBbBBBBBbBb.',
      'bBBkkkkkkkBBb',
      '.kkdddddddkk.'
    ],
    /* иконки 12x12 */
    sword: [
      '..........sk', '.........swk', '........swk.', '.......swk..', '......swk...',
      '.k...swk....', '..kkswk.....', '...kgGk.....', '..kgkkGk....', '.kbk..kGk...',
      'kbk.........', '............'
    ].map(function (r) { return r.replace(/s/g, 'A').replace(/w/g, 'e'); }),
    shield: [
      '.kkkkkkkkkk.', 'kaAAAAAaaaak', 'kaAAAAAaaaak', 'kaAAggAaaaak', 'kaAAggAaaaak',
      'kaAAAAAaaaak', '.kaAAAAaaak.', '..kaAAAaak..', '...kaAaak...', '....kaak....',
      '.....kk.....', '............'
    ],
    helm: [
      '............', '...kkkkkk...', '..kAAAAaak..', '.kAAAAAaaak.', '.kAAAAAaaak.',
      '.kAkkkkkkak.', '.kAkaaaakak.', '.kAAaaaaaak.', '.kAAk..kaak.', '..kk....kk..',
      '............', '............'
    ],
    armor: [
      '..kk....kk..', '.kaAkkkkAak.', 'kaAAAaaAAaak', 'kaAAAaaAAaak', 'kaAAAaaAAaak',
      '.kaaAaaAaak.', '..kaaaaaak..', '..kaaggaak..', '..kaaaaaak..', '..kaaaaaak..',
      '...kkkkkk...', '............'
    ],
    potion: [
      '............', '....kkkk....', '.....bb.....', '....kkkk....', '...kRRRRk...',
      '..kRrRRrRk..', '..kRRrrRRk..', '..kRRRRRRk..', '..kRRRRRRk..', '...kRRRRk...',
      '....kkkk....', '............'
    ],
    herb: [
      '............', '......kk....', '....kkhhk...', '..kkhhhhk.k.', '.khhhHhhkkhk',
      '.khhHhhhhhhk', '..kkhHhhhkk.', '....khHhk...', '.....kHk....', '.....kBk....',
      '....kkBkk...', '............'
    ],
    key: [
      '............', '...kkkk.....', '..kggggk....', '.kgk..kgk...', '.kg....gk...',
      '.kgk..kgk...', '..kggggkk...', '....kgk.....', '....kggkk...', '....kgk.....',
      '....kggkk...', '.....kk.....'
    ],
    scroll: [
      '............', '.kkkkkkkkk..', 'keeeeeeeek..', 'kekkkkkkek..', 'keeeeeeeek..',
      'kekkkkkeek..', 'keeeeeeeek..', 'kekkkkkkek..', 'keeeeeeeek..', '.kkkkkkkkk..',
      '............', '............'
    ],
    ring: [
      '............', '....kkkk....', '...kyyyyk...', '....kkkk....', '...kgkkgk...',
      '..kgk..kgk..', '..kg....gk..', '..kgk..kgk..', '...kgkkgk...', '....kkkk....',
      '............', '............'
    ],
    coin: [
      '............', '...kkkkkk...', '..kyyyyggk..', '.kyyggggGgk.', '.kygkkkkGgk.',
      '.kygkggkGgk.', '.kygkggkGgk.', '.kygkkkkGgk.', '.kyggGGGGgk.', '..kgggGGgk..',
      '...kkkkkk...', '............'
    ],
    skull: [
      '............', '...kkkkkk...', '..kwwwwwwk..', '.kwwwwwwwwk.', '.kwkkwwkkwk.',
      '.kwkRwwkRwk.', '.kwwwkkwwwk.', '..kwwwwwwk..', '...kwkwkwk..', '...kkkkkkk..',
      '............', '............'
    ],
    bag: [
      '............', '....kkkk....', '....kbbk....', '...kbbbbk...', '..kBbbbbBk..',
      '.kBbbgggbBk.', '.kBbbgRgbBk.', '.kBbbgggbBk.', '.kBBbbbbBBk.', '..kBBBBBBk..',
      '...kkkkkk...', '............'
    ],
    djump: [
      '.....kk.....', '....kAAk....', '...kAAAAk...', '..kAkAAkAk..', '....kAAk....',
      '............', '.....kk.....', '....kAAk....', '...kAAAAk...', '..kAkAAkAk..',
      '....kAAk....', '............'
    ],
    dash: [
      '............', '.k....kk....', '..k..kAAk...', '.kAk.kAAAk..', '..kAkkAAAAk.',
      '.kAAAAAAAAAk', '..kAkkAAAAk.', '.kAk.kAAAk..', '..k..kAAk...', '.k....kk....',
      '............', '............'
    ],
    climb: [
      '............', '.kk.....kk..', '.kAk...kAk..', '.kAkkkkkAk..', '.kAAAAAAAk..',
      '.kAAkkkkAk..', '.kk.kAAk.k..', '....kAAk....', '...kAkkAk...', '...kAk.kAk..',
      '...kk...kk..', '............'
    ],
    lock: [
      '............', '...kkkkkk...', '..kpkkkkpk..', '..kp....pk..', '.kkkkkkkkkk.',
      '.kppppppppk.', '.kpppkkpppk.', '.kpppkkpppk.', '.kppppkpppk.', '.kppppppppk.',
      '.kkkkkkkkkk.', '............'
    ],
    axe: [
      '............', '....kkkk....', '...kAAAAk...', '..kAAAAAAk..', '..kAAAAAk...',
      '...kkkbk....', '.....kbk....', '.....kbk....', '.....kbk....', '.....kbk....',
      '.....kBk....', '.....kk.....'
    ],
    flame0: ['..R..', '.RgR.', '.RgR.', 'RgyyR', 'RgyeR', 'RgyeR', '.RgR.'],
    flame1: ['...R.', '..RgR', '.RggR', 'RgyyR', 'RgyeR', 'RgyeR', '.RgR.'],
    flame2: ['.R...', 'RgR..', 'RggR.', 'RgyyR', 'RgyeR', 'RgyeR', '.RgR.'],
    fire0: [
      '.....R.....', '....Rg.....', '...RgR..R..', '...RggR.Rg.', '..RggyRRgR.',
      '..RgyyggyR.', '.RgyyeyyyR.', '.RgyeeeyygR', 'RgyyeeeeyyR', 'RgyeeeeeyyR',
      'RggyeeeeygR', '.RggyyyygR.'
    ],
    fire1: [
      '......R....', '.....Rg....', '..R..RgR...', '.Rg.RggR...', '.RgRRggyR..',
      '.RgyggyyR..', '.RgyyyeyyR.', 'RgyyeeeyygR', 'RgyyeeeeyyR', 'RgyeeeeeyyR',
      'RggyeeeeygR', '.RggyyyygR.'
    ],
    fire2: [
      '....R......', '....gR.....', '...RgR.R...', '..RgggRRg..', '..RgyyggyR.',
      '.RgyyeyyyR.', '.RgyeeeyyR.', '.RgyeeeyygR', 'RgyyeeeeyyR', 'RgyeeeeeyyR',
      'RggyeeeeygR', '.RggyyyygR.'
    ]
  };

  function drawSprite(ctx, rows, x, y, flip) {
    for (var j = 0; j < rows.length; j++) {
      var row = rows[j];
      for (var i = 0; i < row.length; i++) {
        var ch = row.charAt(flip ? row.length - 1 - i : i);
        var col = PAL[ch];
        if (col) { ctx.fillStyle = col; ctx.fillRect(x + i, y + j, 1, 1); }
      }
    }
  }
  function sprW(rows) { var w = 0; rows.forEach(function (r) { if (r.length > w) w = r.length; }); return w; }

  function mountSprites(root) {
    (root || document).querySelectorAll('canvas[data-spr]').forEach(function (cv) {
      var rows = SPR[cv.dataset.spr]; if (!rows) return;
      var w = sprW(rows), h = rows.length, z = +cv.dataset.zoom || 1;
      cv.width = w; cv.height = h;
      cv.style.width = (w * z) + 'px'; cv.style.height = (h * z) + 'px';
      var ctx = cv.getContext('2d'); ctx.imageSmoothingEnabled = false;
      ctx.clearRect(0, 0, w, h);
      drawSprite(ctx, rows, 0, 0, cv.dataset.flip === '1');
      if (!cv.hasAttribute('role')) cv.setAttribute('aria-hidden', 'true');
    });
  }

  /* ---------- Утилиты рисования ---------- */
  function rect(c, x, y, w, h, col) { c.fillStyle = col; c.fillRect(x, y, w, h); }
  function hash(x, y) {
    var h = (Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263)) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
  }
  function em(hex) { // «эмиссивный» пиксель: не затемняется проходом освещения (alpha 0.99)
    var n = parseInt(hex.slice(1), 16);
    return 'rgba(' + (n >> 16) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',0.99)';
  }
  var BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];

  function sky(c, cols, y0, y1) {
    var n = cols.length - 1;
    for (var y = y0; y < y1; y++) {
      var pos = (y - y0) / (y1 - y0) * n, i = Math.min(n - 1, Math.floor(pos)), fr = pos - i;
      for (var x = 0; x < W; x++) {
        var b = (BAYER[y & 3][x & 3] + 0.5) / 16;
        rect(c, x, y, 1, 1, cols[i + (fr > b ? 1 : 0)]);
      }
    }
  }
  function stars(c, ymax, count, seed) {
    for (var i = 0; i < count; i++) {
      var x = Math.floor(hash(i, seed) * W), y = Math.floor(hash(seed, i + 77) * ymax);
      rect(c, x, y, 1, 1, em(hash(i, 5) > 0.7 ? C.bone : C.steel3));
    }
  }
  function moon(c, cx, cy, r) {
    for (var d = r + 1; d < r + 16; d++) { // ореол
      for (var a = 0; a < 360; a += 1) {
        var x = Math.round(cx + Math.cos(a * Math.PI / 180) * d), y = Math.round(cy + Math.sin(a * Math.PI / 180) * d);
        if (hash(x, y) < (1 - (d - r) / 16) * 0.45) rect(c, x, y, 1, 1, em(C.steel9));
      }
    }
    for (var yy = -r; yy <= r; yy++) for (var xx = -r; xx <= r; xx++) {
      if (xx * xx + yy * yy <= r * r) {
        var col = C.stone5;
        if (xx + yy < -r * 0.7) col = C.bone;
        else if (hash(xx + cx, yy + cy) < 0.12 && xx + yy > -r * 0.2) col = C.stone3;
        rect(c, cx + xx, cy + yy, 1, 1, em(col));
      }
    }
  }
  function ridge(c, baseY, amp, seed, col) {
    for (var x = 0; x < W; x++) {
      var v = 0.5 + 0.3 * Math.sin(x * 0.021 + seed) + 0.2 * Math.sin(x * 0.053 + seed * 2) + 0.1 * Math.sin(x * 0.137 + seed * 3);
      var h = Math.round((baseY - amp * v) / 2) * 2;
      rect(c, x, h, 1, H - h, col);
    }
  }
  function bricks(c, x0, y0, w, h, o) {
    rect(c, x0, y0, w, h, o.mortar);
    for (var row = 0, y = y0; y < y0 + h; row++, y += o.bh) {
      var off = (row % 2) * (o.bw / 2);
      for (var x = x0 - off; x < x0 + w; x += o.bw) {
        var t = o.tones[Math.floor(hash(x + 9, y + 3) * o.tones.length)];
        var bx = Math.max(x + 1, x0), ex = Math.min(x + o.bw, x0 + w), by = y + 1, bh = Math.min(o.bh - 1, y0 + h - by);
        if (ex > bx && bh > 0) { rect(c, bx, by, ex - bx, bh, t); rect(c, bx, by, ex - bx, 1, o.hi); }
      }
    }
    for (var yy = y0; yy < y0 + h; yy++) for (var xx = x0; xx < x0 + w; xx++) {
      var r = hash(xx * 3, yy * 7);
      if (r < 0.025) rect(c, xx, yy, 1, 1, o.mortar);
      else if (o.moss && yy > y0 + h * 0.55 && r > 1 - (yy - (y0 + h * 0.55)) / (h * 0.45) * 0.14) rect(c, xx, yy, 1, 1, C.green3);
    }
  }
  var WALL = { bw: 16, bh: 8, tones: [C.stone, '#44444a', '#505056', '#3f3f45'], mortar: '#2b2b30', hi: '#5a5a60', moss: true };
  var WALL_D = { bw: 16, bh: 8, tones: ['#3a3a3f', '#36363c', '#3e3e44'], mortar: '#232327', hi: '#46464c', moss: true };

  function castle(c, gx, gy, towers, col, winCol) {
    towers.forEach(function (t, k) {
      var x = gx + t[0], w = t[1], h = t[2], top = gy - h;
      rect(c, x, top, w, h, col);
      if (t[3] === 'spire') {
        var sh = Math.round(w * 1.5);
        for (var j = 0; j < sh; j++) {
          var ww = Math.max(2, Math.round((w + 4) * (1 - j / sh)));
          rect(c, x + Math.round((w - ww) / 2), top - j - 1, ww, 1, col);
        }
        rect(c, x + Math.floor(w / 2), top - sh - 6, 1, 6, col);
      } else {
        for (var i = 0; i < w; i += 6) rect(c, x + i, top - 3, 4, 3, col);
      }
      for (var wy = top + 8; wy < gy - 12; wy += 14) {
        if (hash(k, wy) > 0.4) rect(c, x + Math.floor(w / 2) - 1, wy, 2, 5, em(winCol));
      }
    });
  }
  function archFill(c, cx, springY, r, col, yTop) {
    for (var y = yTop; y < springY; y++) {
      var dy = springY - y, hw = Math.floor(Math.sqrt(Math.max(0, r * r - dy * dy)));
      rect(c, cx - hw, y, hw * 2, 1, col);
    }
  }
  function pointedFill(c, cx, top, bottom, halfW, col) {
    for (var y = top; y < bottom; y++) {
      var hw = Math.min(halfW, Math.floor((y - top) * 0.9));
      rect(c, cx - hw, y, hw * 2, 1, col);
    }
  }
  function line(c, x0, y0, x1, y1, col) {
    var dx = Math.abs(x1 - x0), sx = x0 < x1 ? 1 : -1, dy = -Math.abs(y1 - y0), sy = y0 < y1 ? 1 : -1, err = dx + dy;
    for (;;) {
      rect(c, x0, y0, 1, 1, col);
      if (x0 === x1 && y0 === y1) break;
      var e2 = 2 * err;
      if (e2 >= dy) { err += dy; x0 += sx; }
      if (e2 <= dx) { err += dx; y0 += sy; }
    }
  }

  /* ---------- Сцены ---------- */
  var GY = 222; // линия земли деревни

  function paintVillage(c, o) {
    o = o || {};
    sky(c, [C.night9, C.night, C.night3, C.night5], 0, 170);
    stars(c, 110, 70, 3);
    moon(c, 250, 46, 13);
    ridge(c, 150, 46, 1.3, '#161b27');
    castle(c, 110, 150, [[0, 26, 60, 'spire'], [30, 34, 44, 'flat'], [70, 40, 84, 'spire'], [116, 30, 52, 'flat'], [150, 26, 70, 'spire'], [180, 38, 46, 'flat']], '#10141d', C.gold9);
    ridge(c, 176, 30, 2.7, '#1a2030');
    // каменная стена-бастион
    bricks(c, 0, 112, W, GY - 112, WALL);
    for (var x = 0; x < W; x += 24) { rect(c, x + 4, 104, 14, 8, '#44444a'); rect(c, x + 4, 104, 14, 1, '#5a5a60'); }
    rect(c, 0, 112, W, 2, '#2b2b30');
    // стяг
    rect(c, 280, 118, 18, 2, C.brown3);
    for (var j = 0; j < 38; j++) {
      var notch = j > 30 ? (j - 30) : 0;
      rect(c, 282 + notch, 120 + j, 14 - notch * 2, 1, C.blood);
    }
    rect(c, 288, 128, 2, 10, C.gold9); rect(c, 285, 131, 8, 2, C.gold9);
    // арка ворот
    archFill(c, 212, 164, 32, '#5c5c62', 128); rect(c, 180, 164, 64, 58, '#5c5c62');
    archFill(c, 212, 164, 28, '#0e0f14', 136); rect(c, 184, 164, 56, 58, '#0e0f14');
    for (var gx = 187; gx < 240; gx += 6) {
      var top = 164 - Math.floor(Math.sqrt(Math.max(0, 784 - (gx - 212) * (gx - 212))));
      rect(c, gx, top, 2, 176 - top, C.brown3);
    }
    rect(c, 184, 150, 56, 2, C.brown); rect(c, 184, 170, 56, 2, C.brown);
    for (var kx = 184; kx < 240; kx += 8) rect(c, kx, 128 + 0, 1, 0, C.void);
    // факелы (кронштейн)
    [170, 256].forEach(function (tx) {
      rect(c, tx, 168, 2, 12, C.brown3); rect(c, tx - 2, 166, 6, 3, C.stone9); rect(c, tx - 1, 180, 4, 2, C.stone9);
    });
    // хижина
    rect(c, 14, 150, 82, GY - 150, C.brown3);
    for (var px = 16; px < 96; px += 6) rect(c, px, 150, 1, GY - 150, C.brown);
    rect(c, 14, 150, 82, 3, C.brown9); rect(c, 14, 186, 82, 2, C.brown9);
    rect(c, 14, 150, 3, GY - 150, C.brown9); rect(c, 93, 150, 3, GY - 150, C.brown9);
    for (var ry = 0; ry < 32; ry++) {
      var half = Math.max(2, Math.round(ry * 50 / 32));
      rect(c, 55 - half, 118 + ry, half * 2, 1, ry % 4 === 0 ? C.brown9 : (ry % 2 ? '#33261b' : '#2e231a'));
    }
    rect(c, 5, 148, 100, 3, C.brown9);
    rect(c, 58, 166, 14, 16, C.brown9); rect(c, 60, 168, 10, 12, em(C.gold)); rect(c, 64, 168, 2, 12, C.brown9); rect(c, 60, 173, 10, 2, C.brown9);
    rect(c, 26, 190, 16, 32, '#1f1812'); for (var dx = 30; dx < 42; dx += 4) rect(c, dx, 190, 1, 32, C.brown9);
    rect(c, 36, 206, 2, 2, C.gold9);
    // уступ-платформа
    rect(c, 320, 184, 12, 38, '#35353a'); rect(c, 392, 184, 12, 38, '#35353a');
    bricks(c, 306, 170, 112, 14, WALL);
    rect(c, 306, 168, 112, 2, C.stone3);
    for (var mx = 306; mx < 418; mx++) if (hash(mx, 9) > 0.55) rect(c, mx, 167, 1, 1 + (hash(mx, 4) > 0.6 ? 1 : 0), C.green3);
    // сундук на уступе
    rect(c, 356, 158, 18, 10, C.brown3); rect(c, 356, 156, 18, 3, C.brown); rect(c, 356, 162, 18, 1, C.brown9); rect(c, 364, 160, 3, 4, C.gold);
    rect(c, 356, 156, 18, 1, C.stone3);
    // завал (препятствие)
    for (var rx = 424; rx < 472; rx++) {
      var tp = 166 + Math.floor(Math.abs(rx - 447) * 1.1);
      for (var ry2 = tp; ry2 < GY; ry2 += 4) {
        var hh = hash(rx, ry2);
        rect(c, rx, ry2, 1, Math.min(4, GY - ry2), hh < 0.3 ? C.stone9 : hh < 0.7 ? C.stone : C.stone3);
      }
    }
    for (var b = 0; b < 26; b++) {
      var bx = 426 + Math.floor(hash(b, 1) * 42), by = 172 + Math.floor(hash(b, 2) * 46);
      if (by > 166 + Math.abs(bx - 447) * 1.1) { rect(c, bx, by, 7, 5, hash(b, 3) > 0.5 ? C.stone3 : C.stone); rect(c, bx, by, 7, 1, C.stone5); rect(c, bx, by + 4, 7, 1, C.stone9); }
    }
    for (var th = 0; th < 5; th++) line(c, 428 + th * 9, 200 + (th % 2) * 6, 424 + th * 10, 188 - (th % 3) * 4, C.void);
    // земля
    rect(c, 0, GY, W, H - GY, C.brown);
    for (var gx2 = 0; gx2 < W; gx2++) {
      if (hash(gx2, 1) > 0.35) rect(c, gx2, GY - 1, 1, 1 + (hash(gx2, 2) > 0.7 ? 1 : 0), C.green3);
      rect(c, gx2, GY, 1, 1, C.brown3);
      for (var gy2 = GY + 2; gy2 < H; gy2++) {
        var hv = hash(gx2, gy2);
        if (hv < 0.12) rect(c, gx2, gy2, 1, 1, C.brown9);
        else if (hv > 0.94) rect(c, gx2, gy2, 1, 1, C.brown3);
      }
    }
    for (var sx = 0; sx < W; sx += 14) {
      var sw = 8 + Math.floor(hash(sx, 3) * 8), sy = GY + 8 + Math.floor(hash(sx, 4) * 24);
      if (hash(sx, 5) > 0.35) { rect(c, sx, sy, sw, 5, hash(sx, 6) > 0.5 ? C.stone9 : C.stone); rect(c, sx, sy, sw, 1, C.stone3); }
    }
    for (var py = 0; py < 5; py++) for (var pxx = 0; pxx < 52; pxx++) {
      if (hash(pxx, py + 40) > 0.2 + py * 0.1) rect(c, 140 + pxx + py * 2, 228 + py, 1, 1, py === 0 ? C.steel : C.steel9);
    }
    rect(c, 174, 229, 1, 3, em(C.gold9));
    // бочки
    [[262, 206], [278, 210]].forEach(function (p, i) {
      var bw = i ? 16 : 14, bh = i ? 12 : 16;
      rect(c, p[0], p[1], bw, bh, C.brown3); rect(c, p[0], p[1] + 3, bw, 1, C.brown9); rect(c, p[0], p[1] + bh - 4, bw, 1, C.brown9);
      rect(c, p[0], p[1], bw, 1, C.brown); rect(c, p[0] + 3, p[1], 1, bh, C.brown);
    });
    if (o.hero !== false) drawSprite(c, SPR.hero, 118, GY - 23, false);
    if (o.enemy !== false) drawSprite(c, SPR.hollow, 206, GY - 21, true);
  }
  function villageLights(t) {
    var f = function (s, a, b) { return 1 + a * Math.sin(t * 1.9 + s) + b * Math.sin(t * 3.7 + s * 2); };
    return [
      { x: 171, y: 166, r: 92 * f(0, 0.05, 0.03), i: 0.95 },
      { x: 257, y: 166, r: 92 * f(2, 0.05, 0.03), i: 0.95 },
      { x: 66, y: 174, r: 46, i: 0.5 },
      { x: 126, y: 206, r: 48, i: 0.3, cool: true }, /* читаемость силуэта героя, AC-07.1 */
      { x: 250, y: 46, r: 130, i: 0.12, cool: true }
    ];
  }
  function villageOverlay(ctx, t) {
    [171, 257].forEach(function (x, i) { drawSprite(ctx, SPR['flame' + ((t + i) % 3)], x - 2, 158, false); });
  }

  function paintMenu(c) {
    sky(c, [C.void, C.night9, C.night, C.night3, C.night5], 0, 215);
    stars(c, 150, 90, 9);
    moon(c, 372, 64, 26);
    ridge(c, 190, 54, 0.4, '#171c29');
    ridge(c, 208, 40, 1.9, '#12161f');
    // замок на скале
    for (var x = 288; x < W; x++) {
      var h = 210 - Math.round((0.5 + 0.5 * Math.sin(x * 0.04)) * 8) - (x > 300 ? 0 : (300 - x));
      rect(c, x, h, 1, H - h, '#0d1018');
    }
    castle(c, 300, 214, [[0, 24, 70, 'flat'], [28, 30, 100, 'spire'], [62, 40, 60, 'flat'], [106, 26, 118, 'spire'], [136, 30, 74, 'flat']], '#0b0d14', C.gold);
    // туман (дизеринг)
    for (var y = 192; y < 246; y++) for (var xx = 0; xx < W; xx++) {
      var p = Math.max(0, 1 - Math.abs(y - 222) / 28) * 0.4;
      if (hash(xx >> 1, y >> 1) < p) rect(c, xx, y, 1, 1, em(hash(xx, y) > 0.5 ? C.steel9 : C.night5));
    }
    // передний план: скала с героем
    for (var fx = 0; fx < 330; fx++) {
      var fy = 236 - Math.round(Math.max(0, 22 - Math.abs(fx - 252) * 0.5));
      rect(c, fx, fy, 1, H - fy, '#07080b');
    }
    drawSprite(c, SPR.hero, 244, 236 - 22 - 23 + 1, false);
    // мёртвое дерево
    var tx = 40;
    rect(c, tx, 150, 4, 120, '#07080b');
    line(c, tx + 2, 156, tx - 24, 128, '#07080b'); line(c, tx + 2, 170, tx + 26, 140, '#07080b');
    line(c, tx - 24, 128, tx - 30, 108, '#07080b'); line(c, tx + 26, 140, tx + 30, 112, '#07080b');
    line(c, tx - 12, 142, tx - 36, 150, '#07080b'); line(c, tx + 14, 154, tx + 40, 160, '#07080b');
    line(c, tx + 2, 150, tx + 2, 120, '#07080b'); line(c, tx + 2, 138, tx + 10, 118, '#07080b');
  }
  function menuLights(t) {
    return [{ x: 372, y: 64, r: 200, i: 0.28, cool: true }, { x: 330, y: 170, r: 70 + Math.sin(t) * 2, i: 0.35 }];
  }

  function paintCamp(c) {
    rect(c, 0, 0, W, H, C.night9);
    bricks(c, 0, 0, W, 156, WALL_D);
    [88, 392].forEach(function (cx) {
      pointedFill(c, cx, 22, 128, 28, '#5c5c62');
      pointedFill(c, cx, 28, 124, 22, em(C.night3));
      rect(c, cx - 22, 70, 44, 54, em(C.night3));
      pointedFill(c, cx, 28, 124, 22, em(C.night3));
      for (var i = 0; i < 24; i++) rect(c, cx - 20 + Math.floor(hash(i, cx) * 40), 40 + Math.floor(hash(cx, i) * 80), 1, 1, em(C.steel3));
      rect(c, cx - 1, 40, 2, 84, '#5c5c62'); rect(c, cx - 22, 78, 44, 2, '#5c5c62'); rect(c, cx - 22, 104, 44, 2, '#5c5c62');
      rect(c, cx - 26, 124, 52, 4, C.stone3);
    });
    // колонны
    [[0, 26], [454, 26]].forEach(function (p) {
      rect(c, p[0], 0, p[1], 156, '#3d3d43'); rect(c, p[0] + (p[0] ? 0 : 22), 0, 4, 156, '#2b2b30');
      rect(c, p[0] - 2 + (p[0] ? 0 : 0), 140, p[1] + 2, 16, '#4a4a4f');
    });
    // пол
    rect(c, 0, 156, W, H - 156, C.brown);
    for (var y = 156, rowH = 8, r = 0; y < H; y += rowH, rowH += 2, r++) {
      for (var x = -(r * 13 % 48); x < W; x += 40 + r * 4) {
        var t = hash(x, y);
        rect(c, x + 1, y + 1, 38 + r * 4, rowH - 1, t > 0.6 ? '#3f3a32' : t > 0.3 ? C.stone9 : '#38342d');
        rect(c, x + 1, y + 1, 38 + r * 4, 1, '#55524a');
      }
    }
    rect(c, 0, 154, W, 3, C.stone3);
    // костровище
    for (var s = 0; s < 9; s++) { rect(c, 214 + s * 4, 154 + (s % 2), 5, 4, s % 2 ? C.stone : C.stone3); }
    drawSprite(c, SPR.logs, 226, 148, false);
    // реквизит
    rect(c, 330, 140, 22, 16, C.brown3); rect(c, 330, 140, 22, 2, C.brown9); rect(c, 330, 148, 22, 1, C.brown9); rect(c, 339, 140, 1, 16, C.brown9);
    rect(c, 340, 148, 16, 8, '#4a3d2f'); rect(c, 340, 148, 16, 1, C.brown3);
    drawSprite(c, SPR.hero, 176, 156 - 23 + 1, false);
    drawSprite(c, SPR.keeper, 262, 156 - 22 + 1, true);
  }
  function campLights(t) {
    var j = 1 + 0.07 * Math.sin(t * 2.3) + 0.05 * Math.sin(t * 4.1);
    return [{ x: 234, y: 140, r: 175 * j, i: 1.15 }, { x: 88, y: 122, r: 120, i: 0.22, cool: true }, { x: 392, y: 122, r: 120, i: 0.22, cool: true }];
  }
  function campOverlay(ctx, t) { drawSprite(ctx, SPR['fire' + (t % 3)], 229, 138, false); }

  /* ---------- Рендер: свет, дизеринг, виньетка ---------- */
  function lightPass(src, out, lights, amb, steps, vig, desat) {
    var s = src.data, o = out.data;
    for (var y = 0; y < H; y++) {
      for (var x = 0; x < W; x++) {
        var i = (y * W + x) * 4, r = s[i], g = s[i + 1], b = s[i + 2];
        if (s[i + 3] < 255) { o[i] = r; o[i + 1] = g; o[i + 2] = b; o[i + 3] = 255; continue; }
        var f = amb, warm = 0;
        for (var k = 0; k < lights.length; k++) {
          var L = lights[k], dx = x - L.x, dy = (y - L.y) * 1.15, d = Math.sqrt(dx * dx + dy * dy);
          if (d < L.r) { var t = 1 - d / L.r, v = L.i * t * t; f += v; if (!L.cool) warm += v; }
        }
        if (vig) { var nx = (x - W / 2) / (W / 2), ny = (y - H / 2) / (H / 2); f -= vig * (nx * nx + ny * ny) * 0.5; }
        var q = Math.floor(f * steps + (BAYER[y & 3][x & 3] + 0.5) / 16) / steps;
        q = q < 0.06 ? 0.06 : q > 1.15 ? 1.15 : q;
        var w = Math.min(0.5, warm);
        r = r * (1 + 0.45 * w); g = g * (1 + 0.12 * w); b = b * (1 - 0.35 * w);
        if (desat) { var l = 0.3 * r + 0.59 * g + 0.11 * b; r += (l - r) * desat; g += (l - g) * desat; b += (l - b) * desat; }
        r *= q; g *= q; b *= q;
        o[i] = r > 255 ? 255 : r; o[i + 1] = g > 255 ? 255 : g; o[i + 2] = b > 255 ? 255 : b; o[i + 3] = 255;
      }
    }
  }

  function runScene(canvas, spec) {
    canvas.width = W; canvas.height = H;
    var ctx = canvas.getContext('2d'); ctx.imageSmoothingEnabled = false;
    var base = document.createElement('canvas'); base.width = W; base.height = H;
    var bc = base.getContext('2d'); bc.imageSmoothingEnabled = false;
    spec.paint(bc);
    var src = bc.getImageData(0, 0, W, H), out = ctx.createImageData(W, H), t = 0, timer = null;
    function frame() {
      lightPass(src, out, spec.lights(t), spec.amb, spec.steps || 6, spec.vig || 0, spec.desat || 0);
      ctx.putImageData(out, 0, 0);
      if (spec.overlay) spec.overlay(ctx, t);
    }
    function start() { if (!timer) timer = setInterval(function () { t++; frame(); }, 140); }
    function stop() { if (timer) { clearInterval(timer); timer = null; } }
    frame();
    var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)');
    if (!(reduce && reduce.matches) && spec.animate !== false) start();
    document.addEventListener('visibilitychange', function () { if (document.hidden) stop(); else if (!(reduce && reduce.matches) && spec.animate !== false) start(); });
    return { redraw: frame };
  }

  var SCENES = {
    village: { paint: function (c) { paintVillage(c); }, lights: villageLights, overlay: villageOverlay, amb: 0.5, steps: 6, vig: 0.55 },
    villageEmpty: { paint: function (c) { paintVillage(c, { hero: false, enemy: false }); }, lights: villageLights, overlay: villageOverlay, amb: 0.36, steps: 6, vig: 0.8, desat: 0.5 },
    menu: { paint: paintMenu, lights: menuLights, amb: 0.78, steps: 8, vig: 0.6 },
    camp: { paint: paintCamp, lights: campLights, overlay: campOverlay, amb: 0.36, steps: 7, vig: 0.7 }
  };
  function mountScenes() {
    document.querySelectorAll('canvas[data-scene]').forEach(function (cv) {
      var spec = SCENES[cv.dataset.scene]; if (!spec) return;
      if (cv.dataset.static === '1') spec = Object.assign({}, spec, { animate: false });
      runScene(cv, spec);
    });
  }

  /* ---------- Мини-карта ---------- */
  var MAP = [
    '............',
    '...##..#G...',
    '..###.###?..',
    '..#F###@##..',
    '.###.#.#.#..',
    '.#G#F#.#....',
    '.#..###.....',
    '....#.#.....',
    '............'
  ];
  function drawMinimap(cv, blink) {
    var ctx = cv.getContext('2d'); ctx.imageSmoothingEnabled = false;
    cv.width = 96; cv.height = 54;
    ctx.clearRect(0, 0, 96, 54);
    MAP.forEach(function (row, j) {
      for (var i = 0; i < row.length; i++) {
        var ch = row.charAt(i), x = i * 8, y = j * 6;
        if (ch === '.') continue;
        if (ch === '?') { rect(ctx, x, y, 7, 5, C.night); rect(ctx, x + 1, y + 1, 5, 3, C.void); continue; }
        rect(ctx, x, y, 7, 5, ch === '@' ? C.gold : C.steel);
        rect(ctx, x + 1, y + 1, 5, 3, ch === '@' ? (blink ? C.gold3 : C.gold) : C.steel9);
        if (ch === 'F') rect(ctx, x + 2, y + 1, 3, 3, C.gold3);
        if (ch === 'G') { rect(ctx, x + 1, y + 1, 5, 3, C.void); rect(ctx, x + 2, y + 1, 3, 3, C.steel3); rect(ctx, x + 3, y + 2, 1, 1, C.void); }
      }
    });
  }
  function mountMinimaps() {
    document.querySelectorAll('canvas[data-minimap]').forEach(function (cv) {
      var b = false; drawMinimap(cv, b);
      var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
      if (!reduce) setInterval(function () { b = !b; drawMinimap(cv, b); }, 600);
    });
  }

  /* ---------- Целочисленное масштабирование (stretch: viewport / integer) ---------- */
  function fit() {
    var chrome = document.querySelectorAll('header.chrome'), used = 0;
    chrome.forEach(function (e) { used += e.offsetHeight; });
    var s = Math.max(1, Math.floor(Math.min(window.innerWidth / W, (window.innerHeight - used - (document.documentElement.classList.contains('embed') ? 0 : 8)) / H)));
    document.documentElement.style.setProperty('--s', s);
    var tag = document.getElementById('scale-tag'); if (tag) tag.textContent = '×' + s + ' (' + W * s + '×' + H * s + ')';
  }
  window.addEventListener('resize', fit);

  /* ---------- Переключатель состояний (для страниц с data-state) ---------- */
  function mountStateSwitch() {
    var stage = document.getElementById('stage'), btns = document.querySelectorAll('[data-set-state]');
    if (!stage || !btns.length) return;
    function set(v) {
      stage.dataset.state = v;
      btns.forEach(function (b) { b.setAttribute('aria-pressed', String(b.dataset.setState === v)); });
      stage.dispatchEvent(new CustomEvent('statechange', { detail: v }));
    }
    btns.forEach(function (b) { b.addEventListener('click', function () { set(b.dataset.setState); }); });
    var q = new URLSearchParams(location.search).get('state');
    set(q || btns[0].dataset.setState);
  }

  function init() {
    var qs = new URLSearchParams(location.search);
    if (qs.get('embed') === '1') document.documentElement.classList.add('embed');
    if (qs.get('still') === '1' || qs.get('embed') === '1') document.documentElement.classList.add('still');
    mountSprites(); mountScenes(); mountMinimaps(); mountStateSwitch(); fit(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
  window.PX = { C: C, SPR: SPR, mountSprites: mountSprites, fit: fit };
})();
