#!/usr/bin/env python3
"""
Parse the openHiTLS Scloud+ KAT test vectors and generate:
  1. kat_vectors.h — C header with the parsed vectors
  2. kat_vectors.txt — human-readable summary
  3. kat_seeds.mem — seeds in .mem format for RTL simulation

Usage:
  python tb/scripts/parse_kat_vectors.py
"""
import os, sys

KAT_FILE = "KAT/test_suite_sdv_pqcp_scloudplus.data"
OUT_DIR = "tb/vectors/kat"

def parse_kat(filepath):
    """Parse KAT .data file and extract VECTOR_TC001 entries."""
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    vectors = []
    lines = content.split('\n')
    for line in lines:
        line = line.strip()
        if not line or 'VECTOR_TC001:' not in line:
            continue

        # Format: TESTNAME:PQCP_SCLOUDPLUS_128:"alpha":"randZ":"randM":"pk":"sk":"ct":"ss"
        parts = line.split(':', 1)
        if len(parts) < 2:
            continue

        rest = parts[1]

        # Split by : but respect quotes
        # The format is: LEVEL:"hex1":"hex2":"hex3":"hex4":"hex5":"hex6":"hex7"
        fields = []
        current = ""
        in_quote = False
        for ch in rest:
            if ch == '"':
                if in_quote:
                    fields.append(current)
                    current = ""
                in_quote = not in_quote
            elif in_quote:
                current += ch
            elif ch == ':':
                if current:
                    fields.append(current)
                    current = ""
            else:
                current += ch
        if current:
            fields.append(current)

        if len(fields) >= 8:
            vectors.append({
                'level': fields[0].strip(),
                'alpha': fields[1].strip(),
                'randZ': fields[2].strip(),
                'randM': fields[3].strip(),
                'expPk': fields[4].strip(),
                'expSk': fields[5].strip(),
                'expCipher': fields[6].strip(),
                'expSharedKey': fields[7].strip(),
            })

    return vectors


def ss_from_level(level):
    if '128' in level: return 16
    if '192' in level: return 24
    if '256' in level: return 32
    return 16


