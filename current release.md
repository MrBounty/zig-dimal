-  Changed Quantity to Tensor that can use any shape and is a single @Vector.
   Point being to add WebGPU easily from this.
   Scalr suffer in performance tho, I will work on that

Maybe I can do a jupiter like web interface with cells to make Dim analysis
I could:
  - Use cells with a toy language
  - A nice debugger to display current variables with dimensions, type and value
  - Realtime error (I try to compile at change, display error on the cell)
  - Integrate a small graphic API that use Raylib canvas
  - COuld generate template at comptime =o
