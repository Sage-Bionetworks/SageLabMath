//
//  SBLLabMath.m
//  SageLabMath
//
// Copyright (c) 2015, 2016, Sage Bionetworks. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// 1.  Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// 2.  Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// 3.  Neither the name of the copyright holder(s) nor the names of any contributors
// may be used to endorse or promote products derived from this software without
// specific prior written permission. No license is granted to the trademarks of
// the copyright holders even if such marks are included in this software.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "SBLLabMath.h"
#import "buffer.h"
#import "signalprocessing.h"
#include <stdlib.h>
#include <math.h>
@import Accelerate;

SBLRealArray *zeros(size_t rows, size_t columns)
{
    SBLRealArray *ra = [SBLRealArray new];
    [ra setRows:rows columns:columns];
    memset(ra.data, 0, ra.allocatedSize * ra.typeSize);
    return ra;
}

SBLRealArray *ones(size_t rows, size_t columns)
{
    SBLRealArray *ra = [SBLRealArray new];
    [ra setRows:rows columns:columns];
    double *p = ra.data;
    double *pEnd = p + ra.rows * ra.cols;
    while (p < pEnd) {
        *p++ = 1.0;
    }
    
    return ra;
}

SBLRealArray *NaN(size_t rows, size_t columns)
{
    SBLRealArray *ra = zeros(rows, columns);
    double *p = ra.data;
    double *pEnd = ra.data + rows * columns;
    while (p < pEnd) {
        *p++ = NAN;
    }
    
    return ra;
}

SBLRealArray *sortrows(SBLRealArray *table, size_t column)
{
    SBLRealArray *sorted = [table copy];
    
    if (sorted.cols == 1) {
        // just sort it in place and be done with it
        qsort_b(sorted.data, sorted.rows, sorted.typeSize, ^int(const void *ptr1, const void *ptr2) {
            double v1 = *(double *)ptr1;
            double v2 = *(double *)ptr2;
            return v1 < v2 ? -1 : v1 > v2 ? 1 : 0;
        });
    } else {
        // create a permutation array of row indices--we'll sort this first, then permute the rows
        SBLIntArray *permute = [SBLIntArray new];
        [permute setRows:table.rows columns:1];
        size_t *p = permute.data;
        size_t *pEnd = p + permute.rows;
        size_t index = 0;
        while (p < pEnd) {
            *p++ = index++;
        }
        
        const double *refColumn = sorted.data + sorted.rows * column;
        qsort_b(permute.data, permute.rows, permute.typeSize, ^int(const void *ptr1, const void *ptr2) {
            size_t index1 = *(size_t *)ptr1;
            size_t index2 = *(size_t *)ptr2;
            double v1 = refColumn[index1];
            double v2 = refColumn[index2];
            return v1 < v2 ? -1 : v1 > v2 ? 1 : 0;
        });
        
        // now permute the rows of each column of sorted according to the permutation array
        size_t rows = permute.rows;
        for (size_t column = 0; column < sorted.cols; ++column) {
            // make a copy of the permutation array to work with--we are going to mess with it
            size_t indices[rows];
            memcpy(indices, permute.data, rows * permute.typeSize);
            
            double *coldata = sorted.data + column * rows;
            for (size_t i = 0; i < rows; ++i) {
                // Check if this element needs to be permuted
                size_t iSrc = indices[i];
                if (iSrc == i) {
                    continue; // already where it needs to be--skip
                }
                
                size_t iDst = i;
                double temp = coldata[iDst];
                
                // Follow the permutation cycle
                do {
                    coldata[iDst] = coldata[iSrc];
                    indices[iSrc] = iDst;
                    
                    iDst = iSrc;
                    iSrc = indices[iSrc];
                } while (iSrc != i);
                
                coldata[iDst] = temp;
                indices[iDst] = iDst;
            }
        }
    }
    
    return sorted;
}

inline static double sqr(double x) {
    return x*x;
}

