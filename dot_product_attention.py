# import numpy as np
# import random

# matrix_q = np.zeros((16, 16));
# matrix_k = np.zeros((16, 16));
# matrix_v = np.zeros((16, 16));
# matrix_scores = np.zeros((16, 16));
# matrix_scores_normalized = np.zeros((16, 16));
# matrix_scores_scaled = np.zeros((16, 16));
# matrix_weighted_output = np.zeros((16, 16));




# def softmax_3pass(input_array):
#     n = len(input_array)
#     output = np.zeros(n, dtype=float)
    
#     # First pass: find max
#     max_val = input_array[0]
#     for i in range(1, n):
#         if input_array[i] > max_val:
#             max_val = input_array[i]
    
#     # Second pass: compute exp(x - max) and sum
#     sum_val = 0.0
#     for i in range(n):
#         output[i] = np.exp(input_array[i] - max_val)
#         sum_val += output[i]
    
#     # Third pass: normalize
#     for i in range(n):
#         output[i] /= sum_val
    
#     return output   #src: https://medium.com/data-science-collective/online-softmax-to-flash-attention-and-why-it-matters-9d676e7c50a8



# for i in range(16):
#     for j in range(16):
#         x = random.uniform(-10.0, 10.0)
#         matrix_q[i][j] = x

# for i in range(16):
#     for j in range(16):
#         x = random.uniform(-10.0, 10.0)
#         matrix_k[i][j] = x

# for i in range(16):
#     for j in range(16):
#         x = random.uniform(-10.0, 10.0)
#         matrix_v[i][j] = x

# matrix_k_transposed = np.transpose(matrix_k)
# matrix_scores = np.matmul(matrix_q, matrix_k_transposed)
# matrix_scores_scaled = matrix_scores / np.sqrt(16)
# matrix_scores_normalized = np.apply_along_axis(softmax_3pass, 1, matrix_scores_scaled)
# matrix_weighted_output = np.matmul(matrix_scores_normalized, matrix_v)  


      
# # print (matrix_q)
# # print("\n")
# # print (matrix_k)
# # print("\n")
# # print (matrix_scores)
# # print("\n")
# # print (matrix_v)


#src: https://medium.com/@saraswatp/understanding-scaled-dot-product-attention-in-transformer-models-5fe02b0f150c
import numpy as np
import torch
import matplotlib.pyplot as plt
import seaborn as sns
import random

# Define word embeddings
# embeddings = {
#     # 'the': np.array([0.1, 0.2, 0.3]),
#     # 'cat': np.array([0.4, 0.5, 0.6]),
#     # 'sat': np.array([0.7, 0.8, 0.9]),
#     # 'on': np.array([1.0, 1.1, 1.2]),
#     # 'mat': np.array([1.3, 1.4, 1.5])
# }

# Define input sentence
# sentence = ['the', 'cat', 'sat', 'on', 'the', 'mat']

# # Convert sentence to embeddings
# embedded_tokens = np.array([embeddings[word] for word in sentence])

# Self-attention function using PyTorch
def scaled_dot_product_attention(q, k, v):
    # QK^T
    matmul_qk = torch.matmul(q, (k))

    # dk = embedding dimension
   # dk = k.shape[-1]

    # Scale by sqrt(dk)
    scaled_attention_logits = matmul_qk / 4

    # Optional mask
    # if mask is not None:
    #     scaled_attention_logits += mask * -1e9

    # Softmax over last dimension
    attention_weights = torch.softmax(scaled_attention_logits, dim=-1)

    # Multiply by V
    output = torch.matmul(attention_weights, v)

    return output, attention_weights

# Q = K = V for self-attention
#Q = K = V = torch.tensor(embedded_tokens, dtype=torch.float32)
matrix_q, matrix_k, matrix_v = torch.zeros((16, 16)), torch.zeros((16, 16)), torch.zeros((16, 16))
for i in range(16):
    for j in range(16):
        x = random.uniform(-10.0, 10.0)
        matrix_q[i][j] = x

for i in range(16):
    for j in range(16):
        x = random.uniform(-10.0, 10.0)
        matrix_k[i][j] = x

for i in range(16):
    for j in range(16):
        x = random.uniform(-10.0, 10.0)
        matrix_v[i][j] = x

# Apply self-attention
output, attention_weights = scaled_dot_product_attention(matrix_q, torch.transpose(matrix_k,0,1), matrix_v)

# Print attention weights
print("Attention Weights:")
print(attention_weights.numpy())

# Print output
print("Output:")
print(output.numpy())

# Visualize attention weights
#tokens = sentence
# plt.figure(figsize=(10, 8))
# sns.heatmap(
#     attention_weights.numpy(),
#     xticklabels=tokens,
#     yticklabels=tokens,
#     cmap='viridis',
#     annot=True
# )
# plt.xlabel('Input Tokens')
# plt.ylabel('Attention given to Tokens')
# plt.title('Attention Weights Heatmap')
# plt.show()