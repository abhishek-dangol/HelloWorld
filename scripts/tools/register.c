// Finds how image B must be scaled (x and y separately) to match image A. BMP files, same size.
// Usage: register a.bmp b.bmp   Prints best sx sy tx ty (B sampled at centre + (p-centre)/s + t).
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
static unsigned char *load(const char *path, int *w, int *h) {
    FILE *f = fopen(path, "rb"); if (!f) { perror(path); exit(1); }
    unsigned char hd[54]; fread(hd, 1, 54, f);
    int off = *(int *)(hd + 10); *w = *(int *)(hd + 18); *h = *(int *)(hd + 22);
    int bpp = *(short *)(hd + 28) / 8; int flip = *h > 0; if (*h < 0) *h = -*h;
    fseek(f, off, SEEK_SET);
    int stride = ((*w * bpp + 3) / 4) * 4;
    unsigned char *row = malloc(stride), *g = malloc(*w * *h);
    for (int y = 0; y < *h; y++) {
        fread(row, 1, stride, f);
        int yy = flip ? *h - 1 - y : y;
        for (int x = 0; x < *w; x++) g[yy * *w + x] = (row[x*bpp] + row[x*bpp+1] + row[x*bpp+2]) / 3;
    }
    return g;
}
static double samp(unsigned char *g, int w, int h, double x, double y) {
    if (x < 0 || y < 0 || x > w - 1.001 || y > h - 1.001) return -1;
    int x0 = (int)x, y0 = (int)y; double fx = x - x0, fy = y - y0;
    return g[y0*w+x0]*(1-fx)*(1-fy) + g[y0*w+x0+1]*fx*(1-fy) + g[(y0+1)*w+x0]*(1-fx)*fy + g[(y0+1)*w+x0+1]*fx*fy;
}
int main(int c, char **v) {
    int w, h, w2, h2;
    unsigned char *a = load(v[1], &w, &h), *b = load(v[2], &w2, &h2);
    double best = 1e18, bsx = 1, bsy = 1, btx = 0, bty = 0;
    for (double sx = 0.80; sx <= 1.30; sx += 0.01)
    for (double sy = 0.80; sy <= 1.30; sy += 0.01)
    for (double tx = -6; tx <= 6; tx += 1)
    for (double ty = -6; ty <= 6; ty += 1) {
        double err = 0; int n = 0;
        for (int y = 0; y < h; y += 2) for (int x = 0; x < w; x += 2) {
            double s = samp(b, w, h, w/2.0 + (x - w/2.0)/sx + tx, h/2.0 + (y - h/2.0)/sy + ty);
            if (s < 0) continue; err += fabs(s - a[y*w+x]); n++;
        }
        if (n < w*h/8) continue;
        err /= n;
        if (err < best) { best = err; bsx = sx; bsy = sy; btx = tx; bty = ty; }
    }
    printf("best err %.2f sx %.2f sy %.2f tx %.0f ty %.0f\n", best, bsx, bsy, btx, bty);
    return 0;
}
