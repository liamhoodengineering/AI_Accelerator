import numpy as np

# Create a 16x16 matrix of zeros
matrix = np.zeros((16, 16))

# Or create an identity matrix (1s on the diagonal, 0s elsewhere)
identity_matrix = np.eye(16)



# Generate random integers between 0 and 99 (inclusive of 0, exclusive of 100)
random_matrix_1 = np.random.randint(0, 10, size=(16, 16))
random_matrix_2 = np.random.randint(0, 10, size=(16, 16))

product_matrix_3 = random_matrix_1*random_matrix_2

print(product_matrix_3)