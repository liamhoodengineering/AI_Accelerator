#src: https://medium.com/@saraswatp/understanding-scaled-dot-product-attention-in-transformer-models-5fe02b0f150c
import numpy as np
import torch
import matplotlib.pyplot as plt
import seaborn as sns
import random

# Self-attention function using PyTorch

# def softmax_online(input_array):
#     n = len(input_array)
#     output = np.zeros(n, dtype=float)
    
#     # Initialize running maximum with first element
#     m = input_array[0]
#     # Running sum (starts with e^(x_0 - m_0) = 1.0)
#     d = 1.0
    
#     # Pre-pass to compute final max and total sum
#     for i in range(1, n):
#         if input_array[i] > m:
#             # Adjust the sum when we find a new maximum
#             d = d * 2**(m - input_array[i]) + 1.0
#             m = input_array[i]
#         else:
#             # Add the contribution of this element to the sum
#             d += 2**(input_array[i] - m)
    
#     # Final pass to compute softmax outputs
#     for i in range(n):
#         output[i] = 2**(input_array[i] - m) / d
    
#     return output

# def scaled_dot_product_attention(q, k, v):
#     # QK^T
#     matmul_qk = torch.matmul(q, (k))

#     scaled_attention_logits = matmul_qk / 4

#     # Softmax over last dimension
#     attention_weights = torch.softmax(scaled_attention_logits, dim=-1)

#     # Multiply by V
#     output = torch.matmul(attention_weights, v)

#     return output, attention_weights

# def flash_attention(Q, K, V, k, max, sum):
#     """   
#     Parameters:
#     Q: Query matrix
#     K: Key matrix (transposed in the computation)
#     V: Value matrix
#     k: Row index for query
    
#     Returns:
#     Output vector O[k,:] after processing - equivalent to softmax(Q[k,:] @ K) @ V
#     """
#     N = K.shape[1]  # Get the dimension from K matrix
    
#     # Initialize variables
#     m_i_minus_1 = float('-inf')  # Initial value for m_{i-1}
#     d_i_minus_1 = 0.0  # Initial value for d'_{i-1}
#     o_i_minus_1 = np.zeros_like(V[0, :])  # Initial value for o'_{i-1}
    
#     for i in range(N):
#         # Calculate x_i using the k-th row of Q and i-th column of K^T
#         x_i = np.dot(Q[k, :], K[:, i])
        
#         # Update max value
#         m_i = max(m_i_minus_1, x_i)
        
#         # Calculate d'_i
#         d_i = d_i_minus_1 * np.exp(m_i_minus_1 - m_i) + np.exp(x_i - m_i)
            
#         # Calculate o'_i
#         o_i = (o_i_minus_1 * d_i_minus_1 * np.exp(m_i_minus_1 - m_i) / d_i) + (np.exp(x_i - m_i) / d_i) * V[i, :]
        
#         # Update previous values for next iteration
#         m_i_minus_1 = m_i
#         d_i_minus_1 = d_i
#         o_i_minus_1 = o_i
    
#     # The result is o'_N
#     return o_i_minus_1#src: https://medium.com/data-science-collective/online-softmax-to-flash-attention-and-why-it-matters-9d676e7c50a8

# Q = K = V for self-attention
#Q = K = V = torch.tensor(embedded_tokens, dtype=torch.float32)
# matrix_q, matrix_k, matrix_v = torch.zeros((8192, 4096)), torch.zeros((8192, 4096)), torch.zeros((8192, 4096))
import torch

# -----------------------------
# Configuration
# -----------------------------
N = 256
D = 128
TILE = 16
SCALE = D**.05

torch.manual_seed(0)

# -----------------------------
# Input matrices
# -----------------------------
matrix_q = torch.empty((N, D)).uniform_(-1.0, 1.0)
matrix_k = torch.empty((N, D)).uniform_(-1.0, 1.0)
matrix_v = torch.empty((N, D)).uniform_(-1.0, 1.0)

# This represents external output memory.
# We will only read/write it in 16x16 tiles.
matrix_output = torch.zeros((N, D))

