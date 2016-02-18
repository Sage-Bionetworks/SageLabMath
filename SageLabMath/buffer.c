//
//  buffer.c
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

#include "buffer.h"
#include <string.h>

void buffer_overlap(double *out, double *in, uint64_t inSize, uint64_t framelen,
                    uint64_t overlap)
{
    uint64_t frameinc = framelen - overlap;
    uint64_t columns = (inSize + frameinc - 1) / frameinc;
    
    double *pOut = out;
    double *pIn = in;
    double *endOfIn = in + inSize;
    uint64_t outSize = columns * framelen;
    double *endOfOut = pOut + outSize;
    
    // MATLAB uses column-major order
    // pad the first buffer (column) with zeroes for overlap
    for (uint64_t i = 0; i < overlap; ++i) {
        *pOut++ = 0.0;
    }
    
    // fill in the columns
    while (pIn < endOfIn) {
        // put the new stuff in at the end of this column
        for (uint64_t i = 0; i < frameinc && pIn < endOfIn; ++i) {
            *pOut++ = *pIn++;
        }
        
        if  (pIn < endOfIn) {
            // copy the overlap to the start of the next column
            for (uint64_t i = 0; i < overlap; ++i) {
                *pOut = *(pOut - overlap);
                pOut++;
            }
        }
    }
    
    // pad the end of the last column with zeroes
    while (pOut < endOfOut) {
        *pOut++ = 0.0;
    }
}

void buffer_nooverlap(double *out, double *in, uint64_t inSize, uint64_t framelen)
{
    buffer_overlap(out, in, inSize, framelen, 0);
}