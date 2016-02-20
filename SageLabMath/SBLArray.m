//
//  SBLArray.m
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

#import "SBLArray.h"
#import "SBLLabMath.h"
#import "signalprocessing.h"
@import Accelerate;

#pragma mark - SBLArray

@interface SBLArray()

@property (nonatomic, assign) void *data;

@end

@implementation SBLArray

- (instancetype)init
{
    if (self = [super init]) {
        _rows = 0;
        _cols = 0;
        _allocatedSize = 0;
        _data = NULL;
    }

    return self;
}

- (size_t)typeSize
{
    return 1; // subclasses *must* override
}

- (void)reallocToSize:(size_t)newSize
{
    size_t typeSize = self.typeSize;
    size_t newBytes = newSize * typeSize;
    _data = reallocf(_data, newBytes);
    
    if (_data) {
#define DEBUG_UNINITIALIZED_ARRAYS 0
#if DEBUG_UNINITIALIZED_ARRAYS
        size_t addedSize = newSize - _allocatedSize;
        if (addedSize > 0) {
            // garbage out the newly allocated part so it will cause problems if used before being set
            double *p = (double *)(_data + _rows * _cols * typeSize);
            double *pEnd = p + newBytes / sizeof(double);
            while (p < pEnd) {
                *p++ = NAN;
            }
        }
#endif
        _allocatedSize = newSize;
    } else {
        _allocatedSize = 0;
    }
    
    if (newSize && !_data) {
        NSLog(@"Failed to allocate %lu bytes for %@", newBytes, NSStringFromClass([self class]));
    }
}

- (BOOL)setRows:(size_t)rows columns:(size_t)columns
{
    size_t required = rows * columns;
    
    // if we didn't allocate _data, don't mess with it; the caller had just better know what they're doing
    BOOL ours = !_data || _allocatedSize;
    
    if (!required) {
        if (_data && _allocatedSize) {
            free(_data);
        }
        _data = NULL;
    } else if (ours) {
        // minimum allocation granularity is 16 bytes
        size_t minSize = 16 / self.typeSize;
        required = MAX(minSize, required);
        if (_allocatedSize < required) {
            size_t newSize = _allocatedSize << 1;
            if (!newSize) {
                newSize = minSize;
            }
            while (newSize < required) {
                newSize <<= 1;
            }
            
            [self reallocToSize:newSize];
        } else if (_allocatedSize >> 1 >= required) {
            size_t newSize = _allocatedSize >> 1;
            while (newSize > required) {
                newSize >>= 1;
            }
            if (newSize < required) {
                newSize <<= 1;
            }
            
            [self reallocToSize:newSize];
        }
    }
    
    if (_data || !required) {
        _rows = rows;
        _cols = columns;
    }
    
    return (_data || !required);
}

- (BOOL)isVector
{
    return _rows == 1 || _cols == 1;
}

- (BOOL)isempty
{
    return _rows == 0 || _cols == 0;
}

- (size_t)length
{
    if (self.isempty) {
        return 0;
    }
    return MAX(_rows, _cols);
}

- (BOOL)concatenateColumnVectors:(NSArray *)arrays
{
    if (self.cols > 1) {
        return NO;
    }
    
    size_t totalSize = _rows;
    for (SBLArray *array in arrays) {
        if (array.cols > 1) {
            return NO;
        }
        totalSize +=  array.rows * array.cols;
    }
    
    size_t offsetToNew = _rows * _cols * self.typeSize;
    BOOL canDo = [self setRows:totalSize columns:1];
    char *p = (char *)_data + offsetToNew;
    if (canDo) {
        for (SBLArray *array in arrays) {
            size_t addedBytes = array.rows * array.cols * array.typeSize;
            memcpy(p, (char *)array.data, addedBytes);
            p += addedBytes;
        }
        _rows = totalSize;
    }
    
    return canDo;
}

- (BOOL)addColumns:(NSArray *)arrays
{
    // make sure they're all the right size
    size_t rows = _rows;
    for (SBLArray *array in arrays) {
        if (!rows) {
            rows = array.rows;
        }
        if (array.rows != rows) {
            return NO;
        }
        if (array.cols != 1) {
            return NO;
        }
    }
    
    size_t totalCols = _cols + arrays.count;
    size_t totalRows = rows;
    
    // Matlab uses column-major order; we're going to follow their convention to avoid confusion in the conversion
    BOOL canDo = [self concatenateColumnVectors:arrays];
    _rows = totalRows;
    _cols = totalCols;
    
    return canDo;
}

- (instancetype)copy
{
    SBLArray *copy = [[self class] new];
    [copy setRows:_rows columns:_cols];
    memcpy(copy.data, _data, _rows * _cols * self.typeSize);
    
    return copy;
}

- (instancetype)subarrayWithRows:(NSRange)rows columns:(NSRange)columns
{
    SBLArray *subarray = [[self class] new];
    [subarray setRows:rows.length columns:columns.length];
    char *pDest = (char *)subarray.data;
    size_t destStride = subarray.rows * subarray.typeSize;
    size_t endCol = columns.length + columns.location;
    char *p = (char *)_data + self.typeSize * (_rows * columns.location + rows.location);
    size_t srcStride = self.typeSize * self.rows;
    size_t colHeight = self.typeSize * rows.length;
    for (size_t col = columns.location; col < endCol; ++col) {
        memcpy(pDest, p, colHeight);
        p += srcStride;
        pDest += destStride;
    }
    
    return subarray;
}

