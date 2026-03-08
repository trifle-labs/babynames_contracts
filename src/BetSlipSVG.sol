// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Base64.sol";
import "./BetSlipLogo.sol";
import "./interfaces/IBetSlipRenderer.sol";

/**
 * @title BetSlipSVG
 * @notice Deployed contract for generating onchain SVG art for Baby Name Market bet slip NFTs.
 *         Produces a 400×491 receipt-style slip matching the slip-generator reference.
 *         Deployed separately to avoid EIP-170 contract size limits on BabyNameMarket.
 */
contract BetSlipSVG is IBetSlipRenderer {

    BetSlipLogo public immutable logo;

    constructor(address _logo) {
        logo = BetSlipLogo(_logo);
    }

    // ── Status constants ────────────────────────────────────────────────
    uint8 internal constant STATUS_ACTIVE  = 0;
    uint8 internal constant STATUS_CLOSED  = 1;
    uint8 internal constant STATUS_WON     = 2;
    uint8 internal constant STATUS_LOST    = 3;

    uint8 internal constant GENDER_FEMALE  = 0;
    uint8 internal constant GENDER_MALE    = 1;

    uint8 internal constant CAT_SINGLE     = 0;
    uint8 internal constant CAT_EXACTA     = 1;
    uint8 internal constant CAT_TRIFECTA   = 2;
    uint8 internal constant CAT_TOP_N      = 3;

    // ── Layout constants ────────────────────────────────────────────────
    // W=400, M=24, LOGO_H=105, H=491
    // All Y-positions hard-coded from the JS reference layout.

    // ════════════════════════════════════════════════════════════════════
    //  Entry point
    // ════════════════════════════════════════════════════════════════════

    function renderTokenURI(SlipData calldata d) external view override returns (string memory) {
        string memory svg    = _svg(d);
        string memory imgB64 = Base64.encode(bytes(svg));

        string memory json = string.concat(
            '{"name":"Bet Slip #',
            _zeroPad8(d.tokenId),
            '","description":"Baby Name Market prediction slip","image":"data:image/svg+xml;base64,',
            imgB64,
            '","attributes":',
            _attributes(d),
            "}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    // ════════════════════════════════════════════════════════════════════
    //  SVG root — split into small helpers to stay under stack limit
    // ════════════════════════════════════════════════════════════════════

    function _svg(SlipData memory d) private view returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="491" viewBox="0 0 400 491">',
            _defs(),
            _background(),
            _logo(),
            _contentGroup(d),
            _creases(d.tokenId),
            "</svg>"
        );
    }

    // ── Defs ────────────────────────────────────────────────────────────

    function _defs() private pure returns (string memory) {
        return string.concat(
            "<defs>",
            _paperLightFilter(),
            _contentWarpFilter(),
            _vignetteGradient(),
            _creaseBlurFilter(),
            "</defs>"
        );
    }

    function _paperLightFilter() private pure returns (string memory) {
        return string.concat(
            '<filter id="paperLight" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">',
            '<feTurbulence type="fractalNoise" baseFrequency="0.008 0.0112" numOctaves="3" seed="7" stitchTiles="stitch" result="wrinkleNoise"/>',
            '<feDiffuseLighting in="wrinkleNoise" surfaceScale="3" diffuseConstant="0.85" lighting-color="#ffffff" result="wrinkleLit">',
            '<feDistantLight azimuth="105" elevation="35"/>',
            "</feDiffuseLighting>",
            '<feBlend in="SourceGraphic" in2="wrinkleLit" mode="overlay" result="warped"/>',
            '<feComponentTransfer in="warped">',
            '<feFuncR type="linear" slope="1" intercept="0"/>',
            '<feFuncG type="linear" slope="1" intercept="0"/>',
            '<feFuncB type="linear" slope="1" intercept="0"/>',
            "</feComponentTransfer>",
            "</filter>"
        );
    }

    function _contentWarpFilter() private pure returns (string memory) {
        return string.concat(
            '<filter id="contentWarp" x="-1%" y="-1%" width="102%" height="102%">',
            '<feTurbulence type="fractalNoise" baseFrequency="0.008 0.0112" numOctaves="3" seed="7" stitchTiles="stitch" result="wn"/>',
            '<feDisplacementMap in="SourceGraphic" in2="wn" scale="0" xChannelSelector="R" yChannelSelector="G"/>',
            "</filter>"
        );
    }

    function _vignetteGradient() private pure returns (string memory) {
        return string.concat(
            '<radialGradient id="vign" cx="50%" cy="48%" r="68%">',
            '<stop offset="0%" stop-color="#ffffff" stop-opacity="0"/>',
            '<stop offset="100%" stop-color="#888888" stop-opacity="0.12"/>',
            "</radialGradient>"
        );
    }

    function _creaseBlurFilter() private pure returns (string memory) {
        return '<filter id="cf"><feGaussianBlur stdDeviation="1.4"/></filter>';
    }

    // ── Background (3 rects) ────────────────────────────────────────────

    function _background() private pure returns (string memory) {
        return string.concat(
            '<rect width="400" height="491" fill="#ffffff"/>',
            '<rect width="400" height="491" fill="#ffffff" filter="url(#paperLight)"/>',
            '<rect width="400" height="491" fill="url(#vign)"/>'
        );
    }

    // ── Logo ────────────────────────────────────────────────────────────

    function _logo() private view returns (string memory) {
        return string.concat(
            '<svg x="0" y="0" width="400" height="105" viewBox="0 0 250 66" preserveAspectRatio="xMidYMid meet">',
            logo.paths(),
            "</svg>"
        );
    }

    // ── Content group (wrapped in contentWarp filter) ───────────────────

    function _contentGroup(SlipData memory d) private pure returns (string memory) {
        return string.concat(
            '<g filter="url(#contentWarp)">',
            _marketSection(d),
            _betSection(d),
            _payoutSection(d),
            _idSection(d.tokenId),
            _barcodeSection(d.tokenId),
            _matrixAndArrows(d.tokenId),
            "</g>"
        );
    }

    // ── MARKET section ──────────────────────────────────────────────────

    function _marketSection(SlipData memory d) private pure returns (string memory) {
        return string.concat(
            _marketLabel(d),
            _yearHeading(d),
            _resolvesLine(d),
            '<line x1="24" y1="188" x2="376" y2="188" stroke="#111" stroke-width="2.2"/>'
        );
    }

    function _marketLabel(SlipData memory d) private pure returns (string memory) {
        return string.concat(
            '<text x="24" y="127" font-family="Arial,sans-serif" font-size="12" font-weight="bold" fill="#111" letter-spacing="0.5">MARKET</text>',
            '<text x="376" y="127" text-anchor="end" font-family="Arial,sans-serif" font-size="12" fill="#111">',
            _formatDate(d.purchasedAt),
            "</text>"
        );
    }

    function _yearHeading(SlipData memory d) private pure returns (string memory) {
        return string.concat(
            '<text x="24" y="160" font-family="Arial,sans-serif" font-size="28" font-weight="900" fill="#111">',
            _uint2str(d.year),
            " Market</text>"
        );
    }

    function _resolvesLine(SlipData memory d) private pure returns (string memory) {
        return string.concat(
            '<text x="24" y="176" font-family="Arial,sans-serif" font-size="11" font-weight="700" fill="#555" letter-spacing="0.3">RESOLVES&#160;',
            _formatDeadline(d.deadline, d.year),
            "</text>"
        );
    }

    // ── BET section ─────────────────────────────────────────────────────

    function _betSection(SlipData memory d) private pure returns (string memory) {
        string memory cat = _formatCategory(d.categoryType, d.gender, d.position);
        string memory amt = _formatAmount(d.amount, d.tokenDecimals);
        return string.concat(
            _betAmountLine(amt, cat),
            _selectedNameLine(d.poolName),
            '<line x1="24" y1="244" x2="376" y2="244" stroke="#111" stroke-width="1.5"/>'
        );
    }

    function _betAmountLine(string memory amt, string memory cat) private pure returns (string memory) {
        return string.concat(
            '<text x="24" y="213" font-family="Arial,sans-serif" font-size="19" font-weight="900" fill="#111">',
            amt,
            " ",
            cat,
            "</text>",
            '<text x="376" y="213" text-anchor="end" font-family="Arial,sans-serif" font-size="19" font-weight="900" fill="#111">',
            amt,
            "</text>"
        );
    }

    function _selectedNameLine(string memory name) private pure returns (string memory) {
        return string.concat(
            '<text x="30" y="231" font-family="Arial,sans-serif" font-size="12" fill="#111">SELECTED NAME:&#160;<tspan font-weight="bold">',
            name,
            "</tspan></text>"
        );
    }

    // ── PAYOUT section ──────────────────────────────────────────────────

    function _payoutSection(SlipData memory d) private pure returns (string memory) {
        string memory payoutAmt = _computePayoutStr(d);
        return string.concat(
            _payoutAmountText(payoutAmt),
            _payoutLabelText(d.poolName),
            _payoutMetaText(d)
        );
    }

    function _payoutAmountText(string memory payoutAmt) private pure returns (string memory) {
        return string.concat(
            '<text x="24" y="277" font-family="Arial,sans-serif" font-size="26" font-weight="900" fill="#111">',
            payoutAmt,
            "</text>"
        );
    }

    function _payoutLabelText(string memory name) private pure returns (string memory) {
        return string.concat(
            '<text x="24" y="292" font-family="Arial,sans-serif" font-size="9.5" font-weight="700" fill="#555" letter-spacing="0.8">EST. PAYOUT IF ',
            name,
            " WINS</text>"
        );
    }

    function _payoutMetaText(SlipData memory d) private pure returns (string memory) {
        return string.concat(
            '<text x="24" y="309" font-family="Arial,sans-serif" font-size="9" fill="#888">AS OF ',
            _formatDate(d.currentTime),
            "&#160;&#160;&#183;&#160;&#160;&#8635; REFRESH METADATA FOR LATEST ODDS</text>"
        );
    }

    // ── Slip ID + barcode ───────────────────────────────────────────────

    function _idSection(uint256 tokenId) private pure returns (string memory) {
        return string.concat(
            '<text x="200" y="333" text-anchor="middle" font-family="Arial,sans-serif" font-size="15" letter-spacing="3" fill="#222">',
            _zeroPad8(tokenId),
            "</text>"
        );
    }

    function _barcodeSection(uint256 tokenId) private pure returns (string memory) {
        return _makeITFBarcode(tokenId);
    }

    // ── Binary matrix + arrows ──────────────────────────────────────────

    function _matrixAndArrows(uint256 tokenId) private pure returns (string memory) {
        return string.concat(
            _binaryMatrix(tokenId),
            _downArrows()
        );
    }

    // ════════════════════════════════════════════════════════════════════
    //  ITF Barcode
    // ════════════════════════════════════════════════════════════════════

    // Interleaved 2-of-5 patterns: 0=narrow, 1=wide
    // [NNWWN, WNNNW, NWNNW, WWNNN, NNWNW, WNWNN, NWWNN, NNNWW, WNNWN, NWNWN]

    function _itfPattern(uint8 digit) private pure returns (uint8[5] memory p) {
        if (digit == 0) return [0,0,1,1,0];
        if (digit == 1) return [1,0,0,0,1];
        if (digit == 2) return [0,1,0,0,1];
        if (digit == 3) return [1,1,0,0,0];
        if (digit == 4) return [0,0,1,0,1];
        if (digit == 5) return [1,0,1,0,0];
        if (digit == 6) return [0,1,1,0,0];
        if (digit == 7) return [0,0,0,1,1];
        if (digit == 8) return [1,0,0,1,0];
        return [0,1,0,1,0]; // 9
    }

    function _makeITFBarcode(uint256 tokenId) private pure returns (string memory) {
        uint8[8] memory digits = _tokenDigits(tokenId);

        // ITF_RATIO = 2.5, totalW = 352, barH = 52, x0 = 24, y0 = 347
        // totalUnits = 4 + 4*16 + (2.5+2) = 4 + 64 + 4.5 = 72.5
        // N = 352 / 72.5 ≈ 4.8552
        // We use fixed-point *1000 for precision
        uint256 totalW1000 = 352000;
        uint256 totalUnits1000 = 72500; // 72.5 * 1000
        uint256 n1000 = totalW1000 * 1000 / totalUnits1000; // N*1000
        uint256 w1000 = n1000 * 2500 / 1000; // W*1000 = N*2.5*1000

        // Build element array: each element is (width*1000, isBar)
        // Max elements: 4 (start) + 4*10 (pairs) + 3 (end) = 47
        uint256[47] memory widths;
        bool[47] memory isBars;
        uint256 idx;

        // Start guard: N-bar N-space N-bar N-space
        widths[0] = n1000; isBars[0] = true;
        widths[1] = n1000; isBars[1] = false;
        widths[2] = n1000; isBars[2] = true;
        widths[3] = n1000; isBars[3] = false;
        idx = 4;

        // 4 digit pairs
        for (uint256 p = 0; p < 4; p++) {
            uint8[5] memory p1 = _itfPattern(digits[p * 2]);
            uint8[5] memory p2 = _itfPattern(digits[p * 2 + 1]);
            for (uint256 i = 0; i < 5; i++) {
                widths[idx] = p1[i] == 1 ? w1000 : n1000;
                isBars[idx] = true;
                idx++;
                widths[idx] = p2[i] == 1 ? w1000 : n1000;
                isBars[idx] = false;
                idx++;
            }
        }

        // End guard: W-bar N-space N-bar
        widths[idx] = w1000; isBars[idx] = true; idx++;
        widths[idx] = n1000; isBars[idx] = false; idx++;
        widths[idx] = n1000; isBars[idx] = true; idx++;

        // Render bars
        return _renderBars(widths, isBars, idx);
    }

    function _renderBars(
        uint256[47] memory widths,
        bool[47] memory isBars,
        uint256 count
    ) private pure returns (string memory) {
        // x0 = 24, y0 = 347, barH = 52
        // Use fixed point: cx * 1000
        uint256 cx1000 = 24000;
        string memory svg;

        for (uint256 i = 0; i < count; i++) {
            if (isBars[i]) {
                svg = string.concat(
                    svg,
                    '<rect x="',
                    _fixedStr(cx1000, 3, 2),
                    '" y="347" width="',
                    _fixedStr(widths[i], 3, 2),
                    '" height="52" fill="#111"/>'
                );
            }
            cx1000 += widths[i];
        }
        return svg;
    }

    function _tokenDigits(uint256 tokenId) private pure returns (uint8[8] memory digits) {
        uint256 n = tokenId;
        // fill right to left
        for (uint256 i = 8; i > 0; i--) {
            digits[i - 1] = uint8(n % 10);
            n /= 10;
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  Binary matrix: 20 cols × 6 rows = 120 bits
    // ════════════════════════════════════════════════════════════════════

    function _binaryMatrix(uint256 tokenId) private pure returns (string memory) {
        // yHorizTop = 347 + 52 + 14 = 413
        // COLS=20, ROWS=6, DASH_W=9, GAP_W=5, COL_W=14
        // x0 = (400 - (20*14 - 5))/2 = (400 - 275)/2 = 62 (rounded)
        uint256 x0 = 62;
        uint256 yTop = 413;

        string memory svg;
        for (uint256 col = 0; col < 20; col++) {
            for (uint256 row = 0; row < 6; row++) {
                uint256 bitIdx = col * 6 + row;
                // bit 0 is MSB (col0,row0), bit 119 is LSB
                if (_getBit(tokenId, 119 - bitIdx)) {
                    uint256 rx = x0 + col * 14;
                    uint256 ry = yTop + row * 7; // ROW_H(3) + ROW_GAP(4) = 7
                    svg = string.concat(
                        svg,
                        '<rect x="', _uint2str(rx),
                        '" y="', _uint2str(ry),
                        '" width="9" height="3" fill="#111"/>'
                    );
                }
            }
        }
        return svg;
    }

    function _getBit(uint256 val, uint256 bitPos) private pure returns (bool) {
        return (val >> bitPos) & 1 == 1;
    }

    // ════════════════════════════════════════════════════════════════════
    //  Down arrows
    // ════════════════════════════════════════════════════════════════════

    function _downArrows() private pure returns (string memory) {
        // arrowStemTop = 413 + 38 + 6 = 457, arrowBaseY = 467, arrowTipY = 481
        // lCX=38, rCX=362, stemW=8, stemH=10, arrowHW=10
        return string.concat(
            // Left arrow stem + triangle
            '<rect x="34" y="457" width="8" height="10" fill="#111"/>',
            '<polygon points="28,467 48,467 38,481" fill="#111"/>',
            // Right arrow stem + triangle
            '<rect x="358" y="457" width="8" height="10" fill="#111"/>',
            '<polygon points="352,467 372,467 362,481" fill="#111"/>'
        );
    }

    // ════════════════════════════════════════════════════════════════════
    //  Creases — seeded PRNG, 4 creases
    // ════════════════════════════════════════════════════════════════════

    function _creases(uint256 tokenId) private pure returns (string memory) {
        uint256 seed = (tokenId == 0 ? uint256(1) : tokenId) * 0x9e3779b9;
        // Truncate to 32 bits for xorshift
        uint32 s = uint32(seed);

        string memory svg;
        for (uint256 i = 0; i < 4; i++) {
            (svg, s) = _oneCrease(svg, s);
        }
        return svg;
    }

    function _oneCrease(string memory prev, uint32 s) private pure returns (string memory, uint32) {
        // rnd() returns 0..0xffffffff, we use /0xffffffff for [0,1]
        uint256 r1; uint256 r2; uint256 r3; uint256 r4; uint256 r5;
        (s, r1) = _rnd(s);
        (s, r2) = _rnd(s);
        (s, r3) = _rnd(s);
        (s, r4) = _rnd(s);
        (s, r5) = _rnd(s);

        // px = W*(0.5 + (r1-0.5)*spread*2) where spread=0.45
        // = 400*(0.5 + (r1-0.5)*0.9)
        // = 200 + 400*0.9*(r1-0.5) = 200 + 360*(r1-0.5)
        int256 px = 200 + int256(r1 * 360 / 0xffffffff) - 180;
        int256 py = 245 + int256(r2 * 441 / 0xffffffff) - 220; // H=491, same formula

        // angle: baseAngle = r3>0.5 ? 0 : 90, jitter = (r4-0.5)*50
        int256 baseAngle = r3 > 0x7fffffff ? int256(0) : int256(90);
        int256 angle = baseAngle + int256(r4 * 50 / 0xffffffff) - 25;

        // opacity: (0.4 + r5*0.4/max) * 0.6
        uint256 opRaw = (400 + r5 * 400 / 0xffffffff);
        uint256 opacity1000 = opRaw * 600 / 1000; // *0.6
        uint256 opacity2_1000 = opacity1000 * 750 / 1000; // *0.75

        // stroke width: 1.5 * (0.8 + r5*0.4/max) — reuse r5
        uint256 sw1000 = 1500 * (800 + r5 * 400 / 0xffffffff) / 1000;

        // Compute line endpoints extending through (px,py) at angle
        // We'll use simplified approach: extend by 600px in each direction
        (int256 x1, int256 y1, int256 x2, int256 y2) = _lineThruPoint(px, py, angle);

        // Perpendicular offset for highlight (~2px)
        // ox = -sin(angle)*2, oy = cos(angle)*2
        // Approximate: for small angles near 0 or 90
        (int256 ox, int256 oy) = _perpOffset(angle);

        string memory result = string.concat(
            prev,
            _creaseShadowLine(x1, y1, x2, y2, sw1000, opacity1000),
            _creaseHighlightLine(x1 + ox, y1 + oy, x2 + ox, y2 + oy, sw1000 * 650 / 1000, opacity2_1000)
        );
        return (result, s);
    }

    function _creaseShadowLine(
        int256 x1, int256 y1, int256 x2, int256 y2,
        uint256 sw1000, uint256 op1000
    ) private pure returns (string memory) {
        return string.concat(
            '<line x1="', _int2str(x1), '" y1="', _int2str(y1),
            '" x2="', _int2str(x2), '" y2="', _int2str(y2),
            '" stroke="#444" stroke-width="', _fixedStr(sw1000, 3, 1),
            '" opacity="', _fixedStr(op1000, 3, 3),
            '" filter="url(#cf)"/>'
        );
    }

    function _creaseHighlightLine(
        int256 x1, int256 y1, int256 x2, int256 y2,
        uint256 sw1000, uint256 op1000
    ) private pure returns (string memory) {
        return string.concat(
            '<line x1="', _int2str(x1), '" y1="', _int2str(y1),
            '" x2="', _int2str(x2), '" y2="', _int2str(y2),
            '" stroke="#ffffff" stroke-width="', _fixedStr(sw1000, 3, 1),
            '" opacity="', _fixedStr(op1000, 3, 3),
            '" filter="url(#cf)"/>'
        );
    }

    function _rnd(uint32 s) private pure returns (uint32, uint256) {
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        return (s, uint256(s));
    }

    /**
     * @dev Extend a line through (px,py) at `angle` degrees to edges of a 400×491 box.
     *      Uses a lookup table for sin/cos at integer degrees. Simplified: extends ±600px.
     */
    function _lineThruPoint(int256 px, int256 py, int256 angle) private pure returns (int256, int256, int256, int256) {
        // cos and sin * 1000
        (int256 cs, int256 sn) = _cosSin(angle);
        int256 ext = 600;
        int256 x1 = px - cs * ext / 1000;
        int256 y1 = py - sn * ext / 1000;
        int256 x2 = px + cs * ext / 1000;
        int256 y2 = py + sn * ext / 1000;
        return (x1, y1, x2, y2);
    }

    function _perpOffset(int256 angle) private pure returns (int256 ox, int256 oy) {
        (int256 cs, int256 sn) = _cosSin(angle);
        ox = -sn * 2 / 1000;
        oy = cs * 2 / 1000;
    }

    /**
     * @dev Returns (cos*1000, sin*1000) for common crease angles.
     *      Creases are biased toward 0° or 90° ±25°, so we cover that range.
     */
    function _cosSin(int256 deg) private pure returns (int256 cs, int256 sn) {
        // Normalize to 0-360
        int256 d = deg % 360;
        if (d < 0) d += 360;

        // Use quadrant reduction and a small lookup
        // For simplicity, approximate with linear interpolation at key points
        // We only need rough values for visual crease lines
        if (d <= 90) {
            (cs, sn) = _cosSinQ1(d);
        } else if (d <= 180) {
            (int256 c, int256 s) = _cosSinQ1(180 - d);
            cs = -c;
            sn = s;
        } else if (d <= 270) {
            (int256 c, int256 s) = _cosSinQ1(d - 180);
            cs = -c;
            sn = -s;
        } else {
            (int256 c, int256 s) = _cosSinQ1(360 - d);
            cs = c;
            sn = -s;
        }
    }

    function _cosSinQ1(int256 deg) private pure returns (int256 cs, int256 sn) {
        // First quadrant cos/sin * 1000 for key angles
        if (deg <= 5)  return (int256(1000), deg * 87 / 5);   // cos≈1, sin≈deg*0.0174
        if (deg <= 15) return (int256(966), int256(259));
        if (deg <= 25) return (int256(906), int256(423));
        if (deg <= 35) return (int256(819), int256(574));
        if (deg <= 45) return (int256(707), int256(707));
        if (deg <= 55) return (int256(574), int256(819));
        if (deg <= 65) return (int256(423), int256(906));
        if (deg <= 75) return (int256(259), int256(966));
        if (deg <= 85) return (int256(87),  int256(996));
        return (int256(0), int256(1000)); // 90
    }

    // ════════════════════════════════════════════════════════════════════
    //  Formatting helpers
    // ════════════════════════════════════════════════════════════════════

    function _formatAmount(uint256 normalized, uint8 decimals) private pure returns (string memory) {
        uint256 scaleFactor = 10 ** (18 - decimals);
        uint256 native = normalized / scaleFactor;
        uint256 whole  = native / (10 ** decimals);
        uint256 frac   = native % (10 ** decimals);
        uint256 fracScaled = frac * 100 / (10 ** decimals);
        string memory fracStr = fracScaled < 10
            ? string.concat("0", _uint2str(fracScaled))
            : _uint2str(fracScaled);
        return string.concat("$", _uint2str(whole), ".", fracStr);
    }

    function _computePayoutStr(SlipData memory d) private pure returns (string memory) {
        if (d.poolCollateral == 0) return "$0.00";
        // payout = amount * multiplier where multiplier = catCollateral * 0.9 / poolCollateral
        // payout = amount * catCollateral * 90 / (poolCollateral * 100)
        // In native decimals:
        uint256 scaleFactor = 10 ** (18 - d.tokenDecimals);
        uint256 amountNative = d.amount / scaleFactor;
        uint256 catNative = d.categoryCollateral / scaleFactor;

        // payout in native = amountNative * catNative * 90 / (poolCollateralNative * 100)
        uint256 poolNative = d.poolCollateral / scaleFactor;
        if (poolNative == 0) return "$0.00";
        uint256 payoutNative = amountNative * catNative * 90 / (poolNative * 100);

        uint256 whole = payoutNative / (10 ** d.tokenDecimals);
        uint256 frac  = payoutNative % (10 ** d.tokenDecimals);
        uint256 fracScaled = frac * 100 / (10 ** d.tokenDecimals);
        string memory fracStr = fracScaled < 10
            ? string.concat("0", _uint2str(fracScaled))
            : _uint2str(fracScaled);
        return string.concat("$", _uint2str(whole), ".", fracStr);
    }

    function _formatCategory(uint8 catType, uint8 gender, uint256 position) private pure returns (string memory) {
        string memory g = gender == GENDER_FEMALE ? "GIRL" : "BOY";
        if (catType == CAT_SINGLE) {
            return string.concat(g, " #", _uint2str(position));
        } else if (catType == CAT_EXACTA) {
            return string.concat(g, " EXACTA");
        } else if (catType == CAT_TRIFECTA) {
            return string.concat(g, " TRIFECTA");
        } else {
            return string.concat(g, " TOP-", _uint2str(position));
        }
    }

    function _formatDate(uint256 ts) private pure returns (string memory) {
        if (ts == 0) return "TBD";
        (uint256 y, uint256 m, uint256 day) = _epochToDate(ts);
        // Time portion
        uint256 secsInDay = ts % 86400;
        uint256 hour24 = secsInDay / 3600;
        uint256 minute = (secsInDay % 3600) / 60;

        string memory dd = day < 10 ? string.concat("0", _uint2str(day)) : _uint2str(day);
        string memory mon = _monthAbbr(m);
        uint256 yy = y % 100;
        string memory yyStr = yy < 10 ? string.concat("0", _uint2str(yy)) : _uint2str(yy);

        // 12-hour format
        string memory ampm = hour24 >= 12 ? "PM" : "AM";
        uint256 hour12 = hour24 % 12;
        if (hour12 == 0) hour12 = 12;
        string memory minStr = minute < 10 ? string.concat("0", _uint2str(minute)) : _uint2str(minute);

        return string.concat(dd, "-", mon, "-", yyStr, " ", _uint2str(hour12), ":", minStr, ampm);
    }

    function _formatDeadline(uint256 ts, uint256 /* year */) private pure returns (string memory) {
        if (ts == 0) return "TBD";
        // Check if deadline falls on Mother's Day (second Sunday of May)
        (uint256 dy, uint256 dm, ) = _epochToDate(ts);
        if (dm == 5) {
            // Assume it's Mother's Day if it's in May
            return string.concat("MOTHERS DAY ", _uint2str(dy));
        }
        // Otherwise format as date
        return _formatDate(ts);
    }

    function _epochToDate(uint256 ts) private pure returns (uint256 year, uint256 month, uint256 day) {
        uint256 z   = ts / 86400 + 719468;
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        year        = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp  = (5 * doy + 2) / 153;
        day         = doy - (153 * mp + 2) / 5 + 1;
        month       = mp < 10 ? mp + 3 : mp - 9;
        if (month <= 2) year += 1;
    }

    function _monthAbbr(uint256 m) private pure returns (string memory) {
        if (m == 1)  return "JAN";
        if (m == 2)  return "FEB";
        if (m == 3)  return "MAR";
        if (m == 4)  return "APR";
        if (m == 5)  return "MAY";
        if (m == 6)  return "JUN";
        if (m == 7)  return "JUL";
        if (m == 8)  return "AUG";
        if (m == 9)  return "SEP";
        if (m == 10) return "OCT";
        if (m == 11) return "NOV";
        return "DEC";
    }

    function _zeroPad8(uint256 n) private pure returns (string memory) {
        string memory s = _uint2str(n);
        bytes memory b  = bytes(s);
        if (b.length >= 8) return s;
        uint256 needed = 8 - b.length;
        string memory pad = "";
        for (uint256 i = 0; i < needed; i++) {
            pad = string.concat(pad, "0");
        }
        return string.concat(pad, s);
    }

    function _uint2str(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _int2str(int256 value) private pure returns (string memory) {
        if (value >= 0) return _uint2str(uint256(value));
        return string.concat("-", _uint2str(uint256(-value)));
    }

    /**
     * @dev Format fixed-point number. val has `precision` decimal digits of precision.
     *      Output shows `decimals` decimal places.
     *      E.g., _fixedStr(4855, 3, 2) = "4.85"
     */
    function _fixedStr(uint256 val, uint256 precision, uint256 decimals) private pure returns (string memory) {
        uint256 divisor = 10 ** precision;
        uint256 whole = val / divisor;
        uint256 frac = val % divisor;
        // Scale frac to desired decimal places
        uint256 fracScaled = frac * (10 ** decimals) / divisor;
        // Pad fractional part
        string memory fracStr = _uint2str(fracScaled);
        bytes memory fb = bytes(fracStr);
        string memory pad = "";
        for (uint256 i = fb.length; i < decimals; i++) {
            pad = string.concat(pad, "0");
        }
        return string.concat(_uint2str(whole), ".", pad, fracStr);
    }

    // ── Status helpers ──────────────────────────────────────────────────

    function _statusCode(SlipData memory d) private pure returns (string memory) {
        if (d.resolved) {
            return d.won ? "WON" : "LOST";
        }
        if (d.currentTime >= d.deadline) return "CLOSED";
        return "ACTIVE";
    }

    // ── Attributes JSON ─────────────────────────────────────────────────

    function _attributes(SlipData memory d) private pure returns (string memory) {
        return string.concat(
            '[{"trait_type":"Year","value":', _uint2str(d.year), '},',
            '{"trait_type":"Pool Name","value":"', d.poolName, '"},',
            '{"trait_type":"Category","value":"', _formatCategory(d.categoryType, d.gender, d.position), '"},',
            '{"trait_type":"Status","value":"', _statusCode(d), '"},',
            '{"trait_type":"Amount (normalized)","value":', _uint2str(d.amount), '}',
            ']'
        );
    }
}
