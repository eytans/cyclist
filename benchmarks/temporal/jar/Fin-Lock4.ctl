fields: next;
precondition: a->zero * r->zero * ls(x,nil);
property:AF(a->one * r->one * ls(x,nil));
a.next:=one;
while x!=nil do
      temp:=x;
      x:=x.next;
      free(temp)
od;
r.next:=one