BOOL quadraticFit(int n, const double x[], const double y[], double coeffs[])
{
    double   sumx = 0.0;                        /* sum of x                      */
    double   sumx2 = 0.0;                       /* sum of x**2                   */
    double   sumx3 = 0.0;                       /* sum of x**3                   */
    double   sumx4 = 0.0;                       /* sum of x**4                   */
    double   sumxy = 0.0;                       /* sum of x * y                  */
    double   sumx2y = 0.0;                      /* sum of x**2 * y               */
    double   sumy = 0.0;                        /* sum of y                      */
    
    for (int i=0;i<n;i++)
    {
        sumx   += x[i];
        sumx2  += sqr(x[i]);
        sumx3  += sqr(x[i]) * x[i];
        sumx4  += sqr(sqr(x[i]));
        sumxy  += x[i] * y[i];
        sumx2y += sqr(x[i]) * y[i];
        sumy   += y[i];
    }
    
    double sxx = sumx2 - (sqr(sumx) / n);
    double sxy = sumxy - (sumx * sumy / n);
    double sxx2 = sumx3 - (sumx * sumx2 / n);
    double sx2y = sumx2y - (sumx2 * sumy / n);
    double sx2x2 = sumx4 - (sqr(sumx2) / n);
    
    double denom = sxx * sx2x2 - sqr(sxx2);
    if (denom == 0) {
        // singular matrix. can't solve the problem.
        coeffs[0] = 0;
        coeffs[1] = 0;
        coeffs[2] = 0;
        return NO;
    }
    
    coeffs[0] = (sx2y * sxx - sxy * sxx2) / denom;
    coeffs[1] = (sxy * sx2x2 - sx2y * sxx2) / denom;
    coeffs[2] = sumy / n - coeffs[1] * sumx / n - coeffs[0] * sumx2 / n;
    
    return YES;
}

BOOL linearFit(int n, const double x[], const double y[], double coeffs[])
{
    double   sumx = 0.0;                        /* sum of x                      */
    double   sumx2 = 0.0;                       /* sum of x**2                   */
    double   sumxy = 0.0;                       /* sum of x * y                  */
    double   sumy = 0.0;                        /* sum of y                      */
    double   sumy2 = 0.0;                       /* sum of y**2                   */
    
    for (int i=0;i<n;i++)
    {
        sumx  += x[i];
        sumx2 += sqr(x[i]);
        sumxy += x[i] * y[i];
        sumy  += y[i];
        sumy2 += sqr(y[i]);
    }
    
    double denom = (n * sumx2 - sqr(sumx));
    if (denom == 0) {
        // singular matrix. can't solve the problem.
        coeffs[0] = 0;
        coeffs[1] = 0;
        return NO;
    }
    
    coeffs[0] = (n * sumxy  -  sumx * sumy) / denom;
    coeffs[1] = (sumy * sumx2  -  sumx * sumxy) / denom;
    
    return YES;
}

SBLRealArray *polyfit(SBLRealArray *x, SBLRealArray *y, int order)
{
    // both have to be single dimension vectors (row or col vector doesn't matter)
    if (!(x.rows == 1 || x.cols == 1) || !(y.rows == 1 || y.cols == 1)) {
        return nil;
    }
    
    // both have to be the same size
    size_t numPoints = x.rows * x.cols;
    if (y.rows * y.cols != numPoints) {
        return nil;
    }
    
    SBLRealArray *coeffs = [SBLRealArray new];
    [coeffs setRows:order + 1 columns:1];
    if (order == 1) {
        linearFit((int)numPoints, x.data, y.data, coeffs.data);
    } else if (order == 2) {
        quadraticFit((int)numPoints, x.data, y.data, coeffs.data);
    }
    
    return coeffs;
}

static inline double polyvalForPoint(double x, SBLRealArray *coeffs)
{
    size_t c_size = coeffs.rows * coeffs.cols;
    double *p = coeffs.data;
    double *pEnd = p + c_size;
    double value = *p++;
    while (p < pEnd) {
        value *= x;
        value += *p++;
    }
    
    return value;
}

SBLRealArray *polyval(SBLRealArray *c, SBLRealArray *x)
{
    size_t x_size = x.rows * x.cols;
    
    SBLRealArray *polyval = zeros(x.rows, x.cols);
    const double *p = x.data;
    const double *pEnd = p + x_size;
    double *pDest = polyval.data;
    
    while (p < pEnd) {
        double point = *p++;
        *pDest++ = polyvalForPoint(point, c);
    }
    
    return polyval;
}