- (instancetype)subarrayWithRowIndices:(SBLIntArray *)rows columnIndices:(SBLIntArray *)columns
{
    SBLArray *subarray = [[self class] new];
    size_t rowsSize = rows.rows * rows.cols;
    size_t colsSize = columns.rows * columns.cols;
    [subarray setRows:rowsSize columns:colsSize];
    char *pDest = (char *)subarray.data;
    
    const ssize_t *pColIdxs = columns.data;
    size_t typeSize = self.typeSize;
    
    for (size_t col = 0; col < colsSize; ++col) {
        size_t colIdx = *pColIdxs++ - 1;
        const ssize_t *pRowIdxs = rows.data;
        
        for (size_t row = 0; row < rowsSize; ++row) {
            size_t rowIdx = *pRowIdxs++ - 1; // because Matlab uses quaint one-based indexing
            char *pSrc = (char *)_data + (colIdx * _rows + rowIdx) * typeSize;
            blit(pDest, pSrc, typeSize);
            pDest += typeSize;
        }
    }
    
    return subarray;
}

- (void)setSubarrayRows:(NSRange)rows columns:(NSRange)columns fromArray:(SBLArray *)array
{
    // make sure the types match
    if ([self class] != [array class]) {
        return; // no match, silently fail
    }
    
    // make sure all dimensions are suitable
    if (rows.length != array.rows || columns.length != array.cols || rows.length > self.rows || columns.length > self.cols) {
        // invalid operation attempted; again, silently fail because that's ALWAYS a good idea
        return;
    }
    
    size_t endOfCols = columns.location + columns.length;
    size_t arrayStride = rows.length * self.typeSize;
    const char *pSrc = array.data;
    for (size_t column = columns.location; column < endOfCols; ++column) {
        char *pDest = _data + (column * _rows + rows.location) * self.typeSize;
        blit(pDest, pSrc, arrayStride);
        pSrc += arrayStride;
    }
}

- (void)setElementsWithRowIndices:(SBLIntArray *)rows columnIndices:(SBLIntArray *)columns fromArray:(SBLArray *)array
{
    // make sure the types match
    if ([self class] != [array class]) {
        return; // no match, silently fail
    }
    
    // make sure all dimensions are suitable
    size_t rowsSize = rows.rows * rows.cols;
    size_t colsSize = columns.rows * columns.cols;
    if (rowsSize * colsSize != array.rows * array.cols) {
        // invalid operation attempted; again, silently fail because that's ALWAYS a good idea
        return;
    }
    
    const ssize_t *pColIdxs = columns.data;
    size_t typeSize = self.typeSize;
    const char *pSrc = array.data;
    
    for (size_t col = 0; col < colsSize; ++col) {
        size_t colIdx = *pColIdxs++ - 1;
        const ssize_t *pRowIdxs = rows.data;
        
        for (size_t row = 0; row < rowsSize; ++row) {
            size_t rowIdx = *pRowIdxs++ - 1;
            char *pDest = (char *)_data + (colIdx * _rows + rowIdx) * typeSize;
            blit(pDest, pSrc, typeSize);
            pSrc += typeSize;
        }
    }
}

- (SBLIntArray *)find
{
    SBLIntArray *found = [SBLIntArray new];
    
    // make it plenty big enough to start with
    size_t totals = _rows * _cols;
    size_t typeSize = self.typeSize;
    [found setRows:totals columns:1];
    char *p = _data;
    char *pEnd = p + totals * typeSize;
    ssize_t *pDest = found.data;
    size_t numFound = 0;
    while (p < pEnd) {
        if (![self isZero:p]) {
            *pDest++ = (p - (char *)_data) / typeSize + 1;
            ++numFound;
        }
        p += typeSize;
    }
    
    [found setRows:numFound columns:1];
    return found;
}

- (SBLIntArray *)findFirst:(size_t)howMany
{
    SBLIntArray *found = [SBLIntArray new];
    [found setRows:howMany columns:1];
    
    size_t totals = _rows * _cols;
    size_t typeSize = self.typeSize;
    char *p = _data;
    char *pEnd = p + totals * typeSize;
    ssize_t *pDest = found.data;
    size_t numFound = 0;
    while (p < pEnd && numFound < howMany) {
        if (![self isZero:p]) {
            *pDest++ = (p - (char *)_data) / typeSize + 1;
            ++numFound;
        }
        p += typeSize;
    }
    
    [found setRows:numFound columns:1];
    return found;
}

- (SBLIntArray *)findLast:(size_t)howMany
{
    SBLIntArray *found = [SBLIntArray new];
    [found setRows:howMany columns:1];
    
    size_t totals = _rows * _cols;
    size_t typeSize = self.typeSize;
    char *pEnd = _data ;
    char *p = pEnd + (totals - 1) * typeSize;
    ssize_t *pDest = found.data;
    size_t numFound = 0;
    while (p >= pEnd && numFound < howMany) {
        if (![self isZero:p]) {
            *pDest++ = (p - (char *)_data) / typeSize + 1;
            ++numFound;
        }
        p -= typeSize;
    }
    
    [found setRows:numFound columns:1];
    return found;
}

- (instancetype)elementsWithIndices:(SBLIntArray *)indexArray
{
    SBLArray *elements = [[self class] new];
    size_t rows = indexArray.rows;
    size_t cols = 1;
    if (rows == 1) {
        rows = indexArray.cols;
    }
    [elements setRows:rows columns:cols];
    
    const ssize_t *pIdx = indexArray.data;
    const ssize_t *pEnd = pIdx + rows;
    const char *source = _data;
    char *pDest = elements.data;
    size_t destStride = elements.typeSize;
    while (pIdx < pEnd) {
        size_t index = *pIdx++ - 1;
        blit(pDest, source + index * destStride, destStride);
        pDest += destStride;
    }
    
    return elements;
}

