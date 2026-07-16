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
        # Update output in 16x16 output-column tiles
        # -----------------------------
        for l in range(0, D, TILE):

            # Load old O tile from external memory
            old_output_tile = matrix_output[i:i+TILE, l:l+TILE]

            # Load only one 16x16 V tile
            v_tile = matrix_v[j:j+TILE, l:l+TILE]

            # Old normalized output needs to be converted back
            # into a numerator under the new max.
            old_output_contribution = old_output_tile * old_sum_scaled[:, None]

            # New contribution from the current score tile and V tile
            new_output_contribution = exp_scores @ v_tile

            # Normalize by updated denominator
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

# -----------------------------
# Verification
# -----------------------------
qt_diff = torch.abs(matrix_QT - matrix_QT_gold)
output_diff = torch.abs(matrix_output - matrix_output_gold)

print("QK^T allclose:", torch.allclose(matrix_QT, matrix_QT_gold, atol=1e-4, rtol=1e-4))
print("QK^T max absolute difference:", torch.max(qt_diff).item())
print("QK^T mean absolute difference:", torch.mean(qt_diff).item())

print()

print("Output allclose:", torch.allclose(matrix_output, matrix_output_gold, atol=1e-4, rtol=1e-4))
print("Output max absolute difference:", torch.max(output_diff).item())
print("Output mean absolute difference:", torch.mean(output_diff).item())