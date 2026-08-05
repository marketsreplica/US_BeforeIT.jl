/* iso.js — isometric tile math + low-level canvas paint helpers.
   Pure geometry & color: no app or economic state lives here.
   Projection: classic 2:1 dimetric. grid (gx,gy) -> world px:
     x = (gx - gy) * TW2 ; y = (gx + gy) * TH2
   Screen-down is +gx+gy, so painter's order = ascending (gx+gy). */
window.Iso = (function () {
  'use strict';

  var TILE_W = 44, TILE_H = 22;
  var TW2 = TILE_W / 2, TH2 = TILE_H / 2;

  function wx(gx, gy) { return (gx - gy) * TW2; }
  function wy(gx, gy) { return (gx + gy) * TH2; }

  /* Path a flat diamond covering tile-rect [gx..gx+w] x [gy..gy+h] (world px).
     dy: optional vertical offset (used for raised slabs). */
  function diamond(ctx, gx, gy, w, h, dy) {
    dy = dy || 0;
    ctx.beginPath();
    ctx.moveTo(wx(gx, gy), wy(gx, gy) + dy);
    ctx.lineTo(wx(gx + w, gy), wy(gx + w, gy) + dy);
    ctx.lineTo(wx(gx + w, gy + h), wy(gx + w, gy + h) + dy);
    ctx.lineTo(wx(gx, gy + h), wy(gx, gy + h) + dy);
    ctx.closePath();
  }

  /* ---------- color helpers ---------- */
  function hexRgb(hex) {
    var h = hex.replace('#', '');
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    var n = parseInt(h, 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  function rgbCss(c) { return 'rgb(' + (c[0] | 0) + ',' + (c[1] | 0) + ',' + (c[2] | 0) + ')'; }
  function rgba(hex, a) {
    var c = hexRgb(hex);
    return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')';
  }
  /* mix two hex colors, t in [0,1] toward b */
  function mix(a, b, t) {
    var ca = hexRgb(a), cb = hexRgb(b);
    return rgbCss([ca[0] + (cb[0] - ca[0]) * t, ca[1] + (cb[1] - ca[1]) * t, ca[2] + (cb[2] - ca[2]) * t]);
  }
  /* lighten (f>0) / darken (f<0) */
  function shade(hex, f) {
    var c = hexRgb(hex), t = f > 0 ? 255 : 0, p = Math.abs(f);
    return rgbCss([c[0] + (t - c[0]) * p, c[1] + (t - c[1]) * p, c[2] + (t - c[2]) * p]);
  }

  /* ---------- box: extruded tile-rect, the universal building primitive ----------
     Fills SW face, SE face, then top. colors: {left,right,top} css strings.
     Returns projected base corners {n,e,s,w} (each [x,y]) for window placement. */
  function box(ctx, gx, gy, fw, fh, hpx, colors) {
    var nX = wx(gx, gy), nY = wy(gx, gy);
    var eX = wx(gx + fw, gy), eY = wy(gx + fw, gy);
    var sX = wx(gx + fw, gy + fh), sY = wy(gx + fw, gy + fh);
    var wX = wx(gx, gy + fh), wYv = wy(gx, gy + fh);
    // SW (left) face
    ctx.fillStyle = colors.left;
    ctx.beginPath();
    ctx.moveTo(wX, wYv); ctx.lineTo(sX, sY); ctx.lineTo(sX, sY - hpx); ctx.lineTo(wX, wYv - hpx);
    ctx.closePath(); ctx.fill();
    // SE (right) face
    ctx.fillStyle = colors.right;
    ctx.beginPath();
    ctx.moveTo(sX, sY); ctx.lineTo(eX, eY); ctx.lineTo(eX, eY - hpx); ctx.lineTo(sX, sY - hpx);
    ctx.closePath(); ctx.fill();
    // top
    ctx.fillStyle = colors.top;
    ctx.beginPath();
    ctx.moveTo(nX, nY - hpx); ctx.lineTo(eX, eY - hpx); ctx.lineTo(sX, sY - hpx); ctx.lineTo(wX, wYv - hpx);
    ctx.closePath(); ctx.fill();
    return { n: [nX, nY], e: [eX, eY], s: [sX, sY], w: [wX, wYv] };
  }

  /* Ghost wireframe of a box: top diamond at height + the three visible
     vertical edges. Caller sets strokeStyle/lineWidth. */
  function boxGhost(ctx, gx, gy, fw, fh, hpx) {
    var nX = wx(gx, gy), nY = wy(gx, gy);
    var eX = wx(gx + fw, gy), eY = wy(gx + fw, gy);
    var sX = wx(gx + fw, gy + fh), sY = wy(gx + fw, gy + fh);
    var wX = wx(gx, gy + fh), wYv = wy(gx, gy + fh);
    ctx.beginPath();
    ctx.moveTo(nX, nY - hpx); ctx.lineTo(eX, eY - hpx); ctx.lineTo(sX, sY - hpx);
    ctx.lineTo(wX, wYv - hpx); ctx.closePath();
    ctx.moveTo(wX, wYv); ctx.lineTo(wX, wYv - hpx);
    ctx.moveTo(sX, sY); ctx.lineTo(sX, sY - hpx);
    ctx.moveTo(eX, eY); ctx.lineTo(eX, eY - hpx);
    ctx.stroke();
  }

  /* Emit lit-window quads for one building face into the CURRENT path.
     p0,p1 = bottom corners of the face (ground level), hpx = face height.
     isLit(col,row,cols,rows) decides which windows glow. */
  function faceWindows(ctx, p0, p1, hpx, isLit) {
    var dx = p1[0] - p0[0], dy = p1[1] - p0[1];
    var len = Math.sqrt(dx * dx + dy * dy);
    if (len < 7 || hpx < 12) return;
    var cols = Math.max(1, Math.floor(len / 8));
    var rows = Math.max(1, Math.floor((hpx - 8) / 10));
    var ux = dx / len, uy = dy / len;
    var ww = 2.8, wh = 4.4;                       // window quad size (world px)
    for (var r = 0; r < rows; r++) {
      var yOff = -(hpx - 7 - r * 10);            // from the top of the face down
      for (var c = 0; c < cols; c++) {
        if (!isLit(c, r, cols, rows)) continue;
        var u = (c + 0.5) / cols * len;
        var bx = p0[0] + ux * u - ux * ww / 2;
        var by = p0[1] + uy * u - uy * ww / 2 + yOff;
        ctx.moveTo(bx, by);
        ctx.lineTo(bx + ux * ww, by + uy * ww);
        ctx.lineTo(bx + ux * ww, by + uy * ww + wh);
        ctx.lineTo(bx, by + wh);
        ctx.closePath();
      }
    }
  }

  return {
    TILE_W: TILE_W, TILE_H: TILE_H, TW2: TW2, TH2: TH2,
    wx: wx, wy: wy, diamond: diamond,
    box: box, boxGhost: boxGhost, faceWindows: faceWindows,
    hexRgb: hexRgb, rgba: rgba, mix: mix, shade: shade
  };
})();
