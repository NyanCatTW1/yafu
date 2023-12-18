@* Generating 64bit-primes.

Copyright (C) 2000,2007 Jens Franke, Thorsten Kleinjung.
This file is part of gnfs4linux, distributed under the terms of the 
GNU General Public Licence and WITHOUT ANY WARRANTY.

You should have received a copy of the GNU General Public License along
with this program; see the file COPYING.  If not, write to the Free
Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
02111-1307, USA.

The primes below this bound are stored by their differences, which are
generated by an Eratosthenes sieve when the program starts.
Since this sieving procedure is much quicker than the factorisation
methods we use, it makes sense to execute it on startup rather than to waste
hard disk space on storing its results.

@(primgen64.c@>=
#include <math.h>
#include <sys/types.h>
#include <limits.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "gmp.h"

#include "asm/siever-config.h"
#include "primgen64.h"
#include "if.h"

#define P64_SIEVESIZE 0x80000
#define PRIMEDIFFS_ALLOCSIZE P64_SIEVESIZE/4 /* must be > 65536 */
#define U64_MAX 0xffffffffffffffffULL

static unsigned char *primediffs=NULL;
static size_t primediffs_alloc=0;
static u64_t NCommonPrimes, CommonPmax;

@
@(primgen64.h@>=
typedef struct {
  u64_t Pind;
  u64_t first_in_sieve;
  u64_t nPrim;
  u64_t Prime;
  unsigned char *PDiffs;
  u64_t PDiffs_allocated;
} pr64_struct;

void initprime64(pr64_struct *ps);
u64_t firstprime64(pr64_struct *ps);
u64_t nextprime64(pr64_struct *ps);
void clearprime64(pr64_struct *ps);
u64_t pr64_seek(pr64_struct *ps,u64_t lb);

@
@(primgen64.c@>=
void initprime64(pr64_struct *ps)
{
  if(primediffs==NULL)
    @<Sieve 16-bit primes@>@;
  ps->Pind=0;
  ps->PDiffs=NULL;
  ps->nPrim=0;
  ps->Prime=0;
  ps->PDiffs_allocated=0;
  ps->first_in_sieve=0;
}

@
@(primgen64.c@>=
void clearprime64(pr64_struct *ps)
{
  if(ps->PDiffs) free(ps->PDiffs);
  ps->PDiffs_allocated=0;
}

@
@(primgen64.c@>=
u64_t firstprime64(pr64_struct *ps)
{
  ps->first_in_sieve=0;
  ps->Prime=2;
  ps->Pind=0;
  return 2;
}

@
@(primgen64.c@>=
u64_t nextprime64(pr64_struct *ps)
{
  if(ps->first_in_sieve) {
    if(ps->Pind<ps->nPrim) {
      ps->Prime+=2*ps->PDiffs[ps->Pind++];
      return ps->Prime;
    } else {
      if(ps->first_in_sieve<U64_MAX-2*P64_SIEVESIZE) {
        ps->first_in_sieve+=2*P64_SIEVESIZE;
        @<Sieve more primes@>@;
      } else return 0; /* Exhausted all 64-bit primes. */
    }
  }
  if(++(ps->Pind)==1) {
    ps->Prime=3;
    return 3;
  }
  ps->first_in_sieve=ps->Prime+2;
  ps->Pind=0;
  ps->nPrim=0;
  @<Sieve more primes@>@;
}

@ First sieve in |primediffs|, then use it to store the differences.
Only sieve odd numbers.
@<Sieve 16...@>=
{
  u64_t i,j,p;
  primediffs=xmalloc(PRIMEDIFFS_ALLOCSIZE);
  primediffs_alloc=PRIMEDIFFS_ALLOCSIZE;
  memset(primediffs,1,1+USHRT_MAX);
  for(i=3;i<0x100;i+=2) {
    if(primediffs[i])
      for(j=i*i;j<=USHRT_MAX;j+=i*2) primediffs[j]=0;
  }
  p=3;
  for(i=2,j=5;j<=USHRT_MAX;j+=2)
    if(primediffs[j]) {
      primediffs[i++]=(j-p)/2;
      p=j;
    }
  NCommonPrimes=i;
  CommonPmax=p;
}


@
@<Sieve more p...@>=
{
  unsigned char *sieve;
  u64_t i,M,j,diff,q,dmax=0,lasti,nprim,ssz;

  sieve=xmalloc(P64_SIEVESIZE);
  if(ps->PDiffs_allocated==0) {
    ps->PDiffs=xmalloc(PRIMEDIFFS_ALLOCSIZE);
    ps->PDiffs_allocated=PRIMEDIFFS_ALLOCSIZE;
  }
  /* Obviously, we are in a situation where |Prime| holds the largest
     prime we have obtained so far. */
  if(ps->first_in_sieve<U64_MAX-2*P64_SIEVESIZE) ssz=P64_SIEVESIZE;
  else ssz=(U64_MAX-ps->first_in_sieve)/2;
  M=1+floor(sqrt(ps->first_in_sieve+2*ssz));
  if (M>CommonPmax) 
    @<Sieve more common primes@>@;
  memset(sieve,1,P64_SIEVESIZE);
  for(i=2,q=3;q<=M;q+=2*primediffs[i++]) {
    j=ps->first_in_sieve%q;
    if(j) {
      if(j&1) j=(q-j)/2; else j=q-j/2;
    }
    if (ps->first_in_sieve+2*j==q) j+=q;
    for(;j<ssz;j+=q) sieve[j]=0;
  }
  for(i=0,nprim=0;i<ssz;i++) if(sieve[i]) {
    if(!nprim) {
      nprim=1;
      ps->Prime=ps->first_in_sieve+2*i;
      lasti=i;
    } else {
      if(nprim>ps->PDiffs_allocated)
        complain("Should never find that many primes!\n");
      diff=i-lasti;
      lasti=i;
      if(diff>dmax && (dmax=diff)>UCHAR_MAX)
        complain("Difference %llu between consecutive primes!\n",dmax);
      ps->PDiffs[nprim-1]=(unsigned char)diff;
      nprim++;
    }
  }
  free(sieve);
  if(nprim==0)
    complain("Found no prime\n");
  ps->nPrim=nprim-1;
  ps->Pind=0;
  return ps->Prime;
}

@ Only sieve odd numbers.
@<Sieve more c...@>=
{
  u64_t i,cM,q,j,diff,dmax=0,oldprime,start;

  while (1) {
    memset(sieve,1,P64_SIEVESIZE);
    oldprime=CommonPmax;
    start=oldprime+2;
    cM=1+floor(sqrt(start+2*P64_SIEVESIZE));
    for(i=2,q=3;q<=cM;q+=2*primediffs[i++]) {
      j=start%q;
      if(j) {
        if(j&1) j=(q-j)/2; else j=q-j/2;
      }
      for(;j<P64_SIEVESIZE;j+=q) sieve[j]=0;
    }
    for(i=0,q=start;i<P64_SIEVESIZE;i++,q+=2)
      if(sieve[i]) {
        diff=(q-oldprime)/2;
        if(diff>dmax && (dmax=diff)>UCHAR_MAX)
          complain("Difference %llu between consecutive primes!\n",dmax);
        if (NCommonPrimes>=(u64_t)primediffs_alloc) {
          primediffs_alloc+=PRIMEDIFFS_ALLOCSIZE;
          primediffs=(unsigned char *)xrealloc(primediffs,primediffs_alloc);
        }
        primediffs[NCommonPrimes++]=diff;
        oldprime=q;
      }
    CommonPmax=q; /* might be composite, but is only used for sieving */
    if (CommonPmax>=M) break;
  }
}


@
@(primgen64.c@>=
u64_t
pr64_seek(pr64_struct *ps,u64_t lb)
{
  if(lb<3) return firstprime64(ps);
  if(lb%2==0) lb++;
  ps->first_in_sieve=lb;
  @<Sieve more primes@>@;
}