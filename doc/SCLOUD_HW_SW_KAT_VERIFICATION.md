# Scloud+ HW/SW KAT Verification Status

## 1. Purpose

This document records the DS-assisted hardware/software verification chain
added on 2026-06-22. It distinguishes KAT-derived functional coverage from a
complete byte-exact openHiTLS known-answer test.

## 2. Verification Inputs

The source vectors are stored in:

```text
KAT/test_suite_sdv_pqcp_scloudplus.data
KAT/test_suite_sdv_pqcp_scloudplus.c
```

`tb/scripts/parse_kat_vectors.py` parses nine vectors into
`tb/vectors/kat/`: three vectors each for ss16, ss24, and ss32. The generated
data includes alpha, randZ, randM, expected public/private keys, ciphertext,
and shared secret fields.

## 3. Confirmed Results

### 3.1 KAT-derived software MsgFunc

`sw/test/test_kat_vectors.c` uses the nine KAT `randM` values as messages:

| Parameter set | tau | Blocks | Result |
| --- | ---: | ---: | ---: |
| ss16 | 3 | 2 | 3/3 PASS |
| ss24 | 4 | 2 | 3/3 PASS |
| ss32 | 3 | 4 | 3/3 PASS |

Total MsgFunc result: `9/9 PASS` using the SW HAL backend.

The same executable also completed nine SHAKE256 repeatability checks:
`9/9 PASS`. These checks prove deterministic local behavior; they are not a
comparison against an external SHAKE known-answer digest.

### 3.2 RTL HW/SW co-verification

`tb/kem/tb_scloudplus_cosim.v` loads a software-provided tau3 message into the
RCE DPRAM model, executes RTL MsgEncode and MsgDecode, and compares the RTL
decoded bytes with the original message.

```text
RTL MsgEncode: PASS
RTL MsgDecode roundtrip: PASS
Results: 2 pass, 0 fail
```

The normal RCE regression additionally covers tau3 MSGENC/MSGDEC and tau4
MSGENC_ADD/SUB_MSGDEC. The exact 8-lane distance engine has also passed 200
random comparisons against the original parallel distance tree.

### 3.3 Additional regression evidence

- Python C-model-aligned MsgFunc self-test: ss16/ss24/ss32 PASS.
- C HAL functional suite: 8/8 PASS.
- Matrix RTL: basic, 8-bit, Scloud+128, and official-parameter vectors PASS.

## 4. Current KAT Closure Boundary

The current repository does not yet demonstrate a complete official
openHiTLS byte-exact KAT pass:

- The local KEM implementation uses simplified A generation and sampling.
- `test_kat_vectors.c` does not compare generated pk, sk, ciphertext, and
  shared secret byte-for-byte against all expected KAT fields.
- A local rerun completed ss16 KeyGen/Encaps/Decaps, then terminated with
  Windows heap corruption during ss24 Encaps. Therefore the full three-level
  local KEM functional run is not closed.
- The RTL cosim currently sends one tau3 MsgFunc message through hardware; it
  does not send all nine complete KEM KAT vectors through the RCE.

Accordingly, the verified status is:

```text
KAT-derived MsgFunc SW verification: PASS
RTL/SW MsgFunc co-verification: PASS
Complete openHiTLS pk/sk/ct/ss KAT equivalence: NOT YET CLOSED
```

## 5. Reproduction

```text
python tb/scripts/parse_kat_vectors.py
build/test_kat.exe
vvp build/cosim.vvp
bash tb/scripts/run_verify.sh --full
```

The KAT executable must be launched from the repository root. The existing
`build/test_kat.log` records an older incorrect-path invocation and must not be
used as PASS evidence.

## 6. Closure Work

1. Fix the ss24 Encaps memory corruption and add explicit output capacities.
2. Replace simplified A generation and sampling with the official behavior.
3. Compare pk, sk, ciphertext, encapsulated shared secret, and decapsulated
   shared secret against every expected KAT field.
4. Drive all ss16/ss24/ss32 KAT MsgFunc blocks through the RCE RTL backend.
5. Save a machine-readable summary with test count, pass/fail count, commit,
   simulator version, and vector-source hash.