- (void)setElementsWithIndices:(SBLIntArray *)indexArray fromArray:(SBLArray *)array
{
    // array type must match self
    if ([self class] != [array class]) {
        return;
    }
    
    // do nothing if either is empty
    if (!(indexArray.rows && indexArray.cols && array.rows && array.cols)) {
        return;
    }
    
    // make sure they're the same sizes (though if they're both vectors, don't care whether row or column)
    if ((indexArray.rows * indexArray.cols != array.rows * array.cols) ||
        (!([indexArray isVector] && [array isVector]) && (indexArray.rows != array.rows || indexArray.cols != array.cols))) {
        // not suitable for assignment
        return;
    }
    
    size_t stride = self.typeSize;
    const char *pSrc = array.data;
    const ssize_t *pIdx = indexArray.data;
    const ssize_t *endIdx = pIdx + indexArray.rows * indexArray.cols;
    const size_t mySize = _rows * _cols;
    while (pIdx < endIdx) {
        size_t index = *pIdx++ - 1;
        if (index > mySize) {
            // just skip out-of-bounds indices
            continue;
        }
        blit(_data + index * stride, pSrc, stride);
        pSrc += stride;
    }
}

static inline void blit(char *dest, const char *src, size_t count)
{
    char *end = dest + count;
    while (dest < end) {
        *dest++ = *src++;
    }
}

- (instancetype)transpose
{
    SBLArray *transpose = [[self class] new];
    [transpose setRows:_cols columns:_rows];
    if (_rows == 1 || _cols == 1) {
        // it's just a vector--copy it and we're done
        memcpy(transpose.data, _data, _rows * _cols * self.typeSize);
    } else {
        size_t typeSize = self.typeSize;
        size_t tColStride = transpose.rows * typeSize;
        const char *pSrc = _data;
        const char *pEnd = pSrc + _rows * _cols * typeSize;
        char *rowStart = transpose.data;
        char *pDest = rowStart;
        while (pSrc < pEnd) {
            for (size_t srcRow = 0; srcRow < _rows; ++srcRow) {
                blit(pDest, pSrc, typeSize);
                pSrc += typeSize;
                pDest += tColStride;
            }
            rowStart += typeSize;
            pDest = rowStart;
        }
    }
    return transpose;
}

void flipCol(char *outCol, const char *inCol, size_t rows, size_t stride)
{
    const char *pIn = inCol;
    const char *pEnd = pIn + rows * stride;
    char *pOut = outCol + (rows - 1) * stride;
    
    while (pIn < pEnd) {
        blit(pOut, pIn, stride);
        pIn += stride;
        pOut -= stride;
    }
}

- (instancetype)flipud
{
    if (_rows == 1) {
        // row vector is unchanged by flipud
        return [self copy];
    }
    
    SBLArray *flipud = [[self class] new];
    [flipud setRows:_rows columns:_cols];
    size_t stride = _rows * self.typeSize;
    char *pIn = _data;
    char *pOut = flipud.data;
    for (size_t col = 0; col < _cols; ++col) {
        flipCol(pOut, pIn, _rows, self.typeSize);
        pIn += stride;
        pOut += stride;
    }
    
    return flipud;
}

- (BOOL)isZero:(void *)valPtr
{
    return YES; // must override in all subclasses
}

+ (instancetype)zerosInRows:(size_t)rows columns:(size_t)columns
{
    SBLArray *ra = [self new];
    [ra setRows:rows columns:columns];
    memset(ra.data, 0, ra.allocatedSize * ra.typeSize);
    return ra;
}

- (void)dealloc
{
    // only free it if we actually allocated it
    if (_allocatedSize) {
        free(_data);
    }
}

@end

#pragma mark - SBLComplexArray

@implementation SBLComplexArray

@dynamic data;

- (size_t)typeSize
{
    return sizeof(DSPDoubleComplex);
}

- (SBLRealArray *)abs
{
    SBLRealArray *abs = [SBLRealArray new];
    [abs setRows:self.rows columns:self.cols];
    const DOUBLE_COMPLEX *p = self.data;
    const DOUBLE_COMPLEX *pEnd = p + self.rows * self.cols;
    double *pDest = abs.data;
    while (p < pEnd) {
        DOUBLE_COMPLEX this = *p++;
        *pDest++ = sqrt(this.real * this.real + this.imag * this.imag);
    }
    
    return abs;
}



- (BOOL)isZero:(void *)valPtr
{
    DSPDoubleComplex cval = *(DSPDoubleComplex *)valPtr;
    return (cval.real == 0.0 &&  cval.imag == 0.0);
}

@end

#pragma mark - SBLRealArray

@implementation SBLRealArray

@dynamic data;

+ (SBLRealArray *)rowVectorWithStart:(double)start step:(double)step cap:(double)cap
{
    SBLRealArray *rv = [SBLRealArray new];
    if (step == 0.0 || (cap - start) / step < 0.0) {
        return rv;
    }
    size_t cols = round((cap - start) / step) + 1;
    [rv setRows:1 columns:cols];
    double *p = rv.data;
    double *pEnd = p + cols;
    
    double index = 0.0;
    while (p < pEnd) {
        *p++ = start + index++ * step;
    }
        
    return rv;
}

