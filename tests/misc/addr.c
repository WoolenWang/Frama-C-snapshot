/* run.config
   GCC:
   OPT: -memory-footprint 1 -val -deps -out -input
   OPT: -memory-footprint 1 -val -deps -out -input -main f
*/


int t[5];
int x;
int *p,*q;

void f(int i) {
//  x = t[i];
  p = t+i;
// q = &t[i];
}

void main () {
  t[2] = 77;
  f(2);
  
}