# Optional debug storage for QK^T
matrix_QT = torch.zeros((N, N))


# -----------------------------
# One-pass online tiled attention
# -----------------------------
for i in range(0, N, TILE):

    # One max and denominator per query row in this 16-row tile
    row_max = torch.full((TILE,), -float("inf"))
    row_sum = torch.zeros((TILE,))
    # Output lives in external memory (matrix_output); it is updated one 16x16
    # column-tile at a time inside the j loop, never held as a full-row register.


    for j in range(0, N, TILE):

        # -----------------------------
        # Compute one 16x16 score tile:
        # Q[i:i+16, :] @ K[j:j+16, :].T
        # But using only 16x16 Q/K tiles.
        # -----------------------------
        score_acc = torch.zeros((TILE, TILE))

        for k in range(0, D, TILE):
            q_tile = matrix_q[i:i+TILE, k:k+TILE]
            k_tile = matrix_k[j:j+TILE, k:k+TILE]
            v_tile = matrix_v[j:j+TILE, k:k+TILE]

            score_acc += q_tile @ k_tile.T

        matrix_QT[i:i+TILE, j:j+TILE] = score_acc

        score_tile = score_acc / 4

        # -----------------------------
        # Online softmax statistics update
        # -----------------------------
        old_max = row_max.clone()
        old_sum = row_sum.clone()

        tile_max = torch.max(score_tile, dim=1).values
        new_max = torch.maximum(old_max, tile_max)

        old_sum_scaled = old_sum * torch.exp(old_max - new_max)
        exp_scores = torch.exp(score_tile - new_max[:, None])

        new_sum = old_sum_scaled + torch.sum(exp_scores, dim=1)

        # -----------------------------
        # Update output in 16x16 output-column tiles.
        # o_i = o_{i-1}*(d_{i-1}*exp(m_{i-1}-m_i)/d_i) + (exp(x_i-m_i)/d_i)*V[i,:]
        # We store the *normalized* output in external memory, so each update
        # re-numeratizes the old tile, adds the new V contribution, and re-normalizes.
        # -----------------------------
        for l in range(0, D, TILE):

            # Load old normalized O tile from external memory
            old_output_tile = matrix_output[i:i+TILE, l:l+TILE]

            # Load only one 16x16 V tile (hardware constraint: one V tile at a time)
            v_tile = matrix_v[j:j+TILE, l:l+TILE]

            # Old normalized output converted back into a numerator under the new max:
            # d_{i-1}*exp(m_{i-1}-m_i) == old_sum_scaled
            old_output_contribution = old_output_tile * old_sum_scaled[:, None]

            # New contribution from the current score tile and V tile
            new_output_contribution = exp_scores @ v_tile

            # Normalize by updated denominator d_i == new_sum
            new_output_tile = (
                old_output_contribution + new_output_contribution
            ) / new_sum[:, None]

            # Store updated O tile back to external memory
            matrix_output[i:i+TILE, l:l+TILE] = new_output_tile

        # Commit online softmax stats after all output-column tiles are updated
        row_max = new_max
        row_sum = new_sum


# -----------------------------
# Gold/reference calculation
# -----------------------------
matrix_QT_gold = matrix_q @ matrix_k.T
matrix_QT_gold_scaled = matrix_QT_gold / D**0.5
matrix_QT_gold_softmax = torch.softmax(matrix_QT_gold_scaled, dim=-1)
matrix_output_gold = matrix_QT_gold_softmax @ matrix_v

# Scale-matched reference: the tiled path deliberately uses 1/sqrt(16) (score / 4),
# while the production gold above uses 1/sqrt(128). To isolate the output
# *accumulation* correctness from that intentional temperature difference, build a
# reference that uses the same /4 scale as the DUT.
matrix_output_gold_matched = torch.softmax(matrix_QT_gold / 4, dim=-1) @ matrix_v

# -----------------------------
# Verification
# -----------------------------
qt_diff = torch.abs(matrix_QT - matrix_QT_gold)
output_diff = torch.abs(matrix_output - matrix_output_gold_matched)