- (size_t)typeSize
{
    return sizeof(double);
}

- (SBLRealArray *)applyReal:(applyRealBlock)block
{
    SBLRealArray *applied = [SBLRealArray new];
    [applied setRows:self.rows columns:self.cols];
    double *p = self.data;
    double *pEnd = p + self.rows * self.cols;
    double *pDest = applied.data;
    while (p < pEnd) {
        *pDest++ = block(*p++);
    }
    return applied;
}

- (SBLRealArray *)applyReal:(applyRealArrayBlock)block withRealArray:(SBLRealArray *)array
{
    // sizes must match if there's another array
    if (array.rows != self.rows || array.cols != self.cols) {
        return nil;
    }
    
    SBLRealArray *applied = [SBLRealArray new];
    [applied setRows:self.rows columns:self.cols];
    const double *p = self.data;
    const double *pOther = array.data;
    const double *pEnd = p + self.rows * self.cols;
    double *pDest = applied.data;
    while (p < pEnd) {
        *pDest++ = block(*p++, *pOther++);
    }
    return applied;
}

- (SBLIntArray *)applyInt:(applyRealIntBlock)block
{
    SBLIntArray *applied = [SBLIntArray new];
    [applied setRows:self.rows columns:self.cols];
    double *p = self.data;
    double *pEnd = p + self.rows * self.cols;
    ssize_t *pDest = applied.data;
    while (p < pEnd) {
        *pDest++ = block(*p++);
    }
    return applied;
}

- (SBLIntArray *)applyInt:(applyRealArrayIntBlock)block withRealArray:(SBLRealArray *)array
{
    // sizes must match if there's another array
    if (array.rows != self.rows || array.cols != self.cols) {
        return nil;
    }
    
    SBLIntArray *applied = [SBLIntArray new];
    [applied setRows:self.rows columns:self.cols];
    const double *p = self.data;
    const double *pOther = array.data;
    const double *pEnd = p + self.rows * self.cols;
    ssize_t *pDest = applied.data;
    while (p < pEnd) {
        *pDest++ = block(*p++, *pOther++);
    }
    return applied;
}

- (SBLRealArray *)abs
{
    SBLRealArray *abs = [SBLRealArray new];
    [abs setRows:self.rows columns:self.cols];
    const double *p = self.data;
    const double *pEnd = p + self.rows * self.cols;
    double *pDest = abs.data;
    while (p < pEnd) {
        *pDest++ = fabs(*p++);
    }
    
    return abs;
}

- (SBLRealArray *)round
{
    SBLRealArray *roundArray = [SBLRealArray new];
    [roundArray setRows:self.rows columns:self.cols];
    const double *p = self.data;
    const double *pEnd = p + self.rows * self.cols;
    double *pDest = roundArray.data;
    while (p < pEnd) {
        *pDest++ = round(*p++);
    }
    
    return roundArray;
}

double minForColumn(const double *colStart, size_t rows, ssize_t *index)
{
    const double *p = colStart;
    const double *pEnd = p + rows;
    double min = *p++;
    while (p < pEnd && isnan(min)) {
        min = *p++;
    }
    if (index) {
        // start it with *something*
        *index = p - colStart + 1;
    }
    while (p < pEnd) {
        double val = *p++;
        if (isnan(val)) {
            continue;
        }
        if (val < min) {
            if (index) {
                *index = p - colStart;
            }
            min = val;
        }
        ++p;
    }
    
    return min;
}

- (SBLRealArray *)min
{
    SBLRealArray *min = [SBLRealArray new];
    [min setRows:1 columns:self.cols];
    const double *p = self.data;
    const double *pEnd = p + self.rows * self.cols;
    double *pDest = min.data;
    if (self.rows == 1) {
        // pretend it's a column vector by swapping indices
        [min setRows:1 columns:1];
        pDest = min.data; // in case reallocf() moved it
        while (p < pEnd) {
            *pDest++ = minForColumn(p, self.cols, NULL);
            p += self.cols;
        }
    } else {
        while (p < pEnd) {
            *pDest++ = minForColumn(p, self.rows, NULL);
            p += self.rows;
        }
    }
    
    return min;
}

- (SBLRealArray *)minAndIndices:(SBLIntArray *__autoreleasing *)indices
{
    SBLRealArray *min = [SBLRealArray new];
    [min setRows:1 columns:self.cols];
    *indices = [SBLIntArray new];
    [*indices setRows:1 columns:self.cols];
    const double *p = self.data;
    const double *pEnd = p + self.rows * self.cols;
    double *pDest = min.data;
    ssize_t *pIDest = (*indices).data;
    if (self.rows == 1) {
        // pretend it's a column vector by swapping indices
        [min setRows:1 columns:1];
        pDest = min.data; // in case reallocf() moved it
        while (p < pEnd) {
            *pDest++ = minForColumn(p, self.cols, pIDest++);
            p += self.cols;
        }
    } else {
        while (p < pEnd) {
            *pDest++ = minForColumn(p, self.rows, pIDest++);
            p += self.rows;
        }
    }
    
    return min;
}

double maxForColumn(const double *colStart, size_t rows, ssize_t *index)
{
    const double *p = colStart;
    const double *pEnd = p + rows;
    double max = *p++;
    while (p < pEnd && isnan(max)) {
        max = *p++;
    }
    if (index) {
        // start it with *something*
        *index = p - colStart; // + 1; --we've already incremented p past this one
    }
    while (p < pEnd) {
        double val = *p++;
        if (isnan(val)) {
            continue;
        }
        if (val > max) {
            if (index) {
                // Matlab one-based indices
                *index = p - colStart; // + 1; --we've already incremented p past this one
            }
            max = val;
        }
    }
    
    return max;
}