SBLRealArray *repmat(SBLRealArray *x, size_t rowsreps, size_t colsreps)
{
    SBLRealArray *reppedmat = [SBLRealArray new];
    [reppedmat setRows:x.rows * rowsreps columns:x.cols * colsreps];
    if (!rowsreps || !colsreps) {
        return reppedmat;
    }
    
    size_t originalRows = x.rows;

    // extend each column rowsreps times
    const double *pSrc = x.data;
    const double *pEnd = pSrc + originalRows;
    double *pDest = reppedmat.data;
    for (size_t col = 0; col < x.cols; ++col) {
        for (size_t rowrep = 0; rowrep < rowsreps; ++rowrep) {
            // copy the original column rowsreps times sequentially.
            // ptr blit is way faster than memcpy function call for smaller numbers of rows,
            // probably reasonably close for larger numbers.
            const double *p = pSrc;
            while (p < pEnd) {
                *pDest++ = *p++;
            }
        }
        // move pSrc, pEnd for the next column
        pSrc = pEnd;
        pEnd += originalRows;
    }
    
    // now replicate the whole shebang colsreps times
    double *pSrcAll = reppedmat.data;
    const size_t reppedRowsSize = reppedmat.rows * x.cols;
    const size_t wholeShebang = reppedRowsSize * reppedmat.typeSize;
    double *pDestAll = pSrcAll + reppedRowsSize;
    for (size_t colrep = 1; colrep < colsreps; ++colrep) {
        // this is more likely to involve copying a larger amount of data a smaller number of times,
        // which is where memcpy really shines.
        memcpy(pDestAll, pSrcAll, wholeShebang);
        pDestAll += reppedRowsSize;
    }
    
    return reppedmat;
}

double quantileForColumn(SBLRealArray *column, double p)
{
    SBLRealArray *sorted = sortrows(column, 1);
    size_t n = column.rows;
    double indexish = p * n - 0.5;
    if (indexish < 0.0) {
        return sorted.data[0];
    }
    if (indexish >= n - 1.0) {
        return sorted.data[n - 1];
    }
    if (indexish == floor(indexish)) {
        return sorted.data[(size_t)indexish];
    }
    
    // it's between two values, so do a linear interpolation
    size_t lower = floor(indexish);
    size_t higher = indexish + 1;
    double betwixt = indexish - lower;
    double xLower = sorted.data[lower];
    double xHigher = sorted.data[higher];
    double value = xLower + betwixt * (xHigher - xLower);
    return value;
}

SBLRealArray *quantile(SBLRealArray *x, double p)
{
    SBLRealArray *quantile = [SBLRealArray new];
    SBLRealArray *array = x;
    
    if (x.rows == 1) {
        // just transpose it to a column vector by switching the dimensions
        [quantile setRows:1 columns:1];
        SBLRealArray *xPrime = [x copy];
        xPrime.rows = x.cols;
        xPrime.cols = x.rows;
        array = xPrime;
    }
    [quantile setRows:1 columns:array.cols];
    
    double *pDest = quantile.data;
    for (size_t col = 0; col < array.cols; ++col) {
        SBLRealArray *column = [array subarrayWithRows:NSMakeRange(0, array.rows) columns:NSMakeRange(col, 1)];
        *pDest++ = quantileForColumn(column, p);
    }
    
    return quantile;
}

SBLRealArray *buffer(SBLRealArray *x, size_t n, size_t p)
{
    size_t sizex = MAX(x.rows, x.cols);
    size_t buflen = (sizex + n - 1) / n;
    SBLRealArray *buffer = zeros(n, buflen);
    buffer_overlap(buffer.data, x.data, sizex, n, p);
    return buffer;
}

SBLRealArray *linspace(double start, double end, size_t n)
{
    SBLRealArray *linspace = [SBLRealArray new];
    [linspace setRows:1 columns:n];
    vDSP_vgenD(&start, &end, linspace.data, 1, n);
    return linspace;
}

