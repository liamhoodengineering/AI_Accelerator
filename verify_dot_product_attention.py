"""Verifier for dot_product_attention.py.

Establishes the correctness of the scaled-dot-product-attention golden model
via three independent lines of evidence:

  V1  - mathematical invariants of the attention weights
  V2  - cross-implementation agreement (script's function, numpy 3-pass
        softmax re-implementation, torch built-in oracle)
  V3  - directed edge cases with hand-computable answers

The original script is NOT imported (it executes and prints at import time
and pulls in matplotlib/seaborn); its attention function is replicated
verbatim below.
"""

import random
import sys

import numpy as np
import torch


# ----------------------------------------------------------------------
# Replicated verbatim from dot_product_attention.py (lines 94-114)
# ----------------------------------------------------------------------
def scaled_dot_product_attention(q, k, v):
    matmul_qk = torch.matmul(q, (k))
    scaled_attention_logits = matmul_qk / 4
    attention_weights = torch.softmax(scaled_attention_logits, dim=-1)
    output = torch.matmul(attention_weights, v)
    return output, attention_weights


# ----------------------------------------------------------------------
# Resurrected from the commented block (lines 15-35): 3-pass softmax
# ----------------------------------------------------------------------
def softmax_3pass(input_array):
    n = len(input_array)
    output = np.zeros(n, dtype=float)

    max_val = input_array[0]
    for i in range(1, n):
        if input_array[i] > max_val:
            max_val = input_array[i]

    sum_val = 0.0
    for i in range(n):
        output[i] = np.exp(input_array[i] - max_val)
        sum_val += output[i]

    for i in range(n):
        output[i] /= sum_val

    return output


def make_qkv(seed=0):
    """Replicates the script's random generation (uniform -10..10)."""
    random.seed(seed)
    torch.manual_seed(seed)
    mats = []
    for _ in range(3):
        m = torch.zeros((16, 16))
        for i in range(16):
            for j in range(16):
                m[i][j] = random.uniform(-10.0, 10.0)
        mats.append(m)
    return mats


results = []


def report(name, ok, detail=""):
    results.append(ok)
    tag = "PASS" if ok else "FAIL"
    print(f"{tag} {name}" + (f"  ({detail})" if detail else ""))


# ----------------------------------------------------------------------
# V1 - invariants
# ----------------------------------------------------------------------
q, k, v = make_qkv(seed=0)
out, w = scaled_dot_product_attention(q, torch.transpose(k, 0, 1), v)

ok_shape = (w.shape == (16, 16)) and (out.shape == (16, 16))
ok_range = bool(((w >= 0.0) & (w <= 1.0)).all())
row_sums = w.sum(dim=-1)
ok_sums = bool(torch.allclose(row_sums, torch.ones(16), atol=1e-5))
report("V1: weights shape/range/row-sums",
       ok_shape and ok_range and ok_sums,
       f"max row-sum dev = {float((row_sums - 1.0).abs().max()):.2e}")

# ----------------------------------------------------------------------
# V2 - cross-implementation agreement
# ----------------------------------------------------------------------
q_np, k_np, v_np = q.numpy().astype(float), k.numpy().astype(float), v.numpy().astype(float)

# Oracle 2: manual numpy path (explicit transpose + 3-pass softmax)
scores = (q_np @ k_np.T) / np.sqrt(16)
w_np = np.apply_along_axis(softmax_3pass, 1, scores)
out_np = w_np @ v_np

# Oracle 3: torch built-in (does the transpose and 1/sqrt(dk) internally)
out_ref = torch.nn.functional.scaled_dot_product_attention(
    q.unsqueeze(0), k.unsqueeze(0), v.unsqueeze(0)).squeeze(0)

d_w = float(np.abs(w.numpy() - w_np).max())
d_o12 = float(np.abs(out.numpy() - out_np).max())
d_o13 = float(np.abs(out.numpy() - out_ref.numpy()).max())
ok_v2 = d_w < 1e-4 and d_o12 < 1e-4 and d_o13 < 1e-4
report("V2: script vs numpy-3pass vs torch built-in", ok_v2,
       f"max |dW|={d_w:.2e}, |dOut| numpy={d_o12:.2e}, torch={d_o13:.2e}")

# ----------------------------------------------------------------------
# V3a - uniform logits: Q=0 -> weights all 1/16, output = column mean of V
# ----------------------------------------------------------------------
q0 = torch.zeros((16, 16))
out_u, w_u = scaled_dot_product_attention(q0, torch.transpose(k, 0, 1), v)
ok_wu = bool(torch.allclose(w_u, torch.full((16, 16), 1.0 / 16.0), atol=1e-6))
ok_ou = bool(torch.allclose(out_u, v.mean(dim=0).expand(16, 16), atol=1e-5))
report("V3a: uniform logits -> uniform weights", ok_wu and ok_ou)

# ----------------------------------------------------------------------
# V3b - dominant logit: score[i][sel] >> others -> output row ~= V[sel]
# ----------------------------------------------------------------------
# Build K so column j of K^T is e_j scaled: K = 200 * I. Q = I.
# scores = Q @ K^T / 4 = 50 * I -> diagonal dominates each row by 50.
q_d = torch.eye(16)
k_d = 200.0 * torch.eye(16)
out_d, w_d = scaled_dot_product_attention(q_d, torch.transpose(k_d, 0, 1), v)
ok_wd = bool(torch.allclose(torch.diagonal(w_d), torch.ones(16), atol=1e-3))
ok_od = bool(torch.allclose(out_d, v, atol=1e-3))
report("V3b: dominant logit -> selects V row", ok_wd and ok_od,
       f"min diag weight = {float(torch.diagonal(w_d).min()):.6f}")

# ----------------------------------------------------------------------
# V3c - extreme values stay finite
# ----------------------------------------------------------------------
q_x = torch.full((16, 16), 10.0)
k_x = torch.full((16, 16), -10.0)
out_x, w_x = scaled_dot_product_attention(q_x, torch.transpose(k_x, 0, 1), v)
ok_x = bool(torch.isfinite(w_x).all()) and bool(torch.isfinite(out_x).all())
report("V3c: extreme values remain finite", ok_x)

# ----------------------------------------------------------------------
print()
n_pass = sum(results)
print(f"==== {n_pass}/{len(results)} checks passed ====")
sys.exit(0 if n_pass == len(results) else 1)
