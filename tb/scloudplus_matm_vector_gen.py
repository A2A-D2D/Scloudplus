#!/usr/bin/env python3
"""Generate deterministic Scloud+ MatM software vectors for RTL verification."""

from pathlib import Path

B = 8
Q_WIDTH = 8
Q_MOD = 1 << Q_WIDTH
OUT_DIR = Path(__file__).resolve().parent / "vectors_scloudplus"


def mat_a(rows, cols, salt):
    data = []
    for r in range(rows):
        row = []
        for c in range(cols):
            row.append((17 * r + 31 * c + 19 * salt + 7 * r * c + 3) % Q_MOD)
        data.append(row)
    return data


def mat_s(rows, cols, salt):
    data = []
    lut = [0, 1, -1, 0, 1, -1, 1]
    for r in range(rows):
        row = []
        for c in range(cols):
            row.append(lut[(5 * r + 3 * c + salt) % len(lut)])
        data.append(row)
    return data


def mat_mul_ternary(left, right):
    rows = len(left)
    inner = len(left[0])
    cols = len(right[0])
    out = []
    for r in range(rows):
        row = []
        for c in range(cols):
            acc = 0
            for k in range(inner):
                acc += left[r][k] * right[k][c]
            row.append(acc % Q_MOD)
        out.append(row)
    return out


def transpose(mat):
    return [list(col) for col in zip(*mat)]


def coeff_enc(value):
    if value == 1:
        return 1
    if value == -1:
        return 2
    return 0


def block_word(mat, row_blk, col_blk, coeff=False):
    vals = []
    for r in range(B):
        for c in range(B):
            value = mat[row_blk * B + r][col_blk * B + c]
            vals.append(coeff_enc(value) if coeff else value % Q_MOD)
    return vals


def hex_line(vals, width):
    total = 0
    mask = (1 << width) - 1
    for idx, value in enumerate(vals):
        total |= (value & mask) << (idx * width)
    return f"{total:0{(len(vals) * width + 3) // 4}x}"


def write_case(name, left, right):
    rows = len(left)
    inner = len(left[0])
    cols = len(right[0])
    row_blocks = rows // B
    inner_blocks = inner // B
    col_blocks = cols // B
    expect = mat_mul_ternary(left, right)
    req_lines = []
    out_lines = []

    for rb in range(row_blocks):
        for cb in range(col_blocks):
            for ib in range(inner_blocks):
                req_lines.append(
                    hex_line(block_word(left, rb, ib, False), Q_WIDTH)
                    + "_"
                    + hex_line(block_word(right, ib, cb, True), 2)
                )
            out_lines.append(hex_line(block_word(expect, rb, cb, False), Q_WIDTH))

    (OUT_DIR / f"{name}_req.mem").write_text("\n".join(req_lines) + "\n", encoding="ascii")
    (OUT_DIR / f"{name}_exp.mem").write_text("\n".join(out_lines) + "\n", encoding="ascii")
    return row_blocks, inner_blocks, col_blocks, len(req_lines), len(out_lines)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    cases = []

    a_keygen = mat_a(16, 16, 1)
    s_keygen = mat_s(16, 8, 2)
    cases.append(("keygen_as",) + write_case("keygen_as", a_keygen, s_keygen))

    a_enc = mat_a(16, 16, 3)
    sp_enc = mat_s(8, 16, 4)
    cases.append(("enc_c1_transpose",) + write_case("enc_c1_transpose", transpose(a_enc), transpose(sp_enc)))

    c1_dec = mat_a(8, 16, 5)
    s_dec = mat_s(16, 8, 6)
    cases.append(("dec_c1s",) + write_case("dec_c1s", c1_dec, s_dec))

    for item in cases:
        print("%s row_blocks=%d inner_blocks=%d col_blocks=%d req_count=%d out_count=%d" % item)


if __name__ == "__main__":
    main()
