import numpy as np
import torch as tr

# def flash_attention(Q, K, V, k):
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
#     return o_i_minus_1

import numpy as np

def softmax_online(input_array):
    n = len(input_array)
    output = np.zeros(n, dtype=float)
    
    # Initialize running maximum with first element
    m = input_array[0]
    # Running sum (starts with e^(x_0 - m_0) = 1.0)
    d = 1.0
    
    # Pre-pass to compute final max and total sum
    for i in range(1, n):
        if input_array[i] > m:
            # Adjust the sum when we find a new maximum
            d = d * np.exp(m - input_array[i]) + 1.0
            m = input_array[i]
        else:
            # Add the contribution of this element to the sum
            d += np.exp(input_array[i] - m)
    
    # Final pass to compute softmax outputs
    for i in range(n):
        output[i] = np.exp(input_array[i] - m) / d
    
    return output
    

def softmax_3pass(input_array):
    n = len(input_array)
    output = np.zeros(n, dtype=float)
    
    # First pass: find maxclear
    max_val = input_array[0]
    for i in range(1, n):
        if input_array[i] > max_val:
            max_val = input_array[i]
    
    # Second pass: compute exp(x - max) and sum
    sum_val = 0.0
    for i in range(n):
        output[i] = np.exp(input_array[i] - max_val)
        sum_val += output[i]
    
    # Third pass: normalize
    for i in range(n):
        output[i] /= sum_val
    
    return output

all_arrays = [np.zeros(16, dtype=float) for _ in range(1)]

for i in range(1):
    for j in range(16):
        all_arrays[i][j] = np.random.uniform(-1.0, 1.0)
# array_1 = np.array([16.367, 62.5992, 70.5406, 23.2988, 49.3379, 79.8652, 51.1812, 76.3548, 94.6376, 10.6951, 12.3933, 66.9182, 6.386, 96.2377, 28.576, 30.9856])
# array_2 = np.array([19.1947, 43.9285, 56.2227, 91.4947, 36.4353, 13.826, 27.9652, 75.135, 92.2225, 71.166, 97.8609, 98.9694, 55.3104, 80.7613, 61.7984, 45.2309])
# array_3 = np.array([9.1415, 46.6442, 85.3031, 65.2398, 50.9326, 41.0195, 27.2196, 57.1047, 24.8124, 27.8206, 32.0884, 14.5737, 7.849, 92.7098, 86.5131, 34.8982])
# array_4 = np.array([5.2207, 74.3928, 10.1418, 39.7692, 23.1084, 64.6439, 10.3808, 85.7387, 31.3591, 0.9017, 76.4646, 72.8892, 10.2974, 81.8337, 35.3288, 41.3625])
# array_5 = np.array([32.9568, 77.1808, 60.345, 24.5575, 31.733, 63.8236, 60.8195, 51.5667, 41.5278, 41.5024, 93.9575, 14.7843, 88.3943, 65.187, 70.0379, 8.89])
# array_6 = np.array([8.7581, 80.2125, 60.6352, 10.651, 0.3628, 23.4675, 32.1201, 46.9634, 4.1319, 22.8533, 28.1399, 53.4877, 13.0852, 43.8688, 40.1576, 71.7516])
# array_7 = np.array([67.0003, 27.6359, 84.7466, 5.8926, 34.785, 97.2935, 62.8949, 79.9098, 17.0551, 82.8552, 17.6629, 5.7707, 31.9619, 23.1944, 95.5025, 59.7262])
# array_8 = np.array([13.3491, 41.7534, 58.3658, 50.7729, 16.9716, 4.5397, 35.4063, 64.3466, 71.6741, 45.618, 52.0473, 2.522, 2.767, 11.4163, 17.0582, 43.233])
# array_9 = np.array([28.5772, 68.8089, 33.1649, 96.5037, 22.1587, 80.6491, 86.983, 43.357, 51.4275, 5.1168, 51.8525, 28.4893, 48.9388, 8.3872, 78.1038, 54.6477])
# array_10 = np.array([96.909, 2.705, 45.4075, 59.3713, 85.9662, 45.0798, 59.9564, 51.9607, 57.5061, 72.0259, 78.601, 5.8649, 84.1786, 53.1068, 81.8226, 6.4766])
# array_11 = np.array([27.1859, 22.4749, 9.5311, 87.8757, 65.2771, 52.7313, 97.4268, 40.074, 42.8425, 35.7933, 16.9366, 28.1312, 27.6829, 7.7751, 28.7383, 80.8682])
# array_12 = np.array([20.1808, 18.9847, 76.3666, 78.2988, 84.391, 9.8336, 57.0503, 6.2663, 30.1708, 27.0193, 41.9513, 3.8065, 40.6911, 44.9706, 78.1057, 76.0586])
# array_13 = np.array([90.4883, 31.0626, 79.5089, 9.0165, 95.7646, 16.6661, 67.6972, 6.1942, 78.6602, 87.2995, 31.3959, 14.1097, 55.3819, 19.8796, 84.2295, 16.4035])
# array_14 = np.array([43.8359, 24.7958, 60.9099, 77.681, 99.9165, 77.109, 16.7594, 2.3892, 24.8712, 7.5406, 97.8049, 1.349, 45.0475, 21.7555, 19.3395, 67.0109])
# array_15 = np.array([8.1645, 38.8079, 13.1846, 96.8628, 64.2036, 40.0371, 11.7418, 45.9329, 6.4952, 73.1095, 53.6017, 63.7469, 4.6724, 51.8474, 42.6628, 0.2122])