- (SBLRealArray *)max
{
    SBLRealArray *max = [SBLRealArray new];
    [max setRows:1 columns:self.cols];
    const double *p = self.data;
    const double *pEnd = p + self.rows * self.cols;
    double *pDest = max.data;
    if (self.rows == 1) {
        // pretend it's a column vector by swapping indices
        [max setRows:1 columns:1];
        pDest = max.data; // in case reallocf() moved it
        while (p < pEnd) {
            *pDest++ = maxForColumn(p, self.cols, NULL);
            p += self.cols;
        }
    } else {
        while (p < pEnd) {
            *pDest++ = maxForColumn(p, self.rows, NULL);
            p += self.rows;
        }
    }
    
    return max;
}

- (SBLRealArray *)maxAndIndices:(SBLIntArray *__autoreleasing *)indices
{
    SBLRealArray *max = [SBLRealArray new];
    [max setRows:1 columns:self.cols];
    *indices = [SBLIntArray new];
    [*indices setRows:1 columns:self.cols];
    const double *p = self.data;
    const double *pEnd = p + self.rows * self.cols;
    double *pDest = max.data;
    ssize_t *pIDest = (*indices).data;
    if (self.rows == 1) {
        // pretend it's a column vector by swapping indices
        [max setRows:1 columns:1];
        pDest = max.data; // in case reallocf() moved it
        while (p < pEnd) {
            *pDest++ = maxForColumn(p, self.cols, pIDest++);
            p += self.cols;
        }
    } else {
        while (p < pEnd) {
            *pDest++ = maxForColumn(p, self.rows, pIDest++);
            p += self.rows;
        }
    }
    
    return max;
}

double meanForColumn(const double *colStart, size_t rows)
{
    const double *p = colStart;
    const double *pEnd = p + rows;
    double sum = 0.0;
    size_t validRows = rows;
    while (p < pEnd) {
        double val = *p++;
        
        // skip NaNs and don't count them as zeros
        if (isnan(val)) {
            --validRows;
            continue;
        }
        sum += val;
    }
    
    return sum / (double)validRows;
}

- (SBLRealArray *)mean
{
    SBLRealArray *mean = [SBLRealArray new];
    [mean setRows:1 columns:self.cols];
    const double *p = self.data;
    const double *pEnd = p + self.rows * self.cols;
    double *pDest = mean.data;
    if (self.rows == 1) {
        // pretend it's a column vector by swapping indices
        [mean setRows:1 columns:1];
        pDest = mean.data; // in case reallocf() moved it
        while (p < pEnd) {
            *pDest++ = meanForColumn(p, self.cols);
            p += self.cols;
        }
    } else {
        while (p < pEnd) {
            *pDest++ = meanForColumn(p, self.rows);
            p += self.rows;
        }
    }
    
    return mean;
}

double medianForColumn(const double *colStart, size_t rows)
{
    double sortedCol[rows];
    memcpy(sortedCol, colStart, rows * sizeof(double));
    qsort_b(sortedCol, rows, sizeof(double), ^int(const void *ptr1, const void *ptr2) {
        double v1 = *(double *)ptr1;
        double v2 = *(double *)ptr2;
        // sort all the NaNs to the bottom (even below -Inf) so we can just skip over 'em
        return isnan(v1) || isnan(v2) ? -1 : v1 < v2 ? -1 : v1 > v2 ? 1 : 0;
    });
    
    double median = NAN;
    
    // don't count the NaNs
    const double *p = colStart;
    const double *pEnd = colStart + rows;
    size_t validRows = rows;
    while (p < pEnd) {
        if (!isnan(*p)) {
            break;
        }
        ++p;
        --validRows;
    }
    
    size_t mid = validRows >> 1;
    if (validRows % 2) {
        // odd--take the middle one
        median = sortedCol[mid];
    } else {
        // even--split the difference
        double low = sortedCol[mid - 1];
        double high = sortedCol[mid];
        median = (low + high) / 2.0;
    }
    
    return median;
}

- (SBLRealArray *)median
{
    SBLRealArray *median = [SBLRealArray new];
    [median setRows:1 columns:self.cols];
    const double *p = self.data;
    const double *pEnd = p + self.rows * self.cols;
    double *pDest = median.data;
    if (self.rows == 1) {
        // pretend it's a column vector by swapping indices
        [median setRows:1 columns:1];
        pDest = median.data; // in case reallocf() moved it
        while (p < pEnd) {
            *pDest++ = medianForColumn(p, self.cols);
            p += self.cols;
        }
    } else {
        while (p < pEnd) {
            *pDest++ = medianForColumn(p, self.rows);
            p += self.rows;
        }
    }
    
    return median;
}

- (double)norm
{
    double sumsq = 0.0;
    const double *p = self.data;
    const double *pEnd = p + self.rows * self.cols;
    while (p < pEnd) {
        double value = *p++;
        if (isnan(value)) {
            return NAN;
        }
        sumsq += value * value;
    }
    
    return sqrt(sumsq);
}

- (SBLRealArray *)iqr
{
    SBLRealArray *quartile = quantile(self, 0.25);
    SBLRealArray *threequartile = quantile(self, 0.75);
    SBLRealArray *iqr = [threequartile applyReal:^double(const double element, const double otherArrayElement) {
        return element - otherArrayElement;
    } withRealArray:quartile];
    
    return iqr;
}