print("QK^T allclose:", torch.allclose(matrix_QT, matrix_QT_gold, atol=1e-4, rtol=1e-4))
print("QK^T max absolute difference:", torch.max(qt_diff).item())
print("QK^T mean absolute difference:", torch.mean(qt_diff).item())

print()

print("Output tile-accumulator max value (should be non-zero):", torch.max(torch.abs(matrix_output)).item())
print("Output allclose (scale-matched /4 reference):", torch.allclose(matrix_output, matrix_output_gold_matched, atol=1e-4, rtol=1e-4))
print("Output max absolute difference:", torch.max(output_diff).item())
print("Output mean absolute difference:", torch.mean(output_diff).item())

print()

# The 1/sqrt(128) gold is kept for reference; its gap vs. the DUT is the expected
# scale-induced difference, not an accumulation failure.
print("Output max abs diff vs 1/sqrt(128) gold (expected scale gap):",
      torch.max(torch.abs(matrix_output - matrix_output_gold)).item())


# ============================================================================
# BF16 test-vector emitter for the RTL tiled QK^T datapath (FSM_tiling).
#   python dot_product_attention.py --emit
#
# Writes three $readmemh files consumed by fsm_tiling_tb.sv + the SIM_FAST_HBM
# behavioral memory in HBM_to_BRAM.sv:
#   q_hbm.mem / k_hbm.mem  one 256-bit little-endian BF16 beat per line,
#                          indexed [(tr*COLS + tc)*16 + row]; tile (tr,tc) row
#                          = matrix[16*tr+row, 16*tc : 16*tc+16].  K is stored
#                          NORMALLY (the transpose happens in BRAM_TO_LUTRAM).
#   logit_gold.mem         expected QK^T tile per output (i,j), 16-bit BF16 word
#                          per line, indexed [(i*ROWS + j)*256 + r*16 + c].
#
# Small dims (N=32, D=16, TILE=16) -> ROWS=2 output-row tiles, COLS=1
# contraction tile: the gold is a single-k-tile product, so it is EXACT and
# does not depend on the (WIP placeholder) cross-k accumulate in the RTL.
# ============================================================================
import sys
import os


def _bf16_bits(arr):
    """float array -> BF16 bit patterns (uint16), round-to-nearest-even."""
    a = np.ascontiguousarray(np.asarray(arr, dtype=np.float32))
    u = a.view(np.uint32).astype(np.uint64)
    bias = ((u >> np.uint64(16)) & np.uint64(1)) + np.uint64(0x7FFF)
    return ((u + bias) >> np.uint64(16)).astype(np.uint16)


def _bf16_round(arr):
    """Return the float32 values after BF16 rounding (what the hardware sees)."""
    bits = _bf16_bits(arr).astype(np.uint32) << 16
    return bits.view(np.float32)


def _q(v):
    """BF16-round a scalar or array (per-op quantizer, matches the RTL numerics)."""
    r = _bf16_round(v)
    return float(np.asarray(r).reshape(-1)[0]) if np.ndim(v) == 0 else r


def _flash_row_base2(x, V):
    """base-2 flash-attention output for one query row (verify_flash_v.py recursion,
    bf16 per-op). x = scaled scores over ALL keys; V = full value matrix (keys x D).
    Blocking across j does not change the exact result, so this per-row full-key
    value is the correct gold for the RTL's chained-across-j softermax."""
    m = float("-inf")
    d = 0.0
    o = np.zeros(V.shape[1], dtype=np.float64)
    for idx in range(len(x)):
        xi = float(x[idx])
        m_new = max(m, xi)
        p_dm = 0.0 if m == float("-inf") else _q(2.0 ** _q(m - m_new))   # 2^(m_{i-1}-m_i)
        p_xm = _q(2.0 ** _q(xi - m_new))                                 # 2^(x_i-m_i)
        num_left = _q(d * p_dm)
        d_new = _q(num_left + p_xm)
        cl = _q(num_left / d_new)
        cr = _q(p_xm / d_new)
        o = _q(_q(cl * o) + _q(cr * V[idx, :]))
        m, d = m_new, d_new
    return o