# all_arrays = [array_1, array_2, array_3, array_4, array_5, array_6, array_7, array_8, array_9, array_10, array_11, array_12, array_13, array_14, array_15]

# for i in range(len(all_arrays)):
#     temp_arr = np.array(softmax_3pass(all_arrays[i]))
#     for j in range(len(temp_arr)):
#         temp_arr[j] = round(temp_arr[j], 4)

for i in range(len(all_arrays)):
    with open("input.txt", "a") as file:
        file.write("\n\n")
       # print("\n\n")
    if(i == 0):
       with open("input.txt", "w") as file:
            # Original float values
            
            file.write("\n\n")

            # Convert to BF16 tensor
            bf16_arr = tr.tensor(all_arrays[i], dtype=tr.float16)

            #print(bf16_arr)

            # Get BF16 hex bit patterns
            bf16_bits = bf16_arr.view(tr.uint16)

            #print()
            file.write(" ".join([str(x.item()) for x in bf16_arr]))
            #file.write(" ".join([hex(x.item()) for x in bf16_bits]))

            # Print original values
           # print(" ".join(all_arrays[i].astype(str)))
    else:
        with open("input.txt", "a") as file:
            file.write("\n\n")

            # Convert to BF16 tensor
            bf16_arr = tr.tensor(all_arrays[i], dtype=tr.float16)

            # Get BF16 hex bit patterns
            bf16_bits = bf16_arr.view(tr.uint16)

            # Write BF16 hex values
            file.write(" ".join([str(x.item()) for x in bf16_arr]))
           # file.write(" ".join([hex(x.item()) for x in bf16_bits]))

for i in range(len(all_arrays)):
    with open("output.txt", "a") as file:
        file.write("\n\n")
       # print("\n\n")
    if(i == 0):
       with open("output.txt", "w") as file:
            # Original float values
            
            file.write("\n\n")

            # Convert to BF16 tensor
            bf16_arr = tr.tensor(softmax_online(all_arrays[i]), dtype=tr.float16)

            #print(bf16_arr)
           # file.write(" ".join(softmax_3pass(all_arrays[i]).astype(str)))

            # Get BF16 hex bit patterns
            bf16_bits = bf16_arr.view(tr.uint16)

            #print()
            file.write(" ".join([str(x.item()) for x in bf16_arr]))
           # file.write(" ".join([hex(x.item()) for x in bf16_bits]))

            # Print original values
           # print(" ".join(all_arrays[i].astype(str)))
    else:
        with open("output.txt", "a") as file:
            file.write("\n\n")

            # Convert to BF16 tensor
            bf16_arr = tr.tensor(softmax_online(all_arrays[i]), dtype=tr.bfloat16)

            # Get BF16 hex bit patterns
            bf16_bits = bf16_arr.view(tr.uint16)

            # Write BF16 hex values
            #file.write(" ".join([hex(x.item()) for x in bf16_bits]))
            file.write(" ".join([str(x.item()) for x in bf16_arr]))

# for i in range(len(all_arrays)):
#     with open("output.txt", "a") as file:
#         file.write("\n\n")
#        # print("\n\n")
#     if(i == 0):
#         with open("output.txt", "w") as file:
#             file.write(" ".join(softmax_3pass(all_arrays[i]).astype(str)))
#           #  print(" ".join(softmax_3pass(all_arrays[i]).astype(str)))
#     else:
#         with open("output.txt", "a") as file:
           
#             file.write(" ".join(softmax_3pass(all_arrays[i]).astype(str)))
#          #   print(" ".join(softmax_3pass(all_arrays[i]).astype(str)))






# # Convert to a PyTorch tensor with bfloat16 type
# # bf16_tensor = torch.tensor(double_val, dtype=torch.bfloat16)

# # print(bf16_tensor)           # Output: tensor(3.1406, dtype=torch.bfloat16)
# # print(bf16_tensor.item())    # Back to a standard Python float