double varForColumn(const double *colStart, size_t rows)
{
    double mean = meanForColumn(colStart, rows);
    
    const double *p = colStart;
    const double *pEnd = p + rows;
    double sumsq = 0.0;
    while (p < pEnd) {
        double dev = *p++ - mean;
        sumsq += dev * dev;
    }
    
    // see docs for Matlab var() function
    double N = (rows > 1) ? (double)(rows - 1) : 1.0;
    
    return sumsq / N;
}


- (SBLRealArray *)var
{
    SBLRealArray *var = [SBLRealArray new];
    [var setRows:1 columns:self.cols];
    const double *p = self.data;
    const double *pEnd = p + self.rows * self.cols;
    double *pDest = var.data;
    if (self.rows == 1) {
        // pretend it's a column vector by swapping indices
        [var setRows:1 columns:1];
        pDest = var.data; // in case reallocf() moved it
        while (p < pEnd) {
            *pDest++ = varForColumn(p, self.cols);
            p += self.cols;
        }
    } else {
        while (p < pEnd) {
            *pDest++ = varForColumn(p, self.rows);
            p += self.rows;
        }
    }
    
    return var;
}

void diffsForColumn(double *destStart, const double *colStart, size_t rows)
{
    const double *p = colStart;
    const double *pNext = p + 1;
    const double *pEnd = p + rows;
    double *pDest = destStart;
    while (pNext < pEnd) {
        *pDest++ = *pNext++ - *p++;
    }
}

- (SBLRealArray *)diff
{
    SBLRealArray *diff = [SBLRealArray new];
    if (self.rows == 0 || self.cols == 0) {
        return diff;
    }
    [diff setRows:self.rows - 1 columns:self.cols];
    const double *p = self.data;
    const double *pEnd = p + self.rows * self.cols;
    double *pDest = diff.data;
    if (self.rows == 1) {
        // pretend it's a column vector by swapping indices
        [diff setRows:1 columns:self.cols - 1];
        pDest = diff.data; // if rows were 1, then it was empty before
        while (p < pEnd) {
            diffsForColumn(pDest, p, self.cols);
            p += self.cols;
            pDest += diff.cols;
        }
    } else {
        while (p < pEnd) {
            diffsForColumn(pDest, p, self.rows);
            p += self.rows;
            pDest += diff.rows;
        }
    }
    
    return diff;
}

void cumsumsForColumn(double *destStart, const double *colStart, size_t rows)
{
    const double *pPrev = destStart;
    const double *p = colStart + 1;
    const double *pEnd = colStart + rows;
    double *pDest = destStart;
    *pDest++ = *colStart;
    while (p < pEnd) {
        *pDest++ = *p++ + *pPrev++;
    }
}

- (SBLRealArray *)cumsum
{
    SBLRealArray *cumsum = [SBLRealArray new];
    [cumsum setRows:self.rows columns:self.cols];
    const double *p = self.data;
    const double *pEnd = p + self.rows * self.cols;
    double *pDest = cumsum.data;
    if (self.rows == 1) {
        // pretend it's a column vector by swapping indices
        while (p < pEnd) {
            cumsumsForColumn(pDest, p, self.cols);
            p += self.cols;
            pDest += cumsum.cols;
        }
    } else {
        while (p < pEnd) {
            cumsumsForColumn(pDest, p, self.rows);
            p += self.rows;
            pDest += cumsum.rows;
        }
    }
    
    return cumsum;
}

- (SBLRealArray *)sum
{
    SBLRealArray *sum = [SBLRealArray new];
    [sum setRows:1 columns:self.cols];
    const double *p = self.data;
    const double *pEnd = p + self.rows * self.cols;
    double *pDest = sum.data;
    size_t elements = self.rows;
    if (self.rows == 1) {
        // pretend it's a column vector by swapping indices
        [sum setRows:1 columns:1];
        pDest = sum.data; // in case reallocf() moved it
        elements = self.cols;
    }
    while (p < pEnd) {
        vDSP_sveD(p, 1, pDest++, elements);
        p += self.rows;
    }

    return sum;
}

void addRowsFromColumn(double *destStart, const double *colStart, size_t rows)
{
    const double *p = colStart;
    const double *pEnd = p + rows;
    double *pDest = destStart;
    while (p < pEnd) {
        *pDest++ += *p++;
    }
}

- (SBLRealArray *)sum2
{
    SBLRealArray *sum2 = zeros(self.rows, 1);
    for (size_t column = 0; column < self.cols; ++column) {
        addRowsFromColumn(sum2.data, self.data + column * self.rows, self.rows);
    }
    
    return sum2;
}

- (SBLRealArray *)square
{
    return [self applyReal:^double(const double element) {
        return element * element;
    }];
}

- (SBLRealArray *)sqrt
{
    // assumes all values in self are non-negative; seems to be true for Max Little's code
    return [self applyReal:^double(const double element) {
        return sqrt(element);
    }];
}

- (SBLRealArray *)sin
{
    return [self applyReal:^double(const double element) {
        return sin(element);
    }];
}

- (SBLRealArray *)sinpi
{
    SBLRealArray *sinpi = [SBLRealArray new];
    [sinpi setRows:self.rows columns:self.cols];
    int elements = (int)(self.rows * self.cols);
    vvsinpi(sinpi.data, self.data, &elements);
    
    return sinpi;
}

