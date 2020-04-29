#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "../timerc.h"

/*--------------------------------------------------------------
 *    Lower Triangular Matrix Inverse
 *    CPU Iterative, CPU MAT MULT
 *    Solves Lower Triangle System of Equations

 *    Author: Roger Wang
 *-------------------------------------------------------------- */

// Helper Functions
void printSubMat(double *a, int idx, int size, int n, const char *title) {
    printf("%s\n", title);
    for (int i = 0; i < size; ++i) {
        for (int j = 0; j < size; ++j) {
            int local_idx = idx + i * n + j;
            printf("%5.2f ", a[local_idx]);
        }
        printf("\n");
    }
    printf("\n");
}

void printMat(double *a, int n, const char *title) {
    printf("%s\n", title);
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            printf("%5.2f ", a[i * n + j]);
        }
        printf("\n");
    }
    printf("\n\n");
}

void printVec(double *b, int n, const char *title) {
    printf("%s\n", title);
    for (int i = 0; i < n; i++) {
        printf("%5.2f ", b[i]);
    }
    printf("\n");
}

double *initMat(int n) {
    double *a = (double *)malloc(n * n * sizeof(double));
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            if (i >= j)
                a[i * n + j] = rand() / (double)RAND_MAX;
            else
                a[i * n + j] = 0;
        }
    }
    return a;
}

double *initVec(int n) {
    double *b = (double *)malloc(n * sizeof(double));
    for (int i = 0; i < n; i++) {
        b[i] = rand() / (double)RAND_MAX;
    }
    return b;
}

void copyMat(double *newA, double *a, int idx, int size, int n) {
    for (int i = 0; i < size; ++i) {
        for (int j = 0; j < size; ++j) {
            int local_idx = idx + i * n + j;
            a[local_idx] = newA[i * size + j];
        }
    }
}

void multMat(double *a, int idx_1, int idx_2, int size, int n, double *res) {
    for (int i = 0; i < size; i++) {
        for (int j = 0; j < size; j++) {
            res[i * size + j] = 0;
            for (int k = 0; k < size; k++)
                res[i * size + j] += a[idx_1 + i * n + k] * a[idx_2 + k * n + j];
        }
    }
}

void multMatVec(double *a, double *b, double *x, int n) {
    for (int i = 0; i < n; i++) {
        x[i] = 0;
        for (int j = 0; j < n; j++) {
            x[i] += a[i * n + j] * b[j];
        }
    }
}

void checkInverse(double *a, double *a_inv, double *res, int n) {
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            res[i * n + j] = 0.0;
            for (int k = 0; k < n; k++)
                res[i * n + j] += a[i * n + k] * a_inv[k * n + j];
        }
    }
}

void addNegative(double *a, int idx, int size, int n) {
    for (int i = 0; i < size; ++i) {
        for (int j = 0; j < size; ++j) {
            int local_idx = idx + i * n + j;
            a[local_idx] = -1 * a[local_idx];
        }
    }
}

// Base Case 2x2 Inplace inversion
__host__ __device__ void invertTwoByTwo(double *a, int idx, int n) {
    int idx0 = idx;
    int idx1 = idx + 1;
    int idx2 = idx + n;
    int idx3 = idx + n + 1;
    double det = a[idx0] * a[idx3] - a[idx2] * a[idx1];
    double temp;
    temp = a[idx3];
    a[idx3] = a[idx0];
    a[idx0] = temp;
    a[idx2] = -a[idx2];
    a[idx1] = -a[idx1];

    a[idx0] *= (1 / det);
    a[idx1] *= (1 / det);
    a[idx2] *= (1 / det);
    a[idx3] *= (1 / det);
}

void invertHelper(double *a, int idx, int size, int n) {
    // Base Case: Invert if a is a simple 2x2 matrix
    if (size == 2) {
        invertTwoByTwo(a, idx, n);
        return;
    }

    // Calculate starting index for the 3 submatrices
    int a11_idx = idx;                            // upper left submatrix
    int a22_idx = idx + size / 2 * n + size / 2;  // lower right submatrix
    int a21_idx = idx + size / 2 * n;             // bottom left full submatrix

    // Invert A21
    double *res = (double *)malloc(size * size * sizeof(double));
    multMat(a, a22_idx, a21_idx, size / 2, n, res);  // A22 * A21
    copyMat(res, a, a21_idx, size / 2, n);           // Put result into A21
    multMat(a, a21_idx, a11_idx, size / 2, n, res);  // A21 * A11
    copyMat(res, a, a21_idx, size / 2, n);           // Put result into A21
    addNegative(a, a21_idx, size / 2, n);            // Add negative sign to A21
    free(res);
}

void invertBottomUp(double *a, int n) {
    int total_iter = log2(n);
    for (int iter = 0; iter < total_iter; iter++) {
        int total_ops = pow(2, total_iter - iter - 1);
        for (int op_idx = 0; op_idx < total_ops; op_idx++) {
            int block_size = n / total_ops;
            int inv_idx = op_idx * ((n * n / total_ops) + block_size);
            // printf("Inv_idx: %d Block Size: %d\n", inv_idx, block_size);
            invertHelper(a, inv_idx, block_size, n);
        }
    }
}

int main() {
    float cpu_time;
    int n = pow(2, 10);  // Matrix size: 2^x = n
    double *a, *a_old, *b, *b_old;
    double *x = (double *)malloc(n * sizeof(double));
    a = initMat(n);
    a_old = initMat(n);
    b = initVec(n);
    b_old = initVec(n);

    // printMat(a, n, "Initial Matrix:");
    cstart();
    invertBottomUp(a, n);
    cend(&cpu_time);
    printf("CPU matrix inverse time: %f\n", cpu_time);
    // printMat(a, n, "Inverted Matrix:");

    // Double check matrix inversion
    // double *res = (double *)malloc(n * n * sizeof(double));
    // checkInverse(a_old, a, res, n);
    // printMat(res, n, "A * A^-1 (should be identity mat):");
    // free(res);

    // Get Solution
    // multMatVec(a, b_old, x, n);
    // printVec(x, n, "x: (Solution)");
    // Check Solution
    // multMatVec(a_old, x, b, n);
    // printVec(b_old, n, "original b:");
    // printVec(b, n, "solved b:");

    free(x);
    free(a);
    free(a_old);
    free(b);
    free(b_old);
    return 0;
}