SBLRealArray *hamming(size_t windowSize)
{
    SBLRealArray *hammingWindow = [SBLRealArray new];
    [hammingWindow setRows:windowSize columns:1];
    sp_hamming(hammingWindow.data, windowSize);
    return hammingWindow;
}

SBLRealArray *hanning(size_t windowSize)
{
    SBLRealArray *hanningWindow = [SBLRealArray new];
    [hanningWindow setRows:windowSize columns:1];
    sp_hanning(hanningWindow.data, windowSize);
    return hanningWindow;
}

SBLComplexArray *specgram(SBLRealArray *x, size_t windowSize, double samplingRate, SBLRealArray *window, size_t overlap, SBLRealArray **freqs, SBLRealArray **times)
{
    SBLComplexArray *specgram = [SBLComplexArray new];
    size_t framestep = windowSize - overlap;
    size_t bins = ((double)windowSize / 2.0 + 1.0);
    size_t length_xzp = MAX(x.rows, x.cols);
    size_t frames = (length_xzp - overlap) / framestep;
    [specgram setRows:bins columns:frames];
    *freqs = zeros(bins,1);
    *times = zeros(frames,1);

    spectrogram(specgram.data, (*freqs).data, (*times).data, x.data, x.rows * x.cols, window.data, overlap, windowSize, samplingRate);
    return specgram;
}

inline static double interpLinear(double xLo, double xHi, double vLo, double vHi, double thisx)
{
    if (vLo == vHi) {
        return vLo;
    }
    
    double ratio = (thisx - xLo) / (xHi - xLo);
    return (1.0 - ratio) * vLo + ratio * vHi;
}

inline static double interpSpline(double a, double b, double c, double d, double x, double thisx)
{
    double deltax = thisx - x;
    double value = d * deltax;
    value += c;
    value *= deltax;
    value += b;
    value *= deltax;
    value += a;
    return value;
}

void tridiag(double *A, double *B, double *C, double *D, size_t len)
{
    int i;
    double b, *F;
    
    F = (double *)calloc(len, sizeof(double));
    
    // Gaussian elimination; forward substitution
    b = B[0];
    D[0] = D[0] / b;
    for (i = 1; i < len; ++i) {
        F[i] = C[i - 1] / b;
        b = B[i] - A[i] * F[i];
        if (b == 0.0) {
            // oops, guess we'll get NaNs
        }
        D[i] = (D[i] - D[i - 1] * A[i]) / b;
    }
    
    // back substitution
    for (i = (int)len - 2; i >= 0; --i) {
        D[i] -= (D[i + 1] * F[i + 1]);
    }
    
    free(F);
}

void getYD(const double *X, const double *Y, double *YD, size_t len)
{
    int i;
    double h0, h1, r0, r1, *A, *B, *C;
    
    // allocate mem for tridiagonal bands A, B, C
    A = (double *)calloc(len, sizeof(double));
    B = (double *)calloc(len, sizeof(double));
    C = (double *)calloc(len, sizeof(double));
    
    // init first row
    h0 = X[1] - X[0];
    h1 = X[2] - X[1];
    r0 = (Y[1] - Y[0]) / h0;
    r1 = (Y[2] - Y[1]) / h1;
    B[0] = h1 * (h0 + h1);
    C[0] = (h0 + h1) * (h0 + h1);
    YD[0] = r0 * (3.0 * h0 * h1 + 2.0 * h1 * h1) + r1 * h0 * h0;
    
    // init tridiagonal bands and vector YD
    for (i = 1; i < len - 1; ++i) {
        h0 = X[i] - X[i - 1];
        h1 = X[i + 1] - X[i];
        r0 = (Y[i] - Y[i - 1]) / h0;
        r1 = (Y[i + 1] - Y[i]) / h1;
        A[i] = h1;
        B[i] = 2.0 * (h0 + h1);
        C[i] = h0;
        YD[i] = 3.0 * (r0 * h1 + r1 * h0);
    }
    
    // last row
    A[i] = (h0 + h1) * (h0 + h1);
    B[i] = h0 * (h0 + h1);
    YD[i] = r0 * h1 * h1 + r1 * (3.0 * h0 * h1 + 2.0 * h0 * h0);
    
    // solve for the tridiagonal matrix: YD = YD * (tridiag matrix)'
    tridiag(A, B, C, YD, len);
    
    free(A);
    free(B);
    free(C);
    
}

