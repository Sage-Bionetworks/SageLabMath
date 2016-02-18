//
//  SBLArray.h
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

#import <Foundation/Foundation.h>
#import <sys/types.h>
@import Accelerate;

@class SBLArray;
@class SBLRealArray;
@class SBLIntArray;

typedef double (^applyRealBlock)(const double element);
typedef size_t (^applyRealIntBlock)(const double element);
typedef double (^applyRealArrayBlock)(const double element, const double otherArrayElement);
typedef size_t (^applyRealArrayIntBlock)(const double element, const double otherArrayElement);
typedef double (^applyIntArrayRealBlock)(const double element, const size_t otherArrayElement);

@interface SBLArray : NSObject

@property (nonatomic, assign) size_t rows;
@property (nonatomic, assign) size_t cols;
@property (nonatomic, assign) size_t allocatedSize;

- (size_t)typeSize;

- (BOOL)setRows:(size_t)rows columns:(size_t)columns;

- (BOOL)isVector;

// all arrays must be of the same SBLXxxArray subclass, and must have cols == 1
- (BOOL)concatenateColumnVectors:(NSArray *)arrays;

// all arrays must be of the same SBLXxxArray subclass, must have cols == 1, and must have the same number of rows (or 0)
- (BOOL)addColumns:(NSArray *)arrays;

- (instancetype)subarrayWithRows:(NSRange)rows columns:(NSRange)columns;
- (instancetype)subarrayWithRowIndices:(SBLIntArray *)rows columnIndices:(SBLIntArray *)columns;

// self and array types must match, and array rows and columns must match lengths of rows and columns ranges (and fit within self)
- (void)setSubarrayRows:(NSRange)rows columns:(NSRange)columns fromArray:(SBLArray *)array;

// number of elements in rows * columns must match size of array (need not be the same dimensions, but data will be treated
// as if it were)
- (void)setElementsWithRowIndices:(SBLIntArray *)rows columnIndices:(SBLIntArray *)columns fromArray:(SBLArray *)array;

- (SBLIntArray *)find;
- (SBLIntArray *)findFirst:(size_t)howMany;
- (SBLIntArray *)findLast:(size_t)howMany;
- (instancetype)elementsWithIndices:(SBLIntArray *)indexArray;

// array type must match self, and its size must match that of indexArray
- (void)setElementsWithIndices:(SBLIntArray *)indexArray fromArray:(SBLArray *)array;

- (instancetype)transpose;
- (instancetype)flipud;

// internal method used by find--overridden by subclasses
- (BOOL)isZero:(void *)valPtr;

@end

@interface SBLComplexArray : SBLArray

@property (nonatomic, assign) DSPDoubleComplex *data;

- (SBLRealArray *)abs;

@end

@interface SBLRealArray : SBLArray

@property (nonatomic, assign) double *data;

+ (SBLRealArray *)rowVectorWithStart:(double)start step:(double)step cap:(double)cap;
- (SBLRealArray *)applyReal:(applyRealBlock)block;
- (SBLRealArray *)applyReal:(applyRealArrayBlock)block withRealArray:(SBLRealArray *)array;
- (SBLIntArray *)applyInt:(applyRealIntBlock)block;
- (SBLIntArray *)applyInt:(applyRealArrayIntBlock)block withRealArray:(SBLRealArray *)array;
- (SBLRealArray *)abs;
- (SBLRealArray *)round;
- (SBLRealArray *)min;
- (SBLRealArray *)minAndIndices:(SBLIntArray **)indices;
- (SBLRealArray *)max;
- (SBLRealArray *)maxAndIndices:(SBLIntArray **)indices;
- (SBLRealArray *)mean;
- (SBLRealArray *)median;
- (double)norm;
- (SBLRealArray *)iqr;
- (SBLRealArray *)var;
- (SBLRealArray *)diff;
- (SBLRealArray *)cumsum;
- (SBLRealArray *)sum;
- (SBLRealArray *)sum2; // sums along rows instead of down cols. MATLAB: sum(x, 2)
- (SBLRealArray *)square;
- (SBLRealArray *)sqrt;
- (SBLRealArray *)sin;
- (SBLRealArray *)sinpi;
- (SBLRealArray *)sin:(applyRealBlock)block;
- (SBLRealArray *)cos;
- (SBLRealArray *)cospi;
- (SBLRealArray *)cos:(applyRealBlock)block;
- (SBLRealArray *)atan2:(SBLRealArray *)x;
- (SBLRealArray *)log;
- (SBLRealArray *)log2;
- (SBLRealArray *)log10;
- (SBLRealArray *)exp2;
- (SBLRealArray *)pow:(double)exp;
- (SBLRealArray *)oneOverX;
- (SBLRealArray *)diag;
- (SBLComplexArray *)fft;
- (SBLRealArray *)matmult:(SBLRealArray *)matrix;
- (SBLRealArray *)multiply:(double)factor;
- (SBLRealArray *)divide:(double)denominator;
- (SBLRealArray *)divideElementByElement:(SBLRealArray *)denominators;
- (SBLRealArray *)divideRows:(NSRange)rows byRow:(size_t)row ofRealArray:(SBLRealArray *)denominators;
- (SBLRealArray *)under:(double)numerator;
- (SBLRealArray *)add:(double)addend;
- (SBLRealArray *)subtract:(double)subtrahend;
- (SBLRealArray *)subtractFrom:(double)minuend;

@end

@interface SBLIntArray : SBLArray

@property (nonatomic, assign) size_t *data;

+ (SBLIntArray *)rowVectorFrom:(size_t)start to:(size_t)end;

@end
