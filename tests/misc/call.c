int p[10],q[10];
int *r;

int res;

void f(int*t) {
  res = *(t+5);
}


/* @
  @ assigns \result , p[c] \from p[c..(c+3)], p[*], p[2];
  @ assigns q[5] \from p[1], c ;
  @*/
void main(int c)
{int lcount= 0;
 res= 1111;
  for (lcount=0; lcount<=6; lcount++)
    {
      p[lcount]=lcount;
      q[lcount]=lcount+10;};

  p[5] = 177;
  q[5] = 188;

  int *tmp ;
  {
    if (c) {
      tmp = p;
    } else {
      tmp = q;
    }

    f(tmp); // t --> deps(tmp)

    }
}

struct A {int a; int b;} x;

void f_struct(struct A y) {
  res = y.b;
}

void caller_struct() {
  struct A z = res?x:x;
  f_struct(z);

}


void f_ptr(int*X) {
  res = *X;
}
void caller_ptr() {
  int * e = res?&x.a:&x.b;
  f_ptr(e);

}