void interpSplineForColumn(double *outColumn, const double *inColumnX, const double *inColumnY, const double *inQueryPts, size_t sampleRows, size_t queryRows)
{
    int i, j;
    double *YD, A0 = 0.0, A1 = 0.0, A2 = 0.0, A3 = 0.0, dx, dy, p1 = 0.0, p2 = 0.0, p3;
    
    // compute 1st derivatives at each point -> YD
    YD = (double *)calloc(sampleRows, sizeof(double));
    getYD(inColumnX, inColumnY, YD, sampleRows);
    
    // p1 is left endpoint of interval
    // p2 is query point
    // p3 is right endpoint of interval
    // j is input index for current interval
    p3 = inQueryPts[0] - 1.0; // force coeff init the first time through the loop
    for (i = j = 0; i < queryRows; ++i) {
        // see if we're in a new interval
        p2 = inQueryPts[i];
        if (p2 > p3) {
            // find the interval containing p2
            for (; j < sampleRows && p2 > inColumnX[j]; ++j);
            if (p2 < inColumnX[j]) {
                --j;
            }
            p1 = inColumnX[j];
            p3 = inColumnX[j + 1];
            
            // compute the spline coefficients
            dx = 1.0 / (inColumnX[j + 1] - inColumnX[j]);
            dy = (inColumnY[j+1] - inColumnY[j]) * dx;
            A0 = inColumnY[j];
            A1 = YD[j];
            A2 = dx * (3.0 * dy - 2.0 * YD[j] - YD[j + 1]);
            A3 = dx * dx * (-2.0 * dy + YD[j] + YD[j + 1]);
        }
        
        outColumn[i] = interpSpline(A0, A1, A2, A3, p1, p2);
    }
    free(YD);
}

void interpLinearForColumn(double *outColumn, const double *inColumnX, const double *inColumnY, const double *inQueryPts, size_t sampleRows, size_t queryRows)
{
    double *pOut = outColumn;
    const double *pX = inColumnX;
    const double *pY = inColumnY;
    const double *pQ = inQueryPts;
    const double *pEndQ = pQ + queryRows;
    const double *pEndX = pX + sampleRows;
    
    // *pQ is guaranteed to be >= inColumnX[0] and <= inColumnX[end]
    while (pQ < pEndQ) {
        while (*pX < *pQ && pX < pEndX) {
            ++pX;
            ++pY;
        }
        if (*pQ == *pX) {
            // landed on one--no need to interpolate
            *pOut++ = *pY;
        } else {
            // we passed it
            *pOut++ = interpLinear(*(pX - 1), *pX, *(pY - 1), *pY, *pQ);
        }
        ++pQ;
    }
}

void interpForColumn(double *outColumn, const double *inColumnX, const double *inColumnY, const double *inQueryPts, size_t sampleRows, size_t queryRows, double extrap, SBLInterp1Method method)
{
    // assume the input x and query pts are both in monotonically increasing order
    double *pOut = outColumn;
    const double *pQ = inQueryPts;
    const double * const pEndQ = pQ + queryRows;
    const double rangeLo = inColumnX[0];
    const double rangeHi = inColumnX[sampleRows - 1];
    
    size_t interpRows = queryRows;
    // fill in any out-of-range-below with extrapolation value
    while (*pQ < rangeLo && pQ < pEndQ) {
        *pOut++ = extrap;
        ++pQ;
        --interpRows;
    }
    
    // same for above
    const double *pQHi = inQueryPts + queryRows - 1;
    const double * const pQHiEnd = pQ;
    double *pOutHi = outColumn + queryRows - 1;
    while (*pQHi > rangeHi && pQHi >= pQHiEnd) {
        *pOutHi-- = extrap;
        --pQHi;
        --interpRows;
    }
    
    // now just interpolate the part that's in range
    if (method == SBLInterp1MethodSpline) {
        interpSplineForColumn(pOut, inColumnX, inColumnY, pQ, sampleRows, interpRows/*, outStride*/);
    } else {
        interpLinearForColumn(pOut, inColumnX, inColumnY, pQ, sampleRows, interpRows/*, outStride*/);
    }
}

