fields: next;
precondition: y!=nil * ls(x,nil) * ls(y,nil) ;
postcondition: ls(y,nil);
while x!=nil {
  z := y.next;
  if z=nil {
    y.next := x;
    x := x.next;
    y := y.next;
    y.next := nil
  } else {
    y := y.next
  }
}
 