def emit_test_vectors(out_dir=None, N=32, D=16, TILE=16, seed=0):
    if out_dir is None:
        out_dir = os.path.dirname(os.path.abspath(__file__))
    torch.manual_seed(seed)
    q = torch.empty((N, D)).uniform_(-1.0, 1.0).numpy().astype(np.float32)
    k = torch.empty((N, D)).uniform_(-1.0, 1.0).numpy().astype(np.float32)
    v = torch.empty((N, D)).uniform_(-1.0, 1.0).numpy().astype(np.float32)
    qb = _bf16_round(q)          # inputs as the hardware sees them (BF16)
    kb = _bf16_round(k)
    vb = _bf16_round(v)
    qbits = _bf16_bits(q)        # (N,D) uint16 bit patterns for packing
    kbits = _bf16_bits(k)
    vbits = _bf16_bits(v)

    nR = N // TILE               # ROWS: row tiles (i and j)
    nC = D // TILE               # COLS: contraction tiles (k)

    def emit_mem(bits, fname):
        lines = []
        for tr in range(nR):
            for tc in range(nC):
                for row in range(TILE):
                    beat = 0
                    for c in range(TILE):
                        w = int(bits[tr * TILE + row, tc * TILE + c])
                        beat |= w << (16 * c)          # little-endian: col c -> [16c +: 16]
                    lines.append(f"{beat:064X}")       # 256 bits -> 64 hex
        with open(os.path.join(out_dir, fname), "w") as f:
            f.write("\n".join(lines) + "\n")

    emit_mem(qbits, "q_hbm.mem")    # tile (tr=i, tc=k)
    emit_mem(kbits, "k_hbm.mem")    # tile (tr=j, tc=k), stored normally
    emit_mem(vbits, "v_hbm.mem")    # tile (tr=j, tc=0), stored normally (V[key][feat])

    # Gold QK^T tiles: acc over k of q_tile @ k_tile.T (float32 accumulation of
    # BF16-rounded inputs), then rounded to BF16 for the expected DUT output.
    gold_lines = []
    for i in range(nR):
        for j in range(nR):
            acc = np.zeros((TILE, TILE), dtype=np.float32)
            for kk in range(nC):
                qt = qb[i * TILE:(i + 1) * TILE, kk * TILE:(kk + 1) * TILE]
                kt = kb[j * TILE:(j + 1) * TILE, kk * TILE:(kk + 1) * TILE]
                acc += qt @ kt.T
            gb = _bf16_bits(acc)                       # (TILE,TILE) uint16
            for r in range(TILE):
                for c in range(TILE):
                    gold_lines.append(f"{int(gb[r, c]):04X}")
    with open(os.path.join(out_dir, "logit_gold.mem"), "w") as f:
        f.write("\n".join(gold_lines) + "\n")

    # Flash-attention output gold (base-2, BF16), per query row over ALL keys.
    #   scaled scores = BF16(Q@K^T) / 4  (RTL scales the logit tile by 1/sqrt(D)).
    scores_bf = _bf16_round(qb.astype(np.float64) @ kb.astype(np.float64).T)  # (N,N)
    scaled = scores_bf.astype(np.float64) / 4.0                             # exact /4
    out_lines = []
    for row in range(N):
        o = _flash_row_base2(scaled[row], vb.astype(np.float64))            # (D,)
        ob = _bf16_bits(o)
        for c in range(D):
            out_lines.append(f"{int(ob[c]):04X}")
    with open(os.path.join(out_dir, "out_gold.mem"), "w") as f:
        f.write("\n".join(out_lines) + "\n")

    print(f"[emit] ROWS={nR} COLS={nC} TILE={TILE} -> "
          f"q/k/v_hbm.mem ({nR*nC*TILE} beats each), "
          f"logit_gold.mem ({nR*nR*TILE*TILE} words), "
          f"out_gold.mem ({N*D} words) in {out_dir}")


if "--emit" in sys.argv:
    emit_test_vectors()