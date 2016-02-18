//
//  SBLLabMath.h
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

typedef NS_ENUM(int, SBLInterp1Method) {
    SBLInterp1MethodLinear = 0,
    SBLInterp1MethodSpline
};

extern SBLRealArray *zeros(size_t rows, size_t columns);
extern SBLRealArray *ones(size_t rows, size_t columns);
extern SBLRealArray *NaN(size_t rows, size_t columns);
extern SBLRealArray *sortrows(SBLRealArray *table, size_t column);
extern SBLRealArray *polyfit(SBLRealArray *x, SBLRealArray *y, int order);
extern SBLRealArray *polyval(SBLRealArray *c, SBLRealArray *x);
extern SBLRealArray *repmat(SBLRealArray *x, size_t rowsreps, size_t colsreps);
extern SBLRealArray *quantile(SBLRealArray *x, double p);
extern SBLRealArray *buffer(SBLRealArray *x, size_t n, size_t p);
extern SBLRealArray *linspace(double start, double end, size_t n);
extern SBLRealArray *hamming(size_t windowSize);
extern SBLRealArray *hanning(size_t windowSize);
extern SBLComplexArray *specgram(SBLRealArray *x, size_t windowSize, double samplingRate, SBLRealArray *window, size_t overlap, SBLRealArray **freqs, SBLRealArray **times);
extern SBLRealArray *interp1(SBLRealArray *x, SBLRealArray *v, SBLRealArray *xq, SBLInterp1Method method, double extrapolation);