SBLRealArray *interp1(SBLRealArray *x, SBLRealArray *v, SBLRealArray *xq, SBLInterp1Method method, double extrapolation)
{
    SBLRealArray *interp = [SBLRealArray new];
    if (!x || !x.data || !v || !v.data || !xq || !xq.data) {
        return interp;
    }
    size_t querySize = MAX(xq.rows, xq.cols);
    size_t cols = v.rows == 1 ? 1 : v.cols; // number of sample Y value data sets
    
    [interp setRows:querySize columns:cols];
    size_t sampleSizes = v.rows;
    size_t stride = sampleSizes;
    
    double *pOut = interp.data;
    const double *pX = x.data;
    const double *pY = v.data;
    const double *pYEnd = pY + v.rows * v.cols;
    const double *pQ = xq.data;
    while (pY < pYEnd) {
        interpForColumn(pOut, pX, pY, pQ, sampleSizes, querySize, extrapolation, method);
//        ++pOut; // going down the rows of the first column as the starting point for output
        pOut += querySize;
        pY += stride;
    }
    
    return interp;
}
/*
SBLRealArray *interp1X(SBLRealArray *x, SBLRealArray *v, SBLRealArray *xq, SBLInterp1Method method, double extrapolation)
{
    emxArray_real_T *y;
    int low_i;
    int mid_i;
    emxArray_real_T *x;
    size_t nycols;
    size_t nx;
    unsigned int outsize_idx_0;
    unsigned int outsize_idx_1;
    int k;
    emxArray_real_T *pp_breaks;
    emxArray_real_T *pp_coefs;
    emxArray_real_T *yit;
    emxArray_real_T *b_y;
    int32_T exitg1;
    int low_ip1;
    double xloc;
    int nxi;
    int elementsPerPage;
    int coefStride;
    int icp;
    
    SBLRealArray *y = [v copy];
    SBLRealArray *x2 = [x copy];
    SBLRealArray *interp = zeros(xq.rows, v.cols);
    nycols = v.cols;
    nx = x.rows;
//    outsize_idx_0 = (unsigned int)xq->size[0];
//    outsize_idx_1 = (unsigned int)v->size[1];
//    low_i = interp->size[0] * interp->size[1];
//    interp->size[0] = (int)outsize_idx_0;
//    emxEnsureCapacity((emxArray__common *)interp, low_i, (int)sizeof(double));
//    low_i = interp->size[0] * interp->size[1];
//    interp->size[1] = (int)outsize_idx_1;
//    emxEnsureCapacity((emxArray__common *)interp, low_i, (int)sizeof(double));
//    mid_i = (int)outsize_idx_0 * (int)outsize_idx_1;
//    for (low_i = 0; low_i < mid_i; low_i++) {
//        interp->data[low_i] = 0.0;
//    }
//    
//    if (xq->size[0] == 0) {
//    } else {
    if (xq.rows == 0) {
        return interp;
    }
    
    size_t k = 1;
    SBLRealArray *yprime;
    
    BOOL done = NO;
    do {
        if (k < nx) {
            if (isnan(x.data[k - 1])) {
                done = YES;
            } else {
                ++k;
            }
        } else {
            if (x.rows < x.cols) {
                size_t midcol = nx >> 1;
                for (size_t row = 0; row < midcol; ++row) {
                    double temp = x2.data[row];
                    x2.data[row] = x2.data[nx - row - 1];
                    x2.data[nx - row - 1] = temp;
                }
                
                [y flipud];
            }
            
            yprime = [y transpose];
            
        }
    } while (!done);
    
    
        k = 1;
        emxInit_real_T(&pp_breaks, 2);
        c_emxInit_real_T(&pp_coefs, 3);
        b_emxInit_real_T(&yit, 1);
        emxInit_real_T(&b_y, 2);
        do {
            exitg1 = 0;
            if (k <= nx) {
                if (rtIsNaN(x->data[k - 1])) {
                    exitg1 = 1;
                } else {
                    k++;
                }
            } else {
                if (x->data[1] < x->data[0]) {
                    low_i = nx >> 1;
                    for (low_ip1 = 1; low_ip1 <= low_i; low_ip1++) {
                        xloc = x2->data[low_ip1 - 1];
                        x2->data[low_ip1 - 1] = x2->data[nx - low_ip1];
                        x2->data[nx - low_ip1] = xloc;
                    }
                    
                    flip(y);
                }
                
                nxi = xq->size[0];
                low_i = b_y->size[0] * b_y->size[1];
                b_y->size[0] = y->size[1];
                b_y->size[1] = y->size[0];
                emxEnsureCapacity((emxArray__common *)b_y, low_i, (int)sizeof(double));
                mid_i = y->size[0];
                for (low_i = 0; low_i < mid_i; low_i++) {
                    low_ip1 = y->size[1];
                    for (nx = 0; nx < low_ip1; nx++) {
                        b_y->data[nx + b_y->size[0] * low_i] = y->data[low_i + y->size[0] *
                                                                       nx];
                    }
                }
                
                spline(x, b_y, pp_breaks, pp_coefs);
                for (k = 0; k + 1 <= nxi; k++) {
                    if (rtIsNaN(xq->data[k])) {
                        for (nx = 1; nx <= nycols; nx++) {
                            interp->data[(nx - 1) * nxi + k] = rtNaN;
                        }
                    } else {
                        if ((xq->data[k] >= x2->data[0]) && (xq->data[k] <=
                                                                    x2->data[x2->size[0] - 1])) {
                            xloc = xq->data[k];
                            elementsPerPage = pp_coefs->size[0];
                            coefStride = pp_coefs->size[0] * (pp_breaks->size[1] - 1);
                            low_i = yit->size[0];
                            yit->size[0] = pp_coefs->size[0];
                            emxEnsureCapacity((emxArray__common *)yit, low_i, (int)sizeof
                                              (double));
                            if (rtIsNaN(xq->data[k])) {
                                for (nx = 1; nx <= elementsPerPage; nx++) {
                                    yit->data[nx - 1] = xloc;
                                }
                            } else {
                                low_i = 1;
                                low_ip1 = 2;
                                nx = pp_breaks->size[1];
                                while (nx > low_ip1) {
                                    mid_i = (low_i >> 1) + (nx >> 1);
                                    if (((low_i & 1) == 1) && ((nx & 1) == 1)) {
                                        mid_i++;
                                    }
                                    
                                    if (xloc >= pp_breaks->data[mid_i - 1]) {
                                        low_i = mid_i;
                                        low_ip1 = mid_i + 1;
                                    } else {
                                        nx = mid_i;
                                    }
                                }
                                
                                icp = (low_i - 1) * pp_coefs->size[0];
                                xloc = xq->data[k] - pp_breaks->data[low_i - 1];
                                for (nx = 0; nx + 1 <= elementsPerPage; nx++) {
                                    yit->data[nx] = pp_coefs->data[icp + nx];
                                }
                                
                                for (mid_i = 2; mid_i <= pp_coefs->size[2]; mid_i++) {
                                    low_ip1 = icp + (mid_i - 1) * coefStride;
                                    for (nx = 0; nx + 1 <= elementsPerPage; nx++) {
                                        yit->data[nx] = xloc * yit->data[nx] + pp_coefs->
                                        data[low_ip1 + nx];
                                    }
                                }
                            }
                            
                            for (nx = 0; nx + 1 <= nycols; nx++) {
                                interp->data[nx * nxi + k] = yit->data[nx];
                            }
                        }
                    }
                }
                
                exitg1 = 1;
            }
        } while (exitg1 == 0);
        
//        emxFree_real_T(&b_y);
//        emxFree_real_T(&yit);
//        emxFree_real_T(&pp_coefs);
//        emxFree_real_T(&pp_breaks);
//    }
//    
//    emxFree_real_T(&x);
//    emxFree_real_T(&y);
}
 */