- (SBLRealArray *)sin:(applyRealBlock)block
{
    return [self applyReal:^double(const double element) {
        return sin(block(element));
    }];
}

- (SBLRealArray *)cos
{
    return [self applyReal:^double(const double element) {
        return cos(element);
    }];
}

- (SBLRealArray *)cospi
{
    SBLRealArray *cospi = [SBLRealArray new];
    [cospi setRows:self.rows columns:self.cols];
    int elements = (int)(self.rows * self.cols);
    vvcospi(cospi.data, self.data, &elements);
    
    return cospi;
}

- (SBLRealArray *)cos:(applyRealBlock)block
{
    return [self applyReal:^double(const double element) {
        return cos(block(element));
    }];
}

- (SBLRealArray *)atan2:(SBLRealArray *)x
{
    return [self applyReal:^double(const double element, const double otherArrayElement) {
        return atan2(element, otherArrayElement);
    } withRealArray:x];
}

- (SBLRealArray *)log
{
    return [self applyReal:^double(const double element) {
        return log(element);
    }];
}

- (SBLRealArray *)log2
{
    return [self applyReal:^double(const double element) {
        return log2(element);
    }];
}

- (SBLRealArray *)log10
{
    return [self applyReal:^double(const double element) {
        return log10(element);
    }];
}

- (SBLRealArray *)exp2
{
    return [self applyReal:^double(const double element) {
        return exp2(element);
    }];
}

- (SBLRealArray *)pow:(double)exp
{
    return [self applyReal:^double(const double element) {
        return pow(element, exp);
    }];
}

- (SBLRealArray *)oneOverX
{
    return [self applyReal:^double(const double element) {
        return 1.0 / element;
    }];
}

- (SBLRealArray *)diag
{
    SBLRealArray *diag = [SBLRealArray new];
    size_t length = self.rows * self.cols;
    size_t srcStride;
    size_t destStride;

    if (self.rows == 1 || self.cols == 1) {
        // create a square diagonal matrix from this vector
        diag = zeros(length, length);
        srcStride = 1;
        destStride = length + 1;
    } else {
        // create a column vector from the main diagonal of this matrix
        [diag setRows:length columns:1];
        srcStride = length + 1;
        destStride = 1;
    }
    
    const double *pSrc = self.data;
    const double *pEnd = pSrc + length;
    double *pDest = diag.data;
    while (pSrc < pEnd) {
        *pDest = *pSrc;
        pSrc += srcStride;
        pDest += destStride;
    }
    
    return diag;
}

void doFftForColumn(DOUBLE_COMPLEX *outColStart, const double *colStart, size_t rows)
{
    fft(colStart, rows, outColStart);
}

- (SBLComplexArray *)fft
{
    SBLComplexArray *fftout = [SBLComplexArray new];
    [fftout setRows:self.rows columns:self.cols];
    const double *p = self.data;
    const double *pEnd = p + self.rows * self.cols;
    DOUBLE_COMPLEX *pDest = fftout.data;
    if (self.rows == 1) {
        doFftForColumn(pDest, p, self.cols);
    } else {
        while (p < pEnd) {
            doFftForColumn(pDest, p, self.rows);
            p += self.rows;
            pDest += fftout.rows;
        }
    }
    
    return fftout;
}


- (SBLRealArray *)matmult:(SBLRealArray *)matrix
{
    // inner dimensions must match
    if (self.cols != matrix.rows) {
        return nil;
    }
    SBLRealArray *result = [SBLRealArray new];
    [result setRows:self.rows columns:matrix.cols];
    
    // reverse the order of the inputs because of Matlab's column-major vs everyone else's row-major thingy
    // also swap rows for cols and vice-versa for the same stupid reason
    vDSP_mmulD(matrix.data, 1, self.data, 1, result.data, 1, matrix.cols, self.rows, self.cols);
    return result;
}

- (SBLRealArray *)multiply:(double)factor
{
    SBLRealArray *product = [SBLRealArray new];
    [product setRows:self.rows columns:self.cols];
    
    vDSP_vsmulD(self.data, 1, &factor, product.data, 1, self.rows * self.cols);
    return product;
}

- (SBLRealArray *)divide:(double)denominator
{
    SBLRealArray *quotient = [SBLRealArray new];
    [quotient setRows:self.rows columns:self.cols];
    
    vDSP_vsdivD(self.data, 1, &denominator, quotient.data, 1, self.rows * self.cols);
    return quotient;
}


- (SBLRealArray *)divideElementByElement:(SBLRealArray *)denominators
{
    // sizes must match
    if (denominators.rows != self.rows || denominators.cols != self.cols) {
        return nil;
    }
    
    SBLRealArray *quotients = [SBLRealArray new];
    [quotients setRows:self.rows columns:self.cols];
    
    vDSP_vdivD(denominators.data, 1, self.data, 1, quotients.data, 1, self.rows * self.cols);
    
    return quotients;
}

