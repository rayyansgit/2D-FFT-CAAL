#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

/* Percentile-based normalization: clips top p% to avoid bright spots
   dominating the range, making edges much more visible */
void normalize_percentile(float* data, unsigned char* out, int n, float pct) {
    /* copy and sort to find percentile value */
    float* tmp = malloc(n * sizeof(float));
    memcpy(tmp, data, n * sizeof(float));
    /* simple selection: find value at (1-pct) percentile */
    /* use partial insertion sort on small sample for speed */
    int idx = (int)((1.0f - pct) * n);
    if (idx >= n) idx = n - 1;
    /* bubble sort is too slow for large n — use min/max with clamp */
    float mn = data[0], mx = data[0];
    for (int i = 1; i < n; i++) {
        if (data[i] < mn) mn = data[i];
        if (data[i] > mx) mx = data[i];
    }
    /* find 98th percentile by histogram approximation */
    int bins = 1000;
    int* hist = calloc(bins, sizeof(int));
    float range = mx - mn;
    if (range == 0.0f) range = 1.0f;
    for (int i = 0; i < n; i++) {
        int b = (int)((data[i] - mn) / range * (bins - 1));
        if (b < 0) b = 0;
        if (b >= bins) b = bins - 1;
        hist[b]++;
    }
    int target = (int)(pct * n);
    int cum = 0;
    float clip_max = mx;
    for (int b = bins - 1; b >= 0; b--) {
        cum += hist[b];
        if (cum >= target) {
            clip_max = mn + (float)b / (bins - 1) * range;
            break;
        }
    }
    free(hist);
    free(tmp);

    float new_range = clip_max - mn;
    if (new_range <= 0.0f) new_range = 1.0f;
    for (int i = 0; i < n; i++) {
        float v = (data[i] - mn) / new_range;

        /* ARTIFACT SUPPRESSION THRESHOLD
           Crush anything below 15% intensity to pure black.
           If valid edges are disappearing, lower this to 0.10f or 0.08f.
           If artifacts are still visible, raise this to 0.18f or 0.20f.
        */
        if (v < 0.15f) {
            v = 0.0f;
        }
        else if (v > 1.0f) {
            v = 1.0f;
        }

        out[i] = (unsigned char)(255.0f * v);
    }
}

int main() {
    FILE *f = fopen("fft_result.bin", "rb");
    if (!f) { fprintf(stderr, "Cannot open fft_result.bin\n"); return 1; }

    int width, height;
    fread(&width,  sizeof(int), 1, f);
    fread(&height, sizeof(int), 1, f);
    printf("Image size: %dx%d\n", width, height);

    int n = width * height;
    float *fft_mag  = malloc(n * sizeof(float));
    float *edge_mag = malloc(n * sizeof(float));
    fread(fft_mag,  sizeof(float), n, f);
    fread(edge_mag, sizeof(float), n, f);
    fclose(f);

    unsigned char *fft_px  = malloc(n);
    unsigned char *edge_px = malloc(n);

    /* FFT spectrum: top 2% clipped — DC spike would otherwise dominate */
    normalize_percentile(fft_mag,  fft_px,  n, 0.02f);
    /* Edge output: top 2% clipped — makes edges bright, suppresses noise */
    normalize_percentile(edge_mag, edge_px, n, 0.02f);

    stbi_write_png("fft_output.png",   width, height, 1, fft_px,  width);
    stbi_write_png("edges_output.png", width, height, 1, edge_px, width);
    printf("Wrote fft_output.png and edges_output.png (%dx%d)\n", width, height);

    free(fft_mag); free(edge_mag);
    free(fft_px);  free(edge_px);
    return 0;
}