def main():
    vectors = parse_kat(KAT_FILE)
    print(f"Parsed {len(vectors)} KAT vector entries")

    os.makedirs(OUT_DIR, exist_ok=True)

    # ---- Generate C header ----
    with open(os.path.join(OUT_DIR, "kat_vectors.h"), 'w') as f:
        f.write("/* Auto-generated from openHiTLS KAT test vectors */\n")
        f.write(f"/* Source: {KAT_FILE} */\n")
        f.write(f"/* Total vectors: {len(vectors)} */\n\n")
        f.write("#ifndef KAT_VECTORS_H\n#define KAT_VECTORS_H\n\n")
        f.write("#include <stdint.h>\n\n")

        for i, v in enumerate(vectors):
            ss = ss_from_level(v['level'])
            alpha_bytes = len(v['alpha']) // 2
            randZ_bytes = len(v['randZ']) // 2
            randM_bytes = len(v['randM']) // 2
            pk_bytes = len(v['expPk']) // 2
            sk_bytes = len(v['expSk']) // 2
            ct_bytes = len(v['expCipher']) // 2
            ss_bytes = len(v['expSharedKey']) // 2

            f.write(f"/* Vector {i}: ss={ss}, {v['level']} */\n")
            f.write(f"/* alpha={alpha_bytes}B, randZ={randZ_bytes}B, randM={randM_bytes}B */\n")
            f.write(f"/* pk={pk_bytes}B, sk={sk_bytes}B, ct={ct_bytes}B, ss={ss_bytes}B */\n")

            # Write as hex arrays
            for name, val in [('alpha', v['alpha']), ('randZ', v['randZ']),
                              ('randM', v['randM']), ('expPk', v['expPk']),
                              ('expSk', v['expSk']), ('expCipher', v['expCipher']),
                              ('expSharedKey', v['expSharedKey'])]:
                hex_bytes = [val[j:j+2] for j in range(0, len(val), 2)]
                f.write(f"static const uint8_t kat_{i}_{name}[{len(hex_bytes)}] = {{\n    ")
                for k, b in enumerate(hex_bytes):
                    f.write(f"0x{b}")
                    if k < len(hex_bytes) - 1:
                        f.write(", ")
                    if (k + 1) % 16 == 0 and k < len(hex_bytes) - 1:
                        f.write("\n    ")
                f.write("\n};\n\n")

        f.write("typedef struct {\n")
        f.write("    int ss_level;\n")
        f.write("    int alpha_len, randZ_len, randM_len;\n")
        f.write("    int pk_len, sk_len, ct_len, ss_len;\n")
        f.write("    const uint8_t *alpha, *randZ, *randM;\n")
        f.write("    const uint8_t *expPk, *expSk, *expCipher, *expSharedKey;\n")
        f.write("} KatVector;\n\n")

        f.write(f"static const KatVector kat_vectors[{len(vectors)}] = {{\n")
        for i, v in enumerate(vectors):
            ss = ss_from_level(v['level'])
            f.write(f"    {{ {ss}, {len(v['alpha'])//2}, {len(v['randZ'])//2}, {len(v['randM'])//2}, ")
            f.write(f"{len(v['expPk'])//2}, {len(v['expSk'])//2}, {len(v['expCipher'])//2}, {len(v['expSharedKey'])//2}, ")
            f.write(f"kat_{i}_alpha, kat_{i}_randZ, kat_{i}_randM, ")
            f.write(f"kat_{i}_expPk, kat_{i}_expSk, kat_{i}_expCipher, kat_{i}_expSharedKey }},\n")
        f.write("};\n\n")
        f.write("#endif /* KAT_VECTORS_H */\n")

    print(f"  Generated {OUT_DIR}/kat_vectors.h")

    # ---- Generate human-readable summary ----
    with open(os.path.join(OUT_DIR, "kat_summary.txt"), 'w') as f:
        f.write(f"Scloud+ KAT Test Vectors ({len(vectors)} entries)\n")
        f.write("=" * 60 + "\n\n")
        for i, v in enumerate(vectors):
            ss = ss_from_level(v['level'])
            f.write(f"Vector {i}: ss={ss} ({v['level']})\n")
            f.write(f"  alpha ({len(v['alpha'])//2}B):    {v['alpha'][:32]}...\n")
            f.write(f"  randZ ({len(v['randZ'])//2}B):    {v['randZ'][:32]}...\n")
            f.write(f"  randM ({len(v['randM'])//2}B):    {v['randM'][:32]}...\n")
            f.write(f"  expPk ({len(v['expPk'])//2}B):    {v['expPk'][:32]}...\n")
            f.write(f"  expSk ({len(v['expSk'])//2}B):    {v['expSk'][:32]}...\n")
            f.write(f"  expCt ({len(v['expCipher'])//2}B):    {v['expCipher'][:32]}...\n")
            f.write(f"  expSS ({len(v['expSharedKey'])//2}B): {v['expSharedKey']}\n\n")

    print(f"  Generated {OUT_DIR}/kat_summary.txt")

    # ---- Generate .mem files for RTL ----
    # Write seeds as hex bytes for RTL simulation input
    for i, v in enumerate(vectors):
        ss = ss_from_level(v['level'])
        prefix = os.path.join(OUT_DIR, f"kat_{i}_ss{ss}")
        # alpha (randomness for keygen)
        with open(f"{prefix}_alpha.mem", 'w') as f:
            for j in range(0, len(v['alpha']), 2):
                f.write(f"{v['alpha'][j:j+2]}\n")
        # expSharedKey
        with open(f"{prefix}_exp_ss.mem", 'w') as f:
            for j in range(0, len(v['expSharedKey']), 2):
                f.write(f"{v['expSharedKey'][j:j+2]}\n")

    print(f"  Generated .mem files in {OUT_DIR}/")
    print(f"\nTotal: {len(vectors)} KAT vectors ready for testing")


if __name__ == '__main__':
    main()