- (SBLRealArray *)divideRows:(NSRange)rows byRow:(size_t)row ofRealArray:(SBLRealArray *)denominators
{
    // widths must match
    if (denominators.cols != self.cols) {
        return nil;
    }
    
    SBLRealArray *quotients = [SBLRealArray new];
    [quotients setRows:rows.length columns:self.cols];
    
    // row is C zero-based index, not matlab one-based (to match NSRange convention)
    double *denomRow = denominators.data + row;
    size_t denomStride = denominators.rows;
    
    if (rows.length > self.cols) {
        // do it column by column
        double *pCol = self.data + rows.location;
        size_t stride = self.rows;
        size_t destStride = rows.length;
        double *pEnd = pCol + self.cols * stride;
        double *pDenom = denomRow;
        double *pDest = quotients.data;
        while (pCol < pEnd) {
            vDSP_vsdivD(pCol, 1, pDenom, pDest, 1, destStride);
            pCol += stride;
            pDenom += denomStride;
            pDest += destStride;
        }
    } else {
        // do it row by row
        double *pRow = self.data + rows.location;
        size_t stride = self.rows;
        size_t destStride = rows.length;
        double *pEnd = pRow + destStride;
        double *pDest = quotients.data;
        while (pRow < pEnd) {
            vDSP_vdivD(denomRow, denomStride, pRow++, stride, pDest++, destStride, self.cols);
        }
    }
    
    return quotients;
}

- (SBLRealArray *)under:(double)numerator
{
    return [self applyReal:^double(const double element) {
        return numerator / element;
    }];
}

- (SBLRealArray *)add:(double)addend
{
    return [self applyReal:^double(const double element) {
        return element + addend;
    }];
}

- (SBLRealArray *)addArray:(SBLRealArray *)array
{
    return [self applyReal:^double(const double element, const double otherArrayElement) {
        return element + otherArrayElement;
    } withRealArray:array];
}

- (SBLRealArray *)subtract:(double)subtrahend
{
    return [self add:-subtrahend];
}

- (SBLRealArray *)subtractFrom:(double)minuend
{
    return [self applyReal:^double(const double element) {
        return minuend - element;
    }];
}

- (SBLRealArray *)std
{
    NSAssert(self.rows == 1 || self.cols == 1, @"Standard deviation not yet implemented for multidimensional arrays");
    SBLRealArray *stdDev = [SBLRealArray new];
    [stdDev setRows:1 columns:1];
    double mu = [self mean].data[0];
    double sum = 0.0;
    double *p = self.data;
    NSInteger N = self.rows * self.cols;
    double *pEnd = p + N;
    while (p < pEnd) {
        double var = *p++ - mu;
        sum += var * var;
    }
    double variance = sum / (double)(N - 1);
    stdDev.data[0] = sqrt(variance);
    return stdDev;
}

- (SBLIntArray *)isnan
{
    SBLIntArray *result = [SBLIntArray new];
    [result setRows:self.rows columns:self.cols];
    ssize_t *pIsnan = result.data;
    double *p = self.data;
    double *pEnd = p + self.rows * self.cols;
    while (p < pEnd) {
        if (isnan(*p++)) {
            *pIsnan = 1;
        } else {
            *pIsnan = 0;
        }
        ++pIsnan;
    }
    
    return result;
}

- (SBLRealArray *)sign
{
    SBLRealArray *result = [SBLRealArray new];
    [result setRows:self.rows columns:self.cols];
    double *pSign = result.data;
    double *p = self.data;
    double *pEnd = p + self.rows * self.cols;
    while (p < pEnd) {
        if (*p < 0.0) {
            *pSign = -1.0;
        } else if (*p == 0.0) {
            *pSign = 0.0;
        } else if (*p > 0.0) {
            *pSign = 1.0;
        } else {
            *pSign = NAN;
        }
        ++p;
        ++pSign;
    }
    
    return result;
}

// internal method
- (BOOL)isZero:(void *)valPtr
{
    return *(double *)valPtr == 0.0;
}

@end

#pragma mark - SBLIntArray

@implementation SBLIntArray

@dynamic data;

+ (SBLIntArray *)rowVectorFrom:(ssize_t)start to:(ssize_t)end
{
    SBLIntArray *rowVector = [SBLIntArray new];
    size_t cols = end - start + 1;
    if (![rowVector setRows:1 columns:cols]) {
        return nil;
    }
    ssize_t *p = rowVector.data;
    ssize_t *pEnd = p + cols;
    ssize_t value = start;
    while (p < pEnd) {
        *p++ = value++;
    }
    
    return rowVector;
}

- (SBLIntArray *)all
{
    SBLIntArray *result = [SBLIntArray new];
    if (self.rows == 0 && self.cols == 0) {
        [result setRows:1 columns:1];
        result.data[0] = 1;
        return result;
    }
    [result setRows:1 columns:self.cols];
    ssize_t *pAll = result.data;
    ssize_t *p = self.data;
    ssize_t stride = self.rows;
    ssize_t *pNextCol = p + stride;
    ssize_t *pEnd = p + (stride * self.cols);
    while (p < pEnd) {
        *pAll = 1;
        while (p < pNextCol) {
            if (!*p) {
                *pAll = 0;
                p = pNextCol;
                break;
            }
        }
        pNextCol += stride;
        ++pAll;
    }
    
    return result;
}

- (SBLIntArray *)applyInt:(applyIntBlock)block
{
    SBLIntArray *applied = [SBLIntArray new];
    [applied setRows:self.rows columns:self.cols];
    ssize_t *p = self.data;
    ssize_t *pEnd = p + self.rows * self.cols;
    ssize_t *pDest = applied.data;
    while (p < pEnd) {
        *pDest++ = block(*p++);
    }
    return applied;
}



- (SBLIntArray *)add:(ssize_t)addend
{
    return [self applyInt:^ssize_t(const ssize_t element) {
        return element + addend;
    }];
}


- (size_t)typeSize
{
    return sizeof(ssize_t);
}

- (BOOL)isZero:(void *)valPtr
{
    return *(ssize_t *)valPtr == 0;
}


@end
