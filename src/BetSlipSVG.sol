// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Base64.sol";

/**
 * @title BetSlipSVG
 * @notice Library for generating onchain SVG art for Baby Name Market bet slip NFTs
 */
library BetSlipSVG {

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

    struct SlipData {
        uint256 tokenId;
        string  poolName;
        uint256 year;
        uint8   categoryType;
        uint8   gender;       // 0=Female, 1=Male
        uint256 position;     // rank number or top-N
        uint256 amount;       // normalized 1e18 bet amount
        uint8   tokenDecimals;
        uint256 purchasedAt;  // unix timestamp
        uint256 deadline;     // unix timestamp
        uint256 currentTime;  // block.timestamp at tokenURI call time
        uint256 poolCollateral;      // normalized 1e18
        uint256 categoryCollateral;  // normalized 1e18
        bool    resolved;
        bool    won;
    }

    // ============ Entry Points ============

    /**
     * @notice Build a complete ERC721 tokenURI data URI from slip data
     */
    function tokenURI(SlipData memory d) internal pure returns (string memory) {
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

    // ============ SVG Root ============

    function _svg(SlipData memory d) private pure returns (string memory) {
        // Split into two halves to avoid stack-depth issues with large string.concat
        string memory top = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="560" viewBox="0 0 400 560">',
            _defs(),
            _background(),
            _header(_statusCode(d)),
            _perfLine(112),
            _sectionMarket(d),
            _divider(196),
            _sectionBet(d)
        );
        string memory bottom = string.concat(
            _divider(308),
            _sectionResolution(d),
            _divider(362),
            _sectionPayout(d),
            _perfLine(428),
            _sectionSlipId(d.tokenId),
            _footer(),
            "</svg>"
        );
        return string.concat(top, bottom);
    }

    // ============ Defs & Background ============

    function _defs() private pure returns (string memory) {
        return string.concat(
            "<defs>",
            "<filter id='paper' x='0%' y='0%' width='100%' height='100%'>",
            "<feTurbulence type='fractalNoise' baseFrequency='0.65' numOctaves='3' stitchTiles='stitch' result='noise'/>",
            "<feColorMatrix type='saturate' values='0' in='noise' result='grayNoise'/>",
            "<feBlend in='SourceGraphic' in2='grayNoise' mode='multiply'/>",
            "</filter>",
            "</defs>"
        );
    }

    function _background() private pure returns (string memory) {
        return "<rect width='400' height='560' fill='#F7F2E8' rx='16' filter='url(#paper)'/>";
    }

    // ============ Header ============

    function _header(string memory statusLabel) private pure returns (string memory) {
        return string.concat(
            "<rect width='400' height='96' fill='#1B4332' rx='16'/>",
            "<rect y='80' width='400' height='16' fill='#1B4332'/>",
            "<text x='20' y='42' fill='white' font-family='monospace' font-size='20' font-weight='bold'>",
            "BABY NAME MARKET",
            "</text>",
            "<text x='20' y='68' fill='#74C69D' font-family='monospace' font-size='11'>PREDICTION SLIP</text>",
            "<text x='380' y='68' text-anchor='end' fill='",
            _statusColor(statusLabel),
            "' font-family='monospace' font-size='11' font-weight='bold'>",
            statusLabel,
            "</text>"
        );
    }

    // ============ Perforated Line ============

    function _perfLine(uint256 y) private pure returns (string memory) {
        string memory ys = _uint2str(y);
        return string.concat(
            "<circle cx='0' cy='",  ys, "' r='14' fill='#F7F2E8'/>",
            "<circle cx='400' cy='", ys, "' r='14' fill='#F7F2E8'/>",
            "<line x1='25' y1='", ys, "' x2='375' y2='", ys,
            "' stroke='#C9BA9B' stroke-width='1' stroke-dasharray='5,4'/>"
        );
    }

    // ============ Thin Section Divider ============

    function _divider(uint256 y) private pure returns (string memory) {
        string memory ys = _uint2str(y);
        return string.concat(
            "<line x1='20' y1='", ys, "' x2='380' y2='", ys,
            "' stroke='#E5D9C3' stroke-width='1'/>"
        );
    }

    // ============ MARKET Section ============

    function _sectionMarket(SlipData memory d) private pure returns (string memory) {
        return string.concat(
            _label("MARKET", 20, 134),
            _row("Year",   _uint2str(d.year),          20, 156, false),
            _row("Placed", _formatDate(d.purchasedAt),  20, 178, false)
        );
    }

    // ============ BET Section ============

    function _sectionBet(SlipData memory d) private pure returns (string memory) {
        return string.concat(
            _label("BET", 20, 218),
            _row("Amount",   _formatAmount(d.amount, d.tokenDecimals), 20, 240, true),
            _row("Category", _formatCategory(d.categoryType, d.gender, d.position), 20, 262, false),
            _row("Name",     d.poolName,                               20, 284, true)
        );
    }

    // ============ RESOLUTION Section ============

    function _sectionResolution(SlipData memory d) private pure returns (string memory) {
        return string.concat(
            _label("RESOLUTION", 20, 326),
            _row("Resolves On", _formatDate(d.deadline), 20, 348, false)
        );
    }

    // ============ PAYOUT Section ============

    function _sectionPayout(SlipData memory d) private pure returns (string memory) {
        return string.concat(
            _label("PAYOUT", 20, 382),
            _row("Pool Total",    _formatAmount(d.categoryCollateral, d.tokenDecimals), 20, 404, false),
            _row("Win Multiplier", _formatMultiplier(d.categoryCollateral, d.poolCollateral), 20, 420, true)
        );
    }

    // ============ SLIP ID Section ============

    function _sectionSlipId(uint256 tokenId) private pure returns (string memory) {
        string memory padded = _zeroPad8(tokenId);
        return string.concat(
            _label("SLIP ID", 20, 449),
            _barcodeLines(tokenId),
            "<text x='380' y='476' text-anchor='end' fill='#1B4332'",
            " font-family='monospace' font-size='22' font-weight='bold'>",
            padded,
            "</text>"
        );
    }

    // ============ Footer ============

    function _footer() private pure returns (string memory) {
        return "<text x='200' y='530' text-anchor='middle' fill='#9CA3AF'"
               " font-family='monospace' font-size='9' letter-spacing='1'>BABYNAMES.MARKET</text>";
    }

    // ============ SVG Primitives ============

    function _label(string memory text, uint256 x, uint256 y) private pure returns (string memory) {
        return string.concat(
            "<text x='", _uint2str(x), "' y='", _uint2str(y),
            "' fill='#9CA3AF' font-family='monospace' font-size='9' letter-spacing='2'>",
            text,
            "</text>"
        );
    }

    function _row(
        string memory key,
        string memory value,
        uint256 x,
        uint256 y,
        bool highlight
    ) private pure returns (string memory) {
        string memory ys  = _uint2str(y);
        string memory valColor = highlight ? "#1B4332" : "#374151";
        string memory valSize  = highlight ? "14" : "12";
        string memory valWeight = highlight ? " font-weight='bold'" : "";
        return string.concat(
            "<text x='", _uint2str(x), "' y='", ys,
            "' fill='#374151' font-family='monospace' font-size='12'>",
            key,
            "</text>",
            "<text x='380' y='", ys,
            "' text-anchor='end' fill='", valColor,
            "' font-family='monospace' font-size='", valSize, "'", valWeight, ">",
            value,
            "</text>"
        );
    }

    // ============ Barcode Decoration ============

    function _barcodeLines(uint256 tokenId) private pure returns (string memory) {
        // 24 vertical bars of varying width based on token ID bits
        string memory bars;
        uint256 seed = tokenId == 0 ? 1 : tokenId;
        uint256 x = 20;
        for (uint256 i = 0; i < 24; i++) {
            uint256 bit = (seed >> (i % 32)) & 0x3;
            uint256 w = 1 + bit;
            uint256 gap = 1 + ((seed >> ((i + 5) % 32)) & 0x1);
            bars = string.concat(
                bars,
                "<rect x='", _uint2str(x), "' y='458' width='", _uint2str(w),
                "' height='12' fill='#374151'/>"
            );
            x += w + gap;
            if (x > 200) break;
        }
        return bars;
    }

    // ============ Status Helpers ============

    function _statusCode(SlipData memory d) private pure returns (string memory) {
        if (d.resolved) {
            return d.won ? "WON" : "LOST";
        }
        if (d.currentTime >= d.deadline) return "CLOSED";
        return "ACTIVE";
    }

    function _statusColor(string memory label) private pure returns (string memory) {
        // Compare first byte - ACTIVE/WON -> green, LOST -> red, CLOSED -> yellow
        bytes memory b = bytes(label);
        if (b.length == 0) return "#74C69D";
        if (b[0] == "A" || b[0] == "W") return "#74C69D";
        if (b[0] == "L") return "#FCA5A5";
        return "#FDE68A"; // CLOSED
    }

    // ============ Attributes JSON ============

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

    // ============ Formatting Helpers ============

    /**
     * @notice Format a normalized (1e18) amount to a dollar string like "$5.00"
     * Assumes collateral token with given decimals (typically 6 for USDC).
     */
    function _formatAmount(uint256 normalized, uint8 decimals) private pure returns (string memory) {
        // Convert from 1e18 to native decimals, then format
        uint256 scaleFactor = 10 ** (18 - decimals);
        uint256 native = normalized / scaleFactor;               // e.g., 5_000_000 for $5 USDC
        uint256 whole  = native / (10 ** decimals);              // integer part
        uint256 frac   = native % (10 ** decimals);              // fractional part (in native decimals)
        // Show 2 decimal places
        uint256 fracScaled = frac * 100 / (10 ** decimals);       // 0-99
        string memory fracStr = fracScaled < 10
            ? string.concat("0", _uint2str(fracScaled))
            : _uint2str(fracScaled);
        return string.concat("$", _uint2str(whole), ".", fracStr);
    }

    /**
     * @notice Format a multiplier as "X.Xx" (e.g., "3.2x")
     * multiplier = (categoryCollateral * 90%) / poolCollateral
     */
    function _formatMultiplier(uint256 catCollateral, uint256 poolCollateral) private pure returns (string memory) {
        if (poolCollateral == 0) return "--";
        // Use 100x precision: multiply by 100 to get two digits
        uint256 prizePool = catCollateral * 90 / 100;
        uint256 mult100   = prizePool * 100 / poolCollateral; // e.g., 320 for 3.20
        uint256 whole = mult100 / 100;
        uint256 frac  = mult100 % 100;
        // Show 1 decimal place
        string memory fracStr = _uint2str(frac / 10);
        return string.concat(_uint2str(whole), ".", fracStr, "x");
    }

    /**
     * @notice Format a category label (e.g., "GIRL #1", "BOY TOP-10", "GIRL EXACTA")
     */
    function _formatCategory(uint8 catType, uint8 gender, uint256 position) private pure returns (string memory) {
        string memory g = gender == GENDER_FEMALE ? "GIRL" : "BOY";
        if (catType == CAT_SINGLE) {
            return string.concat(g, " #", _uint2str(position));
        } else if (catType == CAT_EXACTA) {
            return string.concat(g, " EXACTA");
        } else if (catType == CAT_TRIFECTA) {
            return string.concat(g, " TRIFECTA");
        } else {
            // CAT_TOP_N
            return string.concat(g, " TOP-", _uint2str(position));
        }
    }

    /**
     * @notice Format a Unix timestamp as DD-MON-YY
     */
    function _formatDate(uint256 ts) private pure returns (string memory) {
        if (ts == 0) return "TBD";
        (uint256 y, uint256 m, uint256 d) = _epochToDate(ts);
        string memory mon = _monthAbbr(m);
        string memory dd  = d < 10 ? string.concat("0", _uint2str(d)) : _uint2str(d);
        // Two-digit year
        uint256 yy  = y % 100;
        string memory yyStr = yy < 10 ? string.concat("0", _uint2str(yy)) : _uint2str(yy);
        return string.concat(dd, "-", mon, "-", yyStr);
    }

    /**
     * @notice Convert Unix epoch to (year, month, day) using Howard Hinnant's algorithm
     */
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

    /**
     * @notice Zero-pad a uint256 to 8 digits
     */
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

    /**
     * @notice Convert uint256 to string
     */
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
}
